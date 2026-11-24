import Foundation

package enum WorksheetLink {
    case website(String)
    case worksheet(String)

    init?(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 2048,
              value.rangeOfCharacter(from: .controlCharacters) == nil, !value.contains("\\") else { return nil }
        if let url = URLComponents(string: value), let scheme = url.scheme {
            guard ["https", "http"].contains(scheme.lowercased()), let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil, url.url != nil else { return nil }
            self = .website(value)
        } else {
            guard !value.contains("//") else { return nil }
            for segment in value.split(separator: "/") where segment != "." && segment != ".." {
                guard let decoded = String(segment).removingPercentEncoding,
                      (try? WorksheetPath(["lap", decoded])) != nil else { return nil }
            }
            self = .worksheet(value)
        }
    }

    /// Laplink célja útvonalrészekként (projekt az első elem); a `from` a hivatkozó lap útvonala.
    static func resolve(_ value: String, from base: [String]) -> [String] {
        let relative = !value.hasPrefix("/") || value == "/.." || value.hasPrefix("/../")
        var parts = relative ? base : []
        for segment in value.split(separator: "/") {
            if segment == ".." { _ = parts.popLast() }
            else if segment != "." { parts.append(String(segment).removingPercentEncoding ?? String(segment)) }
        }
        return parts
    }

    /// Relatív laplink `from` lapról `to` lapra (mindkettő teljes útvonal, projekttel).
    static func relative(from: [String], to: [String]) -> String {
        var common = 0
        while common < from.count, common < to.count, from[common] == to[common] { common += 1 }
        let parts = Array(repeating: "..", count: from.count - common) + to[common...]
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }

    package func destination(from path: WorksheetPath) -> String? {
        switch self {
        case .website(let url): return url
        case .worksheet(let value):
            let relative = !value.hasPrefix("/") || value == "/.." || value.hasPrefix("/../")
            var parts = relative ? path.parts : []
            for segment in value.split(separator: "/") {
                if segment == ".." { _ = parts.popLast() }
                else if segment != "." { parts.append(String(segment).removingPercentEncoding ?? String(segment)) }
            }
            if parts.isEmpty { return "/" }
            return (try? WorksheetPath(parts)).map { "/" + $0.url }
        }
    }

    func iconPath(siteHost: String?) -> String {
        if case .website(let value) = self, let url = URLComponents(string: value),
           let host = url.host, let siteHost,
           (host + (url.port.map { ":\($0)" } ?? "")).lowercased() == siteHost.lowercased() {
            let parts = url.percentEncodedPath.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
            if parts.isEmpty || (try? WorksheetPath(parts)) != nil { return Self.chain }
        }
        return iconPath
    }

    package func isExternal(siteHost: String?) -> Bool {
        if case .website = self { return iconPath(siteHost: siteHost) != Self.chain }
        return false
    }

    /// Prezentáció (.web mappa) jele: monitor.
    static let globe = "M3 4h18v12H3zM8 20h8M12 16v4"
    static let chain = "m10 13 4-4m-5 6-2 2a3.5 3.5 0 0 1-5-5l5-5a3.5 3.5 0 0 1 5 0m0 10a3.5 3.5 0 0 0 5 0l5-5a3.5 3.5 0 0 0-5-5l-2 2"

    private var iconPath: String {
        switch self {
        case .website: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20ZM2 12h20M12 2c-5 5-5 15 0 20 5-5 5-15 0-20Z"
        case .worksheet: Self.chain
        }
    }
}
