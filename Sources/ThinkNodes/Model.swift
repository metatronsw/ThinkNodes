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
    @OptionalPaint var color: String? = nil
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

enum CanvasFileType: String, Codable, Sendable { case image, mp3, txt, md, json, attachment, worksheet, web }

struct CanvasFile: Codable, Equatable, Sendable {
    var type: CanvasFileType
    var asset: String?
    var hideTitle: Bool?
    var filename: String?
    var webPath: String?
    var showFilename: Bool?
    var fileExtension: String?
    var alphaEnabled: Bool?
    @OptionalPaint var alphaBackground: String? = nil

    var imageStem: String {
        filename ?? asset.map { ($0 as NSString).deletingPathExtension } ?? ""
    }

    func displayName(title: String) -> String {
        if type == .image {
            let ext = fileExtension ?? (asset as NSString?)?.pathExtension ?? ""
            return ext.isEmpty ? imageStem : imageStem + "." + ext
        }
        if let filename { return filename }
        if let asset { return asset }
        if (title as NSString).pathExtension.lowercased() == type.rawValue { return title }
        return (title.isEmpty ? "Dokumentum" : title) + "." + type.rawValue
    }

    func reference(title: String) -> String? {
        if type == .web { return nil }
        return asset ?? filename ?? (["txt", "md", "json"].contains(type.rawValue)
            && (title as NSString).pathExtension.lowercased() == type.rawValue ? title : nil)
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

enum BoxBackgroundMode: String, Codable, Sendable {
    case solid, free, empty, blurred
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
    @StoredPaint var fill = "#dce9ff"
    var backgroundEnabled: Bool?
    var backgroundBlur: Bool?
    var backgroundMode: BoxBackgroundMode?
    var resolvedBackgroundMode: BoxBackgroundMode {
        backgroundMode ?? (backgroundEnabled == false ? .free : backgroundBlur == true ? .blurred : .solid)
    }
    var animation: BoxAnimation?
    @StoredPaint var textColor = "#182335"
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
    var elevated: Bool?
    var italic: Bool?
    var underline: Bool?
    var textStyle: TextStyle?

    private enum CodingKeys: String, CodingKey {
        case id, title, text, file, hideText, fitText, shape, fill, backgroundEnabled, backgroundBlur, backgroundMode, animation, bold, titleOutside, link
        case kind, parent, locked, elevated, italic, underline, textStyle
        case position = "pos", width = "w", height = "h", textColor = "textCol"
        case fontSize = "fontSz", alignment = "align", verticalAlignment = "vAlign"
    }

    var isValid: Bool {
        let sizeValid = kind == .connectionPoint ? (4...128).contains(width) && height == width :
            (64...880).contains(width) && (40...680).contains(height)
        guard validSlug(id), validTitle(title) || (title.isEmpty && (kind == .connectionPoint || file?.type == .image)),
              text.utf8.count <= 100_000, sizeValid,
              elevated != true || (parent == nil && kind != .connectionPoint) else { return false }
        if let file {
            guard file.filename.map(validImageStem) ?? true, file.asset.map(validImageStem) ?? true,
                  file.fileExtension.map({ !$0.isEmpty && !$0.contains(".") && validImageStem($0) }) ?? true else { return false }
            switch file.type {
            case .image:
                guard file.asset.flatMap(canvasAssetType)?.hasPrefix("image/") == true,
                      file.filename.map(validImageStem) ?? true, file.alphaBackground.map(validColor) ?? true else { return false }
            case .mp3: guard file.asset.flatMap(canvasAssetType) == "audio/mpeg" else { return false }
            case .txt, .json, .md: break
            case .worksheet: return false
            case .web:
                guard file.asset == nil, file.filename == nil, let reference = file.webPath,
                      (try? WebPresentationReference(reference)) != nil else { return false }
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
        case .lightning: "Zigzag"
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
    @OptionalPaint var color: String? = nil
    var width: Double?
    var startArrow: Bool?
    var endArrow: Bool?
    var label: String?
    var labelInLine: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, source, target, type, appearance, animated, color, startArrow, endArrow, label, labelInLine
        case sourcePoint = "srcPt", width = "w"
    }

    var origin: ConnectionTarget { ConnectionTarget(node: source, point: sourcePoint) }
    var strokeColor: String { color ?? "#526982" }
    static let maximumWidth: Double = 32
    var strokeWidth: Double { min(Self.maximumWidth, (width ?? 2) * (appearance == .thick ? 2 : 1)) }
    var lineWidth: Double { min(Self.maximumWidth, strokeWidth * (appearance == .dotted ? 2 : 1)) }
    var pulseWidth: Double { min(Self.maximumWidth, lineWidth * 1.45) }
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
        color = (try? fields.decode(StoredPaint.self, forKey: .color).wrappedValue)
        width = (try? fields.decode(Double.self, forKey: .width))
        startArrow = (try? fields.decode(Bool.self, forKey: .startArrow)) ?? (legacy == .both ? true : nil)
        endArrow = (try? fields.decode(Bool.self, forKey: .endArrow)) ?? (legacy == .rope || legacy == .solid ? false : nil)
        label = (try? fields.decode(String.self, forKey: .label))
        labelInLine = try? fields.decode(Bool.self, forKey: .labelInLine)
    }
}

struct Worksheet: Content, Equatable {
    var appearance: Appearance?
    var schemaVersion = 2
    var revision = 1
    var resetRevision: Int?
    var title: String
    var text: String?
    var previewImage: String?
    var textJustified: Bool?
    @OptionalPaint var background: String? = nil
    var gridSpacing: Double?
    var creator: String?
    var nodes: [Idea] = []
    var edges: [Connection] = []

    private enum CodingKeys: String, CodingKey {
        case appearance, schemaVersion, revision, resetRevision, title, text, textJustified, background
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

    mutating func removeLegacyWorksheetNodes() {
        let removed = Set(nodes.filter { $0.file?.type == .worksheet }.map(\.id))
        guard !removed.isEmpty else { return }
        nodes.removeAll { removed.contains($0.id) }
        for index in nodes.indices where nodes[index].parent.map(removed.contains) == true {
            nodes[index].parent = nil
        }
        edges.removeAll { $0.source.map(removed.contains) == true || $0.target.node.map(removed.contains) == true }
        while true {
            let degrees = junctionDegrees
            let orphaned = Set(nodes.filter { $0.kind == .connectionPoint && degrees[$0.id, default: 0] < 2 }.map(\.id))
            if orphaned.isEmpty { break }
            nodes.removeAll { orphaned.contains($0.id) }
            edges.removeAll { $0.source.map(orphaned.contains) == true || $0.target.node.map(orphaned.contains) == true }
        }
    }

    func validate() throws {
        guard duplicateConnections.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Ezen az útvonalon már van kábel.")
        }
        if let appearance {
            guard let theme = Themes.catalog.first(where: { $0.id == appearance.theme }),
                  theme.palettes.contains(where: { $0.id == appearance.palette }) else {
                throw Abort(.unprocessableEntity, reason: "Érvénytelen munkalaptéma, paletta vagy mód.")
            }
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
                      && validColor($0.strokeColor) && (0.5...Connection.maximumWidth).contains($0.width ?? 2)
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
    case editor, admin, guest
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
    paintID(value) != nil || value.utf8.count == 7 && value.first == "#" && value.dropFirst().utf8.allSatisfy {
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
        self.url = parts.map(Self.encodeSegment).joined(separator: "/")
    }

    static func encodeSegment(_ segment: String) -> String {
        segment.utf8.map { byte in
            switch byte {
            case 48...57, 65...90, 97...122, 45, 95: String(UnicodeScalar(byte))
            default: String(format: "%%%02X", byte)
            }
        }.joined()
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
    var archivedFiles: [String: String]?
    var worksheets: [String: PageSettings]?
}

struct PageSettings: Codable, Sendable, Equatable {
    var hidden = false
    var frozen: Bool?
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
    var dataDirectoryPath: String { root.path }
    let testMode: Bool
    private var testerCount = 0

    func nextTester() -> String {
        lock.withLock { testerCount += 1; return "Tester" + String(testerCount) }
    }

    private let files = FileManager.default
    private let lock = NSLock()
    private var pendingAttachments: [String: Date] = [:]
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
        let url = try folder(path).appendingPathComponent(path.name).appendingPathExtension("thnode")
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
        let parts = path.parts
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
        let projectRule = ctx.rules[ctx.project]!
        let names = Set((projectRule.editors ?? []) + [projectRule.owner].compactMap { $0 })
        let admin = user?.role == .admin
        let member = user.map { $0.role == .editor && names.contains($0.name) } == true
        let owner = member && user?.name == projectRule.owner
        let guest = user == nil || user?.role == .guest
        let publicProject = projectRule.guestReadable == true
        let readable = admin || member || publicProject
        let editable = admin || member || (guest && publicProject)
        var locked = false, frozen = false, protected = false
        for directory in ctx.chain {
            let rule = ctx.rules[directory]!
            frozen = frozen || rule.frozen == true
            if let hash = rule.passwordHash {
                protected = true
                locked = locked || (!admin && !owner && !unlocks.contains(hash))
            }
        }
        let page = ctx.page
        if let hash = page.passwordHash {
            protected = true
            locked = locked || (!admin && !owner && !unlocks.contains(hash))
        }
        frozen = frozen || page.frozen == true
        var menu = ctx.local
        menu.hidden = page.hidden
        menu.frozen = ctx.local.frozen ?? page.frozen
        menu.passwordHash = ctx.local.passwordHash ?? page.passwordHash
        menu.owner = projectRule.owner
        menu.guestReadable = projectRule.guestReadable
        return DocumentAccess(readable: readable && !locked, editable: editable && !locked && (!frozen || admin || owner),
            manageable: (admin || member) && !locked, listed: readable && !page.hidden,
            locked: readable && locked, hidden: page.hidden, projectRule: menu, sheetRule: menu,
            editorNames: names.sorted(), protectedByPassword: protected, frozen: frozen, passwordRequired: locked)
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
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
                for entry in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
                    let info = try entry.resourceValues(forKeys: keys)
                    guard info.isDirectory == true, info.isSymbolicLink != true,
                          let path = try? WorksheetPath(parts + [entry.lastPathComponent]), let ctx = try? context(path) else { continue }
                    let rights = accessLocked(ctx, user: user, unlocks: unlocks)
                    guard rights.listed, let sheet = try? read(worksheetURL(path)) else { continue }
                    result.append((path, sheet))
                    if rights.readable && !rootsOnly && (recursive || parent == nil) { try visit(entry, path.parts) }
                }
            }
            if let parent {
                let ctx = try context(parent)
                try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
                try visit(ctx.directory, parent.parts)
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
            var updated = prefs
            updated.avatar = entries[name]?.avatar
            entries[name] = updated
            settings.preferences = entries
            try saveSiteSettings(settings)
        }
    }

    func assignAvatar(_ avatar: Int, to name: String) throws {
        try lock.withLock {
            var settings = try readSettings()
            guard (1...12).contains(avatar), settings.users?.contains(where: { $0.name == name }) == true else { throw Abort(.badRequest) }
            var entries = settings.preferences ?? [:]
            entries[name, default: UserPreferences()].avatar = avatar
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

    func open(_ path: WorksheetPath, user: User?, createOnly: Bool = false, unlocks: Set<String> = []) throws -> Worksheet {
        try lock.withLock { try openLocked(path, user: user, createOnly: createOnly, unlocks: unlocks) }
    }

    private func openLocked(_ path: WorksheetPath, user: User?, createOnly: Bool, unlocks: Set<String>, imported: Worksheet? = nil) throws -> Worksheet {
        if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
        let entry = try folder(path)
        if let url = try? worksheetURL(path), files.fileExists(atPath: url.path) {
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            if createOnly { throw Abort(.conflict) }
            return try reconcile(context: ctx, url: url)
        }
        if path.parts.count == 1 {
            guard let user else { throw Abort(.unauthorized) }
            guard user.role != .guest else { throw Abort(.forbidden) }
        }
        var policy = path.parts.count == 1 ? DocumentPolicy(owner: user?.name, guestReadable: false) : DocumentPolicy()
        var importSource: (URL, DocumentPolicy)?
        var sheet = imported ?? Worksheet(appearance: Appearance(), title: String(path.name.prefix(120)))
        sheet.creator = user?.name ?? "Vendég"
        if path.parts.count > 1 {
            let parent = try WorksheetPath(Array(path.parts.dropLast()))
            let parentSheet: Worksheet
            if createOnly {
                parentSheet = try read(worksheetURL(parent))
            } else {
                parentSheet = try openLocked(parent, user: user, createOnly: false, unlocks: unlocks)
            }
            let ctx = try context(parent)
            guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
            if imported == nil {
                sheet.appearance = parentSheet.appearance ?? Appearance()
                sheet.background = parentSheet.background
                sheet.gridSpacing = parentSheet.gridSpacing
            } else {
                importSource = (try worksheetURL(parent), ctx.local)
            }
        }
        guard !files.fileExists(atPath: entry.path),
              !files.fileExists(atPath: entry.appendingPathExtension("thnode").path) else { throw Abort(.conflict) }
        try files.createDirectory(at: entry, withIntermediateDirectories: false)
        do {
            if let (source, metadata) = importSource {
                policy = try copyReferencedAttachments(in: sheet, from: source, metadata: metadata, to: entry)
            }
            try write(policy, to: settingsURL(entry))
            let url = try worksheetURL(path)
            try write(sheet, to: url)
            return try read(url)
        } catch {
            try files.removeItem(at: entry)
            throw error
        }
    }

    enum Preview { case drawing(String), image(URL, String) }

    func preview(_ path: WorksheetPath, user: User?, unlocks: Set<String> = [], mode: String? = nil) throws -> Preview {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let url = try worksheetURL(path)
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            let sheet = resolvedFileNames(try read(url), metadata: ctx.local)
            if let name = sheet.previewImage,
               let file = try attachments(at: url, named: name, metadata: ctx.local).first,
               let mime = previewType(file) { return .image(file, mime) }
            let suffix = mode == "dark" ? ".preview-v10-dark.svg" : ".preview-v10.svg"
            let cache = url.deletingLastPathComponent().appendingPathComponent("." + path.name + suffix)
            try rejectLink(cache)
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, let cached = try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               cached > modified && cached > Themes.loadedAt { return .drawing(try String(contentsOf: cache, encoding: .utf8)) }
            let svg = boardSVG(sheet, assetBase: "/" + path.url, mode: mode)
            try Data(svg.utf8).write(to: cache, options: .atomic)
            return .drawing(svg)
        }
    }

    func pageExists(_ path: WorksheetPath) -> Bool {
        lock.withLock {
            guard let url = try? worksheetURL(path) else { return false }
            return files.fileExists(atPath: url.path)
        }
    }

    func load(_ path: WorksheetPath, user: User?, unlocks: Set<String> = []) throws -> Worksheet {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            return try reconcile(context: ctx, url: worksheetURL(path))
        }
    }

    func update(_ path: WorksheetPath, worksheet: Worksheet, user: User?, restoring: Bool = false, unlocks: Set<String> = [],
                checkSelection: (Worksheet) throws -> Void = { _ in }) throws -> Worksheet {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
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
            updated.removeLegacyWorksheetNodes()
            if current.appearance != nil && updated.appearance == nil { throw Abort(.unprocessableEntity) }
            updated.creator = current.creator
            updated.revision = current.revision + 1
            updated.resetRevision = restoring ? updated.revision : current.resetRevision
            try updated.validate()
            updated.schemaVersion = 2
            let url = try worksheetURL(path)
            let directory = ctx.directory
            var metadata = ctx.local
            var media = metadata.mediaFiles ?? [:]
            var archived = metadata.archivedFiles ?? [:]
            func sourceOf(_ ref: String) throws -> URL? {
                try attachments(at: url, named: ref, metadata: metadata).first
            }
            let previous = Dictionary(uniqueKeysWithValues: current.nodes.map { ($0.id, $0) })
            let currentRefs = Set(current.nodes.compactMap { $0.file?.reference(title: $0.title) })
            var renames: [String: String] = [:]
            for index in updated.nodes.indices {
                let node = updated.nodes[index]
                guard let file = node.file else { continue }
                let old = previous[node.id]
                let ref = file.asset ?? old.flatMap { $0.file?.reference(title: $0.title) }
                guard let ref, let filename = file.filename, filename != old?.file?.filename else { continue }
                let source = try sourceOf(ref)
                guard let source else {
                    if file.asset != nil && archived[ref] == nil { throw Abort(.notFound, reason: "A fájl nem található.") }
                    continue
                }
                let ext = source.pathExtension
                let name = file.type == .image ? filename + (ext.isEmpty ? "" : "." + ext) : filename
                guard (name as NSString).pathExtension == ext else {
                    throw Abort(.unprocessableEntity, reason: "A fájl kiterjesztése nem változtatható meg.")
                }
                if let prior = renames.updateValue(name, forKey: ref), prior != name {
                    throw Abort(.unprocessableEntity, reason: "Egy fájlhoz csak egy név tartozhat.")
                }
                updated.nodes[index].file?.asset = ref
            }
            let nextRefs = Set(updated.nodes.compactMap { $0.file?.reference(title: $0.title) })
            var moved: [(from: URL, to: URL)] = []
            func move(_ source: URL, _ destination: URL) throws {
                try files.moveItem(at: source, to: destination)
                moved.append((source, destination))
            }
            do {
                for ref in nextRefs.subtracting(currentRefs).sorted() {
                    guard let archivedName = archived[ref] else { continue }
                    let source = try projectTrashPath(archivedName, project: ctx.project, createParents: false)
                    let name = media[ref] ?? ref
                    let destination = try unusedAttachment(name, in: directory, metadata: nil)
                    try move(source, destination)
                    archived.removeValue(forKey: ref)
                }
                for (ref, name) in renames.sorted(by: { $0.key < $1.key }) {
                    guard let source = try sourceOf(ref), source.lastPathComponent != name else { continue }
                    let destination = directory.appendingPathComponent(name)
                    let caseOnly = source.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
                    if caseOnly, files.fileExists(atPath: destination.path),
                       try !files.contentsOfDirectory(atPath: directory.path).contains(name) {
                        let intermediate = directory.appendingPathComponent(".rename-" + UUID().uuidString)
                        try move(source, intermediate)
                        try move(intermediate, destination)
                    } else {
                        _ = try unusedAttachment(name, in: directory, metadata: metadata, status: .unprocessableEntity)
                        try move(source, destination)
                    }
                    media[ref] = name
                    if ref != updated.previewImage, source.lastPathComponent == updated.previewImage { updated.previewImage = name }
                }
                for index in updated.nodes.indices {
                    let node = updated.nodes[index]
                    guard let ref = node.file?.reference(title: node.title), let name = renames[ref] else { continue }
                    updated.nodes[index].file?.filename = node.file?.type == .image ? (name as NSString).deletingPathExtension : name
                }
                let keep = Set(nextRefs.map { media[$0] ?? $0 })
                for ref in currentRefs.subtracting(nextRefs).sorted() {
                    guard let source = try sourceOf(ref),
                          !keep.contains(source.lastPathComponent) else { continue }
                    let destination = try trashDestination(source, in: ctx)
                    try move(source, destination)
                    let relative = String(destination.path.dropFirst(ctx.project.path.count + "/.trash/".count))
                    archived[ref] = relative
                    if let preview = updated.previewImage, (media[preview] ?? preview) == source.lastPathComponent {
                        updated.previewImage = nil
                    }
                }
                if media != (metadata.mediaFiles ?? [:]) || archived != (metadata.archivedFiles ?? [:]) {
                    metadata.mediaFiles = media.isEmpty ? nil : media
                    metadata.archivedFiles = archived.isEmpty ? nil : archived
                    next.rules[directory] = metadata
                }
                try updated.validate()
                try persist(next, previous: ctx)
                do { try write(updated, to: url) }
                catch { try persist(ctx, previous: next); throw error }
                for ref in nextRefs {
                    let name = media[ref] ?? ref
                    pendingAttachments.removeValue(forKey: pendingFileKey(name, folder: ctx.folderPath))
                }
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
            var next = ctx
            var page = ctx.page
            switch operation.action {
            case "hide": page.hidden.toggle()
            case "freeze":
                next.rules[ctx.directory]?.frozen = !(rights.sheetRule.frozen ?? false)
                page.frozen = nil
            case "password":
                let password = operation.value ?? ""
                guard password.utf8.count <= 72 else { throw Abort(.badRequest) }
                let hash = password.isEmpty ? nil : try Bcrypt.hash(password)
                next.rules[ctx.directory]?.passwordHash = hash
                page.passwordHash = nil
            case "mode" where path.parts.count == 1:
                guard let mode = operation.value, ["public", "internal"].contains(mode) else { throw Abort(.badRequest) }
                next.rules[ctx.directory]?.guestReadable = mode == "public"
            case "grant", "revoke":
                guard path.parts.count == 1, let name = operation.value else { throw Abort(.badRequest) }
                var editors = Set(ctx.local.editors ?? [])
                if operation.action == "grant" {
                    guard try readUsers().contains(where: { $0.name == name && $0.role == .editor }) else {
                        throw Abort(.badRequest, reason: "A projekthez szerkesztő szerepkörű fiókot adhatsz hozzá.")
                    }
                    if name != ctx.local.owner { editors.insert(name) }
                } else { editors.remove(name) }
                next.rules[ctx.project]?.editors = editors.sorted()
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
        let file = try worksheetURL(path)
        let source = ctx.directory
        let renamed = try name.map { try WorksheetPath(Array(path.parts.dropLast()) + [$0]) }
        if renamed?.url == path.url { return renamed }
        let destination: URL
        if let renamed {
            let entry = try folder(renamed)
            let sibling = entry.appendingPathExtension("thnode")
            guard !files.fileExists(atPath: entry.path), !files.fileExists(atPath: sibling.path) else { throw Abort(.conflict) }
            destination = entry
        } else {
            if ctx.directory == ctx.project {
                let trash = root.appendingPathComponent(".trash")
                try rejectLink(trash)
                try files.createDirectory(at: trash, withIntermediateDirectories: true)
                destination = trash.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
            } else {
                destination = try trashDestination(source, in: ctx)
            }
        }
        var settings = ctx.rules[ctx.project]!
        let prefix = ctx.key.split(separator: "/").dropLast().joined(separator: "/")
        var pages = settings.worksheets ?? [:]
        for (key, value) in settings.worksheets ?? [:] where key == ctx.key || (prefix.isEmpty || key.hasPrefix(prefix + "/")) {
            pages.removeValue(forKey: key)
            if let name {
                var parts = key.split(separator: "/").map(String.init)
                if !prefix.isEmpty { parts[prefix.split(separator: "/").count-1] = name }
                if key == ctx.key { parts[parts.count-1] = name + ".thnode" }
                pages[parts.joined(separator: "/")] = value
            }
        }
        settings.worksheets = pages
        try files.moveItem(at: source, to: destination)
        let oldMain = destination.appendingPathComponent(file.lastPathComponent)
        var movedMain: URL?
        do {
            if let name {
                let newMain = destination.appendingPathComponent(name + ".thnode")
                guard !files.fileExists(atPath: newMain.path) else { throw Abort(.conflict) }
                try files.moveItem(at: oldMain, to: newMain)
                movedMain = newMain
            }
            if ctx.directory != ctx.project || name != nil {
                let project = ctx.directory == ctx.project ? destination : ctx.project
                try write(settings, to: settingsURL(project))
            }
        } catch {
            if let movedMain { try files.moveItem(at: movedMain, to: oldMain) }
            try files.moveItem(at: destination, to: source)
            throw error
        }
        return renamed
    }

    private func resolvedFileNames(_ sheet: Worksheet, metadata: DocumentPolicy) -> Worksheet {
        var result = sheet
        for index in sheet.nodes.indices {
            let node = sheet.nodes[index]
            guard let file = node.file, let ref = file.reference(title: node.title),
                  let name = metadata.mediaFiles?[ref] else { continue }
            result.nodes[index].file?.filename = file.type == .image ? (name as NSString).deletingPathExtension : name
            if file.type == .image { result.nodes[index].file?.fileExtension = (name as NSString).pathExtension }
        }
        return result
    }

    func reconcileAtStartup() {
        lock.withLock {
            func visit(_ directory: URL, parts: [String]) {
                let entries = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                               options: [.skipsHiddenFiles])) ?? []
                for entry in entries {
                    guard let info = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                          info.isDirectory == true, info.isSymbolicLink != true,
                          let path = try? WorksheetPath(parts + [entry.lastPathComponent]),
                          (try? context(path)) != nil, let url = try? worksheetURL(path),
                          files.fileExists(atPath: url.path) else { continue }
                    for legacy in (try? sheetFiles(in: entry)) ?? [] where legacy.lastPathComponent != url.lastPathComponent {
                        do { try migrateLegacyWorksheet(legacy, parent: path, context: try context(path)) }
                        catch {
                            let message = "ThinkNodes: Sikertelen munkalap-áthelyezés (/" + path.url + "/" + legacy.lastPathComponent
                                + "): " + ((error as? any AbortError)?.reason ?? String(describing: error)) + "\n"
                            FileHandle.standardError.write(Data(message.utf8))
                        }
                    }
                    if let ctx = try? context(path) { _ = try? reconcile(context: ctx, url: url) }
                    visit(entry, parts: path.parts)
                }
            }
            visit(root, parts: [])
        }
    }

    private func migrateLegacyWorksheet(_ legacy: URL, parent: WorksheetPath, context ctx: Context) throws {
        let name = legacy.deletingPathExtension().lastPathComponent
        let child = try WorksheetPath(parent.parts + [name])
        let destination = try folder(child)
        guard !files.fileExists(atPath: destination.path) else { throw Abort(.conflict, reason: "A(z) /" + child.url + " mappa már létezik.") }

        var sheet = try JSONDecoder().decode(Worksheet.self, from: Data(contentsOf: legacy))
        sheet.removeLegacyWorksheetNodes()
        var metadata = ctx.local
        var media = metadata.mediaFiles ?? [:]
        for index in sheet.nodes.indices {
            guard let file = sheet.nodes[index].file, [.image, .mp3].contains(file.type),
                  file.asset.flatMap(canvasAssetType) == nil, let reference = file.reference(title: sheet.nodes[index].title),
                  let attachment = try attachments(at: legacy, named: reference, metadata: metadata).first else { continue }
            let ext = attachment.pathExtension.lowercased()
            let canonical = ext == "jpeg" ? "jpg" : ext
            guard let type = canvasMediaTypes[canonical],
                  file.type == .image ? type.hasPrefix("image/") : type == "audio/mpeg",
                  try (attachment.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 12 * 1024 * 1024,
                  try matchesMediaHeader(Data(contentsOf: attachment), type: type) else { continue }
            let asset = UUID().uuidString.lowercased() + "." + canonical
            media[asset] = attachment.lastPathComponent
            sheet.nodes[index].file?.asset = asset
        }
        try sheet.validate()
        metadata.mediaFiles = media
        let prefix = Array(parent.parts.dropFirst())
        let oldKey = (prefix + [legacy.lastPathComponent]).joined(separator: "/")
        let newKey = (prefix + [name, legacy.lastPathComponent]).joined(separator: "/")
        var next = ctx
        var pages = ctx.rules[ctx.project]?.worksheets ?? [:]
        if let page = pages.removeValue(forKey: oldKey) { pages[newKey] = page }
        next.rules[ctx.project]?.worksheets = pages

        let stage = ctx.directory.appendingPathComponent(".worksheet-migration-" + UUID().uuidString)
        let backup = try trashDestination(legacy, in: ctx)
        try files.createDirectory(at: stage, withIntermediateDirectories: false)
        var published = false
        do {
            let policy = try copyReferencedAttachments(in: sheet, from: legacy, metadata: metadata, to: stage)
            try write(policy, to: settingsURL(stage))
            try write(sheet, to: stage.appendingPathComponent(legacy.lastPathComponent))
            try persist(next, previous: ctx)
            do {
                try files.moveItem(at: stage, to: destination)
                published = true
                try files.moveItem(at: legacy, to: backup)
            } catch {
                try persist(ctx, previous: next)
                throw error
            }
        } catch {
            try files.removeItem(at: published ? destination : stage)
            throw error
        }
    }

    private func copyReferencedAttachments(in sheet: Worksheet, from source: URL, metadata: DocumentPolicy, to folder: URL) throws -> DocumentPolicy {
        var refs = Set(sheet.nodes.compactMap { $0.file?.reference(title: $0.title) })
        if let preview = sheet.previewImage { refs.insert(preview) }
        var copied = Set<String>()
        var media: [String: String] = [:]
        for ref in refs.sorted() {
            guard let file = try attachments(at: source, named: ref, metadata: metadata).first else { continue }
            let name = file.lastPathComponent
            if copied.insert(name).inserted { try files.copyItem(at: file, to: folder.appendingPathComponent(name)) }
            if name != ref { media[ref] = name }
        }
        return DocumentPolicy(mediaFiles: media.isEmpty ? nil : media)
    }

    private func reconcile(context ctx: Context, url: URL) throws -> Worksheet {
        let current = resolvedFileNames(try read(url), metadata: ctx.local)
        guard current.nodes.count < 2_000 else { return current }
        let now = Date()
        pendingAttachments = pendingAttachments.filter { $0.value > now }
        var metadata = ctx.local
        var media = metadata.mediaFiles ?? [:]
        let archived = metadata.archivedFiles ?? [:]
        var referenced = Set(current.nodes.compactMap { $0.file?.reference(title: $0.title) }.map { media[$0] ?? $0 })
        if let preview = current.previewImage { referenced.insert(media[preview] ?? preview) }
        var updated = current
        let x = current.nodes.isEmpty ? 0 : min(99_000, current.nodes.map { $0.position.x - $0.width / 2 }.min()! + 160)
        var bottom = current.nodes.map { $0.position.y + $0.height / 2 }.max() ?? -140
        func append(_ title: String, file: CanvasFile, text: String, height: Double) {
            let y = bottom + 55 + height / 2
            guard updated.nodes.count < 2_000, y <= 100_000 else { return }
            bottom = y + height / 2
            updated.nodes.append(Idea(id: UUID().uuidString.lowercased(), title: String(title.prefix(120)), text: text,
                                      file: file, position: Point(x: x, y: y), width: 320, height: height,
                                      fill: "@2", textColor: "@1"))
        }
        for file in try attachments(at: url, named: nil, metadata: metadata) {
            let name = file.lastPathComponent
            guard !referenced.contains(name), pendingAttachments[pendingFileKey(name, folder: ctx.folderPath)] == nil, validImageStem(name),
                  updated.nodes.count < 2_000, bottom + 165 <= 100_000 else { continue }
            let ext = file.pathExtension
            let lower = ext.lowercased()
            let mime = canvasMediaTypes[lower == "jpeg" ? "jpg" : lower]
            let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let candidates = media.filter { $0.value == name }.keys.sorted()
            let existing = candidates.first { archived[$0] == nil }
            var canvasFile = CanvasFile(type: .attachment, asset: existing ?? ("file-" + UUID().uuidString.lowercased()), filename: name, showFilename: false)
            var text = ""
            var height = 100.0
            if let mime, let size, size <= 12 * 1024 * 1024,
               let bytes = try? Data(contentsOf: file), matchesMediaHeader(bytes, type: mime),
               let canonical = canvasMediaTypes.first(where: { $0.value == mime })?.key {
                canvasFile.type = mime == "audio/mpeg" ? .mp3 : .image
                canvasFile.asset = existing.flatMap { canvasAssetType($0) == mime ? $0 : nil }
                    ?? (UUID().uuidString.lowercased() + "." + canonical)
                if canvasFile.type == .image {
                    canvasFile.filename = file.deletingPathExtension().lastPathComponent
                    canvasFile.fileExtension = ext
                }
                height = canvasFile.type == .image ? 180 : 106
            } else if let size, size <= 100_000, ["md", "txt", "json"].contains(lower),
                      let bytes = try? Data(contentsOf: file), matchesAttachmentType(bytes, extension: lower),
                      let source = String(data: bytes, encoding: .utf8) {
                canvasFile.type = CanvasFileType(rawValue: lower)!
                text = source
                height = 200
            }
            let count = updated.nodes.count
            append(name, file: canvasFile, text: text, height: height)
            if updated.nodes.count != count, let ref = canvasFile.asset { media[ref] = name }
        }
        guard updated.nodes != current.nodes else { return current }
        updated.revision += 1
        try updated.validate()
        var next = ctx
        metadata.mediaFiles = media.isEmpty ? nil : media
        next.rules[ctx.directory] = metadata
        try persist(next, previous: ctx)
        do { try write(updated, to: url) }
        catch { try persist(ctx, previous: next); throw error }
        return updated
    }

    func importWorksheet(_ bytes: Data, named name: String, at path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> WorksheetPath {
        try lock.withLock {
            guard bytes.count <= 12 * 1024 * 1024 else { throw Abort(.payloadTooLarge) }
            guard (name as NSString).pathExtension.lowercased() == "thnode",
                  var sheet = try? JSONDecoder().decode(Worksheet.self, from: bytes) else {
                throw Abort(.unprocessableEntity, reason: "Érvénytelen ThinkNodes munkalapfájl.")
            }
            sheet.revision = 1
            sheet.resetRevision = nil
            sheet.removeLegacyWorksheetNodes()
            try sheet.validate()
            let target = try WorksheetPath(path.parts + [(name as NSString).deletingPathExtension])
            _ = try openLocked(target, user: user, createOnly: true, unlocks: unlocks, imported: sheet)
            return target
        }
    }

    private func pendingFileKey(_ name: String, folder: String) -> String {
        "attachment:" + folder + "/" + name
    }

    private func projectTrashPath(_ relative: String, project: URL, createParents: Bool) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." && !$0.isEmpty && !$0.contains("\\") }) else {
            throw Abort(.badRequest)
        }
        var directory = project.appendingPathComponent(".trash", isDirectory: true)
        for part in [""] + parts.dropLast() {
            if !part.isEmpty { directory.appendPathComponent(part, isDirectory: true) }
            try rejectLink(directory)
            if createParents && !files.fileExists(atPath: directory.path) {
                try files.createDirectory(at: directory, withIntermediateDirectories: false)
            }
        }
        let result = directory.appendingPathComponent(parts.last!)
        try rejectLink(result)
        return result
    }

    private func trashDestination(_ source: URL, in ctx: Context) throws -> URL {
        let projectParts = ctx.project.resolvingSymlinksInPath().pathComponents
        let sourceParts = source.resolvingSymlinksInPath().pathComponents
        guard sourceParts.starts(with: projectParts), sourceParts.count > projectParts.count else { throw Abort(.badRequest) }
        let relative = sourceParts.dropFirst(projectParts.count).joined(separator: "/")
        let direct = try projectTrashPath(relative, project: ctx.project, createParents: true)
        if !files.fileExists(atPath: direct.path) { return direct }
        return try projectTrashPath(".versions/" + UUID().uuidString + "/" + relative, project: ctx.project, createParents: true)
    }

    private func sheetFiles(in directory: URL) throws -> [URL] {
        try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                      options: [.skipsHiddenFiles]).filter { file in
            guard file.pathExtension == "thnode" else { return false }
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return info.isRegularFile == true && info.isSymbolicLink != true
        }
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
                    at path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> String {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
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
            pendingAttachments[pendingFileKey(name, folder: ctx.folderPath)] = Date().addingTimeInterval(60)
            return asset
        }
    }

    @discardableResult
    func storeAttachment(_ bytes: Data, named name: String, at path: WorksheetPath, user: User?, unlocks: Set<String>, replaceText: Bool = false) throws -> String {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
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
            guard replaceText || matchesAttachmentType(bytes, extension: ext) else {
                throw Abort(.unsupportedMediaType, reason: "A fájltípus nem támogatott, vagy a tartalom eltér a kiterjesztéstől.")
            }
            let worksheet = try worksheetURL(path)
            let directory = ctx.directory
            var metadata = ctx.local
            if replaceText {
                guard bytes.count <= 100_000,
                      let existing = try attachments(at: worksheet, named: name, metadata: metadata).first,
                      ["md", "txt"].contains(existing.pathExtension.lowercased()),
                      matchesAttachmentType(bytes, extension: existing.pathExtension.lowercased()) else { throw Abort(.badRequest) }
                try bytes.write(to: existing, options: .atomic)
                return name
            }
            let destination = try unusedAttachment(name, in: directory, metadata: metadata)
            guard try attachments(at: worksheet, named: name, metadata: metadata).isEmpty else {
                throw Abort(.conflict, reason: "Ilyen nevű melléklet már létezik.")
            }
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let asset = "file-" + UUID().uuidString.lowercased()
            var media = metadata.mediaFiles ?? [:]
            media[asset] = name
            metadata.mediaFiles = media
            try bytes.write(to: destination, options: .atomic)
            do { try write(metadata, to: settingsURL(directory)) }
            catch { try? files.removeItem(at: destination); throw error }
            pendingAttachments[pendingFileKey(name, folder: ctx.folderPath)] = Date().addingTimeInterval(60)
            return asset
        }
    }

    enum BoxFile { case disk(URL), text(String, String) }

    func boxFile(_ path: WorksheetPath, id: String, user: User?, unlocks: Set<String>) throws -> BoxFile {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            let url = try worksheetURL(path)
            guard let node = try read(url).nodes.first(where: { $0.id == id }), let file = node.file else {
                throw Abort(.notFound)
            }
            if let ref = file.reference(title: node.title),
               let source = try attachments(at: url, named: ref, metadata: ctx.local).first { return .disk(source) }
            guard [.txt, .md, .json].contains(file.type) else { throw Abort(.notFound) }
            return .text(node.text, file.displayName(title: node.title))
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
        var worksheet = try JSONDecoder().decode(Worksheet.self, from: Data(contentsOf: url))
        worksheet.removeLegacyWorksheetNodes()
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
        fill = (try? fields.decode(StoredPaint.self, forKey: .fill).wrappedValue) ?? "#dce9ff"
        backgroundEnabled = try? fields.decode(Bool.self, forKey: .backgroundEnabled)
        backgroundBlur = try? fields.decode(Bool.self, forKey: .backgroundBlur)
        backgroundMode = try fields.decodeIfPresent(BoxBackgroundMode.self, forKey: .backgroundMode)
        animation = try? fields.decode(BoxAnimation.self, forKey: .animation)
        textColor = (try? fields.decode(StoredPaint.self, forKey: .textColor).wrappedValue) ?? "#182335"
        fitText = try? fields.decode(Bool.self, forKey: .fitText)
        fontSize = (try? fields.decode(Double.self, forKey: .fontSize)) ?? 16
        bold = (try? fields.decode(Bool.self, forKey: .bold)) ?? true
        alignment = (try? fields.decode(LabelAlignment.self, forKey: .alignment)) ?? .center
        verticalAlignment = try? fields.decode(VerticalAlignment.self, forKey: .verticalAlignment)
        titleOutside = try? fields.decode(Bool.self, forKey: .titleOutside)
        link = try? fields.decode(String.self, forKey: .link)
        parent = try? fields.decode(String.self, forKey: .parent)
        locked = try? fields.decode(Bool.self, forKey: .locked)
        elevated = try? fields.decode(Bool.self, forKey: .elevated)
        italic = try? fields.decode(Bool.self, forKey: .italic)
        underline = try? fields.decode(Bool.self, forKey: .underline)
        textStyle = try? fields.decode(TextStyle.self, forKey: .textStyle)
    }
}

extension Worksheet {
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try fields.decodeIfPresent(Appearance.self, forKey: .appearance)
        schemaVersion = (try? fields.decode(Int.self, forKey: .schemaVersion)) ?? 2
        revision = (try? fields.decode(Int.self, forKey: .revision)) ?? 1
        resetRevision = try? fields.decode(Int.self, forKey: .resetRevision)
        title = (try? fields.decode(String.self, forKey: .title)) ?? "Munkalap"
        text = try? fields.decode(String.self, forKey: .text)
        previewImage = try? fields.decode(String.self, forKey: .previewImage)
        textJustified = try? fields.decode(Bool.self, forKey: .textJustified)
        background = try? fields.decode(StoredPaint.self, forKey: .background).wrappedValue
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

extension WorksheetStore {
    private struct WebAccess {
        let admin: Bool
        let projectMember: Bool
        let projectOwner: Bool
        var readable: Bool
        var publicRead: Bool
        var hashes: [String] = []

