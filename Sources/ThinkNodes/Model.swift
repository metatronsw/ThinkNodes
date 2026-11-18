import Foundation
import Vapor

struct Point: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    var isValid: Bool {
        x.isFinite && y.isFinite && abs(x) <= 100_000 && abs(y) <= 100_000
    }
}

enum Shape: String, Codable, Sendable {
    case rounded, rectangle, ellipse, diamond
}

enum LabelAlignment: String, Codable, Sendable {
    case left, center, right
}

struct Idea: Codable, Sendable {
    var id: String
    var title: String
    var markdown = ""
    var comment: String?
    var autoSize: Bool?
    var showMarkdown: Bool?
    var position: Point
    var width: Double = 176
    var height: Double = 80
    var shape: Shape = .rounded
    var fill = "#dce9ff"
    var textColor = "#182335"
    var border = "#839bbc"
    var fontSize: Double = 16
    var bold = true
    var alignment: LabelAlignment = .center

    var isValid: Bool {
        validSlug(id) && validTitle(title) && markdown.utf8.count <= 100_000
            && validComment(comment) && position.isValid
            && (64...880).contains(width) && (40...680).contains(height)
            && (10...60).contains(fontSize)
            && [fill, textColor, border].allSatisfy(validColor)
    }
}

enum ConnectionStyle: String, Codable, Sendable {
    case arrow, both, dashed, rope

    var label: String {
        switch self {
        case .arrow: "Egyirányú nyíl"
        case .both: "Kétirányú nyíl"
        case .dashed: "Szaggatott nyíl"
        case .rope: "Íves kötél"
        }
    }
}

struct ConnectionTarget: Codable, Sendable {
    var node: String?
    var point: Point?

    func isValid(in nodeIDs: Set<String>, source: String) -> Bool {
        if let node {
            return point == nil && node != source && nodeIDs.contains(node)
        }
        return point?.isValid == true
    }
}

struct Connection: Codable, Sendable {
    var id: String
    var source: String
    var target: ConnectionTarget
    var style: ConnectionStyle
}

struct Worksheet: Content {
    var schemaVersion = 1
    var revision = 1
    var title: String
    var comment: String?
    var markdown: String?
    var nodes: [Idea] = []
    var edges: [Connection] = []

    func validate() throws {
        let nodeIDs = Set(nodes.map(\.id))
        guard schemaVersion == 1, revision > 0, revision < Int.max, validTitle(title),
              validComment(comment), (markdown?.utf8.count ?? 0) <= 100_000,
              nodes.count <= 2_000, edges.count <= 4_000,
              nodeIDs.count == nodes.count, Set(edges.map(\.id)).count == edges.count,
              nodes.allSatisfy(\.isValid), edges.allSatisfy({
                  validSlug($0.id) && nodeIDs.contains($0.source)
                      && $0.target.isValid(in: nodeIDs, source: $0.source)
              })
        else {
            throw Abort(.unprocessableEntity, reason: "Érvénytelen munkalapadat.")
        }
    }
}

struct SiteSettings: Codable, Sendable {
    var requireLogin = false
    var guestCreation = true
}

enum Role: String, Codable, Sendable {
    case editor, admin
}

struct User: Codable, Sendable {
    var name: String
    var role: Role
    var passwordHash: String
}

func validSlug(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy {
        (97...122).contains($0) || (48...57).contains($0) || $0 == 45
    }
}

private func validTitle(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 120
        && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}

private func validComment(_ value: String?) -> Bool {
    guard let value else { return true }
    return value.utf16.count <= 500 && !value.unicodeScalars.contains {
        CharacterSet.controlCharacters.contains($0)
    }
}

private func validColor(_ value: String) -> Bool {
    value.utf8.count == 7 && value.first == "#" && value.dropFirst().utf8.allSatisfy {
        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
    }
}

struct WorksheetPath: Sendable {
    let parts: [String]
    let name: String
    let url: String

    private static let reserved = ["admin", "api", "edit", "export", "login", "logout", "health", "open", "vendor"]

    init(_ raw: [String]) throws {
        let parts = raw.map(\.precomposedStringWithCanonicalMapping)
        guard let name = parts.last, let first = parts.first, parts.count <= 12,
              !Self.reserved.contains(first.lowercased()),
              parts.allSatisfy({ part in
                  !part.isEmpty && part.utf8.count <= 180 && part.unicodeScalars.allSatisfy {
                      CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
                          || CharacterSet.nonBaseCharacters.contains($0) || $0 == "-" || $0 == "_"
                  }
              })
        else { throw Abort(.notFound, reason: "Érvénytelen munkalapútvonal.") }
        self.parts = parts
        self.name = name
        self.url = parts.map { part in
            part.utf8.map { byte in
                switch byte {
                case 48...57, 65...90, 97...122, 45, 95: String(UnicodeScalar(byte))
                default: String(format: "%%%02X", byte)
                }
            }.joined()
        }.joined(separator: "/")
    }
}

