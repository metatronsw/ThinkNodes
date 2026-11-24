import Foundation
import Vapor
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct WebPresentationReference: Sendable {
    let folders: [String]
    let name: String

    init(_ reference: String) throws {
        let parts = reference.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let directory = parts.last, directory.hasSuffix(".web") else { throw Abort(.notFound) }
        let checked = try WorksheetPath(["project"] + parts.dropLast() + [String(directory.dropLast(4))])
        let folders = Array(checked.parts.dropFirst().dropLast())
        guard !folders.contains("web") else { throw Abort(.notFound) }
        self.folders = folders
        name = checked.name
    }

    var relativePath: String { (folders + [name + ".web"]).joined(separator: "/") }

    func url(in project: String) -> String {
        "/" + ([project] + folders + ["web", name]).map(WorksheetPath.encodeSegment).joined(separator: "/") + "/"
    }
}

struct WebPresentationRequest: Sendable {
    let project: String
    let reference: WebPresentationReference
    let asset: [String]
    let trailingSlash: Bool
    let lease: UUID?

    var scope: String { reference.url(in: project) }

    func assetScope(_ lease: UUID) -> String { scope + "_tn-assets/" + lease.uuidString + "/" }

    var url: String {
        let base = scope
        if asset.isEmpty { return trailingSlash ? base : String(base.dropLast()) }
        return base + asset.map(Self.encodeAsset).joined(separator: "/") + (trailingSlash ? "/" : "")
    }

    static func matches(_ raw: String) -> Bool {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 3, parts.first?.isEmpty == true,
              let project = parts[1].removingPercentEncoding, (try? WorksheetPath([project])) != nil else { return false }
        return parts.dropFirst(2).dropLast().contains { $0.removingPercentEncoding == "web" }
    }

    static func candidates(_ raw: String) throws -> [Self] {
        guard matches(raw), raw.utf8.count <= 4096 else { return [] }
        let trailingSlash = raw.hasSuffix("/")
        var pieces = raw.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        if trailingSlash { pieces.removeLast() }
        let decoded = try pieces.map { part -> String in
            guard let value = part.removingPercentEncoding, validAssetSegment(value) else { throw Abort(.notFound) }
            return value
        }
        guard decoded.count <= 64 else { throw Abort(.notFound) }
        return decoded.indices.dropFirst().dropLast().compactMap { index in
            guard decoded[index] == "web",
                  let path = try? WorksheetPath(Array(decoded[..<index])),
                  let project = path.parts.first,
                  let reference = try? WebPresentationReference((Array(path.parts.dropFirst()) + [decoded[index + 1] + ".web"]).joined(separator: "/"))
            else { return nil }
            var asset = Array(decoded.dropFirst(index + 2))
            var lease: UUID?
            if asset.first == "_tn-assets" {
                guard asset.count >= 2, let id = UUID(uuidString: asset[1]) else { return nil }
                lease = id
                asset.removeFirst(2)
            }
            return Self(project: project, reference: reference, asset: asset, trailingSlash: trailingSlash, lease: lease)
        }
    }

    static func encodeAsset(_ value: String) -> String {
        WorksheetPath.encodeSegment(value).replacingOccurrences(of: "%2E", with: ".")
    }

    private static func validAssetSegment(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && !value.hasPrefix(".") &&
            !value.contains("/") && !value.contains("\\") && !value.contains(":") && !value.contains("%") &&
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
            (value as NSString).pathExtension.lowercased() != "thnode"
    }
}

struct WebPresentationInfo: Content {
    let reference: String
    let title: String
    let url: String
    let preview: String?
    let manageable: Bool
    let publicWeb: Bool
}

struct WebPresentationSettings: Content {
    let reference: String
    let publicWeb: Bool
}

struct WebAsset: Sendable {
    let handle: FileHandle
    let size: Int
    let name: String