        mutating func restrict(_ policy: DocumentPolicy, user: User?) {
            if policy.guestReadable == false || policy.editors != nil { publicRead = false }
            protect(policy.passwordHash)
            guard !admin else { return }
            if policy.guestReadable == false { readable = readable && projectMember }
            if let editors = policy.editors {
                let allowed = editors + [policy.owner].compactMap { $0 }
                readable = readable && (user.map { allowed.contains($0.name) } == true)
            }
        }

        mutating func protect(_ hash: String?) {
            if let hash {
                publicRead = false
                if !admin && !projectOwner { hashes.append(hash) }
            }
        }

        func authorize(_ user: User?, unlocks: Set<String>) throws {
            guard readable else { throw Abort(user == nil ? .unauthorized : .forbidden) }
            guard hashes.allSatisfy(unlocks.contains) else { throw Abort(.locked) }
        }

        func canManage(unlocks: Set<String>) -> Bool {
            readable && (admin || projectMember) && hashes.allSatisfy(unlocks.contains)
        }
    }

    private struct WebContext {
        let directory: URL
        let policy: DocumentPolicy
        let access: WebAccess
        let manageable: Bool
    }

    private func webPolicy(at directory: URL) throws -> DocumentPolicy? {
        let url = try settingsURL(directory)
        guard files.fileExists(atPath: url.path) else { return nil }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard info.isRegularFile == true else { throw Abort(.notFound) }
        return try JSONDecoder().decode(DocumentPolicy.self, from: Data(contentsOf: url))
    }

