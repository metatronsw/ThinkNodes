import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Vapor

struct Point: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    var isValid: Bool {
        x.isFinite && y.isFinite && abs(x) <= 100_000 && abs(y) <= 100_000
    }
}

private struct WorksheetElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private func automaticBorder(_ fill: String) -> String {
    guard let rgb = Int(fill.dropFirst(), radix: 16) else { return "#526982" }
    return String(format: "#%02x%02x%02x", (rgb >> 16) * 2 / 3, ((rgb >> 8) & 255) * 2 / 3, (rgb & 255) * 2 / 3)
}

enum Shape: String, Codable, Sendable {
    case rounded, rectangle, ellipse, diamond
    case triangle, pentagon, hexagon, parallelogram
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
    var justified: Bool?
    var alignment: LabelAlignment?
    var verticalAlignment: VerticalAlignment?

    private enum CodingKeys: String, CodingKey {
        case color, size, bold, italic, underline, justified
        case alignment = "align", verticalAlignment = "vAlign"
    }

    var isValid: Bool {
        (color.map(validColor) ?? true) && (size.map { (1...10000).contains($0) && $0.rounded() == $0 } ?? true)
    }
}

enum CanvasFileType: String, Codable, Sendable { case image, mp3, txt, md, json, attachment }

struct CanvasFile: Codable, Equatable, Sendable {
    var type: CanvasFileType
    var asset: String?
    var hideTitle: Bool?
    var filename: String?
    var showFilename: Bool?
    var alphaEnabled: Bool?
    var alphaBackground: String?

    var imageStem: String {
        filename ?? asset.map { ($0 as NSString).deletingPathExtension } ?? ""
    }
}

private func validImageStem(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 200 && !value.hasPrefix(".")
        && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || "/\\:".unicodeScalars.contains($0) }
}

func canvasAssetType(_ name: String) -> String? {
    let parts = name.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
          id.uuidString.lowercased() == parts[0] else { return nil }
    return canvasMediaTypes[String(parts[1])]
}

private final class SVGDocument: NSObject, XMLParserDelegate {
    private var hasSVGRoot = false

    static func matches(_ bytes: Data) -> Bool {
        let document = SVGDocument()
        let parser = XMLParser(data: bytes)
        parser.shouldProcessNamespaces = true
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = document
        return parser.parse() && document.hasSVGRoot
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard !hasSVGRoot else { return }
        hasSVGRoot = elementName == "svg" && namespaceURI == "http://www.w3.org/2000/svg"
        if !hasSVGRoot { parser.abortParsing() }
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        parser.abortParsing()
    }
}

private func matchesMediaHeader(_ bytes: Data, type: String) -> Bool {
    switch type {
    case "image/png": return bytes.starts(with: [137,80,78,71,13,10,26,10])
    case "image/jpeg": return bytes.starts(with: [255,216,255])
    case "image/gif": return bytes.starts(with: "GIF87a".utf8) || bytes.starts(with: "GIF89a".utf8)
    case "image/webp": return bytes.starts(with: "RIFF".utf8) && bytes.dropFirst(8).starts(with: "WEBP".utf8)
    case "image/svg+xml": return SVGDocument.matches(bytes)
    case "audio/mpeg":
        return bytes.starts(with: "ID3".utf8) || (bytes.count >= 4 && bytes[0] == 255 && bytes[1] & 0xe6 == 0xe2)
    default: return false
    }
}

let canvasMediaTypes = ["png": "image/png", "jpg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
                        "svg": "image/svg+xml", "mp3": "audio/mpeg"]

private func matchesAttachmentType(_ bytes: Data, extension ext: String) -> Bool {
    if let mime = canvasMediaTypes[ext == "jpeg" ? "jpg" : ext] {
        return matchesMediaHeader(bytes, type: mime)
    }
    switch ext {
    case "wav": return bytes.starts(with: "RIFF".utf8) && bytes.dropFirst(8).starts(with: "WAVE".utf8)
    case "ogg": return bytes.starts(with: "OggS".utf8)
    case "flac": return bytes.starts(with: "fLaC".utf8)
    case "pdf": return bytes.starts(with: "%PDF-".utf8)
    case "txt", "md": return String(data: bytes, encoding: .utf8)?.contains("\0") == false
    case "json": return (try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])) != nil
    case "zip", "docx", "xlsx", "pptx":
        return bytes.starts(with: [0x50, 0x4b, 0x03, 0x04]) || bytes.starts(with: [0x50, 0x4b, 0x05, 0x06])
    default: return ext != "thnode"
    }
}

enum BoxAnimation: String, Codable, Sendable {
    case none, pulse, blink, rock, hop
}

