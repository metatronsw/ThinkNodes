import Crypto
import _CryptoExtras
import Foundation
import Vapor

// Projektcsomag: ZIP-export és -import (docs/migration.md).
//
// Nyitott csomag: maga a laphierarchia (`Név/Név.thnode`, `.settings.json`, fájlok, `.web`, allapok), manifest nélkül.
// Titkosított csomag: `thinknodes-encrypted.json` (nyitott fejléc) + `content.bin` (a nyitott ZIP, titkosítva).
// A csomagban a projektre mutató hivatkozások (`.web`, más lap fájlja) a csomag gyökeréhez viszonyítva szerepelnek,
// a csomagon belüli laplinkek relatívak. Jelszó-hash soha nem kerül bele.

// MARK: - ZIP írás

/// Tömörítés nélküli (stored) ZIP. A képek, hangok már tömörítettek; így nem kell külső program vagy zlib.
package enum ZipWriter {
    package enum Source { case file(URL), data(Data) }
    package struct Entry { let path: String; let source: Source }

    static func write(_ entries: [Entry], to destination: URL) throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw Abort(.internalServerError, reason: "A csomag nem hozható létre.")
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var central = Data()
        var offset: UInt64 = 0
        let (time, date) = dosTimestamp(Date())
        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc: UInt32, size: UInt64
            switch entry.source {
            case .data(let data): (crc, size) = (CRC32.checksum(data), UInt64(data.count))
            case .file(let url): (crc, size) = try CRC32.checksum(file: url)
            }
            guard size < 0xFFFF_FFFF, offset + size < 0xFFFF_FFFF, name.count < 0xFFFF else {
                throw Abort(.payloadTooLarge, reason: "A csomag legfeljebb 4 GiB lehet.")
            }
            var local = Data()
            local.le32(0x0403_4b50); local.le16(20); local.le16(0x0800); local.le16(0)
            local.le16(time); local.le16(date); local.le32(crc); local.le32(UInt32(size)); local.le32(UInt32(size))
            local.le16(UInt16(name.count)); local.le16(0); local.append(name)
            try handle.write(contentsOf: local)
            switch entry.source {
            case .data(let data): try handle.write(contentsOf: data)
            case .file(let url):
                let input = try FileHandle(forReadingFrom: url)
                defer { try? input.close() }
                var copied: UInt64 = 0
                while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                    try handle.write(contentsOf: chunk)
                    copied += UInt64(chunk.count)
                }
                // A fájl az ellenőrzőösszeg óta megváltozott: a csomag hibás lenne.
                guard copied == size else { throw Abort(.conflict, reason: "Egy fájl exportálás közben megváltozott; próbáld újra.") }
            }
            // „Unix” rendszer (0x03) + rw-r--r-- jogok: így az unzip a neveket változatlan (UTF-8) bájtokként írja ki;
            // MS-DOS jelöléssel kódlap-átalakítást végezne, és az ékezetes nevek elromlanának.
            central.le32(0x0201_4b50); central.le16(0x0314); central.le16(20); central.le16(0x0800); central.le16(0)
            central.le16(time); central.le16(date); central.le32(crc); central.le32(UInt32(size)); central.le32(UInt32(size))
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0)
            central.le32(UInt32(0o100644) << 16); central.le32(UInt32(offset)); central.append(name)
            offset += UInt64(local.count) + size
        }
        guard entries.count < 0xFFFF, offset + UInt64(central.count) < 0xFFFF_FFFF else {
            throw Abort(.payloadTooLarge, reason: "A csomag túl nagy.")
        }
        var end = Data()
        end.le32(0x0605_4b50); end.le16(0); end.le16(0); end.le16(UInt16(entries.count)); end.le16(UInt16(entries.count))
        end.le32(UInt32(central.count)); end.le32(UInt32(offset)); end.le16(0)
        try handle.write(contentsOf: central + end)
    }

    private static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let time = (parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2
        let day = max(0, (parts.year ?? 1980) - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1)
        return (UInt16(time), UInt16(day))
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) { append(UInt8(value & 0xFF)); append(UInt8(value >> 8)) }
    mutating func le32(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) } }
}

package enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    package static func update(_ crc: UInt32, _ bytes: some Sequence<UInt8>) -> UInt32 {
        var value = ~crc
        for byte in bytes { value = table[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8) }
        return ~value
    }

    static func checksum(_ data: Data) -> UInt32 { update(0, data) }

    static func checksum(file: URL) throws -> (UInt32, UInt64) {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var crc: UInt32 = 0, size: UInt64 = 0
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            crc = update(crc, chunk)
            size += UInt64(chunk.count)
        }
        return (crc, size)
    }
}

// MARK: - Titkosítás