    private func webDirectory(_ name: String, in parent: URL) throws -> URL? {
        let url = parent.appendingPathComponent(name)
        try checkName(url)
        guard files.fileExists(atPath: url.path),
              try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { return nil }
        return url
    }

    private func webContext(project: String, reference: WebPresentationReference, user: User?, unlocks: Set<String>) throws -> WebContext? {
        let requiresLogin = try readSettings().requireLogin
        if requiresLogin && user == nil { throw Abort(.unauthorized) }
        guard var directory = try webDirectory(project, in: root), let rootRule = try webPolicy(at: directory) else { return nil }
        let member = user.map { user in
            user.role == .editor && (user.name == rootRule.owner || rootRule.editors?.contains(user.name) == true)
        } == true
        let admin = user?.role == .admin
        var access = WebAccess(admin: admin, projectMember: member, projectOwner: member && user?.name == rootRule.owner,
            readable: admin || member || rootRule.guestReadable == true,
            publicRead: !requiresLogin && rootRule.guestReadable == true)
        access.protect(rootRule.passwordHash)
        var parts: [String] = []
        access.protect(rootRule.worksheets?[project + ".thnode"]?.passwordHash)
        for folder in reference.folders {
            guard access.readable else { throw Abort(user == nil ? .unauthorized : .forbidden) }
            guard let next = try webDirectory(folder, in: directory) else { return nil }
            directory = next
            parts.append(folder)
            if let rule = try webPolicy(at: directory) { access.restrict(rule, user: user) }
            let key = (parts + [folder + ".thnode"]).joined(separator: "/")
            access.protect(rootRule.worksheets?[key]?.passwordHash)
        }
        guard access.readable else { throw Abort(user == nil ? .unauthorized : .forbidden) }
        guard let presentation = try webDirectory(reference.name + ".web", in: directory) else { return nil }
        let policy = try webPolicy(at: presentation) ?? DocumentPolicy()
        let manageable = access.canManage(unlocks: unlocks)
        access.restrict(policy, user: user)
        return WebContext(directory: presentation, policy: policy, access: access, manageable: manageable)
    }