struct Idea: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var text = ""
    var file: CanvasFile?
    var hideText: Bool?
    var position: Point
    var width: Double = 176
    var height: Double = 80
    var shape: Shape = .rounded
    var fill = "#dce9ff"
    var backgroundEnabled: Bool?
    var animation: BoxAnimation?
    var textColor = "#182335"
    var border: String { automaticBorder(fill) }
    var fitText: Bool?
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

    private enum CodingKeys: String, CodingKey {
        case id, title, text, file, hideText, fitText, shape, fill, backgroundEnabled, animation, bold, titleOutside, link
        case kind, parent, locked, italic, underline, textStyle
        case position = "pos", width = "w", height = "h", textColor = "textCol"
        case fontSize = "fontSz", alignment = "align", verticalAlignment = "vAlign"
    }

    var isValid: Bool {
        let sizeValid = kind == .connectionPoint ? (4...128).contains(width) && height == width :
            (64...880).contains(width) && (40...680).contains(height)
        guard validSlug(id), validTitle(title) || (title.isEmpty && (kind == .connectionPoint || file?.type == .image)),
              text.utf8.count <= 100_000, sizeValid else { return false }
        if let file {
            switch file.type {
            case .image:
                guard file.asset.flatMap(canvasAssetType)?.hasPrefix("image/") == true,
                      file.filename.map(validImageStem) ?? true, file.alphaBackground.map(validColor) ?? true else { return false }
            case .mp3: guard file.asset.flatMap(canvasAssetType) == "audio/mpeg" else { return false }
            case .txt, .json, .md: guard file.asset == nil else { return false }
            case .attachment:
                guard let name = file.asset, validImageStem(name),
                      (name as NSString).pathExtension.lowercased() != "thnode" else { return false }
            }
        }
        let validContent = position.isValid
            && (link.map { $0.isEmpty || WorksheetLink($0) != nil } ?? true)
        return validContent && (textStyle?.isValid ?? true)
            && (1...10000).contains(fontSize) && fontSize.rounded() == fontSize
            && [fill, textColor, border].allSatisfy(validColor)
    }
}

enum ConnectionType: String, Codable, CaseIterable, Sendable {
    case straight, sCurve, zigzag, lightning, arc, rope

    var label: String {
        switch self {
        case .straight: "Egyenes"
        case .sCurve: "S-forma"
        case .zigzag: "Villám"
        case .lightning: "Tört"
        case .arc: "Íves"
        case .rope: "Kötél"
        }
    }
}

enum ConnectionAppearance: String, Codable, CaseIterable, Sendable {
    case plain, thick, dashed, dotted
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

extension ConnectionTarget {
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        node = try? fields.decode(String.self, forKey: .node)
        point = try? fields.decode(Point.self, forKey: .point)
    }
}

struct Connection: Equatable, Codable, Sendable {
    var id: String
    var source: String?
    var sourcePoint: Point?
    var target: ConnectionTarget
    var type: ConnectionType = .straight
    var appearance: ConnectionAppearance = .plain
    var animated: Bool?
    var color: String?
    var width: Double?
    var startArrow: Bool?
    var endArrow: Bool?
    var label: String?

    private enum CodingKeys: String, CodingKey {
        case id, source, target, type, appearance, animated, color, startArrow, endArrow, label
        case sourcePoint = "srcPt", width = "w"
    }

    var origin: ConnectionTarget { ConnectionTarget(node: source, point: sourcePoint) }
    var strokeColor: String { color ?? "#526982" }
    var strokeWidth: Double { min(24, (width ?? 2) * (appearance == .thick ? 2 : 1)) }
    var hasStartArrow: Bool { startArrow ?? false }
    var hasEndArrow: Bool { endArrow ?? true }
}

extension Connection {
    private enum LegacyKey: String, CodingKey { case style }
    private enum LegacyStyle: String, Decodable { case arrow, both, solid, dashed, rope }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try? decoder.container(keyedBy: LegacyKey.self).decodeIfPresent(LegacyStyle.self, forKey: .style)
        id = (try? fields.decode(String.self, forKey: .id)) ?? "line-\(decoder.codingPath.last?.intValue ?? 0)"
        source = (try? fields.decode(String.self, forKey: .source))
        sourcePoint = (try? fields.decode(Point.self, forKey: .sourcePoint))
        target = (try? fields.decode(ConnectionTarget.self, forKey: .target)) ?? ConnectionTarget()
        if target.node == nil && target.point == nil { target.point = Point(x: 0, y: 0) }
        if source == nil && sourcePoint == nil { sourcePoint = Point(x: 0, y: 0) }
        type = (try? fields.decode(ConnectionType.self, forKey: .type)) ?? (legacy == .rope ? .rope : .straight)
        appearance = (try? fields.decode(ConnectionAppearance.self, forKey: .appearance)) ?? (legacy == .dashed ? .dashed : .plain)
        animated = try? fields.decode(Bool.self, forKey: .animated)
        color = (try? fields.decode(String.self, forKey: .color))
        width = (try? fields.decode(Double.self, forKey: .width))
        startArrow = (try? fields.decode(Bool.self, forKey: .startArrow)) ?? (legacy == .both ? true : nil)
        endArrow = (try? fields.decode(Bool.self, forKey: .endArrow)) ?? (legacy == .rope || legacy == .solid ? false : nil)
        label = (try? fields.decode(String.self, forKey: .label))
    }
}

