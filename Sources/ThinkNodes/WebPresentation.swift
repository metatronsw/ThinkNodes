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
    let membersOnly: Bool?
    let editors: [String]?
    let passwordProtected: Bool?
}

struct WebPresentationSettings: Content {
    let reference: String
    let membersOnly: Bool
    let editors: [String]?
    let password: String?
    let removePassword: Bool
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

    static func preview(in root: URL, folders: [String]) -> WebAsset? {
        for name in ["preview.png", "screen.png"] {
            if let result = try? open(in: root, folders: folders, asset: [name], trailingSlash: false),
               !result.directory { return result.0 }
        }
        return nil
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
