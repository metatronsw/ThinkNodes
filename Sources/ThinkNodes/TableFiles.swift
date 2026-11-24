import Crypto
import Foundation
import ThinkTable
import Vapor

// Táblázat doboz szerveroldali bekötése (EXCEL.md). A táblázat logikája a ThinkTable modulban van;
// itt csak a fájlkezelés és a végpontok vannak.

enum TableFiles {
    static let fileExtension = "tntable"
    /// Táblázattá alakítható forrásfájlok (első kör: CSV/TSV; a második körben xlsx, xls, ods).
    static let importable: Set<String> = ["csv", "tsv"]

    static func isTable(_ name: String) -> Bool { (name as NSString).pathExtension.lowercased() == fileExtension }

    /// Mentés előtt: ellenőrzés és újraszámolás. A tárolt értéket mindig a szerver számolja (EXCEL.md 3. fejezet).
    static func normalized(_ bytes: Data) throws -> Data {
        do {
            var document = try TableDocument.decode(bytes)
            TableEngine.recalculate(&document)
            return try document.encoded()
        } catch {
            throw Abort(.badRequest, reason: "A táblázat hibás vagy túl nagy.")
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Forrásfájl → táblázat(ok). Több munkalapos formátumnál (második kör) munkalaponként egy.
    static func convert(_ data: Data, filename: String) throws -> [(document: TableDocument, truncated: Bool)] {
        let ext = (filename as NSString).pathExtension.lowercased()
        let stem = (filename as NSString).deletingPathExtension
        switch ext {
        case "csv", "tsv":
            let imported = TableCSV.importCSV(data, name: stem, ext: ext)
            var document = imported.document
            TableEngine.recalculate(&document)
            return [(document, imported.truncated)]
        default:
            throw Abort(.unsupportedMediaType, reason: "Ebből a fájltípusból még nem készíthető táblázat.")
        }
    }
}

extension WorksheetStore {
    /// Teszthez: a frissen feltöltött mellékletek 60 másodperces türelmi ideje lejár.
    func forgetPendingAttachmentsForTesting() { lock.withLock { clearPendingAttachments() } }

    /// A melléklet tényleges fájlneve (a név lehet azonosító is: `file-…`).
    func attachmentFilename(_ path: WorksheetPath, named name: String, user: User?, unlocks: Set<String>) throws -> String {
        guard let url = try contents(path, user: user, unlocks: unlocks, named: name).first else { throw Abort(.notFound) }
        return url.lastPathComponent
    }

    /// Melléklet tartalma olvasásra, jogosultság-ellenőrzéssel.
    func attachmentData(_ path: WorksheetPath, named name: String, user: User?, unlocks: Set<String>, limit: Int = 12 * 1024 * 1024) throws -> Data {
        guard let url = try contents(path, user: user, unlocks: unlocks, named: name).first,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw Abort(.notFound) }
        guard size <= limit else { throw Abort(.payloadTooLarge, reason: "A fájl túl nagy.") }
        return try Data(contentsOf: url)
    }
}

struct TableImportResult: Content {
    var asset: String
    var filename: String
    var name: String?
    var rows: Int
    var cols: Int
    var truncated: Bool
}

struct TableSourceStatus: Content {
    var source: String?
    /// A forrásfájl tényleges neve (a `source` lehet azonosító is).
    var filename: String?
    var changed: Bool
    var missing: Bool
    var edited: Bool
}

/// Végpontok:
/// - `POST /api/table/<lap>?from=<forrás>[&name=<cél.tntable>&replace=1]`: forrásfájlból táblázat (vagy újraolvasás).
/// - `GET /api/table-source/<lap>?name=<x.tntable>`: megváltozott-e a forrásfájl az import óta.
func registerTableRoutes(_ app: any RoutesBuilder, store: WorksheetStore,
                         identity: @escaping @Sendable (Request) throws -> (user: User?, unlocks: Set<String>),
                         verify: @escaping @Sendable (Request) throws -> Void,
                         changed: @escaping @Sendable (WorksheetPath) -> Void) {
    app.post("api", "table", "**") { req async throws -> TableImportResult in
        let who = try identity(req)
        try verify(req)
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let from = req.query[String.self, at: "from"] else { throw Abort(.badRequest) }
        let replace = req.query[String.self, at: "replace"] == "1"
        let target = req.query[String.self, at: "name"]
        if replace && target == nil { throw Abort(.badRequest) }
        let result = try await req.application.threadPool.runIfActive { () throws -> TableImportResult in
            let data = try store.attachmentData(path, named: from, user: who.user, unlocks: who.unlocks)
            let sourceName = try store.contents(path, user: who.user, unlocks: who.unlocks, named: from).first?.lastPathComponent ?? from
            guard var (document, truncated) = try TableFiles.convert(data, filename: sourceName).first else { throw Abort(.unprocessableEntity) }
            document.source = TableSource(name: from, hash: TableFiles.hash(data))
            if replace, let target {
                guard TableFiles.isTable(try store.attachmentFilename(path, named: target, user: who.user, unlocks: who.unlocks)) else {
                    throw Abort(.badRequest, reason: "A cél csak .tntable lehet.")
                }
                // Újraolvasás: az azonosító és a név marad (a későbbi táblázatközi hivatkozások miatt).
                if let old = try? TableDocument.decode(store.attachmentData(path, named: target, user: who.user, unlocks: who.unlocks)) {
                    document.id = old.id
                    document.name = old.name ?? document.name
                }
                document.edited = nil
                try store.storeAttachment(document.encoded(), named: target, at: path, user: who.user, unlocks: who.unlocks, replaceText: true)
                return TableImportResult(asset: target, filename: target, name: document.name, rows: document.size.rows,
                                         cols: document.size.cols, truncated: truncated)
            }
            let stem = target.map { ($0 as NSString).deletingPathExtension }.flatMap { $0.isEmpty ? nil : $0 } ?? (sourceName as NSString).deletingPathExtension
            let bytes = try document.encoded()
            for attempt in 1...50 {
                let filename = (attempt == 1 ? stem : stem + " " + String(attempt)) + "." + TableFiles.fileExtension
                do {
                    let asset = try store.storeAttachment(bytes, named: filename, at: path, user: who.user, unlocks: who.unlocks)
                    return TableImportResult(asset: asset, filename: filename, name: document.name, rows: document.size.rows,
                                             cols: document.size.cols, truncated: truncated)
                } catch let error as AbortError where error.status == .conflict { continue }
            }
            throw Abort(.conflict, reason: "Nem található szabad fájlnév a táblázatnak.")
        }
        changed(path)
        return result
    }

    // Letöltés: `GET /api/table-export/<lap>?name=<x.tntable>&format=csv` (a második körben xlsx, xls).
    app.get("api", "table-export", "**") { req async throws -> Response in
        let who = try identity(req)
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let name = req.query[String.self, at: "name"] else { throw Abort(.badRequest) }
        guard (req.query[String.self, at: "format"] ?? "csv") == "csv" else { throw Abort(.badRequest, reason: "Ismeretlen formátum.") }
        let (data, stem) = try await req.application.threadPool.runIfActive {
            guard TableFiles.isTable(try store.attachmentFilename(path, named: name, user: who.user, unlocks: who.unlocks)) else { throw Abort(.badRequest) }
            let document = try TableDocument.decode(store.attachmentData(path, named: name, user: who.user, unlocks: who.unlocks))
            return (TableCSV.export(document), document.name)
        }
        let filename = (stem ?? "táblázat") + ".csv"
        var headers = HTTPHeaders()
        headers.contentType = HTTPMediaType(type: "text", subType: "csv", parameters: ["charset": "utf-8"])
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "table.csv"
        headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"table.csv\"; filename*=UTF-8''" + encoded)
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }

    app.get("api", "table-source", "**") { req async throws -> TableSourceStatus in
        let who = try identity(req)
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let name = req.query[String.self, at: "name"] else { throw Abort(.badRequest) }
        return try await req.application.threadPool.runIfActive {
            guard TableFiles.isTable(try store.attachmentFilename(path, named: name, user: who.user, unlocks: who.unlocks)) else { throw Abort(.badRequest) }
            let document = try TableDocument.decode(store.attachmentData(path, named: name, user: who.user, unlocks: who.unlocks))
            guard let source = document.source else {
                return TableSourceStatus(source: nil, filename: nil, changed: false, missing: false, edited: document.edited == true)
            }
            guard let data = try? store.attachmentData(path, named: source.name, user: who.user, unlocks: who.unlocks) else {
                return TableSourceStatus(source: source.name, filename: nil, changed: false, missing: true, edited: document.edited == true)
            }
            let filename = try? store.attachmentFilename(path, named: source.name, user: who.user, unlocks: who.unlocks)
            return TableSourceStatus(source: source.name, filename: filename, changed: TableFiles.hash(data) != source.hash, missing: false,
                                     edited: document.edited == true)
        }
    }
}