struct Worksheet: Content, Equatable {
    var schemaVersion = 2
    var revision = 1
    var resetRevision: Int?
    var title: String
    var text: String?
    var previewImage: String?
    var textJustified: Bool?
    var background: String?
    var gridSpacing: Double?
    var creator: String?
    var nodes: [Idea] = []
    var edges: [Connection] = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, resetRevision, title, text, textJustified, background
        case creator, nodes, edges, previewImage
        case gridSpacing = "gridStep"
    }

    var backgroundColor: String { background ?? "#f5f8fc" }

    private var junctionDegrees: [String: Int] {
        var counts: [String: Int] = [:]
        for edge in edges {
            if let source = edge.source { counts[source, default: 0] += 1 }
            if let target = edge.target.node, target != edge.source { counts[target, default: 0] += 1 }
        }
        return counts
    }

    private var duplicateConnections: [Int] {
        var pairs = Set<[String]>()
        return edges.indices.filter { i in
            guard let from = edges[i].source, let to = edges[i].target.node else { return false }
            return !pairs.insert([from, to]).inserted
        }
    }

    func validate() throws {
        guard duplicateConnections.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Ezen az útvonalon már van kábel.")
        }
        let nodeIDs = Set(nodes.map(\.id))
        guard schemaVersion == 2, revision > 0, revision < Int.max, validTitle(title),
              (text?.utf8.count ?? 0) <= 100_000, validColor(backgroundColor),
              (6...160).contains(gridSpacing ?? 32),
              nodes.count <= 2_000, edges.count <= 4_000,
              nodeIDs.count == nodes.count, Set(edges.map(\.id)).count == edges.count,
              nodes.allSatisfy(\.isValid), edges.allSatisfy({
                  validSlug($0.id) && $0.origin.isValid(in: nodeIDs) && $0.target.isValid(in: nodeIDs)
                      && ($0.source == nil || $0.source != $0.target.node)
                      && validColor($0.strokeColor) && (0.5...24).contains($0.width ?? 2)
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

struct UserPreferences: Content {
    var snap = false
    var showGrid = true
    var panLocked = false
    var avatar: Int?
    var theme: String?
}

func previewType(_ url: URL) -> String? {
    let ext = url.pathExtension.lowercased()
    let type = canvasMediaTypes[ext == "jpeg" ? "jpg" : ext]
    return type?.hasPrefix("image/") == true ? type : nil
}

struct SiteSettings: Codable, Sendable {
    var requireLogin = false
    var preferences: [String: UserPreferences]?
    var users: [User]?
}

enum Role: String, Codable, Sendable {
    case editor, admin
}

struct User: Codable, Sendable {
    var name: String
    var role: Role
    var passwordHash: String
    var avatar: Int?
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

struct DocumentPolicy: Codable, Sendable, Equatable {
    var hidden: Bool?
    var frozen: Bool?
    var owner: String?
    var editors: [String]?
    var guestReadable: Bool?
    var passwordHash: String?
    var mediaFiles: [String: String]?
    var worksheets: [String: PageSettings]?
}

struct PageSettings: Codable, Sendable, Equatable {
    var hidden = false
    var frozen: Bool?
    var passwordHash: String?
}

struct DocumentAccess: Sendable {
    var folderPath = ""
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
    var dataDirectoryPath: String { root.path }
    let testMode: Bool
    private var testerCount = 0

    func nextTester() -> String {
        lock.withLock { testerCount += 1; return "Tester" + String(testerCount) }
    }

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

    private func folder(_ path: WorksheetPath) throws -> URL {
        var url = root
        for part in path.parts {
            url.appendPathComponent(part)
            try checkName(url)
        }
        return url
    }

    private func checkName(_ url: URL) throws {
        try rejectLink(url)
        if files.fileExists(atPath: url.path),
           !(try files.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)).contains(url.lastPathComponent) {
            throw Abort(.notFound)
        }
    }

    private func worksheetURL(_ path: WorksheetPath) throws -> URL {
        let entry = try folder(path)
        var isDir: ObjCBool = false
        let directory = files.fileExists(atPath: entry.path, isDirectory: &isDir) && isDir.boolValue
        if !directory && path.parts.count == 1 { throw Abort(.notFound) }
        if !directory && path.name == path.parts.dropLast().last { throw Abort(.notFound) }
        let url = (directory ? entry.appendingPathComponent(path.name) : entry).appendingPathExtension("thnode")
        try checkName(url)
        return url
    }

    private func settingsURL(_ directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(".settings.json")
        try rejectLink(url)
        return url
    }

    private struct Context {
        var chain: [URL]
        var rules: [URL: DocumentPolicy]
        let key: String
        let folderPath: String
        var project: URL { chain[0] }
        var directory: URL { chain[chain.count-1] }
        var local: DocumentPolicy { rules[directory]! }
        var page: PageSettings { rules[project]?.worksheets?[key] ?? PageSettings() }
        mutating func setPage(_ page: PageSettings?) {
            var pages = rules[project]?.worksheets ?? [:]
            pages[key] = page
            rules[project]?.worksheets = pages
        }
    }

    private func context(_ path: WorksheetPath) throws -> Context {
        let file = try worksheetURL(path)
        let main = file.deletingLastPathComponent().lastPathComponent == file.deletingPathExtension().lastPathComponent
        let parts = main ? path.parts : Array(path.parts.dropLast())
        var chain: [URL] = [], rules: [URL: DocumentPolicy] = [:]
        var directory = root
        for part in parts {
            directory.appendPathComponent(part)
            let url = try settingsURL(directory)
            guard files.fileExists(atPath: url.path) else { throw Abort(.notFound) }
            rules[directory] = try JSONDecoder().decode(DocumentPolicy.self, from: Data(contentsOf: url))
            chain.append(directory)
        }
        let key = (Array(parts.dropFirst()) + [file.lastPathComponent]).joined(separator: "/")
        return try Context(chain: chain, rules: rules, key: key, folderPath: WorksheetPath(parts).url)
    }

    private func persist(_ next: Context, previous: Context) throws {
        var written: [URL] = []
        do {
            for directory in next.chain where next.rules[directory] != previous.rules[directory] {
                try write(next.rules[directory]!, to: settingsURL(directory))
                written.append(directory)
            }
        } catch {
            for directory in written.reversed() { try write(previous.rules[directory]!, to: settingsURL(directory)) }
            throw error
        }
    }

    private func accessLocked(_ ctx: Context, user: User?, unlocks: Set<String>) -> DocumentAccess {
        var readable = true, editable = true, locked = false, frozen = false, protected = false
        var names: Set<String>?
        let admin = user?.role == .admin
        for directory in ctx.chain {
            let rule = ctx.rules[directory]!
            let members = Set((rule.editors ?? []) + [rule.owner].compactMap { $0 })
            names = names?.intersection(members) ?? members
            let member = user.map { members.contains($0.name) } == true
            readable = readable && (admin || member || rule.guestReadable == true)
            editable = editable && (admin || member)
            frozen = frozen || rule.frozen == true
            if let hash = rule.passwordHash {
                protected = true
                locked = locked || (!admin && user?.name != rule.owner && !unlocks.contains(hash))
            }
        }
        let page = ctx.page
        if let hash = page.passwordHash {
            protected = true
            locked = locked || (!admin && user?.name != ctx.local.owner && !unlocks.contains(hash))
        }
        frozen = frozen || page.frozen == true
        let manager = editable && (admin || user?.name == ctx.local.owner)
        var menu = ctx.local
        menu.hidden = page.hidden
        if ctx.key.split(separator: "/").last != Substring(ctx.directory.lastPathComponent + ".thnode") {
            menu.frozen = page.frozen
            menu.passwordHash = page.passwordHash
        }
        return DocumentAccess(folderPath: ctx.folderPath, readable: readable && !locked, editable: editable && !locked && (!frozen || manager),
            manageable: manager && !locked, listed: readable && !page.hidden,
            locked: readable && locked, hidden: page.hidden, projectRule: menu, sheetRule: menu,
            editorNames: (names ?? []).sorted(), protectedByPassword: protected, frozen: frozen, passwordRequired: locked)
    }

    func access(_ path: WorksheetPath, sheet: Worksheet, user: User?, unlocks: Set<String> = []) throws -> DocumentAccess {
        try lock.withLock { try accessLocked(context(path), user: user, unlocks: unlocks) }
    }

    private func authorize(_ access: DocumentAccess, user: User?) throws {
        if access.locked { throw Abort(.locked, reason: "Ehhez a munkalaphoz jelszó szükséges.") }
        if !access.readable { throw Abort(user == nil ? .unauthorized : .forbidden) }
    }

    func unlock(_ path: WorksheetPath, password: String, user: User?, attachment: String? = nil) throws -> [String] {
        try lock.withLock {
            let ctx = try context(path)
            guard accessLocked(ctx, user: user, unlocks: []).locked else { throw Abort(.forbidden) }
            let hashes = try (ctx.chain.compactMap { ctx.rules[$0]?.passwordHash } + [ctx.page.passwordHash].compactMap { $0 })
                .filter { try Bcrypt.verify(password, created: $0) }
            guard !hashes.isEmpty else { throw Abort(.forbidden) }
            return hashes
        }
    }

    func list(user: User?, childrenOf parent: WorksheetPath? = nil, rootsOnly: Bool = false, recursive: Bool = false, unlocks: Set<String> = []) throws -> [(path: WorksheetPath, worksheet: Worksheet)] {
        try lock.withLock {
            var result: [(path: WorksheetPath, worksheet: Worksheet)] = []
            func visit(_ directory: URL, _ parts: [String]) throws {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
                for entry in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
                    let info = try entry.resourceValues(forKeys: keys)
                    guard info.isSymbolicLink != true else { continue }
                    let isFolder = info.isDirectory == true
                    let name = isFolder ? entry.lastPathComponent : entry.deletingPathExtension().lastPathComponent
                    guard isFolder || (!parts.isEmpty && info.isRegularFile == true && entry.pathExtension == "thnode" && name != parts.last),
                          let path = try? WorksheetPath(parts + [name]), let ctx = try? context(path) else { continue }
                    let rights = accessLocked(ctx, user: user, unlocks: unlocks)
                    guard rights.listed, let sheet = try? read(worksheetURL(path)) else { continue }
                    result.append((path, sheet))
                    if isFolder && rights.readable && !rootsOnly && (recursive || parent == nil) { try visit(entry, path.parts) }
                }
            }
            if let parent {
                let ctx = try context(parent)
                try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
                if parent.url == ctx.folderPath { try visit(ctx.directory, parent.parts) }
            } else { try visit(root, []) }
            return result.sorted { $0.path.parts.lexicographicallyPrecedes($1.path.parts) }
        }
    }

    func settings() throws -> SiteSettings {
        try lock.withLock { try readSettings() }
    }

    func savePreferences(_ prefs: UserPreferences, for name: String) throws {
        guard prefs.avatar.map({ (1...12).contains($0) }) ?? true,
              prefs.theme.map(validSlug) ?? true else { throw Abort(.badRequest) }
        try lock.withLock {
            var settings = try readSettings()
            var entries = settings.preferences ?? [:]
            entries[name] = prefs
            settings.preferences = entries
            try saveSiteSettings(settings)
        }
    }

    func setSettings(_ settings: SiteSettings) throws {
        try lock.withLock {
            try rejectLink(settingsFile)
            var next = settings
            let existing = try readSettings()
            next.users = existing.users
            next.preferences = existing.preferences
            try saveSiteSettings(next)
        }
    }

    func open(_ path: WorksheetPath, user: User?, createOnly: Bool = false, unlocks: Set<String> = [], directory: Bool = false) throws -> Worksheet {
        try lock.withLock { try openLocked(path, user: user, createOnly: createOnly, unlocks: unlocks, directory: directory).worksheet }
    }

    func openWithStatus(_ path: WorksheetPath, user: User?, createOnly: Bool = false, unlocks: Set<String>) throws -> (worksheet: Worksheet, created: Bool) {
        try lock.withLock { try openLocked(path, user: user, createOnly: createOnly, unlocks: unlocks, directory: false) }
    }

    private func openLocked(_ path: WorksheetPath, user: User?, createOnly: Bool, unlocks: Set<String>, directory: Bool) throws -> (worksheet: Worksheet, created: Bool) {
        if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
        let entry = try folder(path)
        if let url = try? worksheetURL(path), files.fileExists(atPath: url.path) {
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            if createOnly { throw Abort(.conflict) }
            return (try read(worksheetURL(path)), false)
        }
        guard let user else { throw Abort(.unauthorized) }
        var inherited = DocumentPolicy(owner: user.name, guestReadable: false)
        var sheet = Worksheet(title: String(path.name.prefix(120)), creator: user.name)
        if path.parts.count > 1 {
            let parent = try WorksheetPath(Array(path.parts.dropLast()))
            guard parent.name != path.name else { throw Abort(.conflict) }
            let parentSheet = try openLocked(parent, user: user, createOnly: false, unlocks: unlocks, directory: true).worksheet
            let ctx = try context(parent)
            guard ctx.folderPath == parent.url else { throw Abort(.conflict, reason: "Mappát válassz szülőnek.") }
            guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
            inherited = ctx.local
            inherited.mediaFiles = nil
            inherited.worksheets = nil
            sheet.background = parentSheet.background
            sheet.gridSpacing = parentSheet.gridSpacing
        }
        guard !files.fileExists(atPath: entry.path) else { throw Abort(.conflict) }
        let makeFolder = directory || path.parts.count == 1
        if makeFolder {
            try files.createDirectory(at: entry, withIntermediateDirectories: false)
        }
        var createdFile: URL?
        do {
            if makeFolder { try write(inherited, to: settingsURL(entry)) }
            let url = try worksheetURL(path)
            guard !files.fileExists(atPath: url.path) else { throw Abort(.conflict) }
            try write(sheet, to: url)
            createdFile = url
            let ctx = try context(path)
            var next = ctx
            next.setPage(PageSettings())
            try persist(next, previous: ctx)
            return (try read(worksheetURL(path)), true)
        } catch {
            if makeFolder { try files.removeItem(at: entry) }
            else if let createdFile { try files.removeItem(at: createdFile) }
            throw error
        }
    }

    enum Preview { case drawing(String), image(URL, String) }

    func preview(_ path: WorksheetPath, user: User?, unlocks: Set<String> = []) throws -> Preview {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let url = try worksheetURL(path)
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            let sheet = try read(url)
            if let name = sheet.previewImage,
               let file = try attachments(at: url, named: name, metadata: ctx.local).first,
               let mime = previewType(file) { return .image(file, mime) }
            let cache = url.deletingLastPathComponent().appendingPathComponent("." + path.name + ".preview-v8.svg")
            try rejectLink(cache)
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, let cached = try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               cached > modified { return .drawing(try String(contentsOf: cache, encoding: .utf8)) }
            let svg = boardSVG(sheet, assetBase: "/" + path.url)
            try Data(svg.utf8).write(to: cache, options: .atomic)
            return .drawing(svg)
        }
    }

    func load(_ path: WorksheetPath, user: User?, unlocks: Set<String> = []) throws -> Worksheet {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            return try read(worksheetURL(path))
        }
    }

    func update(_ path: WorksheetPath, worksheet: Worksheet, user: User, restoring: Bool = false, unlocks: Set<String> = [],
                checkSelection: (Worksheet) throws -> Void = { _ in }) throws -> Worksheet {
        try lock.withLock {
            let ctx = try context(path)
            var next = ctx
            let current = try read(worksheetURL(path))
            guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
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
            updated.revision = current.revision + 1
            updated.resetRevision = restoring ? updated.revision : current.resetRevision
            try updated.validate()
            updated.schemaVersion = 2
            let url = try worksheetURL(path)
            let directory = ctx.directory
            var metadata = ctx.local
            var media = metadata.mediaFiles ?? [:]
            let previousImages = Dictionary(uniqueKeysWithValues: current.nodes.map { ($0.id, $0.file) })
            var renames: [String: String] = [:]
            for node in updated.nodes {
                guard let file = node.file, file.type == .image, let asset = file.asset else { continue }
                let previous = previousImages[node.id] ?? nil
                if previous?.asset == asset && previous?.filename == file.filename { continue }
                if let prior = renames.updateValue(file.imageStem, forKey: asset), prior != file.imageStem {
                    throw Abort(.unprocessableEntity, reason: "Egy képfájlhoz csak egy név tartozhat.")
                }
            }
            var moved: [(from: URL, to: URL)] = []
            do {
                for (asset, stem) in renames.sorted(by: { $0.key < $1.key }) {
                    guard let source = try attachments(at: url, named: asset, metadata: metadata).first else {
                        throw Abort(.notFound, reason: "A képfájl nem található.")
                    }
                    if source.deletingPathExtension().lastPathComponent == stem { continue }
                    let name = stem + "." + source.pathExtension
                    let destination = try unusedAttachment(name, in: directory, metadata: metadata, status: .unprocessableEntity)
                    try files.moveItem(at: source, to: destination)
                    moved.append((source, destination))
                    media[asset] = name
                }
                for index in updated.nodes.indices {
                    guard let file = updated.nodes[index].file, file.type == .image, let asset = file.asset,
                          let stem = renames[asset] else { continue }
                    updated.nodes[index].file?.filename = stem
                }
                if !moved.isEmpty {
                    metadata.mediaFiles = media
                    next.rules[directory] = metadata
                }
                try persist(next, previous: ctx)
                do { try write(updated, to: url) }
                catch { try persist(ctx, previous: next); throw error }
            } catch {
                for move in moved.reversed() { try files.moveItem(at: move.to, to: move.from) }
                throw error
            }
            return updated
        }
    }

    func manage(_ path: WorksheetPath, operation: DocumentAction, user: User, unlocks: Set<String>) throws -> WorksheetPath? {
        try lock.withLock {
            let ctx = try context(path)
            let rights = accessLocked(ctx, user: user, unlocks: unlocks)
            guard rights.manageable else { throw Abort(.forbidden) }
            guard ["sheet", "project"].contains(operation.scope) else { throw Abort(.badRequest) }
            let main = ctx.folderPath == path.url
            var next = ctx
            var page = ctx.page
            switch operation.action {
            case "hide": page.hidden.toggle()
            case "freeze":
                if main { next.rules[ctx.directory]?.frozen = !(ctx.local.frozen ?? false) }
                else { page.frozen = !(page.frozen ?? false) }
            case "password":
                let password = operation.value ?? ""
                guard password.utf8.count <= 72 else { throw Abort(.badRequest) }
                let hash = password.isEmpty ? nil : try Bcrypt.hash(password)
                if main { next.rules[ctx.directory]?.passwordHash = hash } else { page.passwordHash = hash }
            case "mode" where main:
                guard let mode = operation.value, ["public", "internal"].contains(mode) else { throw Abort(.badRequest) }
                next.rules[ctx.directory]?.guestReadable = mode == "public"
            case "grant", "revoke":
                guard main, let name = operation.value, try readUsers().contains(where: { $0.name == name }) else { throw Abort(.badRequest) }
                var editors = Set(ctx.local.editors ?? [])
                if operation.action == "grant" {
                    guard ctx.chain.dropLast().allSatisfy({ ctx.rules[$0]?.owner == name || ctx.rules[$0]?.editors?.contains(name) == true }) else {
                        throw Abort(.forbidden, reason: "Előbb a szülőmappában adj hozzáférést.")
                    }
                    editors.insert(name)
                } else { editors.remove(name) }
                next.rules[ctx.directory]?.editors = editors.sorted()
            case "rename", "delete":
                return try moveDocument(path, ctx, name: operation.action == "rename" ? (operation.value ?? "") : nil)
            default: throw Abort(.badRequest)
            }
            next.setPage(page)
            try persist(next, previous: ctx)
            return path
        }
    }

    private func moveDocument(_ path: WorksheetPath, _ ctx: Context, name: String?) throws -> WorksheetPath? {
        let main = ctx.folderPath == path.url
        let file = try worksheetURL(path)
        let source = main ? ctx.directory : file
        let renamed = try name.map { try WorksheetPath(Array(path.parts.dropLast()) + [$0]) }
        if renamed?.url == path.url { return renamed }
        let destination: URL
        if let renamed {
            let entry = try folder(renamed)
            let sibling = entry.appendingPathExtension("thnode")
            guard renamed.name != renamed.parts.dropLast().last, !files.fileExists(atPath: entry.path), !files.fileExists(atPath: sibling.path) else { throw Abort(.conflict) }
            destination = main ? entry : sibling
        } else {
            let trash = root.appendingPathComponent(".trash")
            try rejectLink(trash)
            try files.createDirectory(at: trash, withIntermediateDirectories: true)
            destination = trash.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        }
        var settings = ctx.rules[ctx.project]!
        let prefix = ctx.key.split(separator: "/").dropLast().joined(separator: "/")
        var pages = settings.worksheets ?? [:]
        for (key, value) in settings.worksheets ?? [:] where key == ctx.key || (main && (prefix.isEmpty || key.hasPrefix(prefix + "/"))) {
            pages.removeValue(forKey: key)
            if let name {
                var parts = key.split(separator: "/").map(String.init)
                if main && !prefix.isEmpty { parts[prefix.split(separator: "/").count-1] = name }
                if key == ctx.key { parts[parts.count-1] = name + ".thnode" }
                pages[parts.joined(separator: "/")] = value
            }
        }
        settings.worksheets = pages
        try files.moveItem(at: source, to: destination)
        let oldMain = destination.appendingPathComponent(file.lastPathComponent)
        var movedMain: URL?
        do {
            if main, let name {
                let newMain = destination.appendingPathComponent(name + ".thnode")
                guard !files.fileExists(atPath: newMain.path) else { throw Abort(.conflict) }
                try files.moveItem(at: oldMain, to: newMain)
                movedMain = newMain
            }
            if ctx.directory != ctx.project || !main || name != nil {
                let project = main && ctx.directory == ctx.project ? destination : ctx.project
                try write(settings, to: settingsURL(project))
            }
        } catch {
            if let movedMain { try files.moveItem(at: movedMain, to: oldMain) }
            try files.moveItem(at: destination, to: source)
            throw error
        }
        return renamed
    }

    private func unusedAttachment(_ name: String, in directory: URL, metadata: DocumentPolicy?,
                                  status: HTTPStatus = .conflict) throws -> URL {
        guard validImageStem(name) else { throw Abort(.badRequest, reason: "Érvénytelen fájlnév.") }
        try rejectLink(directory)
        let destination = directory.appendingPathComponent(name)
        try rejectLink(destination)
        let collides = files.fileExists(atPath: destination.path) || metadata?.mediaFiles?[name] != nil
        let reservesWorksheet = destination.pathExtension.lowercased() == "thnode"
        guard !collides, !reservesWorksheet else {
            throw Abort(status, reason: "Ilyen nevű fájl vagy munkalap már létezik.")
        }
        return destination
    }

    func storeMedia(_ bytes: Data, type: String, imageName: String? = nil, filename: String? = nil,
                    at path: WorksheetPath, user: User, unlocks: Set<String>) throws -> String {
        try lock.withLock {
            guard let ext = canvasMediaTypes.first(where: { $0.value == type })?.key,
                  !bytes.isEmpty, bytes.count <= 12 * 1024 * 1024 else { throw Abort(.badRequest) }
            let ctx = try context(path)
            _ = try read(worksheetURL(path))
            let access = accessLocked(ctx, user: user, unlocks: unlocks)
            guard access.editable else { throw Abort(.forbidden) }
            guard matchesMediaHeader(bytes, type: type) else {
                throw Abort(.unsupportedMediaType, reason: "A fájl tartalma eltér a megadott típustól.")
            }
            let asset = UUID().uuidString.lowercased() + "." + ext
            let name = filename ?? imageName.map { $0 + "." + ext } ?? asset
            let suffix = (name as NSString).pathExtension.lowercased()
            guard canvasMediaTypes[suffix == "jpeg" ? "jpg" : suffix] == type else {
                throw Abort(.badRequest, reason: "Érvénytelen médiafájlnév.")
            }
            let worksheet = try worksheetURL(path)
            let directory = ctx.directory
            var metadata = ctx.local
            let destination = try unusedAttachment(name, in: directory, metadata: metadata)
            guard try attachments(at: worksheet, named: name, metadata: metadata).isEmpty else {
                throw Abort(.conflict, reason: "Ilyen nevű fájl már létezik.")
            }
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: destination, options: .atomic)
            if name != asset {
                var media = metadata.mediaFiles ?? [:]
                media[asset] = name
                metadata.mediaFiles = media
                do { try write(metadata, to: settingsURL(directory)) }
                catch { try? files.removeItem(at: destination); throw error }
            }
            return asset
        }
    }

    func storeAttachment(_ bytes: Data, named name: String, at path: WorksheetPath, user: User, unlocks: Set<String>) throws {
        try lock.withLock {
            let ctx = try context(path)
            _ = try read(worksheetURL(path))
            let access = accessLocked(ctx, user: user, unlocks: unlocks)
            guard access.editable else { throw Abort(.forbidden) }
            guard validImageStem(name), canvasAssetType(name) == nil else {
                throw Abort(.badRequest, reason: "Érvénytelen fájlnév.")
            }
            guard bytes.count <= 12 * 1024 * 1024 else {
                throw Abort(.payloadTooLarge, reason: "A fájl legfeljebb 12 MiB lehet.")
            }
            let ext = (name as NSString).pathExtension.lowercased()
            guard matchesAttachmentType(bytes, extension: ext) else {
                throw Abort(.unsupportedMediaType, reason: "A fájltípus nem támogatott, vagy a tartalom eltér a kiterjesztéstől.")
            }
            let worksheet = try worksheetURL(path)
            let directory = ctx.directory
            let metadata = ctx.local
            let destination = try unusedAttachment(name, in: directory, metadata: metadata)
            guard try attachments(at: worksheet, named: name, metadata: metadata).isEmpty else {
                throw Abort(.conflict, reason: "Ilyen nevű melléklet már létezik.")
            }
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: destination, options: .atomic)
        }
    }

    func contents(_ path: WorksheetPath, user: User?, unlocks: Set<String>, named name: String? = nil) throws -> [URL] {
        try lock.withLock {
            let url = try worksheetURL(path)
            let ctx = try context(path)
            _ = try read(worksheetURL(path))
            let access = accessLocked(ctx, user: user, unlocks: unlocks)
            try authorize(access, user: user)
            return try attachments(at: url, named: name, metadata: ctx.local)
        }
    }

    private func attachments(at url: URL, named name: String?, metadata: DocumentPolicy?) throws -> [URL] {
        let directory = url.deletingLastPathComponent()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        let entries: [URL]
        if let name {
            let filename = metadata?.mediaFiles?[name] ?? name
            guard validImageStem(filename), URL(fileURLWithPath: filename).pathExtension.lowercased() != "thnode" else { return [] }
            entries = [directory.appendingPathComponent(filename)]
        } else {
            entries = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        }
        return try entries.filter { file in
            guard !file.lastPathComponent.hasPrefix("."), file.pathExtension.lowercased() != "thnode",
                  files.fileExists(atPath: file.path) else { return false }
            let info = try file.resourceValues(forKeys: keys)
            return info.isRegularFile == true && info.isSymbolicLink != true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func archive(_ path: WorksheetPath, expected: Int) throws {
        try lock.withLock {
            let ctx = try context(path)
            guard try read(worksheetURL(path)).revision == expected else { throw Abort(.preconditionFailed) }
            _ = try moveDocument(path, ctx, name: nil)
        }
    }

    func allUsers() throws -> [User] {
        try lock.withLock { try readUsers().sorted { $0.name < $1.name } }
    }

    func user(named name: String) throws -> User? {
        try lock.withLock {
            let settings = try readSettings()
            var user = settings.users?.first { $0.name == name }
            user?.avatar = settings.preferences?[name]?.avatar
            return user
        }
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
            let remaining = users.filter { $0.name != name }
            guard remaining.contains(where: { $0.role == .admin }) else { throw Abort(.unprocessableEntity) }
            var changed: [(URL, DocumentPolicy)] = []
            func removeMemberships(in directory: URL) throws {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
                let entries = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                for folder in entries {
                    let info = try folder.resourceValues(forKeys: keys)
                    guard info.isDirectory == true, info.isSymbolicLink != true else { continue }
                    let file = try settingsURL(folder)
                    guard files.fileExists(atPath: file.path) else { continue }
                    let previous = try JSONDecoder().decode(DocumentPolicy.self, from: Data(contentsOf: file))
                    var next = previous
                    if next.owner == name { next.owner = nil }
                    next.editors?.removeAll { $0 == name }
                    if next != previous {
                        try write(next, to: file)
                        changed.append((file, previous))
                    }
                    try removeMemberships(in: folder)
                }
            }
            do {
                try removeMemberships(in: root)
                try writeUsers(remaining)
            } catch {
                for (file, previous) in changed.reversed() { try write(previous, to: file) }
                throw error
            }
        }
    }

    private var settingsFile: URL { root.appendingPathComponent(".settings.json") }

    private func readSettings() throws -> SiteSettings {
        try rejectLink(settingsFile)
        guard files.fileExists(atPath: settingsFile.path) else { return SiteSettings() }
        return try JSONDecoder().decode(SiteSettings.self, from: Data(contentsOf: settingsFile))
    }

    private func readUsers() throws -> [User] {
        try readSettings().users ?? []
    }

    private func writeUsers(_ users: [User]) throws {
        guard users.contains(where: { $0.role == .admin }) else {
            throw Abort(.unprocessableEntity, reason: "Legalább egy adminisztrátori fióknak meg kell maradnia.")
        }
        var settings = try readSettings()
        settings.users = users
        try saveSiteSettings(settings)
    }

    private func saveSiteSettings(_ settings: SiteSettings) throws {
        try encoder.encode(settings).write(to: settingsFile, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsFile.path)
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

    private func rejectLink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw Abort(.notFound)
        }
    }
}