    static func open(in root: URL, folders: [String], asset: [String], trailingSlash: Bool) throws -> (WebAsset, directory: Bool) {
        var directory = root.path.withCString { systemOpen($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard directory >= 0 else { throw Abort(.notFound) }
        defer { close(directory) }

        for folder in folders + asset.dropLast() {
            let next = folder.withCString { openat(directory, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { throw Abort(.notFound) }
            close(directory)
            directory = next
        }

        func openEntry(_ name: String) throws -> (Int32, stat) {
            let descriptor = name.withCString { openat(directory, $0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
            guard descriptor >= 0 else { throw Abort(.notFound) }
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { close(descriptor); throw Abort(.notFound) }
            return (descriptor, info)
        }

        var name = asset.last ?? "index.html"
        var (descriptor, info) = asset.isEmpty ? (-1, stat()) : try openEntry(name)
        let isDirectory = asset.isEmpty || (info.st_mode & S_IFMT) == S_IFDIR
        if isDirectory {
            if !asset.isEmpty {
                close(directory)
                directory = descriptor
            }
            name = indexName(in: directory)
            (descriptor, info) = try openEntry(name)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_size >= 0,
              (!trailingSlash || isDirectory), let size = Int(exactly: info.st_size) else {
            close(descriptor)
            throw Abort(.notFound)
        }
        return (.init(handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), size: size, name: name), isDirectory)
    }

    /// `index.html`, or the only HTML page of a folder exported under another name (e.g. `code.html`).
    private static func indexName(in directory: Int32) -> String {
        let copy = dup(directory)
        guard copy >= 0 else { return "index.html" }
        guard let stream = fdopendir(copy) else { close(copy); return "index.html" }
        defer { closedir(stream) }
        var pages: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if name == "index.html" { return name }
            let ext = (name as NSString).pathExtension.lowercased()
            if !name.hasPrefix("."), ext == "html" || ext == "htm" { pages.append(name) }
        }
        return pages.count == 1 ? pages[0] : "index.html"
    }

    var mime: String {
        let extensionTypes = [
            "html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8",
            "css": "text/css; charset=utf-8", "js": "text/javascript; charset=utf-8", "mjs": "text/javascript; charset=utf-8",
            "json": "application/json", "svg": "image/svg+xml", "png": "image/png",
            "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
            "ico": "image/x-icon", "woff": "font/woff", "woff2": "font/woff2", "txt": "text/plain; charset=utf-8",
            "mp4": "video/mp4", "webm": "video/webm", "pdf": "application/pdf"
        ]
        return extensionTypes[(name as NSString).pathExtension.lowercased()] ?? "application/octet-stream"
    }

    var isHTML: Bool { mime.hasPrefix("text/html") }

    func response(to req: Request, baseURL: String? = nil) async throws -> Response {
        let range = try baseURL == nil ? byteRange(for: req.headers) : nil
        let prefix: Data
        let consumed: Int
        if let baseURL {
            let sample = try await req.application.threadPool.runIfActive { try handle.read(upToCount: min(size, 16 * 1024)) ?? Data() }
            let start = String(decoding: sample, as: UTF8.self)
            // Keep a leading BOM and doctype ahead of the injected base element.
            let initial = start.range(of: #"(?is)\A(?:\x{FEFF}|[ \t\r\n]|<!--.*?-->)*(?:<!doctype\s[^>]*>)?"#, options: .regularExpression)
            let offset = min(sample.count, initial.map { start[..<$0.upperBound].utf8.count } ?? 0)
            prefix = sample.prefix(offset) + Data("<base href=\"\(escaped(baseURL))\">".utf8) + sample.dropFirst(offset)
            consumed = sample.count
        } else {
            prefix = Data()
            consumed = 0
        }
        var headers: HTTPHeaders = ["Content-Type": mime, "Cache-Control": "no-store",
                                    "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
                                    "X-Frame-Options": "DENY"]
        if baseURL == nil { headers.replaceOrAdd(name: .acceptRanges, value: "bytes") }
        // The sandbox gives the document an opaque origin, where some browsers no longer
        // match 'self' against the server. Name the serving origin explicitly; remote
        // HTTPS resources (CDN scripts, web fonts) stay usable inside the sandbox.
        let own = Self.origin(of: req).map { "'self' " + $0 } ?? "'self'"
        headers.replaceOrAdd(name: "Content-Security-Policy", value: """
            sandbox allow-scripts allow-popups allow-popups-to-escape-sandbox; default-src 'none'; \
            script-src \(own) 'unsafe-inline' 'unsafe-eval' https:; style-src \(own) 'unsafe-inline' https:; \
            img-src \(own) data: blob: https:; font-src \(own) data: https:; media-src \(own) blob: https:; \
            connect-src \(own) https:; object-src 'none'; base-uri \(baseURL == nil ? "'none'" : own); \
            form-action 'none'; frame-ancestors 'none'
            """)
        if let range { headers.replaceOrAdd(name: .contentRange, value: "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(size)") }
        let bytes = range ?? 0..<size
        let body = Response.Body(asyncStream: { stream in
            do {
                if !prefix.isEmpty { try await stream.writeBuffer(ByteBuffer(bytes: prefix)) }
                try await req.application.threadPool.runIfActive { try handle.seek(toOffset: UInt64(bytes.lowerBound + consumed)) }
                var remaining = bytes.count - consumed
                while remaining > 0 {
                    let length = min(64 * 1024, remaining)
                    let data = try await req.application.threadPool.runIfActive { try handle.read(upToCount: length) }
                    guard let data, !data.isEmpty else { throw Abort(.internalServerError) }
                    remaining -= data.count
                    try await stream.writeBuffer(ByteBuffer(bytes: data))
                }
                try await stream.write(.end)
            } catch {
                try? await stream.write(.error(error))
            }
        }, count: bytes.count - consumed + prefix.count, byteBufferAllocator: req.byteBufferAllocator)
        return Response(status: range == nil ? .ok : .partialContent, headers: headers, body: body)
    }

    /// Origin of the server as the browser addressed it, as a CSP host source.
    static func origin(of req: Request) -> String? {
        guard let host = req.headers.first(name: .host), !host.isEmpty, host.utf8.count <= 255,
              host.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || ".-:[]".unicodeScalars.contains($0) })
        else { return nil }
        let tls = req.application.http.server.configuration.tlsConfiguration != nil ||
            req.headers.first(name: "X-Forwarded-Proto")?.lowercased() == "https"
        return (tls ? "https://" : "http://") + host.lowercased()
    }

    private func byteRange(for headers: HTTPHeaders) throws -> Range<Int>? {
        guard headers.contains(name: .range) else { return nil }
        let invalid = Abort(.rangeNotSatisfiable, headers: ["Content-Range": "bytes */\(size)"])
        guard size > 0, let range = headers.range, range.unit == .bytes, range.ranges.count == 1,
              let value = range.ranges.first else { throw invalid }
        switch value {
        case .start(let start):
            guard (0..<size).contains(start) else { throw invalid }
            return start..<size
        case .tail(let length):
            guard length > 0 else { throw invalid }
            return (size - min(length, size))..<size
        case .within(let start, let end):
            guard (0..<size).contains(start), end >= start else { throw invalid }
            return start..<(min(end, size - 1) + 1)
        }
    }
}

private func systemOpen(_ path: UnsafePointer<CChar>, _ flags: Int32) -> Int32 {
    #if canImport(Darwin)
    Darwin.open(path, flags)
    #else
    Glibc.open(path, flags)
    #endif
}

final class WebPresentationSessions: @unchecked Sendable {
    static let cookieName = "thinknodes_web_asset"
    private struct Grant {
        let session: SessionID
        let scope: String
        let secret: String
        let expires: Date
    }

    let requireCookie: Bool
    private let lock = NSLock()
    private var grants: [UUID: Grant] = [:]

    init(requireCookie: Bool = true) { self.requireCookie = requireCookie }

    func issue(session: SessionID, scope: String) -> (id: UUID, secret: String, expires: Date) {
        lock.withLock {
            let now = Date()
            grants = grants.filter { $0.value.expires > now }
            if let existing = grants.first(where: { $0.value.session == session && $0.value.scope == scope }) {
                return (existing.key, existing.value.secret, existing.value.expires)
            }
            let id = UUID()
            let grant = Grant(session: session, scope: scope, secret: UUID().uuidString, expires: now.addingTimeInterval(8 * 3600))
            grants[id] = grant
            return (id, grant.secret, grant.expires)
        }
    }

    func session(lease: UUID, scope: String, cookie: String?) -> SessionID? {
        lock.withLock {
            guard let grant = grants[lease], grant.expires > .now, grant.scope == scope,
                  !requireCookie || grant.secret == cookie else { return nil }
            return grant.session
        }
    }
}

/// Feltöltött weboldal-csomag (.zip) ellenőrzése és kicsomagolása. A `unzip` parancsot használja.
enum WebArchive {
    static let maximumArchive = 100 * 1024 * 1024
    static let maximumExtracted: Int64 = 300 * 1024 * 1024
    static let maximumEntries = 5_000

    /// A .web mappa neve a ZIP fájlnévből: csak betű, szám, `_` és `-` marad.
    static func folderName(_ filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension.precomposedStringWithCanonicalMapping
        var result = ""
        for scalar in stem.unicodeScalars {
            let allowed = CharacterSet.letters.union(.decimalDigits).union(.nonBaseCharacters).contains(scalar) || scalar == "_" || scalar == "-"
            result.unicodeScalars.append(allowed ? scalar : "_")
        }
        while result.contains("__") { result = result.replacingOccurrences(of: "__", with: "_") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        return String((result.isEmpty ? "weboldal" : result).prefix(80))
    }

    private static func unzip(_ arguments: [String]) throws -> String {
        let process = Process()
        let candidates = ["/usr/bin/unzip", "/bin/unzip", "/usr/local/bin/unzip", "/opt/homebrew/bin/unzip"]
        guard let tool = candidates.first(where: FileManager.default.isExecutableFile) else {
            throw Abort(.internalServerError, reason: "A szerveren nincs telepítve az unzip.")
        }
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus <= 1 else { throw Abort(.unprocessableEntity, reason: "A ZIP fájl sérült vagy nem olvasható.") }
        return String(decoding: data, as: UTF8.self)
    }

    /// Kicsomagolja a csomagot a `destination` (még nem létező) mappába, és visszaadja a weboldal gyökerét.
    static func extract(_ archive: URL, into destination: URL) throws -> URL {
        let files = FileManager.default
        try extractSafely(archive, into: destination, maximumEntries: maximumEntries, maximumExtracted: maximumExtracted,
                          sizeMessage: "A kicsomagolt weboldal legfeljebb 300 MiB lehet.")
        do {
            // 4. Ha minden egy közös gyökérmappában van (Finder-tömörítés), az a weboldal gyökere.
            var site = destination
            while true {
                let content = try files.contentsOfDirectory(at: site, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                guard content.count == 1, try content[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                      !hasPage(site) else { break }
                site = content[0]
            }
            guard hasPage(site) else {
                throw Abort(.unprocessableEntity, headers: ["X-ThinkNodes-Not-Website": "1"],
                            reason: "A ZIP-ben nincs index.html (vagy egyetlen .html oldal).")
            }
            // A feltöltő nem állíthat be hozzáférési szabályt a csomaggal.
            try? files.removeItem(at: site.appendingPathComponent(".settings.json"))
            return site
        } catch {
            try? files.removeItem(at: destination)
            throw error
        }
    }

    /// Biztonságos kicsomagolás a `destination` (még nem létező) mappába: nincs abszolút út, `..`, visszaper,
    /// vezérlőkarakter, szimbolikus link; korlátozott darabszám és kicsomagolt méret (zip-bomba ellen).
    static func extractSafely(_ archive: URL, into destination: URL, maximumEntries: Int, maximumExtracted: Int64, sizeMessage: String) throws {
        let files = FileManager.default
        // 1. Bejegyzések.
        let entries = try unzip(["-Z1", archive.path]).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard !entries.isEmpty else { throw Abort(.unprocessableEntity, reason: "A ZIP fájl üres.") }
        guard entries.count <= maximumEntries else { throw Abort(.payloadTooLarge, reason: "A ZIP legfeljebb \(maximumEntries) fájlt tartalmazhat.") }
        for entry in entries {
            let parts = entry.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.hasPrefix("/"), !entry.contains("\\"), !parts.contains(".."),
                  !entry.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw Abort(.unprocessableEntity, reason: "A ZIP érvénytelen útvonalat tartalmaz: \(entry)")
            }
        }
        // 2. Kicsomagolt méret és szimbolikus linkek a fejlécek alapján.
        let listing = try unzip(["-Zl", archive.path])
        var total: Int64 = 0
        for line in listing.split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 9, let mode = columns.first, mode.count == 10, let size = Int64(columns[3]) else { continue }
            if mode.hasPrefix("l") { throw Abort(.unprocessableEntity, reason: "A ZIP szimbolikus linket tartalmaz.") }
            total += size
        }
        guard total <= maximumExtracted else { throw Abort(.payloadTooLarge, reason: sizeMessage) }

        try files.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            _ = try unzip(["-qq", "-n", archive.path, "-x", "__MACOSX/*", "*.DS_Store", "-d", destination.path])
            // 3. Utólagos ellenőrzés: csak közönséges fájl és mappa maradhat.
            var size: Int64 = 0
            if let walker = files.enumerator(at: destination, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]) {
                for case let url as URL in walker {
                    let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
                    guard info.isSymbolicLink != true, info.isRegularFile == true || info.isDirectory == true else {
                        throw Abort(.unprocessableEntity, reason: "A ZIP nem támogatott fájltípust tartalmaz.")
                    }
                    size += Int64(info.fileSize ?? 0)
                    guard size <= maximumExtracted else { throw Abort(.payloadTooLarge, reason: sizeMessage) }
                }
            }
        } catch {
            try? files.removeItem(at: destination)
            throw error
        }
    }

    /// A ZIP bejegyzéseinek listája (útvonalak).
    static func entries(_ archive: URL) throws -> [String] {
        try unzip(["-Z1", archive.path]).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private static func hasPage(_ directory: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        if names.contains("index.html") { return true }
        return names.filter { !$0.hasPrefix(".") && ["html", "htm"].contains(($0 as NSString).pathExtension.lowercased()) }.count == 1
    }
}

/// .web előnézet. Keresési sorrend (`find`):
/// 1. saját, Chromiummal generált kép a .web mappa mellett, mindig csak egy: `.név.web.tn-preview.webp` (tartalék: `.jpg`)
///    (generálás bekapcsolva: más aránynál felülíródik; kikapcsolva: a meglévő kép vágódik);
/// 2. a mappa gyökerében preview / screen / screenshot / thumbnail / thumb / site / cover / og-image / social nevű kép;
/// 3. bármely kép a mappában (először a gyökérben);
/// 4. nil: a szerver helyettes „nincs elérhető előnézet” SVG-t ad.
enum WebScreenshot {
    static let width = 1280
    static let marker = ".tn-preview"
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "svg", "avif"]
    static let previewNames = ["preview", "screen", "screenshot", "thumbnail", "thumb", "site", "cover", "og-image", "social", "poster"]

    /// Előnézet mérete: a doboz mérete vászonegységben (= CSS-pixel a 0-s szinten), 8-as lépésekre kerekítve.
    static func boxSize(width: Double?, height: Double?) -> (width: Int, height: Int)? {
        guard let width, let height, width.isFinite, height.isFinite else { return nil }
        func step(_ value: Double) -> Int { Int((min(max(value, 64), 4096) / 8).rounded()) * 8 }
        return (step(width), step(height))
    }

    /// Azonnal válaszol: friss kép, ha van; különben ütemezi a renderelést, és addig a meglévő képet adja.
    static func find(in directory: URL, size: (width: Int, height: Int)?) -> WebAsset? {
        if let size {
            if let current = fresh(directory, size: size) { return asset(current) }
            schedule(directory, size: size)
        }
        if let generated = generated(for: directory).filter(regularFile).first { return asset(generated) }
        if let named = namedImage(in: directory) { return asset(named) }
        if let any = anyImage(in: directory) { return asset(any) }
        return nil
    }

    private static func asset(_ url: URL) -> WebAsset? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int else { return nil }
        return WebAsset(handle: handle, size: size, name: url.lastPathComponent)
    }

    private static func regularFile(_ url: URL) -> Bool {
        let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return info?.isRegularFile == true && info?.isSymbolicLink != true
    }

    private static func images(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles])) ?? [])
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) && regularFile($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func namedImage(in directory: URL) -> URL? {
        let candidates = images(in: directory)
        for name in previewNames {
            if let match = candidates.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == name }) { return match }
        }
        return nil
    }

    private static func anyImage(in directory: URL) -> URL? {
        if let first = images(in: directory).first { return first }
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var checked = 0
        for case let url as URL in walker {
            checked += 1
            if checked > 5_000 || walker.level > 4 { walker.skipDescendants() }
            if checked > 5_000 { return nil }
            if imageExtensions.contains(url.pathExtension.lowercased()) && regularFile(url) { return url }
        }
        return nil
    }

    private static func modified(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }

    static let browser: String? = {
        if let configured = ProcessInfo.processInfo.environment["THINKNODES_CHROMIUM"], !configured.isEmpty {
            return FileManager.default.isExecutableFile(atPath: configured) ? configured : nil
        }
        let candidates = ["/usr/lib64/chromium-browser/headless_shell", "/usr/bin/chromium-browser", "/usr/bin/chromium", "/usr/bin/google-chrome", "/usr/bin/headless_shell",
            "/Applications/Chromium.app/Contents/MacOS/Chromium", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/opt/homebrew/bin/chromium", "/usr/local/bin/chromium",
            // Helyi fejlesztés: Chrome for Testing headless shell a ~/X-Code/RunTime alatt.
            NSHomeDirectory() + "/X-Code/RunTime/Chromium/chrome-headless-shell-mac-x64/chrome-headless-shell",
            NSHomeDirectory() + "/X-Code/RunTime/Chromium/chrome-headless-shell-mac-arm64/chrome-headless-shell"]
        return candidates.first(where: FileManager.default.isExecutableFile)
    }()

    /// Arány (szélesség / magasság) 0,05-ös lépésekben, hogy átméretezéskor ne keletkezzen túl sok kép.
    static func quantized(_ ratio: Double) -> Double {
        guard ratio.isFinite else { return 1.6 }
        return (min(max(ratio, 0.25), 6) * 20).rounded() / 20
    }

    /// Az egyetlen generált kép: `.név.web.tn-preview.webp` (tartalék: `.jpg`).
    private static func generated(for directory: URL) -> [URL] {
        let parent = directory.deletingLastPathComponent(), prefix = "." + directory.lastPathComponent + marker
        return ((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? [])
            .filter { $0.hasPrefix(prefix) }.map { parent.appendingPathComponent($0) }
    }

    /// Képméret a fájl fejlécéből (PNG, WebP VP8 / VP8L / VP8X).
    static func pixelSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url), let data = try? handle.read(upToCount: 65_536), data.count >= 30 else { return nil }
        let b = [UInt8](data)
        if b.starts(with: [0x89, 0x50, 0x4e, 0x47]) {
            func be(_ o: Int) -> Int { b[o..<o+4].reduce(0) { $0 << 8 | Int($1) } }
            return (be(16), be(20))
        }
        if b[0] == 0xff, b[1] == 0xd8 {
            // JPEG: az első SOF szegmensben van a méret.
            var o = 2
            while o + 9 < b.count, b[o] == 0xff {
                let kind = b[o + 1], length = Int(b[o + 2]) << 8 | Int(b[o + 3])
                if (0xc0...0xcf).contains(kind) && ![0xc4, 0xc8, 0xcc].contains(kind) {
                    return (Int(b[o + 7]) << 8 | Int(b[o + 8]), Int(b[o + 5]) << 8 | Int(b[o + 6]))
                }
                o += 2 + length
            }
            return nil
        }
        guard b[0..<4].elementsEqual("RIFF".utf8), b[8..<12].elementsEqual("WEBP".utf8) else { return nil }
        switch String(decoding: b[12..<16], as: UTF8.self) {
        case "VP8 ": return (Int(b[26]) | Int(b[27] & 0x3f) << 8, Int(b[28]) | Int(b[29] & 0x3f) << 8)
        case "VP8L":
            let bits = UInt32(b[21]) | UInt32(b[22]) << 8 | UInt32(b[23]) << 16 | UInt32(b[24]) << 24
            return (Int(bits & 0x3fff) + 1, Int((bits >> 14) & 0x3fff) + 1)
        case "VP8X": return (1 + (Int(b[24]) | Int(b[25]) << 8 | Int(b[26]) << 16), 1 + (Int(b[27]) | Int(b[28]) << 8 | Int(b[29]) << 16))
        default: return nil
        }
    }

    private static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return false }
        return process.terminationStatus == 0
    }

    /// Az előnézet a doboz arányában. Csak egy kép van; új renderelés, ha nincs, ha más arányú,
    /// vagy ha az oldal (index fájl, .web mappa) újabb nála.
    /// A képernyőkép a doboz méretében készül (az ablak = a doboz), 2× sűrűséggel a retina kijelzőkhöz;
    /// a kép legfeljebb 4096 px lehet a hosszabb oldalán.
    private static func plan(_ size: (width: Int, height: Int)) -> (scale: Double, pixels: (Int, Int)) {
        let scale = max(1, min(2, 4096 / Double(max(size.width, size.height))))
        return (scale, (Int((Double(size.width) * scale).rounded()), Int((Double(size.height) * scale).rounded())))
    }

    private static func page(in directory: URL) -> URL? {
        let files = FileManager.default
        return ["index.html", "index.htm"].map { directory.appendingPathComponent($0) }.first { files.fileExists(atPath: $0.path) }
            ?? ((try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .first { ["html", "htm"].contains($0.pathExtension.lowercased()) }
    }

    /// A meglévő generált kép, ha a kért mérethez készült és újabb az oldalnál.
    private static func fresh(_ directory: URL, size: (width: Int, height: Int)) -> URL? {
        guard let page = page(in: directory), let existing = generated(for: directory).filter(regularFile).first,
              let pixels = pixelSize(existing), let cached = modified(existing) else { return nil }
        let expected = plan(size).pixels
        guard abs(pixels.width - expected.0) <= 2, abs(pixels.height - expected.1) <= 2,
              [page, directory].compactMap(modified).allSatisfy({ $0 <= cached }) else { return nil }
        return existing
    }

    // Háttérsor: egyszerre egy Chromium fut; mappánként egy várakozó kérés (a legutóbbi méret nyer).
    private static let queue = DispatchQueue(label: "thinknodes.web-screenshot", qos: .utility)
    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var pending: [String: (width: Int, height: Int)] = [:]

    /// Renderelés ütemezése a háttérben; a kérés sosem vár rá.
    static func schedule(_ directory: URL, size: (width: Int, height: Int)) {
        guard browser != nil, page(in: directory) != nil else { return }
        let key = directory.path
        let start: Bool = stateLock.withLock {
            let waiting = pending[key] != nil
            pending[key] = size
            return !waiting
        }
        guard start else { return }
        queue.async {
            while let next = stateLock.withLock({ pending[key] }) {
                if fresh(directory, size: next) == nil { render(directory, size: next) }
                let done: Bool = stateLock.withLock {
                    guard let latest = pending[key], latest == next else { return false }
                    pending[key] = nil
                    return true
                }
                if done { break }
            }
        }
    }

    /// Fut-e (vagy vár-e) renderelés a mappára.
    static func isPending(_ directory: URL) -> Bool { stateLock.withLock { pending[directory.path] != nil } }

    /// A generált kép változata (módosítási idő), a kliens ezzel tölti újra a képet.
    static func version(_ directory: URL) -> String {
        generated(for: directory).filter(regularFile).first.flatMap(modified).map { String(Int($0.timeIntervalSince1970 * 1000)) } ?? "0"
    }

    private static func render(_ directory: URL, size: (width: Int, height: Int)) {
        guard let browser, let page = page(in: directory) else { return }
        let files = FileManager.default
        let (scale, _) = plan(size)
        let parent = directory.deletingLastPathComponent()
        // A Chromium közvetlenül WebP-be ment; ha az nem sikerül, JPG a tartalék.
        let profile = files.temporaryDirectory.appendingPathComponent("thinknodes-chromium-" + UUID().uuidString)
        defer { try? files.removeItem(at: profile) }
        for format in ["webp", "jpg"] {
            let shot = parent.appendingPathComponent(".tn-shot-" + UUID().uuidString + "." + format)
            defer { try? files.removeItem(at: shot) }
            guard run(browser, ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--mute-audio", "--no-first-run",
                "--disable-extensions", "--disable-background-networking", "--user-data-dir=" + profile.path,
                "--virtual-time-budget=4000", "--window-size=\(size.width),\(size.height)", "--force-device-scale-factor=" + String(format: "%.3f", scale),
                "--screenshot=" + shot.path, page.absoluteString], timeout: 30),
                  pixelSize(shot) != nil else { continue }
            // Csak egy kép marad: a régi (más méretű vagy formátumú) előnézet törlődik.
            for old in generated(for: directory) { try? files.removeItem(at: old) }
            let target = parent.appendingPathComponent("." + directory.lastPathComponent + marker + "." + format)
            try? files.moveItem(at: shot, to: target)
            return
        }
    }
}

