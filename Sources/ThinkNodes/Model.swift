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

enum VerticalAlignment: String, Codable, Sendable { case top, middle, bottom }

enum IdeaKind: String, Codable, Sendable {
    case container, connectionPoint
}

struct TextStyle: Codable, Equatable, Sendable {
    var color: String?
    var size: Double?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var alignment: LabelAlignment?
    var verticalAlignment: VerticalAlignment?

    var isValid: Bool {
        (color.map(validColor) ?? true) && (size.map { (10...60).contains($0) && $0.rounded() == $0 } ?? true)
    }
}

struct Idea: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var text = ""
    var hideText: Bool?
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
    var verticalAlignment: VerticalAlignment?
    var titleOutside: Bool?
    var link: String?

    var kind: IdeaKind?
    var parent: String?
    var locked: Bool?
    var italic: Bool?
    var underline: Bool?
    var textStyle: TextStyle?
    var textFill: String?
    var textBorder: String?

    var isValid: Bool {
        let sizeValid = kind == .connectionPoint ? (4...128).contains(width) && height == width :
            (64...880).contains(width) && (40...680).contains(height)
        guard validSlug(id), validTitle(title) || (kind == .connectionPoint && title.isEmpty),
              text.utf8.count <= 100_000, sizeValid else { return false }
        let validContent = position.isValid
            && (link.map { $0.isEmpty || WorksheetLink($0) != nil } ?? true)
        return validContent && (textStyle?.isValid ?? true)
            && [textFill, textBorder].compactMap { $0 }.allSatisfy(validColor)
            && (10...60).contains(fontSize) && fontSize.rounded() == fontSize
            && [fill, textColor, border].allSatisfy(validColor)
    }
}

enum ConnectionStyle: String, Codable, Sendable {
    case arrow, both, solid, dashed, rope

    var label: String {
        switch self {
        case .arrow: "Egyirányú nyíl"
        case .both: "Kétirányú nyíl"
        case .solid: "Folytonos vonal"
        case .dashed: "Szaggatott nyíl"
        case .rope: "Íves kötél"
        }
    }
}

struct ConnectionTarget: Equatable, Codable, Sendable {
    var node: String?
    var point: Point?

    func isValid(in nodeIDs: Set<String>) -> Bool {
        if let node {
            return point == nil && nodeIDs.contains(node)
        }
        return point?.isValid == true
    }
}

struct Connection: Equatable, Codable, Sendable {
    var id: String
    var source: String?
    var sourcePoint: Point?
    var target: ConnectionTarget
    var style: ConnectionStyle
    var color: String?
    var width: Double?
    var startArrow: Bool?
    var endArrow: Bool?
    var label: String?

    var origin: ConnectionTarget { ConnectionTarget(node: source, point: sourcePoint) }
    var strokeColor: String { color ?? "#526982" }
    var strokeWidth: Double { width ?? 2 }
    var hasStartArrow: Bool { startArrow ?? (style == .both) }
    var hasEndArrow: Bool { endArrow ?? (style != .rope && style != .solid) }
}

struct Worksheet: Content, Equatable {
    var schemaVersion = 2
    var revision = 1
    var resetRevision: Int?
    var title: String
    var text: String?
    var background: String?
    var gridColor: String?
    var gridSpacing: Double?
    var gridVisible: Bool?
    var creator: String?
    var owner: String?
    var editors: [String]?
    var hidden: Bool?
    var isPublic: Bool?
    var nodes: [Idea] = []
    var edges: [Connection] = []

    var backgroundColor: String { background ?? "#f5f8fc" }

    func canManage(_ user: User?) -> Bool {
        guard let user else { return false }
        return user.role == .admin || user.name == owner || user.name == creator
    }

    func canEdit(_ user: User?) -> Bool {
        guard let user else { return false }
        return canManage(user) || editors?.contains(user.name) == true
    }

    func canRead(_ user: User?) -> Bool {
        (isPublic ?? true) || canEdit(user)
    }

    func withoutAccessDetails() -> Worksheet {
        var copy = self
        copy.owner = nil
        copy.editors = nil
        return copy
    }

    private var junctionDegrees: [String: Int] {
        var counts: [String: Int] = [:]
        for edge in edges {
            if let source = edge.source { counts[source, default: 0] += 1 }
            if let target = edge.target.node, target != edge.source { counts[target, default: 0] += 1 }
        }
        return counts
    }