    func webAsset(_ request: WebPresentationRequest, user: User?, unlocks: Set<String>) throws -> (asset: WebAsset, directory: Bool, publicRead: Bool)? {
        try lock.withLock {
            guard let context = try webContext(project: request.project, reference: request.reference, user: user, unlocks: unlocks) else { return nil }
            try context.access.authorize(user, unlocks: unlocks)
            let dirs = [request.project] + request.reference.folders + [request.reference.name + ".web"]
            let (asset, directory) = try WebAsset.open(in: root, folders: dirs, asset: request.asset, trailingSlash: request.trailingSlash)
            return (asset, directory, context.access.publicRead)
        }
    }

    func unlockWeb(_ requests: [WebPresentationRequest], password: String, user: User?, unlocks: Set<String>) throws -> (WebPresentationRequest, [String]) {
        try lock.withLock {
            for request in requests {
                guard let context = try webContext(project: request.project, reference: request.reference, user: user, unlocks: unlocks) else { continue }
                guard context.access.readable else { throw Abort(.forbidden) }
                let required = Set(context.access.hashes).subtracting(unlocks)
                let matches = try required.filter { try Bcrypt.verify(password, created: $0) }
                guard !matches.isEmpty else { throw Abort(.forbidden) }
                return (request, Array(matches))
            }
            throw Abort(.notFound)
        }
    }