/// scrypt kulcsszármaztatás + AES-256-GCM, darabonként (1 MiB). A darab nonce-a: 4 véletlen bájt + 8 bájtos sorszám;
/// az utolsó darabot a hitelesített adat jelöli, így a csonkítás is kiderül.
package enum PackageCrypto {
    static let headerName = "thinknodes-encrypted.json"
    static let contentName = "content.bin"
    package static let version = 1

    package struct Header: Codable {
        var format = "thinknodes-encrypted"
        package var version = PackageCrypto.version
        var kdf = "scrypt"
        var rounds = 1 << 15
        var blockSize = 8
        var parallelism = 1
        var salt: String
        var cipher = "AES-256-GCM"
        var chunkSize = 1 << 20
        var nonce: String
    }

    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    static func validPassword(_ password: String) -> Bool { (12...256).contains(password.count) }

    /// A fejléc ellenőrzése a jelszó bekérése előtt (ismeretlen vagy újabb formátum, túlzó paraméterek).
    static func checked(_ data: Data) throws -> Header {
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == "thinknodes-encrypted" else {
            throw Abort(.unprocessableEntity, reason: "A titkosított csomag fejléce hibás.")
        }
        guard header.version <= version else {
            throw Abort(.unprocessableEntity, reason: "A csomag újabb ThinkNodes-verzióval készült (\(header.version). titkosítási formátum); frissítsd a szervert.")
        }
        let salt = Data(base64Encoded: header.salt), nonce = Data(base64Encoded: header.nonce)
        guard header.kdf == "scrypt", header.cipher == "AES-256-GCM",
              header.rounds >= 1 << 14, header.rounds <= 1 << 20, header.rounds & (header.rounds - 1) == 0,
              (1...16).contains(header.blockSize), (1...4).contains(header.parallelism),
              (64 * 1024...16 * 1024 * 1024).contains(header.chunkSize),
              let salt, (16...64).contains(salt.count), nonce?.count == 4 else {
            throw Abort(.unprocessableEntity, reason: "A titkosított csomag fejléce nem támogatott.")
        }
        return header
    }

    private static func key(_ password: String, _ header: Header) throws -> SymmetricKey {
        try KDF.Scrypt.deriveKey(from: Array(password.utf8), salt: Data(base64Encoded: header.salt)!, outputByteCount: 32,
                                 rounds: header.rounds, blockSize: header.blockSize, parallelism: header.parallelism)
    }

    private static func nonce(_ header: Header, _ counter: UInt64) throws -> AES.GCM.Nonce {
        var bytes = Data(base64Encoded: header.nonce)!
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((counter >> UInt64(shift)) & 0xFF)) }
        return try AES.GCM.Nonce(data: bytes)
    }

    static func encrypt(_ source: URL, to destination: URL, password: String) throws -> Header {
        let header = Header(salt: randomBytes(16).base64EncodedString(), nonce: randomBytes(4).base64EncodedString())
        let key = try key(password, header)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw Abort(.internalServerError) }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var counter: UInt64 = 0
        var current = try input.read(upToCount: header.chunkSize) ?? Data()
        while true {
            let next = try input.read(upToCount: header.chunkSize) ?? Data()
            let last = next.isEmpty
            let box = try AES.GCM.seal(current, using: key, nonce: nonce(header, counter), authenticating: Data([last ? 1 : 0]))
            try output.write(contentsOf: box.ciphertext + box.tag)
            if last { break }
            current = next
            counter += 1
        }
        return header
    }

    static func decrypt(_ source: URL, header: Header, password: String, to destination: URL) throws {
        let key = try key(password, header)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw Abort(.internalServerError) }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let record = header.chunkSize + 16
        var counter: UInt64 = 0
        var current = try input.read(upToCount: record) ?? Data()
        while true {
            let next = try input.read(upToCount: record) ?? Data()
            let last = next.isEmpty
            guard current.count >= 16 else { throw Abort(.unprocessableEntity, reason: "A csomag sérült.") }
            do {
                let box = try AES.GCM.SealedBox(nonce: nonce(header, counter), ciphertext: current.dropLast(16), tag: current.suffix(16))
                try output.write(contentsOf: AES.GCM.open(box, using: key, authenticating: Data([last ? 1 : 0])))
            } catch {
                throw Abort(.forbidden, reason: counter == 0 ? "Hibás csomagjelszó." : "A csomag sérült.")
            }
            if last { break }
            current = next
            counter += 1
        }
    }
}

// MARK: - Kérések és válaszok

package struct PackageExportRequest: Content {
    /// "tree": a lap az allapjaival (alapértelmezett); "sheet": csak a lap.
    package var scope: String?
    package var versions: Bool?
    /// "copy": a csomagon kívüli fájlok bemásolása; "keep": hivatkozás marad (alapértelmezett).
    var external: String?
    var password: String?
}

package struct PackageEditor: Content {
    package var name: String
    var match: String?
}

package struct PackageReport: Content {
    var token: String
    var needsPassword: Bool
    package var target: String
    package var name: String?
    var sheets: Int?
    var files: Int?
    var bytes: Int64?
    var editors: [PackageEditor]?
    var users: [String]?
    var warnings: [String]?
}

package struct PackageUnlock: Content {
    var token: String
    var password: String
}

package struct PackageCommit: Content {
    var token: String
    package var name: String
    /// Csomagbeli szerkesztőnév → célszerveri felhasználónév (üres: kihagyva).
    var editors: [String: String]?
    var projectPassword: String?
}

// MARK: - Tároló

extension WorksheetStore {
    /// Csomag felső határa: a ZIP (ZIP64 nélküli) formátum korlátja, 4 GiB. A saját export tömörítés nélküli, így a
    /// kicsomagolt méret nagyjából ugyanennyi; idegen (tömörített) ZIP-nél a kicsomagolt tartalom legfeljebb 8 GiB.
    package static let maximumPackage = 4 * 1024 * 1024 * 1024 - 1
    static let maximumPackageExtracted: Int64 = 8 * 1024 * 1024 * 1024
    static let maximumPackageEntries = 20_000
    /// Darabolt feltöltés: egy darab mérete (a kliens ekkora szeleteket küld), és a félbemaradt feltöltés élettartama.
    package static let packageChunk = 8 * 1024 * 1024
    private static let uploadLifetime: TimeInterval = 24 * 3600
    private static let uploadsPerUser = 3
    private static let stagingName = ".package-staging"
    private static let stagingLifetime: TimeInterval = 3600

    private var stagingRoot: URL { root.appendingPathComponent(Self.stagingName) }