extension Idea {
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? fields.decode(IdeaKind.self, forKey: .kind)
        id = (try? fields.decode(String.self, forKey: .id)) ?? "box-\(decoder.codingPath.last?.intValue ?? 0)"
        title = (try? fields.decode(String.self, forKey: .title)) ?? "Ötlet"
        text = (try? fields.decode(String.self, forKey: .text)) ?? ""
        file = try? fields.decode(CanvasFile.self, forKey: .file)
        hideText = try? fields.decode(Bool.self, forKey: .hideText)
        position = (try? fields.decode(Point.self, forKey: .position)) ?? Point(x: 0, y: 0)
        width = (try? fields.decode(Double.self, forKey: .width)) ?? (kind == .connectionPoint ? 12 : 176)
        height = (try? fields.decode(Double.self, forKey: .height)) ?? (kind == .connectionPoint ? width : 80)
        shape = (try? fields.decode(Shape.self, forKey: .shape)) ?? .rounded
        fill = (try? fields.decode(String.self, forKey: .fill)) ?? "#dce9ff"
        backgroundEnabled = try? fields.decode(Bool.self, forKey: .backgroundEnabled)
        animation = try? fields.decode(BoxAnimation.self, forKey: .animation)
        textColor = (try? fields.decode(String.self, forKey: .textColor)) ?? "#182335"
        fitText = try? fields.decode(Bool.self, forKey: .fitText)
        fontSize = (try? fields.decode(Double.self, forKey: .fontSize)) ?? 16
        bold = (try? fields.decode(Bool.self, forKey: .bold)) ?? true
        alignment = (try? fields.decode(LabelAlignment.self, forKey: .alignment)) ?? .center
        verticalAlignment = try? fields.decode(VerticalAlignment.self, forKey: .verticalAlignment)
        titleOutside = try? fields.decode(Bool.self, forKey: .titleOutside)
        link = try? fields.decode(String.self, forKey: .link)
        parent = try? fields.decode(String.self, forKey: .parent)
        locked = try? fields.decode(Bool.self, forKey: .locked)
        italic = try? fields.decode(Bool.self, forKey: .italic)
        underline = try? fields.decode(Bool.self, forKey: .underline)
        textStyle = try? fields.decode(TextStyle.self, forKey: .textStyle)
    }
}

extension Worksheet {
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? fields.decode(Int.self, forKey: .schemaVersion)) ?? 2
        revision = (try? fields.decode(Int.self, forKey: .revision)) ?? 1
        resetRevision = try? fields.decode(Int.self, forKey: .resetRevision)
        title = (try? fields.decode(String.self, forKey: .title)) ?? "Munkalap"
        text = try? fields.decode(String.self, forKey: .text)
        previewImage = try? fields.decode(String.self, forKey: .previewImage)
        textJustified = try? fields.decode(Bool.self, forKey: .textJustified)
        background = try? fields.decode(String.self, forKey: .background)
        gridSpacing = try? fields.decode(Double.self, forKey: .gridSpacing)
        creator = try? fields.decode(String.self, forKey: .creator)
        nodes = (try? fields.decode([WorksheetElement<Idea>].self, forKey: .nodes))?.compactMap(\.value) ?? []
        edges = (try? fields.decode([WorksheetElement<Connection>].self, forKey: .edges))?.compactMap(\.value) ?? []
    }
}

extension Point {
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        x = (try? fields.decode(Double.self, forKey: .x)) ?? 0
        y = (try? fields.decode(Double.self, forKey: .y)) ?? 0
    }
}