    func webPresentations(in path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> [WebPresentationInfo] {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            let project = path.parts[0]
            var presentations: [WebPresentationInfo] = []
            func visit(_ dir: URL, folders: [String]) throws {
                let entries = try files.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                for entry in entries {
                    let info = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard info.isDirectory == true, info.isSymbolicLink != true else { continue }
                    let relative = folders + [entry.lastPathComponent]
                    if entry.pathExtension == "web" {
                        guard let reference = try? WebPresentationReference(relative.joined(separator: "/")),
                              let access = try? webContext(project: project, reference: reference, user: user, unlocks: unlocks),
                              access.access.readable || access.manageable else { continue }
                        let url = reference.url(in: project)
                        let preview = entry.appendingPathComponent("preview.png")
                        let previewExists = (try? rejectLink(preview)) != nil &&
                            (try? preview.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                        let unlocked = access.access.readable && access.access.hashes.allSatisfy(unlocks.contains)
                        presentations.append(WebPresentationInfo(reference: reference.relativePath, title: String(reference.name.prefix(120)), url: url,
                            preview: unlocked && previewExists ? url + "preview.png" : nil, manageable: access.manageable,
                            membersOnly: access.manageable ? access.policy.guestReadable == false : nil,
                            editors: access.manageable ? access.policy.editors : nil,
                            passwordProtected: access.manageable ? access.policy.passwordHash != nil : nil))
                    } else if relative.count < 11, (try? WorksheetPath([project] + relative)) != nil {
                        try visit(entry, folders: relative)
                    }
                }
            }
            try visit(ctx.project, folders: [])
            return presentations.sorted { $0.reference.localizedStandardCompare($1.reference) == .orderedAscending }
        }
    }

    func setWebPresentation(_ settings: WebPresentationSettings, in path: WorksheetPath, user: User, unlocks: Set<String>) throws {
        try lock.withLock {
            let worksheet = try context(path)
            try authorize(accessLocked(worksheet, user: user, unlocks: unlocks), user: user)
            let reference = try WebPresentationReference(settings.reference)
            guard let context = try webContext(project: path.parts[0], reference: reference, user: user, unlocks: unlocks),
                  context.manageable else { throw Abort(.forbidden) }
            guard settings.editors.map({ $0.count <= 500 && $0.allSatisfy(validSlug) }) ?? true,
                  settings.password.map({ (1...72).contains($0.utf8.count) && !settings.removePassword }) ?? true else {
                throw Abort(.badRequest)
            }
            var policy = context.policy
            policy.guestReadable = settings.membersOnly ? false : nil
            policy.editors = settings.editors.map { Set($0).sorted() }
            if settings.removePassword { policy.passwordHash = nil }
            if let password = settings.password { policy.passwordHash = try Bcrypt.hash(password) }
            try write(policy, to: settingsURL(context.directory))
        }
    }
}