    mutating func dissolveUnusedJunctions() {
        let degrees = junctionDegrees
        var removed: [String: Point] = [:]
        nodes.removeAll { node in
            guard node.kind == .connectionPoint, degrees[node.id, default: 0] < 2 else { return false }
            removed[node.id] = node.position
            return true
        }
        guard !removed.isEmpty else { return }
        for i in edges.indices {
            if let source = edges[i].source, let point = removed[source] {
                edges[i].source = nil
                edges[i].sourcePoint = point
            }
            if let target = edges[i].target.node, let point = removed[target] {
                edges[i].target = ConnectionTarget(point: point)
            }
        }
    }

    private var duplicateConnections: [Int] {
        var pairs = Set<[String]>()
        return edges.indices.filter { i in
            guard let from = edges[i].source, let to = edges[i].target.node else { return false }
            return !pairs.insert([from, to]).inserted
        }
    }

    mutating func detachLegacyDuplicateConnections() {
        let positions = Dictionary(nodes.map { ($0.id, $0.position) }, uniquingKeysWith: { first, _ in first })
        for i in duplicateConnections {
            if let id = edges[i].target.node, let point = positions[id] {
                edges[i].target = ConnectionTarget(point: point)
            }
        }
    }

    func validate() throws {
        guard duplicateConnections.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Ezen az útvonalon már van kábel.")
        }
        let nodeIDs = Set(nodes.map(\.id))
        guard (1...2).contains(schemaVersion), revision > 0, revision < Int.max, validTitle(title),
              (text?.utf8.count ?? 0) <= 100_000, validColor(backgroundColor),
              validColor(gridColor ?? "#ccd7eb"), (6...160).contains(gridSpacing ?? 20),
              owner.map({ validSlug($0) || isTesterName($0) }) ?? true,
              (editors?.count ?? 0) <= 2_000, editors?.allSatisfy(validSlug) ?? true,
              nodes.count <= 2_000, edges.count <= 4_000,
              nodeIDs.count == nodes.count, Set(edges.map(\.id)).count == edges.count,
              nodes.allSatisfy(\.isValid), edges.allSatisfy({
                  validSlug($0.id) && $0.origin.isValid(in: nodeIDs) && $0.target.isValid(in: nodeIDs)
                      && ($0.source == nil || $0.source != $0.target.node)
                      && validColor($0.strokeColor) && (0.5...24).contains($0.strokeWidth)
                      && validComment($0.label) && ($0.label?.utf16.count ?? 0) <= 120
              })
        else {
            throw Abort(.unprocessableEntity, reason: "Érvénytelen munkalapadat.")
        }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let degrees = junctionDegrees
        var checked = Set<String>()
        for node in nodes {
            if node.kind == .connectionPoint && degrees[node.id, default: 0] < 2 {
                throw Abort(.unprocessableEntity, reason: "A csomóponthoz legalább két vonal szükséges.")
            }
            var path = Set<String>()
            var current = node
            while let id = current.parent, !checked.contains(current.id) {
                guard path.insert(current.id).inserted, let parent = byID[id], parent.kind == .container else {
                    throw Abort(.unprocessableEntity, reason: "Érvénytelen konténerkapcsolat.")
                }
                current = parent
            }
            checked.formUnion(path)
        }
    }
}

struct SiteSettings: Codable, Sendable {
    var requireLogin = false
}

enum Role: String, Codable, Sendable {
    case editor, admin
}

struct User: Codable, Sendable {
    var name: String
    var role: Role
    var passwordHash: String
}