/// Közös könyvtár (Public/common): ikonok, képek, hangok minden projektnek; csak olvasható.
enum CommonLibrary {
    static func list(_ folders: [String], publicDirectory: String) throws -> BrowseListing {
        let root = URL(fileURLWithPath: publicDirectory).appendingPathComponent("common", isDirectory: true)
        var directory = root
        for folder in folders {
            guard validSegment(folder) else { throw Abort(.notFound) }
            directory.appendPathComponent(folder, isDirectory: true)
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true
        else { return BrowseListing(path: CanvasFile.common, parent: nil, manageable: false, entries: []) }
        var entries: [BrowseListing.Entry] = []
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            let info = try url.resourceValues(forKeys: Set(keys))
            guard info.isSymbolicLink != true, validSegment(url.lastPathComponent) else { continue }
            if info.isDirectory == true { entries.append(.init(name: url.lastPathComponent, kind: "folder", publicAccess: true)) }
            else if info.isRegularFile == true { entries.append(.init(name: url.lastPathComponent, kind: "file", publicAccess: true)) }
        }
        entries.sort { ($0.kind == "folder" ? 0 : 1, $0.name.lowercased()) < ($1.kind == "folder" ? 0 : 1, $1.name.lowercased()) }
        let path = ([CanvasFile.common] + folders.map(WorksheetPath.encodeSegment)).joined(separator: "/")
        let parent = folders.isEmpty ? nil : ([CanvasFile.common] + folders.dropLast().map(WorksheetPath.encodeSegment)).joined(separator: "/")
        return BrowseListing(path: path, parent: parent, manageable: false, entries: entries)
    }

    private static func validSegment(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 200 && !value.hasPrefix(".") && !value.contains("/") && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
