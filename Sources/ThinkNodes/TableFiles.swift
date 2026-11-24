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

/// Végpontok (EXCEL.md 7. fejezet):
/// - `POST /api/table/<lap>?from=<melléklet>`: a lap egy mellékletéből (pl. .csv) új, független táblázat.
/// - `POST /api/table/<lap>?name=<fájlnév.csv>` + törzs: feltöltött fájlból új táblázat; a feltöltött fájl nem tárolódik.
/// - mindkettő `&into=<meglévő .tntable>&mode=full|partial`: újraimportálás a meglévő táblázatba (`TableMerge`).
/// - `GET /api/table-export/<lap>?name=<x.tntable>&format=csv`: letöltés.
/// A táblázat és a forrásfájl között nincs kapcsolat: a táblázat a beolvasáskori tartalom másolata.
func registerTableRoutes(_ app: any RoutesBuilder, store: WorksheetStore,
                         identity: @escaping @Sendable (Request) throws -> (user: User?, unlocks: Set<String>),
                         verify: @escaping @Sendable (Request) throws -> Void,
                         changed: @escaping @Sendable (WorksheetPath) -> Void) {
    app.on(.POST, "api", "table", "**", body: .collect(maxSize: "12mb")) { req async throws -> TableImportResult in
        let who = try identity(req)
        try verify(req)
        let path = try WorksheetPath(req.parameters.getCatchall())
        let from = req.query[String.self, at: "from"]
        let uploadName = req.query[String.self, at: "name"]
        let body = req.body.data.map { Data($0.readableBytesView) }
        let into = req.query[String.self, at: "into"]
        let mode = TableImportMode(rawValue: req.query[String.self, at: "mode"] ?? "partial") ?? .partial
        let result = try await req.application.threadPool.runIfActive { () throws -> TableImportResult in
            let data: Data, sourceName: String
            if let from {
                data = try store.attachmentData(path, named: from, user: who.user, unlocks: who.unlocks)
                sourceName = try store.attachmentFilename(path, named: from, user: who.user, unlocks: who.unlocks)
            } else if let uploadName, let body, !body.isEmpty {
                data = body
                sourceName = (uploadName as NSString).lastPathComponent
            } else { throw Abort(.badRequest) }
            guard let (document, truncated) = try TableFiles.convert(data, filename: sourceName).first else { throw Abort(.unprocessableEntity) }
            if let into {
                let filename = try store.attachmentFilename(path, named: into, user: who.user, unlocks: who.unlocks)
                guard TableFiles.isTable(filename) else { throw Abort(.badRequest, reason: "A cél csak táblázat lehet.") }
                let old = try TableDocument.decode(store.attachmentData(path, named: into, user: who.user, unlocks: who.unlocks))
                let merged = TableMerge.reimport(old, with: document, mode: mode)
                try store.storeAttachment(merged.encoded(), named: into, at: path, user: who.user, unlocks: who.unlocks, replaceText: true)
                return TableImportResult(asset: into, filename: filename, name: merged.name, rows: merged.size.rows,
                                         cols: merged.size.cols, truncated: truncated)
            }
            let stem = (sourceName as NSString).deletingPathExtension
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
}
