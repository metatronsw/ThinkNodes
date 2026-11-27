import Foundation
import ThinkCore
import Vapor
import AsyncHTTPClient
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Külső webcím előnézete: az oldal saját megosztási képe (og:image / twitter:image), ennek hiányában
/// címből és webcímből összeállított kártya (SVG). A képek a data könyvtár `.link-previews` mappájában
/// tárolódnak (URL hash szerint), és legfeljebb hetente frissülnek.
///
/// Belső hálózat védelme (SSRF): csak http(s), csak 80/443-as port, a gépnév minden címe nyilvános kell
/// legyen (nem helyi, privát, link-local stb.), az átirányításokat egyenként, ugyanígy ellenőrizzük.
actor LinkPreviews {
    struct Meta: Codable {
        var title: String
        var host: String
        var image: String?      // a tárolt kép fájlneve, ha van
        var fetched: Date
    }

    static let maxAge: TimeInterval = 7 * 24 * 3600
    private let directory: URL
    private let client: HTTPClient
    private var running: [String: Task<Meta, Error>] = [:]

    init(root: URL, eventLoopGroup: EventLoopGroup) {
        directory = root.appendingPathComponent(".link-previews", isDirectory: true)
        var configuration = HTTPClient.Configuration(redirectConfiguration: .disallow,
            timeout: .init(connect: .seconds(5), read: .seconds(8)))
        configuration.decompression = .enabled(limit: .ratio(20))
        client = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup), configuration: configuration)
    }

    func shutdown() async { try? await client.shutdown() }

    /// Előnézet a címhez: kép (fájl) vagy kártya. `refresh`: hetente frissítheti a tárolt adatot.
    func preview(for raw: String, refresh: Bool) async throws -> (file: URL?, meta: Meta) {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, raw.utf8.count <= 2048 else { throw Abort(.badRequest) }
        let key = SHA256.hash(data: Data(raw.utf8)).hex
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let metaURL = directory.appendingPathComponent(key + ".json")
        if let data = try? Data(contentsOf: metaURL), let meta = try? JSONDecoder().decode(Meta.self, from: data),
           !refresh || Date().timeIntervalSince(meta.fetched) < Self.maxAge {
            return (meta.image.map { directory.appendingPathComponent($0) }, meta)
        }
        let task = running[key] ?? Task { try await self.fetch(url, key: key) }
        running[key] = task
        defer { running[key] = nil }
        let meta = try await task.value
        try JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
        return (meta.image.map { directory.appendingPathComponent($0) }, meta)
    }

    private func fetch(_ url: URL, key: String) async throws -> Meta {
        let host = url.host ?? ""
        var meta = Meta(title: host, host: host, image: nil, fetched: Date())
        guard let (page, final) = try? await get(url, limit: 512 * 1024, accept: "text/html") else { return meta }
        let html = String(decoding: page, as: UTF8.self)
        if let title = Self.metaContent(html, ["og:title", "twitter:title"]) ?? Self.titleTag(html) {
            meta.title = String(Self.decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        }
        guard let source = Self.metaContent(html, ["og:image", "og:image:url", "og:image:secure_url", "twitter:image"]),
              let imageURL = URL(string: Self.decodeEntities(source), relativeTo: final)?.absoluteURL,
              let (bytes, _) = try? await get(imageURL, limit: 5 * 1024 * 1024, accept: "image/*"),
              let ext = Self.imageExtension(bytes) else { return meta }
        let name = key + "." + ext
        try bytes.write(to: directory.appendingPathComponent(name), options: .atomic)
        meta.image = name
        return meta
    }

    /// GET legfeljebb 3 átirányítással; minden lépésben ellenőrzi a célt.
    private func get(_ start: URL, limit: Int, accept: String) async throws -> (Data, URL) {
        var url = start
        for _ in 0..<4 {
            try Self.checkPublic(url)
            var request = HTTPClientRequest(url: url.absoluteString)
            request.headers.add(name: "User-Agent", value: "ThinkNodes-LinkPreview/1.0")
            request.headers.add(name: "Accept", value: accept)
            let response = try await client.execute(request, timeout: .seconds(10))
            if (300..<400).contains(Int(response.status.code)) {
                guard let location = response.headers.first(name: "Location"),
                      let next = URL(string: location, relativeTo: url)?.absoluteURL else { throw Abort(.badGateway) }
                url = next
                continue
            }
            guard response.status == .ok else { throw Abort(.badGateway) }
            var data = Data()
            for try await chunk in response.body {
                data.append(contentsOf: chunk.readableBytesView)
                if data.count > limit { break }
            }
            return (data.prefix(limit), url)
        }
        throw Abort(.badGateway)
    }

    /// Csak nyilvános cél: http(s), 80/443, a gépnév minden feloldott címe nyilvános.
    static func checkPublic(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
              [nil, 80, 443].contains(url.port) else { throw Abort(.forbidden) }
        // Mezőnként: az addrinfo mezősorrendje macOS-en és Linuxon (glibc) eltér, a tagonkénti inicializáló nem hordozható.
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = Self.streamSocket
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { throw Abort(.forbidden) }
        defer { freeaddrinfo(first) }
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var any = false
        while let info = cursor {
            if let address = info.pointee.ai_addr {
                any = true
                if info.pointee.ai_family == AF_INET {
                    let raw = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                    if !publicIPv4(raw) { throw Abort(.forbidden) }
                } else if info.pointee.ai_family == AF_INET6 {
                    let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                        withUnsafeBytes(of: pointer.pointee.sin6_addr) { Array($0) }
                    }
                    if !publicIPv6(bytes) { throw Abort(.forbidden) }
                } else { throw Abort(.forbidden) }
            }
            cursor = info.pointee.ai_next
        }
        guard any else { throw Abort(.forbidden) }
    }

    static func publicIPv4(_ a: UInt32) -> Bool {
        let blocked: [(UInt32, UInt32)] = [
            (0x0000_0000, 8), (0x0A00_0000, 8), (0x6440_0000, 10), (0x7F00_0000, 8), (0xA9FE_0000, 16),
            (0xAC10_0000, 12), (0xC000_0000, 24), (0xC0A8_0000, 16), (0xC612_0000, 15), (0xE000_0000, 3),
        ]
        return !blocked.contains { network, bits in a >> (32 - bits) == network >> (32 - bits) }
    }

    static func publicIPv6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        if b.allSatisfy({ $0 == 0 }) || (b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1) { return false }   // ::, ::1
        if b[0] & 0xFE == 0xFC || (b[0] == 0xFE && b[1] & 0xC0 == 0x80) || b[0] == 0xFF { return false }  // fc00::/7, fe80::/10, ff00::/8
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {                            // ::ffff:IPv4
            return publicIPv4(UInt32(b[12]) << 24 | UInt32(b[13]) << 16 | UInt32(b[14]) << 8 | UInt32(b[15]))
        }
        return true
    }

    static func imageExtension(_ bytes: Data) -> String? {
        let b = [UInt8](bytes.prefix(12))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if b.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if b.count >= 12, b[0..<4].elementsEqual("RIFF".utf8), b[8..<12].elementsEqual("WEBP".utf8) { return "webp" }
        return nil   // SVG és más formátum nem (az SVG a saját originünkön szkriptet futtathatna)
    }

    static func metaContent(_ html: String, _ names: [String]) -> String? {
        let head = String(html.prefix(400_000))
        for name in names {
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            for pattern in [
                #"<meta[^>]+(?:property|name)\s*=\s*["']"# + escapedName + #"["'][^>]*content\s*=\s*["']([^"']+)["']"#,
                #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']"# + escapedName + #"["']"#,
            ] {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
                   let range = Range(match.range(at: 1), in: head) { return String(head[range]) }
            }
        }
        return nil
    }

    static func titleTag(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>([^<]{1,300})</title>"#, options: [.caseInsensitive]) else { return nil }
        let head = String(html.prefix(400_000))
        guard let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
              let range = Range(match.range(at: 1), in: head) else { return nil }
        return String(head[range])
    }

    static func decodeEntities(_ text: String) -> String {
        [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Kártya, ha nincs kép: cím és gépnév.
    static func card(_ meta: Meta) -> String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let title = meta.title.count > 60 ? String(meta.title.prefix(57)) + "…" : meta.title
        return """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 200">
              <rect width="320" height="200" fill="#1f2b38"/>
              <g fill="none" stroke="#8aa0b6" stroke-width="3"><circle cx="160" cy="70" r="26"/><path d="M134 70h52M160 44c-13 13-13 39 0 52 13-13 13-39 0-52Z"/></g>
              <text x="160" y="134" fill="#e3ebf3" text-anchor="middle" font-family="sans-serif" font-size="15">\(escape(title))</text>
              <text x="160" y="158" fill="#8aa0b6" text-anchor="middle" font-family="sans-serif" font-size="12">\(escape(meta.host))</text>
            </svg>
            """
    }
}

extension LinkPreviews {
    #if canImport(Darwin)
    static let streamSocket = SOCK_STREAM
    #else
    static let streamSocket = Int32(SOCK_STREAM.rawValue)
    #endif
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