func isTesterName(_ value: String) -> Bool {
    guard value.hasPrefix("Tester"), let number = Int(value.dropFirst(6)), number > 0 else { return false }
    return value == "Tester" + String(number)
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

struct DocumentPolicy: Codable, Sendable {
    var hidden: Bool?
    var frozen: Bool?
    var publicEditing: Bool?
    var users: [String]?
    var owner: String?
    var editors: [String]?
    var guestReadable: Bool?
    var passwordHash: String?
}

struct DocumentAccess: Sendable {
    var readable = false
    var editable = false
    var manageable = false
    var listed = false
    var locked = false
    var hidden = false
    var projectRule = DocumentPolicy()
    var sheetRule = DocumentPolicy()
    var editorNames: [String] = []
    var protectedByPassword = false
    var frozen = false
    var passwordRequired = false
}

struct DocumentAction: Content {
    var scope: String
    var action: String
    var value: String?
    var filename: String? = nil
}

final class WorksheetStore: @unchecked Sendable {
    private let root: URL
    let testMode: Bool
    private var testerCount = 0

    func nextTester() -> String {
        lock.withLock { testerCount += 1; return "Tester" + String(testerCount) }
    }

    private var policyURL: URL { root.appendingPathComponent(".document-policies.json") }
    private let files = FileManager.default
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    init(root: URL, testMode: Bool = false) throws {
        self.testMode = testMode
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try files.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    private func policies() throws -> [String: DocumentPolicy] {
        try rejectLink(policyURL)
        guard files.fileExists(atPath: policyURL.path) else { return [:] }
        return try JSONDecoder().decode([String: DocumentPolicy].self, from: Data(contentsOf: policyURL))
    }

    private func readDocument(_ path: WorksheetPath, rules: [String: DocumentPolicy]) throws -> Worksheet {
        let url = try worksheetURL(path)
        var sheet: Worksheet
        if files.fileExists(atPath: url.path) {
            sheet = try read(url)
        } else {
            let directory = url.deletingPathExtension()
            try rejectLink(directory)
            guard let entries = try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]),
                  let member = entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first(where: {
                      $0.pathExtension == "json" && (try? rejectLink($0)) != nil && (try? read($0)) != nil
                  }) else { throw Abort(.notFound, reason: "A munkalap nem található.") }
            let example = try read(member)
            let memberPath = try WorksheetPath(path.parts + [member.deletingPathExtension().lastPathComponent])
            let owner = rules["sheet/" + memberPath.url]?.owner ?? example.owner
            sheet = Worksheet(title: path.name, background: example.background, creator: example.creator, owner: owner, isPublic: example.isPublic)
        }
        if let rule = rules["sheet/" + path.url] {
            sheet.owner = rule.owner ?? sheet.owner
            sheet.editors = rule.editors ?? sheet.editors
            if let users = rule.users, !users.isEmpty {
                sheet.editors = Set((sheet.editors ?? []) + users).sorted()
            }
            sheet.isPublic = rule.guestReadable ?? sheet.isPublic
            sheet.hidden = rule.hidden ?? sheet.hidden
        }
        return sheet
    }

    private func writeDocument(_ sheet: Worksheet, at path: WorksheetPath, rules: [String: DocumentPolicy]) throws {
        let url = try worksheetURL(path)
        let key = "sheet/" + path.url
        var next = rules
        var rule = rules[key] ?? DocumentPolicy()
        rule.owner = sheet.owner
        rule.users = nil
        rule.editors = sheet.editors
        rule.guestReadable = sheet.isPublic
        rule.hidden = sheet.hidden
        next[key] = rule
        var content = sheet
        content.owner = nil
        content.editors = nil
        content.isPublic = nil
        content.hidden = nil
        try write(next, to: policyURL)
        do { try write(content, to: url) }
        catch { try? write(rules, to: policyURL); throw error }
    }

    private func accessLocked(_ path: WorksheetPath, sheet: Worksheet, user: User?, unlocks: Set<String>,
                              rules: [String: DocumentPolicy]) throws -> DocumentAccess {
        let admin = user?.role == .admin
        let manager = sheet.canManage(user)
        var editors = Set<String>()
        var protectedByPassword = false
        var granted = sheet.canEdit(user)
        var publicEditing: Bool?
        var frozen = false, editingFrozen = false, hidden = false, locked = false
        for depth in 1...path.parts.count {
            let parent = try WorksheetPath(Array(path.parts.prefix(depth)))
            let ancestor = depth == path.parts.count ? sheet : (try? readDocument(parent, rules: rules))
            editors.formUnion(ancestor?.editors ?? [])
            if let user, ancestor?.canEdit(user) == true { granted = true }
            let exempt = admin || (user != nil && (ancestor?.creator ?? ancestor?.owner) == user?.name)
            let project = depth == 1 ? rules["project/" + parent.url] : nil
            if ancestor?.hidden == true {
                hidden = true
            }
            for rule in [project, rules["sheet/" + parent.url]].compactMap({ $0 }) {
                editors.formUnion(rule.users ?? [])
                protectedByPassword = protectedByPassword || rule.passwordHash != nil
                if let mode = rule.publicEditing { publicEditing = mode }
                if let user, rule.users?.contains(user.name) == true { granted = true }
                frozen = frozen || rule.frozen == true
                editingFrozen = editingFrozen || (rule.frozen == true && !exempt)
                hidden = hidden || rule.hidden == true
                if let hash = rule.passwordHash, !exempt, !unlocks.contains(hash) {
                    locked = true
                }
            }
        }
        let allowed = granted || (user != nil && publicEditing == true && sheet.isPublic != false)
        let readable = admin || allowed || (publicEditing != false && sheet.isPublic != false)
        return DocumentAccess(readable: readable && !locked,
                              editable: allowed && !locked && !editingFrozen,
                              manageable: manager && !locked,
                              listed: readable && (!hidden || granted),
                              locked: readable && locked, hidden: hidden,
                              projectRule: rules["project/" + path.url] ?? DocumentPolicy(),
                              sheetRule: rules["sheet/" + path.url] ?? DocumentPolicy(),
                              editorNames: editors.sorted(), protectedByPassword: protectedByPassword,
                              frozen: frozen, passwordRequired: locked)
    }

    func access(_ path: WorksheetPath, sheet: Worksheet, user: User?, unlocks: Set<String> = []) throws -> DocumentAccess {
        try lock.withLock { try accessLocked(path, sheet: sheet, user: user, unlocks: unlocks, rules: policies()) }
    }

    private func authorize(_ access: DocumentAccess, user: User?) throws {
        if access.locked { throw Abort(.locked, reason: "Ehhez a munkalaphoz jelszó szükséges.") }
        if !access.readable { throw Abort(user == nil ? .unauthorized : .forbidden) }
    }

    private func attachmentPolicyKey(_ path: WorksheetPath, _ name: String) -> String {
        let segment = Data(name.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return "attachment/" + path.url + "/" + segment
    }

    private func attachmentGranted(_ path: WorksheetPath, file: String?, user: User?, rules: [String: DocumentPolicy]) -> Bool {
        guard let file, let user else { return false }
        return rules[attachmentPolicyKey(path, file)]?.users?.contains(user.name) == true
    }

    func unlock(_ path: WorksheetPath, password: String, user: User?, attachment: String? = nil) throws -> [String] {
        try lock.withLock {
            let rules = try policies()
            let sheet = try readDocument(path, rules: rules)
            let access = try accessLocked(path, sheet: sheet, user: user, unlocks: [], rules: rules)
            guard access.locked || (access.passwordRequired && attachmentGranted(path, file: attachment, user: user, rules: rules)) else {
                throw Abort(.forbidden)
            }
            var hashes: [String] = []
            for depth in 1...path.parts.count {
                let parent = try WorksheetPath(Array(path.parts.prefix(depth)))
                let keys = depth == 1 ? ["project/" + parent.url, "sheet/" + parent.url] : ["sheet/" + parent.url]
                for key in keys {
                    if let hash = rules[key]?.passwordHash, try Bcrypt.verify(password, created: hash) { hashes.append(hash) }
                }
            }
            guard !hashes.isEmpty else { throw Abort(.forbidden, reason: "Hibás jelszó.") }
            return hashes
        }
    }

    func list(user: User?, childrenOf parent: WorksheetPath? = nil, rootsOnly: Bool = false, unlocks: Set<String> = []) throws -> [(path: WorksheetPath, worksheet: Worksheet)] {
        try lock.withLock {
            let rules = try policies()
            let start = try parent.map { try worksheetURL($0).deletingPathExtension() } ?? root
            try rejectLink(start)
            guard files.fileExists(atPath: start.path) else { return [] }
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            var pending = [(start, parent?.parts ?? [])]
            var result: [(path: WorksheetPath, worksheet: Worksheet)] = []
            while let (directory, parts) = pending.popLast() {
                let entries = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                for url in entries {
                    let properties = try url.resourceValues(forKeys: keys)
                    if properties.isSymbolicLink == true { continue }
                    if properties.isDirectory == true {
                        let nested = parts + [url.lastPathComponent]
                        if parent == nil, rootsOnly, let path = try? WorksheetPath(nested),
                           (try? worksheetURL(path)).map({ !files.fileExists(atPath: $0.path) }) == true,
                           let sheet = try? readDocument(path, rules: rules),
                           try accessLocked(path, sheet: sheet, user: user, unlocks: unlocks, rules: rules).listed {
                            result.append((path, sheet))
                        }
                        if parent == nil, !rootsOnly, nested.count < 12, (try? WorksheetPath(nested)) != nil { pending.append((url, nested)) }
                        continue
                    }
                    guard properties.isRegularFile == true, url.pathExtension == "json",
                          let path = try? WorksheetPath(parts + [url.deletingPathExtension().lastPathComponent]),
                          let worksheet = try? readDocument(path, rules: rules),
                          try accessLocked(path, sheet: worksheet, user: user, unlocks: unlocks, rules: rules).listed else { continue }
                    result.append((path, worksheet))
                }
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

    func open(_ path: WorksheetPath, user: User?, createOnly: Bool = false, unlocks: Set<String> = []) throws -> Worksheet {
        try lock.withLock { try openLocked(path, user: user, createOnly: createOnly, unlocks: unlocks) }
    }

    private func openLocked(_ path: WorksheetPath, user: User?, createOnly: Bool, unlocks: Set<String>) throws -> Worksheet {
        if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
        let url = try worksheetURL(path)
        let rules = try policies()
        let existing: Worksheet?
        do { existing = try readDocument(path, rules: rules) }
        catch let error as Abort where error.status == .notFound { existing = nil }
        if let worksheet = existing {
            try authorize(accessLocked(path, sheet: worksheet, user: user, unlocks: unlocks, rules: rules), user: user)
            if createOnly { throw Abort(.conflict, reason: "Ilyen nevű munkalap már létezik.") }
            return worksheet
        }
        guard let user else {
            throw Abort(.unauthorized, reason: "A munkalap létrehozásához be kell jelentkezni.")
        }
        let rawTitle = path.name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        var worksheet = Worksheet(title: rawTitle.isEmpty ? path.name : String(rawTitle.prefix(120)),
                                  creator: user.name, owner: user.name, isPublic: true)
        if path.parts.count > 1 {
            let parentPath = try WorksheetPath(Array(path.parts.dropLast()))
            let parent = try openLocked(parentPath, user: user, createOnly: false, unlocks: unlocks)
            guard try accessLocked(parentPath, sheet: parent, user: user, unlocks: unlocks, rules: policies()).editable else { throw Abort(.forbidden) }
            worksheet.background = parent.background
            worksheet.gridColor = parent.gridColor
            worksheet.gridSpacing = parent.gridSpacing
            worksheet.gridVisible = parent.gridVisible
            worksheet.owner = parent.owner
            worksheet.isPublic = parent.isPublic
        }
        try worksheet.validate()
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var next = try policies()
        if path.parts.count == 1 { next["project/" + path.url] = DocumentPolicy(publicEditing: true) }
        try writeDocument(worksheet, at: path, rules: next)
        return worksheet
    }

    func previewSVG(_ path: WorksheetPath, user: User?, unlocks: Set<String> = []) throws -> String {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let url = try worksheetURL(path)
            let rules = try policies()
            let sheet = try readDocument(path, rules: rules)
            try authorize(accessLocked(path, sheet: sheet, user: user, unlocks: unlocks, rules: rules), user: user)
            guard files.fileExists(atPath: url.path) else { return boardSVG(sheet) }
            let cache = url.deletingLastPathComponent().appendingPathComponent("." + path.name + ".preview-v3.svg")
            try rejectLink(cache)
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, let cached = try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               cached > modified { return try String(contentsOf: cache, encoding: .utf8) }
            let svg = boardSVG(sheet)
            try Data(svg.utf8).write(to: cache, options: .atomic)
            return svg
        }
    }

    func load(_ path: WorksheetPath, user: User?, unlocks: Set<String> = []) throws -> Worksheet {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let rules = try policies()
            let worksheet = try readDocument(path, rules: rules)
            try authorize(accessLocked(path, sheet: worksheet, user: user, unlocks: unlocks, rules: rules), user: user)
            return worksheet
        }
    }

    func update(_ path: WorksheetPath, worksheet: Worksheet, user: User, restoring: Bool = false, unlocks: Set<String> = [],
                checkSelection: (Worksheet) throws -> Void = { _ in }) throws -> Worksheet {
        try lock.withLock {
            let rules = try policies()
            let current = try readDocument(path, rules: rules)
            guard try accessLocked(path, sheet: current, user: user, unlocks: unlocks, rules: rules).editable else { throw Abort(.forbidden) }
            guard worksheet.revision == current.revision else {
                throw Abort(.preconditionFailed, reason: "A munkalapot közben más módosította. A helyi változtatásaid megmaradtak.")
            }
            try checkSelection(current)
            for node in worksheet.nodes {
                if let value = node.link, !value.isEmpty, WorksheetLink(value)?.destination(from: path) == nil {
                    throw Abort(.unprocessableEntity, reason: "Érvénytelen link. Adj meg egy munkalapútvonalat vagy HTTP(S) webcímet.")
                }
            }
            var updated = worksheet
            updated.creator = current.creator
            if current.owner != updated.owner {
                guard user.role == .admin else { throw Abort(.forbidden) }
                guard let owner = updated.owner, try readUsers().contains(where: { $0.name == owner }) else {
                    throw Abort(.unprocessableEntity, reason: "Válassz létező tulajdonost.")
                }
            }
            if current.editors != updated.editors || current.isPublic != updated.isPublic || current.hidden != updated.hidden {
                guard current.canManage(user) else { throw Abort(.forbidden) }
                if current.editors != updated.editors {
                    let accounts = Set(try readUsers().map(\.name))
                    let added = Set(updated.editors ?? []).subtracting(current.editors ?? [])
                    guard added.isSubset(of: accounts) else {
                        throw Abort(.unprocessableEntity, reason: "Csak létező fiók kaphat szerkesztési jogot.")
                    }
                    if let editors = updated.editors { updated.editors = Array(Set(editors)).sorted() }
                }
            }
            updated.revision = current.revision + 1
            updated.resetRevision = restoring ? updated.revision : current.resetRevision
            try updated.validate()
            updated.schemaVersion = 2
            try writeDocument(updated, at: path, rules: rules)
            return updated
        }
    }

    func manage(_ path: WorksheetPath, operation: DocumentAction, user: User, unlocks: Set<String>) throws -> WorksheetPath? {
        try lock.withLock {
            let url = try worksheetURL(path)
            var rules = try policies()
            let sheet = try readDocument(path, rules: rules)
            guard try accessLocked(path, sheet: sheet, user: user, unlocks: unlocks, rules: rules).manageable else { throw Abort(.forbidden) }
            let project = operation.scope == "project"
            let key: String
            if operation.scope == "attachment", let filename = operation.filename,
               ["grant", "revoke"].contains(operation.action) {
                guard try attachments(at: url, named: filename).first != nil else { throw Abort(.notFound) }
                key = attachmentPolicyKey(path, filename)
            } else {
                guard (project && path.parts.count == 1) || operation.scope == "sheet" else { throw Abort(.badRequest) }
                key = operation.scope + "/" + path.url
            }
            var rule = rules[key] ?? DocumentPolicy()
            switch operation.action {
            case "hide":
                rule.hidden = !(rule.hidden ?? false)
            case "freeze":
                rule.frozen = !(rule.frozen ?? false)
            case "mode" where project:
                guard let value = operation.value, ["public", "internal"].contains(value) else { throw Abort(.badRequest) }
                rule.publicEditing = value == "public"
            case "password":
                let password = operation.value ?? ""
                guard password.utf8.count <= 72 else { throw Abort(.badRequest) }
                rule.passwordHash = password.isEmpty ? nil : try Bcrypt.hash(password)
            case "grant", "revoke":
                guard let name = operation.value, try readUsers().contains(where: { $0.name == name }) else {
                    throw Abort(.badRequest, reason: "A felhasználó nem létezik.")
                }
                let sheetScope = operation.scope == "sheet"
                var users = Set((sheetScope ? sheet.editors : rule.users) ?? [])
                if operation.action == "grant" { users.insert(name) } else { users.remove(name) }
                if sheetScope {
                    rule.editors = users.sorted()
                    rule.users = nil
                } else {
                    rule.users = users.sorted()
                }
            case "rename", "delete":
                let renamed: WorksheetPath?
                let destination: URL
                if operation.action == "rename" {
                    guard let name = operation.value else { throw Abort(.badRequest) }
                    let next = try WorksheetPath(Array(path.parts.dropLast()) + [name])
                    if next.url == path.url { return next }
                    destination = try worksheetURL(next)
                    renamed = next
                } else {
                    let trash = root.appendingPathComponent(".trash/" + UUID().uuidString, isDirectory: true)
                    try rejectLink(root.appendingPathComponent(".trash"))
                    try files.createDirectory(at: trash, withIntermediateDirectories: true)
                    destination = trash.appendingPathComponent(url.lastPathComponent)
                    renamed = nil
                }
                let directory = url.deletingPathExtension()
                let destinationDirectory = destination.deletingPathExtension()
                try rejectLink(directory)
                try rejectLink(destinationDirectory)
                guard !files.fileExists(atPath: destination.path), !files.fileExists(atPath: destinationDirectory.path) else { throw Abort(.conflict) }
                let moveDirectory = (project || renamed != nil) && files.fileExists(atPath: directory.path)
                let oldScope = key
                let oldPolicyPaths = rules.keys.filter { key in
                    let document = key.split(separator: "/", maxSplits: 1).last.map(String.init) ?? ""
                    return (document == path.url && (project || renamed != nil || key == oldScope)) || ((project || renamed != nil) && document.hasPrefix(path.url + "/"))
                }
                for old in oldPolicyPaths {
                    let value = rules.removeValue(forKey: old)
                    if let renamed, let slash = old.firstIndex(of: "/") {
                        let suffix = old[old.index(after: slash)...].dropFirst(path.url.count)
                        rules[String(old[...slash]) + renamed.url + suffix] = value
                    }
                }
                let moveFile = files.fileExists(atPath: url.path)
                if moveFile { try files.moveItem(at: url, to: destination) }
                do {
                    if moveDirectory { try files.moveItem(at: directory, to: destinationDirectory) }
                    try write(rules, to: policyURL)
                } catch {
                    if moveDirectory && files.fileExists(atPath: destinationDirectory.path) {
                        try? files.moveItem(at: destinationDirectory, to: directory)
                    }
                    if moveFile { try? files.moveItem(at: destination, to: url) }
                    throw error
                }
                return renamed
            default:
                throw Abort(.badRequest)
            }
            rules[key] = rule
            try write(rules, to: policyURL)
            return path
        }
    }

    func contents(_ path: WorksheetPath, user: User?, unlocks: Set<String>, named name: String? = nil) throws -> [URL] {
        try lock.withLock {
            let url = try worksheetURL(path)
            let rules = try policies()
            let sheet = try readDocument(path, rules: rules)
            let access = try accessLocked(path, sheet: sheet, user: user, unlocks: unlocks, rules: rules)
            if attachmentGranted(path, file: name, user: user, rules: rules) {
                if access.passwordRequired { throw Abort(.locked, reason: "Ehhez a fájlhoz jelszó szükséges.") }
            } else {
                try authorize(access, user: user)
            }
            return try attachments(at: url, named: name)
        }
    }

    private func attachments(at url: URL, named name: String?) throws -> [URL] {
        let directory = url.deletingPathExtension()
        try rejectLink(directory)
        guard files.fileExists(atPath: directory.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        let entries = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        return try entries.filter { file in
            guard name == nil || file.lastPathComponent == name else { return false }
            let info = try file.resourceValues(forKeys: keys)
            if info.isSymbolicLink == true || info.isRegularFile != true { return false }
            // Worksheets use the normal authenticated document routes.
            return file.pathExtension.lowercased() != "json" || (try? read(file)) == nil
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
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
            let destination = trash.appendingPathComponent("\(UUID().uuidString)-\(path.name).json")
            var rules = try policies()
            // A surviving directory can still contain protected children or attachments.
            let removePolicy = !files.fileExists(atPath: url.deletingPathExtension().path)
                && rules.removeValue(forKey: "sheet/" + path.url) != nil
            try files.moveItem(at: url, to: destination)
            if removePolicy {
                do { try write(rules, to: policyURL) }
                catch { try files.moveItem(at: destination, to: url); throw error }
            }
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
        var worksheet = try JSONDecoder().decode(Worksheet.self, from: Data(contentsOf: url))
        worksheet.detachLegacyDuplicateConnections()
        worksheet.dissolveUnusedJunctions()
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

extension Idea {
    private enum Legacy: String, CodingKey { case markdown, showMarkdown, markdownStyle, markdownFill, markdownBorder }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: Legacy.self)
        id = try fields.decode(String.self, forKey: .id)
        title = try fields.decode(String.self, forKey: .title)
        text = try fields.decodeIfPresent(String.self, forKey: .text) ?? legacy.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        hideText = try fields.decodeIfPresent(Bool.self, forKey: .hideText) ?? legacy.decodeIfPresent(Bool.self, forKey: .showMarkdown).map { !$0 }
        position = try fields.decode(Point.self, forKey: .position)
        width = try fields.decode(Double.self, forKey: .width)
        height = try fields.decode(Double.self, forKey: .height)
        shape = try fields.decode(Shape.self, forKey: .shape)
        fill = try fields.decode(String.self, forKey: .fill)
        textColor = try fields.decode(String.self, forKey: .textColor)
        border = try fields.decode(String.self, forKey: .border)
        fontSize = try fields.decode(Double.self, forKey: .fontSize)
        bold = try fields.decode(Bool.self, forKey: .bold)
        alignment = try fields.decode(LabelAlignment.self, forKey: .alignment)
        verticalAlignment = try fields.decodeIfPresent(VerticalAlignment.self, forKey: .verticalAlignment)
        titleOutside = try fields.decodeIfPresent(Bool.self, forKey: .titleOutside)
        link = try fields.decodeIfPresent(String.self, forKey: .link)
        kind = try fields.decodeIfPresent(IdeaKind.self, forKey: .kind)
        parent = try fields.decodeIfPresent(String.self, forKey: .parent)
        locked = try fields.decodeIfPresent(Bool.self, forKey: .locked)
        italic = try fields.decodeIfPresent(Bool.self, forKey: .italic)
        underline = try fields.decodeIfPresent(Bool.self, forKey: .underline)
        textStyle = try fields.decodeIfPresent(TextStyle.self, forKey: .textStyle) ?? legacy.decodeIfPresent(TextStyle.self, forKey: .markdownStyle)
        textFill = try fields.decodeIfPresent(String.self, forKey: .textFill) ?? legacy.decodeIfPresent(String.self, forKey: .markdownFill)
        textBorder = try fields.decodeIfPresent(String.self, forKey: .textBorder) ?? legacy.decodeIfPresent(String.self, forKey: .markdownBorder)
        if legacy.contains(.markdown) {
            fontSize = fontSize.rounded()
            if let size = textStyle?.size { textStyle?.size = size.rounded() }
        }
    }
}

extension Worksheet {
    private enum Legacy: String, CodingKey { case markdown }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: Legacy.self)
        schemaVersion = try fields.decode(Int.self, forKey: .schemaVersion)
        revision = try fields.decode(Int.self, forKey: .revision)
        resetRevision = try fields.decodeIfPresent(Int.self, forKey: .resetRevision)
        title = try fields.decode(String.self, forKey: .title)
        text = try fields.decodeIfPresent(String.self, forKey: .text) ?? legacy.decodeIfPresent(String.self, forKey: .markdown)
        background = try fields.decodeIfPresent(String.self, forKey: .background)
        gridColor = try fields.decodeIfPresent(String.self, forKey: .gridColor)
        gridSpacing = try fields.decodeIfPresent(Double.self, forKey: .gridSpacing)
        gridVisible = try fields.decodeIfPresent(Bool.self, forKey: .gridVisible)
        creator = try fields.decodeIfPresent(String.self, forKey: .creator)
        owner = try fields.decodeIfPresent(String.self, forKey: .owner)
        editors = try fields.decodeIfPresent([String].self, forKey: .editors)
        hidden = try fields.decodeIfPresent(Bool.self, forKey: .hidden)
        isPublic = try fields.decodeIfPresent(Bool.self, forKey: .isPublic)
        nodes = try fields.decode([Idea].self, forKey: .nodes)
        edges = try fields.decode([Connection].self, forKey: .edges)
    }
}