final class WorksheetStore: @unchecked Sendable {
    private let root: URL
    private let files = FileManager.default
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try files.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func list() throws -> [(path: WorksheetPath, worksheet: Worksheet)] {
        try lock.withLock {
            guard let paths = files.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                               options: [.skipsHiddenFiles]) else { return [] }
            var result: [(path: WorksheetPath, worksheet: Worksheet)] = []
            for case let url as URL in paths {
                let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if properties.isSymbolicLink == true {
                    paths.skipDescendants()
                    continue
                }
                guard properties.isRegularFile == true, url.pathExtension == "json" else { continue }
                let segments = Array(url.deletingPathExtension().pathComponents.dropFirst(root.pathComponents.count))
                guard let path = try? WorksheetPath(segments), let worksheet = try? read(url) else { continue }
                result.append((path, worksheet))
            }
            return result.sorted { $0.path.parts.lexicographicallyPrecedes($1.path.parts) }
        }
    }

    func settings() throws -> SiteSettings {
        try lock.withLock { try readSettings() }
    }

    func setSettings(_ settings: SiteSettings) throws {
        try lock.withLock {
            try rejectLink(settingsFile)
            try write(settings, to: settingsFile)
        }
    }

    func open(_ path: WorksheetPath, authenticated: Bool) throws -> Worksheet {
        try lock.withLock {
            let settings = try readSettings()
            if settings.requireLogin && !authenticated { throw Abort(.unauthorized) }
            let url = try worksheetURL(path)
            if files.fileExists(atPath: url.path) { return try read(url) }
            guard authenticated || settings.guestCreation else {
                throw Abort(.unauthorized, reason: "A munkalap létrehozásához be kell jelentkezni.")
            }
            let rawTitle = path.name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let worksheet = Worksheet(title: rawTitle.isEmpty ? path.name : String(rawTitle.prefix(120)))
            try worksheet.validate()
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(worksheet, to: url)
            return worksheet
        }
    }

    func load(_ path: WorksheetPath, authenticated: Bool) throws -> Worksheet {
        try lock.withLock {
            if try readSettings().requireLogin && !authenticated { throw Abort(.unauthorized) }
            return try read(worksheetURL(path))
        }
    }

    func update(_ path: WorksheetPath, worksheet: Worksheet) throws -> Worksheet {
        try lock.withLock {
            let url = try worksheetURL(path)
            let current = try read(url)
            guard worksheet.revision == current.revision else {
                throw Abort(.preconditionFailed, reason: "A munkalapot közben más módosította. A helyi változtatásaid megmaradtak.")
            }
            var updated = worksheet
            updated.revision = current.revision + 1
            try updated.validate()
            try write(updated, to: url)
            return updated
        }
    }

    func archive(_ path: WorksheetPath, expected: Int) throws {
        try lock.withLock {
            let url = try worksheetURL(path)
            guard try read(url).revision == expected else {
                throw Abort(.preconditionFailed, reason: "A munkalapot közben más módosította.")
            }
            let trash = root.appendingPathComponent(".trash", isDirectory: true)
            try rejectLink(trash)
            try files.createDirectory(at: trash, withIntermediateDirectories: true)
            try files.moveItem(at: url, to: trash.appendingPathComponent("\(UUID().uuidString)-\(path.name).json"))
        }
    }

    func allUsers() throws -> [User] {
        try lock.withLock { try readUsers().sorted { $0.name < $1.name } }
    }

    func user(named name: String) throws -> User? {
        try lock.withLock { try readUsers().first { $0.name == name } }
    }

    func setUser(name: String, role: Role, passwordHash: String?, initialOnly: Bool = false) throws {
        guard validSlug(name) else {
            throw Abort(.unprocessableEntity, reason: "A felhasználónév kisbetűket, számokat és kötőjelet tartalmazhat.")
        }
        try lock.withLock {
            var users = try readUsers()
            if initialOnly && !users.isEmpty { throw Abort(.conflict) }
            let existing = users.first { $0.name == name }
            guard let hash = passwordHash ?? existing?.passwordHash else {
                throw Abort(.unprocessableEntity, reason: "Az új fiókhoz jelszót kell megadni.")
            }
            users.removeAll { $0.name == name }
            users.append(User(name: name, role: role, passwordHash: hash))
            try writeUsers(users)
        }
    }

    func removeUser(named name: String) throws {
        try lock.withLock {
            let users = try readUsers()
            guard users.contains(where: { $0.name == name }) else { throw Abort(.notFound) }
            try writeUsers(users.filter { $0.name != name })
        }
    }

    private var userFile: URL { root.appendingPathComponent(".users.json") }
    private var settingsFile: URL { root.appendingPathComponent(".settings.json") }

    private func readSettings() throws -> SiteSettings {
        try rejectLink(settingsFile)
        guard files.fileExists(atPath: settingsFile.path) else { return SiteSettings() }
        return try JSONDecoder().decode(SiteSettings.self, from: Data(contentsOf: settingsFile))
    }

    private func readUsers() throws -> [User] {
        try rejectLink(userFile)
        guard files.fileExists(atPath: userFile.path) else { return [] }
        return try JSONDecoder().decode([User].self, from: Data(contentsOf: userFile))
    }

    private func writeUsers(_ users: [User]) throws {
        guard users.contains(where: { $0.role == .admin }) else {
            throw Abort(.unprocessableEntity, reason: "Legalább egy adminisztrátori fióknak meg kell maradnia.")
        }
        try write(users, to: userFile)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: userFile.path)
    }

    private func read(_ url: URL) throws -> Worksheet {
        guard files.fileExists(atPath: url.path) else { throw Abort(.notFound, reason: "A munkalap nem található.") }
        let worksheet = try JSONDecoder().decode(Worksheet.self, from: Data(contentsOf: url))
        try worksheet.validate()
        return worksheet
    }

    private func write(_ value: some Encodable, to url: URL) throws {
        try (encoder.encode(value) + Data([10])).write(to: url, options: .atomic)
    }

    private func worksheetURL(_ path: WorksheetPath) throws -> URL {
        var directory = root
        for component in path.parts.dropLast() {
            directory.appendPathComponent(component, isDirectory: true)
            try rejectLink(directory)
        }
        let url = directory.appendingPathComponent(path.name + ".json")
        try rejectLink(url)
        return url
    }

    private func rejectLink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw Abort(.notFound)
        }
    }
}