    private func stagingDirectory() throws -> URL {
        let url = stagingRoot
        try rejectLink(url)
        try files.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Lejárt (vagy indításkor minden) ideiglenes csomag törlése. A félbemaradt feltöltések (`upload-…`) a szerver
    /// újraindítását is túlélik, hogy folytathatók legyenek; ezek az utolsó darab után 24 órával járnak le.
    package func cleanPackageStaging(all: Bool = false) {
        let limit = Date().addingTimeInterval(-Self.stagingLifetime), uploadLimit = Date().addingTimeInterval(-Self.uploadLifetime)
        for url in (try? files.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            func modified(_ item: URL) -> Date {
                (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            }
            if url.lastPathComponent.hasPrefix("upload-") {
                if modified(url.appendingPathComponent("data.part")) < uploadLimit && modified(url) < uploadLimit { try? files.removeItem(at: url) }
            } else if all || modified(url) < limit {
                try? files.removeItem(at: url)
            }
        }
    }

    // MARK: Export

    /// Elkészíti a csomagot egy ideiglenes fájlba; a hívó küldi el és törli.
    package func exportPackage(_ path: WorksheetPath, options: PackageExportRequest, user: User?, unlocks: Set<String>) throws -> URL {
        guard let user, user.role != .guest else { throw Abort(.forbidden, reason: "Exportálni szerkesztő vagy admin tud.") }
        let scope = options.scope ?? "tree", external = options.external ?? "keep"
        guard ["tree", "sheet"].contains(scope), ["copy", "keep"].contains(external) else { throw Abort(.badRequest) }
        let password = options.password.flatMap { $0.isEmpty ? nil : $0 }
        if let password, !PackageCrypto.validPassword(password) {
            throw Abort(.unprocessableEntity, reason: "A csomagjelszó legalább 12 karakter legyen.")
        }
        let (entries, projectHash) = try lock.withLock {
            try packageEntriesLocked(path, tree: scope == "tree", versions: options.versions == true,
                                     copyExternal: external == "copy", user: user, unlocks: unlocks)
        }
        if projectHash != nil && password == nil {
            throw Abort(.unprocessableEntity, reason: "Jelszavas projekt csak titkosítva exportálható: adj meg csomagjelszót.")
        }
        if let password, let projectHash, try Bcrypt.verify(password, created: projectHash) {
            throw Abort(.unprocessableEntity, reason: "A csomagjelszó nem egyezhet a projekt jelszavával.")
        }
        cleanPackageStaging()
        let staging = try stagingDirectory()
        let token = "export-" + UUID().uuidString
        let plain = staging.appendingPathComponent(token + ".zip")
        do { try ZipWriter.write(entries, to: plain) } catch { try? files.removeItem(at: plain); throw error }
        guard let password else { return plain }
        let content = staging.appendingPathComponent(token + ".bin")
        let sealed = staging.appendingPathComponent(token + "-encrypted.zip")
        defer { try? files.removeItem(at: plain); try? files.removeItem(at: content) }
        do {
            let header = try PackageCrypto.encrypt(plain, to: content, password: password)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try ZipWriter.write([.init(path: PackageCrypto.headerName, source: .data(encoder.encode(header))),
                                 .init(path: PackageCrypto.contentName, source: .file(content))], to: sealed)
        } catch { try? files.removeItem(at: sealed); throw error }
        return sealed
    }

    /// A csomag tartalma (zár alatt): a lapok átírt JSON-ja, a megtisztított beállítások és a fájlok helye.
    /// Az elkészült csomag letöltési azonosítója: a fájl a letöltésig (legfeljebb egy óráig) az ideiglenes mappában marad,
    /// és csak az töltheti le, aki készítette. Így a böngésző közvetlenül, lemezre tölti le (megszakadás után folytathatóan).
    package func registerExport(_ file: URL, user: User?) throws -> (token: String, size: Int64) {
        guard let user else { throw Abort(.forbidden) }
        let token = file.deletingPathExtension().lastPathComponent
        try Data(user.name.utf8).write(to: file.appendingPathExtension("owner"))
        let size = ((try? files.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? 0
        return (token, size)
    }

    package func registeredExport(_ token: String, user: User?) throws -> URL {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        let plain = token.hasPrefix("export-") && UUID(uuidString: String(token.dropFirst(7))) != nil
        let sealed = token.hasPrefix("export-") && token.hasSuffix("-encrypted") && UUID(uuidString: String(token.dropFirst(7).dropLast(10))) != nil
        guard plain || sealed, !parts.isEmpty else { throw Abort(.notFound) }
        let file = stagingRoot.appendingPathComponent(token + ".zip")
        try rejectLink(file)
        guard files.fileExists(atPath: file.path) else { throw Abort(.gone, reason: "A csomag letöltési ideje lejárt; készítsd el újra.") }
        guard let user, let owner = try? String(contentsOf: file.appendingPathExtension("owner"), encoding: .utf8), owner == user.name else {
            throw Abort(.forbidden)
        }
        return file
    }

    private func packageEntriesLocked(_ path: WorksheetPath, tree: Bool, versions: Bool, copyExternal: Bool,
                                      user: User, unlocks: Set<String>) throws -> ([ZipWriter.Entry], String?) {
        let ctx = try context(path)
        let access = accessLocked(ctx, user: user, unlocks: unlocks)
        if access.locked { throw Abort(.locked, reason: "Ehhez a munkalaphoz jelszó szükséges.") }
        guard access.manageable else { throw Abort(.forbidden, reason: "Exportálni a projekt szerkesztője vagy admin tud.") }
        let projectRule = ctx.rules[ctx.project]!
        let base = Array(path.parts.dropFirst())
        let rootName = path.name

        // A csomag lapjai a gyökérhez viszonyítva ([] = a gyökér).
        var sheets: [[String]] = [[]]
        func visit(_ directory: URL, _ relative: [String]) throws {
            for entry in try sortedContents(directory) where !entry.lastPathComponent.hasPrefix(".") && entry.pathExtension != "web" {
                let name = entry.lastPathComponent
                guard isPlainDirectory(entry), let sheet = try? WorksheetPath(path.parts + relative + [name]),
                      files.fileExists(atPath: entry.appendingPathComponent(".settings.json").path),
                      files.fileExists(atPath: entry.appendingPathComponent(name + ".thnode").path) else { continue }
                sheets.append(Array(sheet.parts.dropFirst(path.parts.count)))
                try visit(entry, sheets.last!)
            }
        }
        if tree { try visit(ctx.directory, []) }
        let sheetSet = Set(sheets.map { $0.joined(separator: "/") })
        func insideSheet(_ projectRelative: [String]) -> [String]? {
            guard projectRelative.starts(with: base) else { return nil }
            let relative = Array(projectRelative.dropFirst(base.count))
            return sheetSet.contains(relative.joined(separator: "/")) ? relative : nil
        }

        var entries: [ZipWriter.Entry] = []
        var policies: [String: DocumentPolicy] = [:]
        var usedNames: [String: Set<String>] = [:]
        func zipPath(_ relative: [String], _ name: String) -> String { ([rootName] + relative + [name]).joined(separator: "/") }

        /// Hivatkozások átírása a csomag gyökeréhez; `copy`: a csomagon kívüli fájl bemásolása (csak élő lapnál).
        func rewrite(_ sheet: inout Worksheet, relative: [String], copy: Bool) throws {
            let absolute = path.parts + relative
            let key = relative.joined(separator: "/")
            for index in sheet.nodes.indices {
                if let link = sheet.nodes[index].link {
                    switch link.kind {
                    case .sheet:
                        guard case .worksheet(let value)? = WorksheetLink(link.target) else { break }
                        let destination = WorksheetLink.resolve(value, from: absolute)
                        if destination.starts(with: path.parts), insideSheet(Array(destination.dropFirst())) != nil {
                            sheet.nodes[index].link?.target = WorksheetLink.relative(from: absolute, to: destination)
                        } else if !value.hasPrefix("/") || value == "/.." || value.hasPrefix("/../") {
                            sheet.nodes[index].link?.target = "/" + destination.joined(separator: "/")
                        }
                    case .web:
                        if let reference = try? WebPresentationReference(link.target), let folders = insideSheet(reference.folders) {
                            sheet.nodes[index].link?.target = (folders + [reference.name + ".web"]).joined(separator: "/")
                        }
                    case .url: break
                    }
                }
                guard let file = sheet.nodes[index].file, let source = file.source, !file.isCommon else { continue }
                let sourceParts = source.isEmpty ? [] : source.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                if let folders = insideSheet(sourceParts) {
                    sheet.nodes[index].file?.source = folders.joined(separator: "/")
                } else if copy, let owner = try? WorksheetPath([path.parts[0]] + sourceParts),
                          let original = try sharedFile(owner, named: file.asset) {
                    let ext = original.pathExtension
                    let stem = original.deletingPathExtension().lastPathComponent
                    var name = original.lastPathComponent
                    var attempt = 2
                    while usedNames[key, default: []].contains(name) {
                        name = stem + "-" + String(attempt) + (ext.isEmpty ? "" : "." + ext)
                        attempt += 1
                    }
                    usedNames[key, default: []].insert(name)
                    entries.append(.init(path: zipPath(relative, name), source: .file(original)))
                    let asset = canvasAssetType(file.asset) != nil
                        ? UUID().uuidString.lowercased() + "." + file.asset.split(separator: ".").last!
                        : "file-" + UUID().uuidString.lowercased()
                    policies[key, default: DocumentPolicy()].mediaFiles = (policies[key]?.mediaFiles ?? [:]).merging([asset: name]) { $1 }
                    sheet.nodes[index].file?.asset = asset
                    sheet.nodes[index].file?.source = nil
                }
            }
        }

        func encoded(_ sheet: Worksheet) throws -> Data { try encoder.encode(sheet) + Data([10]) }

        for relative in sheets {
            let sheetPath = try WorksheetPath(path.parts + relative)
            let directory = try folder(sheetPath)
            let key = relative.joined(separator: "/")
            let name = sheetPath.name
            var local = try readPolicy(settingsURL(directory))
            local.passwordHash = nil
            if relative.isEmpty {
                local.owner = projectRule.owner
                local.editors = projectRule.editors
                local.guestReadable = projectRule.guestReadable
                let prefix = base.joined(separator: "/")
                var pages: [String: PageSettings] = [:]
                for (pageKey, value) in projectRule.worksheets ?? [:] {
                    let relativeKey = base.isEmpty ? pageKey : (pageKey.hasPrefix(prefix + "/") ? String(pageKey.dropFirst(prefix.count + 1)) : nil)
                    guard let relativeKey else { continue }
                    let folders = relativeKey.split(separator: "/").dropLast().map(String.init)
                    let sheetKey = folders.isEmpty ? "" : folders.joined(separator: "/")
                    guard sheetSet.contains(sheetKey), tree || sheetKey.isEmpty else { continue }
                    pages[relativeKey] = value
                }
                local.worksheets = pages.isEmpty ? nil : pages
            } else {
                local.owner = nil; local.editors = nil; local.guestReadable = nil; local.worksheets = nil
            }
            local.mediaFiles = (local.mediaFiles ?? [:]).merging(policies[key]?.mediaFiles ?? [:]) { $1 }
            policies[key] = local

            var sheet = try read(worksheetURL(sheetPath))
            try rewrite(&sheet, relative: relative, copy: copyExternal)
            entries.append(.init(path: zipPath(relative, name + ".thnode"), source: .data(try encoded(sheet))))

            for entry in try sortedContents(directory) {
                let filename = entry.lastPathComponent
                if filename == ".version" {
                    guard versions, isPlainDirectory(entry) else { continue }
                    for version in try sortedContents(entry) where version.pathExtension == "thnode" && isRegularFile(version) {
                        guard let data = try? Data(contentsOf: version), var old = try? Worksheet.decodeFile(data),
                              old.schemaVersion == Worksheet.currentSchema else { continue }
                        try rewrite(&old, relative: relative, copy: false)
                        entries.append(.init(path: zipPath(relative, ".version/" + version.lastPathComponent), source: .data(try encoded(old))))
                    }
                    continue
                }
                guard !filename.hasPrefix(".") else { continue }
                if isPlainDirectory(entry) {
                    guard entry.pathExtension == "web" else { continue }
                    try addWeb(entry, at: zipPath(relative, filename), to: &entries)
                } else if isRegularFile(entry), entry.pathExtension.lowercased() != "thnode" {
                    usedNames[key, default: []].insert(filename)
                    entries.append(.init(path: zipPath(relative, filename), source: .file(entry)))
                }
            }
        }
        for relative in sheets {
            let key = relative.joined(separator: "/")
            guard var policy = policies[key] else { continue }
            if policy.mediaFiles?.isEmpty == true { policy.mediaFiles = nil }
            entries.append(.init(path: zipPath(relative, ".settings.json"), source: .data(try encoder.encode(policy) + Data([10]))))
        }
        return (entries, projectRule.passwordHash)
    }

    /// .web mappa minden közönséges fájlja; a saját `.settings.json`-ból csak a nyilvánosság marad.
    private func addWeb(_ directory: URL, at prefix: String, to entries: inout [ZipWriter.Entry]) throws {
        guard let walker = files.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]) else { return }
        let base = directory.resolvingSymlinksInPath().pathComponents.count
        for case let url as URL in walker {
            guard isRegularFile(url) else { continue }
            let parts = Array(url.resolvingSymlinksInPath().pathComponents.dropFirst(base))
            if parts == [".settings.json"] {
                guard let policy = try? JSONDecoder().decode(DocumentPolicy.self, from: Data(contentsOf: url)), policy.guestReadable == true else { continue }
                entries.append(.init(path: prefix + "/.settings.json", source: .data(try encoder.encode(DocumentPolicy(guestReadable: true)))))
                continue
            }
            entries.append(.init(path: ([prefix] + parts).joined(separator: "/"), source: .file(url)))
        }
    }

    private func sortedContents(_ directory: URL) throws -> [URL] {
        try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func isPlainDirectory(_ url: URL) -> Bool {
        let info = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return info?.isDirectory == true && info?.isSymbolicLink != true
    }

    private func isRegularFile(_ url: URL) -> Bool {
        let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return info?.isRegularFile == true && info?.isSymbolicLink != true
    }

    // MARK: Import

    private struct PendingImport: Codable {
        package var user: String
        package var target: String?
        var encrypted: Bool
    }

    private func pendingDirectory(_ token: String) throws -> URL {
        guard token.hasPrefix("import-"), UUID(uuidString: String(token.dropFirst(7))) != nil else { throw Abort(.notFound) }
        let url = stagingRoot.appendingPathComponent(token)
        try rejectLink(url)
        guard files.fileExists(atPath: url.path) else { throw Abort(.gone, reason: "Az importálás lejárt; töltsd fel újra a csomagot.") }
        return url
    }

    private func pending(_ token: String, user: User?) throws -> (URL, PendingImport, WorksheetPath?) {
        let directory = try pendingDirectory(token)
        let info = try JSONDecoder().decode(PendingImport.self, from: Data(contentsOf: directory.appendingPathComponent("info.json")))
        guard let user, user.name == info.user else { throw Abort(.forbidden) }
        let target = try info.target.map { try WorksheetPath($0.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }) }
        return (directory, info, target)
    }

    /// Feltöltés (egyben) és kicsomagolás ideiglenes mappába. Titkosított csomagnál a jelszót a `unlockPackage` kéri.
    /// Nagy csomaghoz a darabolt feltöltés való (`beginPackageUpload` … `finishPackageUpload`).
    package func uploadPackage(_ bytes: Data, target: WorksheetPath?, user: User?, unlocks: Set<String>) throws -> PackageReport {
        try checkImportRights(target, user: user, unlocks: unlocks)
        guard bytes.count <= Self.maximumPackage else { throw Abort(.payloadTooLarge, reason: Self.packageTooLarge) }
        cleanPackageStaging()
        let temporary = try stagingDirectory().appendingPathComponent("single-" + UUID().uuidString + ".zip")
        try bytes.write(to: temporary)
        defer { try? files.removeItem(at: temporary) }
        return try stagePackage(temporary, target: target, user: user!)
    }

    private static let packageTooLarge = "A csomag legfeljebb 4 GiB lehet."

    // MARK: Darabolt, folytatható feltöltés
    // A kliens munkamenetet nyit (méret, cél), majd sorban küldi a darabokat; minden darab a fájl végéhez fűződik, és
    // csak akkor fogadható el, ha pontosan ott folytatja, ahol a szerver tart. Megszakadás után a kliens lekérdezi,
    // meddig jutott a feltöltés, és onnan folytatja – akár az oldal újratöltése vagy a szerver újraindítása után is.

    package struct PackageUploadState: Content, Equatable {
        package var id: String
        package var size: Int64
        package var received: Int64
        package var chunk: Int
    }

    private struct PendingUpload: Codable {
        var user: String
        var target: String?
        var size: Int64
    }

    private func uploadDirectory(_ id: String, user: User?) throws -> (URL, PendingUpload) {
        guard id.hasPrefix("upload-"), UUID(uuidString: String(id.dropFirst(7))) != nil else { throw Abort(.notFound) }
        let url = stagingRoot.appendingPathComponent(id)
        try rejectLink(url)
        guard files.fileExists(atPath: url.path),
              let info = try? JSONDecoder().decode(PendingUpload.self, from: Data(contentsOf: url.appendingPathComponent("info.json"))) else {
            throw Abort(.gone, reason: "A feltöltés lejárt; kezdd újra.")
        }
        guard let user, user.name == info.user else { throw Abort(.forbidden) }
        return (url, info)
    }

    private func received(_ directory: URL) -> Int64 {
        let size = (try? files.attributesOfItem(atPath: directory.appendingPathComponent("data.part").path)[.size]) as? NSNumber
        return size?.int64Value ?? 0
    }

    /// Új feltöltés: ellenőrzi a jogot, a méretet és a szabad lemezhelyet (a csomag és a kicsomagolt tartalom is elférjen).
    package func beginPackageUpload(size: Int64, target: WorksheetPath?, user: User?, unlocks: Set<String>) throws -> PackageUploadState {
        try checkImportRights(target, user: user, unlocks: unlocks)
        guard size > 0 else { throw Abort(.badRequest, reason: "Üres fájl.") }
        guard size <= Int64(Self.maximumPackage) else { throw Abort(.payloadTooLarge, reason: Self.packageTooLarge) }
        cleanPackageStaging()
        let staging = try stagingDirectory()
        if let free = try? staging.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free > 0, free < size * 5 / 2 + 256 * 1024 * 1024 {
            throw Abort(.insufficientStorage, reason: "Nincs elég szabad hely a szerveren ehhez a csomaghoz.")
        }
        // Felhasználónként néhány félbemaradt feltöltés maradhat; a legrégebbiek törlődnek.
        let own = ((try? files.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("upload-") }
            .filter { (try? JSONDecoder().decode(PendingUpload.self, from: Data(contentsOf: $0.appendingPathComponent("info.json"))))?.user == user!.name }
            .sorted { received($0) > received($1) }
        for stale in own.dropFirst(Self.uploadsPerUser - 1) { try? files.removeItem(at: stale) }
        let id = "upload-" + UUID().uuidString
        let directory = staging.appendingPathComponent(id)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            try JSONEncoder().encode(PendingUpload(user: user!.name, target: target?.url, size: size)).write(to: directory.appendingPathComponent("info.json"))
            guard files.createFile(atPath: directory.appendingPathComponent("data.part").path, contents: nil) else { throw Abort(.internalServerError) }
        } catch { try? files.removeItem(at: directory); throw error }
        return PackageUploadState(id: id, size: size, received: 0, chunk: Self.packageChunk)
    }

    /// Hol tart a feltöltés (folytatáshoz).
    package func packageUploadState(_ id: String, user: User?) throws -> PackageUploadState {
        try lock.withLock {
            let (directory, info) = try uploadDirectory(id, user: user)
            return PackageUploadState(id: id, size: info.size, received: received(directory), chunk: Self.packageChunk)
        }
    }

    /// Egy darab hozzáfűzése. Csak a szerver szerinti folytatási ponttól fogad el adatot: ha a kliens máshol tart
    /// (pl. egy megszakadt darab mégis megérkezett), 409-cel és a tényleges állással válaszol – a kliens onnan folytat.
    package func appendPackageUpload(_ id: String, offset: Int64, bytes: Data, user: User?) throws -> PackageUploadState {
        try lock.withLock {
            let (directory, info) = try uploadDirectory(id, user: user)
            let current = received(directory)
            guard offset == current else {
                throw Abort(.conflict, headers: ["X-ThinkNodes-Received": String(current)], reason: "A feltöltés máshol tart.")
            }
            guard !bytes.isEmpty, bytes.count <= Self.packageChunk * 2, current + Int64(bytes.count) <= info.size else {
                throw Abort(.badRequest, reason: "Érvénytelen darab.")
            }
            if current == 0, !bytes.starts(with: [0x50, 0x4b, 0x03, 0x04]) { throw Abort(.unsupportedMediaType, reason: "A fájl nem ZIP.") }
            let handle = try FileHandle(forWritingTo: directory.appendingPathComponent("data.part"))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
            return PackageUploadState(id: id, size: info.size, received: current + Int64(bytes.count), chunk: Self.packageChunk)
        }
    }

    /// A teljes fájl megérkezett: kicsomagolás és elemzés, ahogy az egyben feltöltött csomagnál.
    package func finishPackageUpload(_ id: String, user: User?, unlocks: Set<String>) throws -> PackageReport {
        let (directory, info) = try lock.withLock { try uploadDirectory(id, user: user) }
        guard received(directory) == info.size else { throw Abort(.conflict, reason: "A feltöltés még nem teljes.") }
        let target = try info.target.map { try WorksheetPath($0.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }) }
        try checkImportRights(target, user: user, unlocks: unlocks)
        defer { try? files.removeItem(at: directory) }
        return try stagePackage(directory.appendingPathComponent("data.part"), target: target, user: user!)
    }

    package func cancelPackageUpload(_ id: String, user: User?) throws {
        let (directory, _) = try lock.withLock { try uploadDirectory(id, user: user) }
        try files.removeItem(at: directory)
    }

    /// A feltöltött ZIP (`source`, áthelyezve) kicsomagolása ideiglenes mappába, és az import előkészítése.
    private func stagePackage(_ source: URL, target: WorksheetPath?, user: User) throws -> PackageReport {
        let head = try FileHandle(forReadingFrom: source)
        let magic = (try? head.read(upToCount: 4)) ?? Data()
        try? head.close()
        guard magic.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw Abort(.unsupportedMediaType, reason: "A fájl nem ZIP.") }
        let token = "import-" + UUID().uuidString
        let directory = try stagingDirectory().appendingPathComponent(token)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let archive = directory.appendingPathComponent("upload.zip")
            try files.moveItem(at: source, to: archive)
            let names = Set(try WebArchive.entries(archive).filter { !$0.hasPrefix("__MACOSX/") })
            let encrypted = names == [PackageCrypto.headerName, PackageCrypto.contentName]
            let info = PendingImport(user: user.name, target: target?.url, encrypted: encrypted)
            try JSONEncoder().encode(info).write(to: directory.appendingPathComponent("info.json"))
            if encrypted {
                try WebArchive.extractSafely(archive, into: directory.appendingPathComponent("sealed"), maximumEntries: 2,
                                             maximumExtracted: Self.maximumPackageExtracted, sizeMessage: "A csomag túl nagy.")
                _ = try PackageCrypto.checked(Data(contentsOf: directory.appendingPathComponent("sealed/" + PackageCrypto.headerName)))
                try files.removeItem(at: archive)
                return PackageReport(token: token, needsPassword: true, target: target == nil ? "project" : "sheet")
            }
            try extractTree(archive, in: directory)
            return try analyze(token: token, directory: directory, target: target, user: user)
        } catch {
            try? files.removeItem(at: directory)
            throw error
        }
    }

    package func unlockPackage(_ request: PackageUnlock, user: User?, unlocks: Set<String>) throws -> PackageReport {
        let (directory, info, target) = try pending(request.token, user: user)
        try checkImportRights(target, user: user, unlocks: unlocks)
        guard info.encrypted, !files.fileExists(atPath: directory.appendingPathComponent("tree").path) else { throw Abort(.conflict) }
        let sealed = directory.appendingPathComponent("sealed")
        let header = try PackageCrypto.checked(Data(contentsOf: sealed.appendingPathComponent(PackageCrypto.headerName)))
        let inner = directory.appendingPathComponent("inner.zip")
        defer { try? files.removeItem(at: inner) }
        do { try PackageCrypto.decrypt(sealed.appendingPathComponent(PackageCrypto.contentName), header: header, password: request.password, to: inner) }
        catch { try? files.removeItem(at: inner); throw error }
        try extractTree(inner, in: directory)
        try? files.removeItem(at: sealed)
        return try analyze(token: request.token, directory: directory, target: target, user: user!)
    }

    package func cancelPackage(_ token: String, user: User?) throws {
        let (directory, _, _) = try pending(token, user: user)
        try files.removeItem(at: directory)
    }

    private func checkImportRights(_ target: WorksheetPath?, user: User?, unlocks: Set<String>) throws {
        guard let user, user.role != .guest else { throw Abort(.forbidden, reason: "Importálni szerkesztő vagy admin tud.") }
        guard let target else { return }
        try lock.withLock {
            let access = accessLocked(try context(target), user: user, unlocks: unlocks)
            if access.locked { throw Abort(.locked, reason: "Ehhez a munkalaphoz jelszó szükséges.") }
            guard access.manageable, access.editable else { throw Abort(.forbidden, reason: "Ide csak a projekt szerkesztője vagy admin importálhat.") }
        }
    }

    private func extractTree(_ archive: URL, in directory: URL) throws {
        try WebArchive.extractSafely(archive, into: directory.appendingPathComponent("tree"), maximumEntries: Self.maximumPackageEntries,
                                     maximumExtracted: Self.maximumPackageExtracted, sizeMessage: "A kicsomagolt csomag legfeljebb 8 GiB lehet.")
        try? files.removeItem(at: archive)
    }

    /// A csomag gyökérlapja: egyetlen .thnode a ZIP gyökerében, vagy egyetlen mappa a vele azonos nevű .thnode-dal.
    private func packageRoot(_ tree: URL) throws -> (folder: URL, stem: String) {
        let visible = try sortedContents(tree).filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
        let sheets = visible.filter { $0.pathExtension.lowercased() == "thnode" && isRegularFile($0) }
        if sheets.count == 1 { return (tree, sheets[0].deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping) }
        if sheets.isEmpty, visible.count == 1, isPlainDirectory(visible[0]) {
            let folder = visible[0], name = folder.lastPathComponent
            if isRegularFile(folder.appendingPathComponent(name + ".thnode")) { return (folder, name.precomposedStringWithCanonicalMapping) }
        }
        throw Abort(.unprocessableEntity, reason: "A ZIP nem ThinkNodes-csomag: a gyökerében egy munkalap (.thnode) vagy egy azonos nevű mappa kell legyen.")
    }

    /// A csomag lapjai (gyökérhez viszonyítva) és a kimaradó mappák. A neveket NFC-re hozza.
    private func packageSheets(_ root: URL, stem: String, warnings: inout [String]) throws -> [(relative: [String], folder: URL, file: URL)] {
        var result: [(relative: [String], folder: URL, file: URL)] = [([], root, root.appendingPathComponent(stem + ".thnode"))]
        if !files.fileExists(atPath: result[0].file.path) {
            // NFD-ben tárolt gyökérfájlnév (pl. macOS-ről).
            guard let file = try sortedContents(root).first(where: {
                $0.pathExtension.lowercased() == "thnode" && $0.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping == stem
            }) else { throw Abort(.unprocessableEntity, reason: "A gyökérlap nem található.") }
            result[0].file = file
        }
        func visit(_ directory: URL, _ relative: [String]) throws {
            for var entry in try sortedContents(directory) where isPlainDirectory(entry) {
                let raw = entry.lastPathComponent
                guard !raw.hasPrefix("."), raw != "__MACOSX", entry.pathExtension != "web" else { continue }
                let name = raw.precomposedStringWithCanonicalMapping
                if name != raw {
                    let renamed = directory.appendingPathComponent(name)
                    try files.moveItem(at: entry, to: renamed)
                    entry = renamed
                }
                let file = try sortedContents(entry).first {
                    $0.pathExtension.lowercased() == "thnode" && $0.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping == name
                }
                guard let file, (try? WorksheetPath(["p"] + relative + [name])) != nil, relative.count < 10 else {
                    warnings.append("Kimarad (nem munkalap): " + (relative + [name]).joined(separator: "/"))
                    continue
                }
                result.append((relative + [name], entry, file))
                try visit(entry, relative + [name])
            }
        }
        try visit(root, [])
        return result
    }

    private func decodePackageSheet(_ url: URL, label: String) throws -> Worksheet {
        struct Version: Decodable { let schemaVersion: Int }
        let data = try Data(contentsOf: url)
        guard data.count <= 12 * 1024 * 1024 else { throw Abort(.payloadTooLarge, reason: "Túl nagy munkalap a csomagban: \(label)") }
        if let version = try? JSONDecoder().decode(Version.self, from: data), version.schemaVersion > Worksheet.currentSchema {
            throw Abort(.unprocessableEntity, reason: "A csomag újabb ThinkNodes-verzióval készült (\(version.schemaVersion). séma, ez a szerver: \(Worksheet.currentSchema)); frissítsd a szervert.")
        }
        do {
            var sheet = try Worksheet.decodeFile(data)
            sheet.schemaVersion = Worksheet.currentSchema
            try sheet.validate()
            return sheet
        } catch {
            throw Abort(.unprocessableEntity, reason: "Hibás munkalap a csomagban: \(label)")
        }
    }

    private func packagePolicy(_ folder: URL, label: String) throws -> DocumentPolicy {
        let url = folder.appendingPathComponent(".settings.json")
        guard isRegularFile(url) else { return DocumentPolicy() }
        guard let policy = try? JSONDecoder().decode(DocumentPolicy.self, from: Data(contentsOf: url)) else {
            throw Abort(.unprocessableEntity, reason: "Hibás beállításfájl a csomagban: \(label)")
        }
        return policy
    }

    private func analyze(token: String, directory: URL, target: WorksheetPath?, user: User) throws -> PackageReport {
        let tree = directory.appendingPathComponent("tree")
        let (root, stem) = try packageRoot(tree)
        var warnings: [String] = []
        let sheets = try packageSheets(root, stem: stem, warnings: &warnings)
        let sheetSet = Set(sheets.map { $0.relative.joined(separator: "/") })
        var policies: [String: DocumentPolicy] = [:]
        var fileCount = 0
        var bytes: Int64 = 0
        for sheet in sheets {
            let label = ([stem] + sheet.relative).joined(separator: "/")
            policies[sheet.relative.joined(separator: "/")] = try packagePolicy(sheet.folder, label: label)
        }
        if let walker = files.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            for case let url as URL in walker where isRegularFile(url) {
                fileCount += 1
                bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        func fileExists(_ folder: String, _ asset: String) -> Bool {
            guard let sheet = sheets.first(where: { $0.relative.joined(separator: "/") == folder }) else { return false }
            let name = policies[folder]?.mediaFiles?[asset] ?? asset
            return validImageStem(name) && isRegularFile(sheet.folder.appendingPathComponent(name))
        }
        for sheet in sheets {
            let label = ([stem] + sheet.relative).joined(separator: "/")
            let content = try decodePackageSheet(sheet.file, label: label)
            var missing = Set<String>()
            for node in content.nodes {
                if let link = node.link {
                    switch link.kind {
                    case .sheet:
                        guard case .worksheet(let value)? = WorksheetLink(link.target) else { break }
                        let relative = !value.hasPrefix("/") || value == "/.." || value.hasPrefix("/../")
                        if relative {
                            let destination = WorksheetLink.resolve(value, from: ["§"] + sheet.relative)
                            if destination.first != "§" || !sheetSet.contains(destination.dropFirst().joined(separator: "/")) { missing.insert(value) }
                        } else {
                            let parts = WorksheetLink.resolve(value, from: [])
                            if !parts.isEmpty, (try? WorksheetPath(parts)).map(pageExists) != true { missing.insert(value) }
                        }
                    case .web:
                        let reference = try? WebPresentationReference(link.target)
                        let folder = reference?.folders.joined(separator: "/") ?? ""
                        if reference == nil || !sheetSet.contains(folder)
                            || !isPlainDirectory(sheets.first { $0.relative.joined(separator: "/") == folder }!.folder.appendingPathComponent(reference!.name + ".web")) {
                            missing.insert(link.target)
                        }
                    case .url: break
                    }
                }
                if let file = node.file, !file.isCommon, !fileExists(file.source ?? sheet.relative.joined(separator: "/"), file.asset) {
                    missing.insert(file.filename ?? file.asset)
                }
            }
            for item in missing.sorted() { warnings.append("Nem található hivatkozás (\(label)): \(item)") }
        }
        let suggested = try lock.withLock { () throws -> String in
            let parent = try target.map { try folder($0) } ?? root
            var base = (try? WorksheetPath([stem])) != nil ? stem : WebArchive.folderName(stem)
            // „web” nevű mappában nem lehet .web prezentációra hivatkozni (a prezentációk címében foglalt).
            if target != nil && base == "web" { base = "web-lap" }
            for attempt in 1...999 {
                let name = attempt == 1 ? base : base + "-" + String(attempt)
                let url = target == nil ? self.root.appendingPathComponent(name) : parent.appendingPathComponent(name)
                if !files.fileExists(atPath: url.path), !files.fileExists(atPath: url.appendingPathExtension("thnode").path) { return name }
            }
            return base
        }
        var report = PackageReport(token: token, needsPassword: false, target: target == nil ? "project" : "sheet", name: suggested,
                                   sheets: sheets.count, files: fileCount, bytes: bytes, warnings: warnings.isEmpty ? nil : warnings)
        if target == nil {
            let rootPolicy = policies[""] ?? DocumentPolicy()
            let editors = try lock.withLock { try readUsers().filter { $0.role == .editor }.map(\.name) }
            var names: [String] = []
            for name in [rootPolicy.owner].compactMap({ $0 }) + (rootPolicy.editors ?? []) where name != user.name && !names.contains(name) {
                names.append(name)
            }
            report.editors = names.map { PackageEditor(name: $0, match: editors.contains($0) ? $0 : nil) }
            report.users = editors.filter { $0 != user.name }.sorted()
        }
        return report
    }

    /// Jóváhagyás: a csomag átírása az új helyre, majd áthelyezés egy lépésben.
    package func commitPackage(_ request: PackageCommit, user: User?, unlocks: Set<String>) throws -> WorksheetPath {
        let (directory, _, target) = try pending(request.token, user: user)
        try checkImportRights(target, user: user, unlocks: unlocks)
        let user = user!
        let tree = directory.appendingPathComponent("tree")
        guard files.fileExists(atPath: tree.path) else { throw Abort(.conflict, reason: "Előbb add meg a csomagjelszót.") }
        let name = request.name.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces)
        let destination = try WorksheetPath((target?.parts ?? []) + [name])
        let passwordHash: String?
        if target == nil, let password = request.projectPassword, !password.isEmpty {
            guard password.utf8.count <= 72 else { throw Abort(.badRequest) }
            passwordHash = try Bcrypt.hash(password)
        } else { passwordHash = nil }
        let (root, stem) = try packageRoot(tree)
        var ignored: [String] = []
        let sheets = try packageSheets(root, stem: stem, warnings: &ignored)
        let sheetSet = Set(sheets.map { $0.relative.joined(separator: "/") })
        for sheet in sheets { _ = try WorksheetPath(destination.parts + sheet.relative) }
        let prefix = Array(destination.parts.dropFirst())
        let users = try lock.withLock { try readUsers() }

        func adopt(_ sheet: inout Worksheet, main: Bool) {
            if main {
                sheet.creator = user.name
                sheet.revision = 1
                sheet.resetRevision = nil
            }
            for index in sheet.nodes.indices {
                if let link = sheet.nodes[index].link, link.kind == .web, let reference = try? WebPresentationReference(link.target) {
                    sheet.nodes[index].link?.target = (prefix + reference.folders + [reference.name + ".web"]).joined(separator: "/")
                }
                if let file = sheet.nodes[index].file, let source = file.source, !file.isCommon {
                    let parts = source.isEmpty ? [] : source.split(separator: "/").map(String.init)
                    sheet.nodes[index].file?.source = (prefix + parts).joined(separator: "/")
                }
            }
        }

        // 1. menet: minden lap átírása és ellenőrzése a memóriában; hiba esetén a csomag érintetlen (más névvel újrapróbálható).
        var adopted: [Worksheet] = []
        for sheet in sheets {
            let label = ([stem] + sheet.relative).joined(separator: "/")
            var content = try decodePackageSheet(sheet.file, label: label)
            adopt(&content, main: true)
            do { try content.validate() } catch {
                let webLinks = content.nodes.contains { $0.link?.kind == .web }
                throw Abort(.unprocessableEntity, reason: webLinks && (prefix + sheet.relative).contains("web")
                    ? "A(z) „\(label)” lap .web prezentációra hivatkozik, ezért az útvonalában nem lehet „web” nevű mappa. Válassz másik nevet."
                    : "A(z) „\(label)” lap ide nem importálható.")
            }
            adopted.append(content)
        }

        // 2. menet: írás a csomag ideiglenes mappájában.
        var movedPages: [String: PageSettings] = [:]
        for (index, sheet) in sheets.enumerated() {
            let label = ([stem] + sheet.relative).joined(separator: "/")
            let sheetName = sheet.relative.last ?? name
            try files.removeItem(at: sheet.file)
            try write(adopted[index], to: sheet.folder.appendingPathComponent(sheetName + ".thnode"))

            var policy = try packagePolicy(sheet.folder, label: label)
            policy.passwordHash = nil
            if sheet.relative.isEmpty {
                var pages: [String: PageSettings] = [:]
                for (key, value) in policy.worksheets ?? [:] {
                    var parts = key.split(separator: "/").map(String.init)
                    guard let file = parts.last, sheetSet.contains(parts.dropLast().joined(separator: "/")) else { continue }
                    if parts.count == 1 {
                        guard file.precomposedStringWithCanonicalMapping == stem + ".thnode" else { continue }
                        parts = [name + ".thnode"]
                    }
                    pages[parts.joined(separator: "/")] = value
                }
                if target == nil {
                    let available = Set(users.filter { $0.role == .editor }.map(\.name))
                    let mapped = (policy.editors ?? []) + [policy.owner].compactMap { $0 }
                    let editors = Set(mapped.compactMap { request.editors?[$0] }.filter { available.contains($0) && $0 != user.name })
                    policy.owner = user.name
                    policy.editors = editors.isEmpty ? nil : editors.sorted()
                    policy.guestReadable = policy.guestReadable ?? false
                    policy.passwordHash = passwordHash
                    policy.worksheets = pages.isEmpty ? nil : pages
                } else {
                    let base = prefix.dropLast().joined(separator: "/")
                    for (key, value) in pages {
                        let parts = key.split(separator: "/").map(String.init)
                        let relocated = parts.count == 1 ? [name, name + ".thnode"] : [name] + parts
                        movedPages[((base.isEmpty ? [] : [base]) + relocated).joined(separator: "/")] = value
                    }
                    policy.owner = nil; policy.editors = nil; policy.guestReadable = nil; policy.worksheets = nil
                }
            } else {
                policy.owner = nil; policy.editors = nil; policy.guestReadable = nil; policy.worksheets = nil
            }
            try write(policy, to: sheet.folder.appendingPathComponent(".settings.json"))

            // Tisztítás: rejtett fájlok (előnézeti gyorsítótár stb.), nem munkalap mappák, hibás mentett állapotok.
            let children = Set(sheets.filter { $0.relative.count == sheet.relative.count + 1 && $0.relative.starts(with: sheet.relative) }.map { $0.folder.lastPathComponent })
            for entry in try sortedContents(sheet.folder) {
                let filename = entry.lastPathComponent
                if filename == ".settings.json" || filename == sheetName + ".thnode" { continue }
                if filename == ".version", isPlainDirectory(entry) {
                    for version in try sortedContents(entry) {
                        guard version.pathExtension == "thnode", isRegularFile(version), (try? WorksheetPath(["p", version.deletingPathExtension().lastPathComponent])) != nil,
                              var old = try? decodePackageSheet(version, label: label) else {
                            try files.removeItem(at: version)
                            continue
                        }
                        adopt(&old, main: false)
                        if (try? old.validate()) == nil { try files.removeItem(at: version); continue }
                        try write(old, to: version)
                    }
                    continue
                }
                if filename.hasPrefix(".") { try files.removeItem(at: entry); continue }
                if isPlainDirectory(entry) {
                    if entry.pathExtension == "web" { try cleanWeb(entry) }
                    else if !children.contains(filename) { try files.removeItem(at: entry) }
                } else if !isRegularFile(entry) || entry.pathExtension.lowercased() == "thnode" || !validImageStem(filename) {
                    try files.removeItem(at: entry)
                }
            }
        }

        try lock.withLock {
            let place: URL
            if let target {
                let ctx = try context(target)
                let access = accessLocked(ctx, user: user, unlocks: unlocks)
                guard access.manageable, access.editable, !access.locked else { throw Abort(.forbidden) }
                place = ctx.directory.appendingPathComponent(name)
            } else {
                place = self.root.appendingPathComponent(name)
            }
            try rejectLink(place)
            guard !files.fileExists(atPath: place.path), !files.fileExists(atPath: place.appendingPathExtension("thnode").path) else {
                throw Abort(.conflict, reason: "Ez a név már foglalt: \(name)")
            }
            try files.moveItem(at: root, to: place)
            guard let target, !movedPages.isEmpty else { return }
            do {
                let ctx = try context(target)
                var next = ctx
                next.rules[ctx.project]?.worksheets = (ctx.rules[ctx.project]?.worksheets ?? [:]).merging(movedPages) { $1 }
                try persist(next, previous: ctx)
            } catch {
                try? files.moveItem(at: place, to: root)
                throw error
            }
        }
        try? files.removeItem(at: directory)
        return destination
    }

    /// .web mappa importáláskor: a saját beállításból csak a nyilvánosság marad.
    private func cleanWeb(_ directory: URL) throws {
        let url = directory.appendingPathComponent(".settings.json")
        guard files.fileExists(atPath: url.path) else { return }
        let policy = try? JSONDecoder().decode(DocumentPolicy.self, from: Data(contentsOf: url))
        try files.removeItem(at: url)
        if policy?.guestReadable == true { try write(DocumentPolicy(guestReadable: true), to: url) }
    }
}
