import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ThinkTable
import Vapor

package struct Point: Codable, Equatable, Sendable {
    package var x: Double
    package var y: Double

    package var isValid: Bool {
        x.isFinite && y.isFinite && abs(x) <= 100_000 && abs(y) <= 100_000
    }
}

private func automaticBorder(_ fill: String) -> String {
    guard let rgb = Int(fill.dropFirst(), radix: 16) else { return "#526982" }
    // Kézi hex-írás: a String(format:) dobozonként, sokszor hívva drága volt.
    let digits = Array("0123456789abcdef")
    var result = "#"
    for channel in [(rgb >> 16) * 2 / 3, ((rgb >> 8) & 255) * 2 / 3, (rgb & 255) * 2 / 3] {
        result.append(digits[channel >> 4]); result.append(digits[channel & 15])
    }
    return result
}

package enum Shape: String, Codable, Sendable {
    case rounded, rectangle, ellipse, diamond
    case triangle, pentagon, hexagon, parallelogram
}

package enum LabelAlignment: String, Codable, Sendable {
    case left, center, right
}

package enum VerticalAlignment: String, Codable, Sendable { case top, middle, bottom }

/// Objektum hivatkozása (`link` képesség): külső cím, munkalap vagy .web mappa.
package enum NodeLinkKind: String, Codable, Sendable { case url, sheet, web }

package struct NodeLink: Codable, Equatable, Sendable {
    var kind: NodeLinkKind
    package var target: String

    package var worksheetLink: WorksheetLink? { kind == .web ? nil : WorksheetLink(target) }
    var webReference: WebPresentationReference? { kind == .web ? try? WebPresentationReference(target) : nil }

    package var isValid: Bool {
        switch (kind, WorksheetLink(target)) {
        case (.url, .website?), (.sheet, .worksheet?): true
        case (.web, _): webReference != nil
        default: false
        }
    }
}

/// Nagy szövegfájl határa (docs/node-types.md, text típus): e fölött a vásznon csak az eleje látszik, és a tartalom
/// nem az oldalsávon, hanem külön ablakban szerkeszthető. A kliens párja: editor.js `largeTextLimit`.
package let largeTextLimit = 256 * 1024

/// A fájlt tároló objektumok (`text`, `code`, `csv`, `image`, `audio`, `document`) fájlja.
package struct CanvasFile: Codable, Equatable, Sendable {
    package var asset: String
    /// Másik munkalap mappájában lévő fájl a projekten belül: a munkalap útvonala a projekt után
    /// ("" = a projekt gyökere). nil: a saját lap mappája. A mentés csak a saját mappás fájlokat kezeli.
    package var source: String?
    var filename: String?
    var showFilename: Bool?
    var fileExtension: String?
    var alphaEnabled: Bool?
    @OptionalPaint var alphaBackground: String? = nil
    /// Szövegfájl változásszámlálója: mentés után nő, a többi kliens ebből tudja, hogy újra kell tölteni.
    package var rev: Int?

    /// Közös könyvtár (Public/common): minden projekt olvashatja, senki nem módosíthatja.
    static let common = "@common"

    static func validSource(_ source: String) -> Bool {
        if source == common { return true }
        let path = source.hasPrefix(common + "/") ? String(source.dropFirst(common.count + 1)) : source
        if path.isEmpty { return true }
        var segments: [String] = ["project"]
        segments.append(contentsOf: path.split(separator: "/", omittingEmptySubsequences: false).map(String.init))
        return (try? WorksheetPath(segments)) != nil
    }

    /// A szövegtartalom kulcsa (WorksheetStore.fileTexts): a forrással együtt, mert két lap mappájában lehet
    /// azonos nevű fájl, és egy lapon mindkettőre mutathat doboz.
    package var textKey: String { source.map { $0 + "\u{0}" + asset } ?? asset }

    package var isCommon: Bool { source == Self.common || source?.hasPrefix(Self.common + "/") == true }

    /// Közös könyvtárbeli fájl címe (`/common/...`), nyilvános statikus fájlként.
    var commonURL: String? {
        guard isCommon, let source else { return nil }
        var segments: [String] = ["common"]
        segments.append(contentsOf: source.split(separator: "/").dropFirst().map { WorksheetPath.encodeSegment(String($0)) })
        segments.append(WebPresentationRequest.encodeAsset(asset))
        return "/" + segments.joined(separator: "/")
    }

    /// A fájlt tároló munkalap útvonala; `own` a doboz saját lapja. Közös könyvtárnál nil.
    package func sheet(from own: WorksheetPath) -> WorksheetPath? {
        guard !isCommon else { return nil }
        guard let source else { return own }
        var segments: [String] = [own.parts[0]]
        if !source.isEmpty { segments.append(contentsOf: source.split(separator: "/").map(String.init)) }
        return try? WorksheetPath(segments)
    }

    var imageStem: String {
        filename ?? (asset as NSString).deletingPathExtension
    }

    /// Megjelenített fájlnév; képnél a tárolt tő + kiterjesztés.
    package func displayName(image: Bool) -> String {
        if image {
            let ext = fileExtension ?? (asset as NSString).pathExtension
            return ext.isEmpty ? imageStem : imageStem + "." + ext
        }
        return filename ?? asset
    }
}

func validImageStem(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 200 && !value.hasPrefix(".")
        && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || "/\\:".unicodeScalars.contains($0) }
}

package func canvasAssetType(_ name: String) -> String? {
    let parts = name.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
          id.uuidString.lowercased() == parts[0] else { return nil }
    return canvasMediaTypes[String(parts[1])]
}

private final class SVGDocument: NSObject, XMLParserDelegate {
    private var hasSVGRoot = false

    package static func matches(_ bytes: Data) -> Bool {
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
    case "audio/wav": return bytes.starts(with: "RIFF".utf8) && bytes.dropFirst(8).starts(with: "WAVE".utf8)
    case "audio/ogg": return bytes.starts(with: "OggS".utf8)
    case "audio/flac": return bytes.starts(with: "fLaC".utf8)
    case "audio/mp4": return bytes.dropFirst(4).starts(with: "ftyp".utf8)
    case "audio/aac":
        return bytes.starts(with: "ID3".utf8) || (bytes.count >= 2 && bytes[0] == 255 && bytes[1] & 0xf6 == 0xf0)
    default: return false
    }
}

let canvasMediaTypes = ["png": "image/png", "jpg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
                        "svg": "image/svg+xml", "mp3": "audio/mpeg", "wav": "audio/wav", "ogg": "audio/ogg",
                        "flac": "audio/flac", "m4a": "audio/mp4", "aac": "audio/aac"]

/// Csatolt (nem média) fájl ellenőrzése: szöveges típusnál a tartalom legyen szöveg, ismert bináris formátumnál a fejléc egyezzen.
private func matchesAttachmentType(_ bytes: Data, extension ext: String) -> Bool {
    if let mime = canvasMediaTypes[ext == "jpeg" ? "jpg" : ext] {
        return matchesMediaHeader(bytes, type: mime)
    }
    switch ext {
    case "pdf": return bytes.starts(with: "%PDF-".utf8)
    case "zip", "docx", "xlsx", "pptx":
        return bytes.starts(with: [0x50, 0x4b, 0x03, 0x04]) || bytes.starts(with: [0x50, 0x4b, 0x05, 0x06])
    default: return ext != "thnode"
    }
}

package enum BoxAnimation: String, Codable, Sendable {
    case none, pulse, blink, rock, hop
}

package enum BoxBackgroundMode: String, Codable, Sendable {
    /// canvas: a háttér a munkalap háttérszíne, a vászon rácsa nélkül (bármelyik dobozon).
    case solid, free, empty, translucent, canvas
}

/// A grafikon (`chart` típusú objektum) beállítása (Public/chart.js). Az adat a vonallal bekötött táblázatból jön.
package struct ChartSettings: Codable, Equatable, Sendable {
    static let kinds: Set<String> = ["bar", "line", "pie", "scatter"]
    static let maximumSeries = 8

    package var kind: String
    /// A kategóriák (pontdiagramnál az x értékek) oszlopa; nil: automatikus, -1: a sorok sorszáma.
    package var labels: Int?
    /// Az értékoszlopok; nil: minden számoszlop.
    package var values: [Int]?
    /// false: az első sor is adat (nincs fejlécsor).
    package var header: Bool?

    var isValid: Bool {
        Self.kinds.contains(kind) && (labels.map { (-1..<16384).contains($0) } ?? true)
            && (values.map { !$0.isEmpty && $0.count <= Self.maximumSeries && $0.allSatisfy((0..<16384).contains) } ?? true)
    }
}

package struct Idea: Codable, Equatable, Sendable {
    package var id: String
    /// Típus a regiszterből (`Public/node-types.json`): box, text, code, csv, image, audio, document, junction.
    package var type = "box"
    /// box: markdown szöveg; junction: címke; fájltípusok: megjegyzés.
    package var text = ""
    package var file: CanvasFile?
    /// box: összecsukás (csak az első sor); fájltípus: megjegyzés elrejtése.
    var hideText: Bool?
    var position: Point
    var width: Double = 176
    var height: Double = 80
    var shape: Shape = .rounded
    @StoredPaint var fill = "#dce9ff"
    var backgroundMode: BoxBackgroundMode?
    var resolvedBackgroundMode: BoxBackgroundMode { backgroundMode ?? .solid }
    var animation: BoxAnimation?
    @StoredPaint var textColor = "#182335"
    var border: String { automaticBorder(fill) }
    var fitText: Bool?
    var fontSize: Double = 16
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    /// A téma három betűtípusa közül a választott (1 = alap; nil = 1).
    var font: Int?
    package var justified: Bool?
    package var alignment: LabelAlignment = .center
    var verticalAlignment: VerticalAlignment?
    package var link: NodeLink?
    /// junction: a címke elforgatása fokban a középpont körül.
    var angle: Double?
    var parent: String?
    /// box: konténer jelző. Konténer az a doboz, amiben éppen van másik objektum; a szerkesztő a jelzőt ehhez igazítja
    /// mentéskor, a rajzolás és az ellenőrzés viszont a tényleges szülő–gyermek kapcsolatból dolgozik (a jelző lehet elavult).
    var container: Bool?
    package var locked: Bool?
    /// konténer: szövegkörbefuttatás, alapból bekapcsolva (nil vagy true); false kapcsolja ki. A konténer saját szövege felülről folyik, és soronként kikerüli a közvetlen
    /// gyermekdobozokat (geometry.js labelLayout, Rendering.swift ideaDrawing); a gyermekek helye kézi marad.
    /// A fájlban `textFlow`; a 2026-11-25-i első változat `autoLayout` néven írta, azt a név olvasáskor még elfogadjuk.
    var textFlow: Bool?
    var elevated: Bool?
    /// .web doboz: true = nincs új előnézet-generálás, a meglévő kép vágódik a doboz arányára.
    /// Munkalap- és külső link: true = nincs előnézet, a doboz szövege látszik.
    var staticPreview: Bool?
    /// .web doboz: a mappa publikus (pillangó ikon a doboz felett); az igazság a .web mappa .settings.json-ja.
    var webPublic: Bool?
    /// Text NAGYBETŰS megjelenítése (doboz szövege, doboz alatti Text, szövegfájl); a tárolt szöveg nem változik.
    package var uppercase: Bool?
    /// Kép és előnézetes doboz kerete: kép alapból ki (true = be), előnézet alapból be (false = ki); színe a doboz színe.
    var frame: Bool?
    /// A keret vastagsága (nil = 1,6, mint minden doboz kerete).
    var frameWidth: Double?
    /// Görgethető tartalom (szövegfájl, CSV, táblázat) mentett görgetési helyzete képpontban: minden résztvevő és a
    /// megtekintő is ezt látja. Az állítja, aki a dobozt kijelölve görget.
    package var scroll: Point?
    /// Grafikon (`chart` típus) beállítása: fajta, kategória- és értékoszlopok.
    package var chart: ChartSettings?
    var hasFrame: Bool { isImage ? frame == true : type == "preview" && frame != false }

    private enum CodingKeys: String, CodingKey {
        case id, type, text, file, hideText, fitText, shape, fill, backgroundMode, animation, bold, italic, underline, font, justified, link
        case angle, parent, container, locked, textFlow, elevated, staticPreview, webPublic, uppercase, frame, frameWidth, scroll, chart
        case position = "pos", width = "w", height = "h", textColor = "textCol"
        case fontSize = "fontSz", alignment = "align", verticalAlignment = "vAlign"
    }

    var root: String { NodeTypes.root(type) }
    /// Linkes doboz előnézettel: a kép kitölti a dobozt, a szöveg buboréksúgóban (geometry.js labelLayout).
    /// .web-nél mindig; munkalap- és külső linknél, ha az előnézet nincs kikapcsolva (`staticPreview`).
    var fillsWithPreview: Bool {
        guard let link else { return false }
        return link.kind == .web || staticPreview != true
    }
    package var isJunction: Bool { root == "junction" }
    var isBox: Bool { root == "box" }
    var isContainer: Bool { isBox && container == true }
    var isImage: Bool { root == "image" }
    var isAudio: Bool { root == "audio" }
    package var isTextFile: Bool { root == "text" }
    func has(_ trait: String) -> Bool { NodeTypes.has(type, trait) }

    /// Rövid név (kereső, akadálymentes felirat, listák): fájlnév, illetve a szöveg első sora formázójelek nélkül.
    package var name: String {
        if let file { return file.displayName(image: isImage) }
        return plainFirstLine(text)
    }

    package var isValid: Bool {
        guard NodeTypes.isKnown(type), validSlug(id), position.isValid, text.utf8.count <= 100_000,
              isJunction ? (4...128).contains(width) && height == width : (64...4096).contains(width) && (40...4096).contains(height),
              elevated != true || (parent == nil && !isJunction),
              frameWidth.map({ (0.5...32).contains($0) }) ?? true,
              scroll.map({ $0.isValid && $0.x >= 0 && $0.y >= 0 }) ?? true,
              chart.map({ $0.isValid && type == "chart" }) ?? true,
              (1...10000).contains(fontSize), fontSize.rounded() == fontSize, (1...3).contains(font ?? 1),
              [fill, textColor, border].allSatisfy(validColor),
              link.map({ $0.isValid && has("link") }) ?? true,
              angle.map({ $0.isFinite && isJunction }) ?? true, container != true || isBox,
              !isJunction || (text.count <= 120 && !text.contains("\n")) else { return false }
        guard let kind = NodeTypes.fileKind(type) else { return file == nil }
        guard let file, validImageStem(file.asset), file.filename.map(validImageStem) ?? true,
              file.fileExtension.map({ !$0.isEmpty && !$0.contains(".") && validImageStem($0) }) ?? true,
              (file.rev ?? 0) >= 0, file.alphaBackground.map(validColor) ?? true,
              file.source.map(CanvasFile.validSource) ?? true else { return false }
        switch kind {
        case "media":
            // Közös (másik lapról vagy tallózóból beillesztett) fájl valódi névvel is hivatkozhat.
            let byName = file.source != nil ? canvasMediaTypes[(file.asset as NSString).pathExtension.lowercased()] : nil
            return (canvasAssetType(file.asset) ?? byName)?.hasPrefix(root + "/") == true
        default:
            return canvasAssetType(file.asset) == nil && (file.asset as NSString).pathExtension.lowercased() != "thnode"
        }
    }
}

/// A markdown szöveg első nem üres sora, formázójelek nélkül.
func plainFirstLine(_ text: String) -> String {
    let line = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
    var value = String(line).trimmingCharacters(in: .whitespaces)
    while let first = value.first, "#>-*+ ".contains(first) { value.removeFirst() }
    if let match = value.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) { value.removeSubrange(match) }
    value = value.replacingOccurrences(of: #"[*_`~]|\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
    return String(value.trimmingCharacters(in: .whitespaces).prefix(120))
}

package enum ConnectionType: String, Codable, CaseIterable, Sendable {
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

package enum ConnectionAppearance: String, Codable, CaseIterable, Sendable {
    case plain, thick, dashed, dotted
}

package struct ConnectionTarget: Equatable, Codable, Sendable {
    package var node: String?
    var point: Point?

    package func isValid(in nodeIDs: Set<String>) -> Bool {
        if let node {
            return point == nil && nodeIDs.contains(node)
        }
        return point?.isValid == true
    }
}

extension ConnectionTarget {
    package init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        node = try? fields.decode(String.self, forKey: .node)
        point = try? fields.decode(Point.self, forKey: .point)
    }
}

package struct Connection: Equatable, Codable, Sendable {
    package var id: String
    package var source: String?
    var sourcePoint: Point?
    package var target: ConnectionTarget
    package var type: ConnectionType = .straight
    package var appearance: ConnectionAppearance = .plain
    var animated: Bool?
    @OptionalPaint var color: String? = nil
    /// Vonalméret: 1 (vékony, alapértelmezett), 2 (közepes), 3 (vastag). A tényleges vastagság a méret alapértéke
    /// (`baseWidths`) szorozva a téma vonaltípusonkénti szorzójával (`Graphics.lineScale`, geometry.js edgePaint). Az egyedi vastagság
    /// (régi `w` mező) megszűnt.
    var size: Int?
    /// A témából feloldott vonalvastagság (nem tárolt mező; renderWorksheetCanvas tölti ki).
    var width: Double?
    var startArrow: Bool?
    var endArrow: Bool?
    var label: String?
    var labelInLine: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, source, target, type, appearance, animated, color, size, startArrow, endArrow, label, labelInLine
        case sourcePoint = "srcPt"
    }

    var origin: ConnectionTarget { ConnectionTarget(node: source, point: sourcePoint) }
    var strokeColor: String { color ?? "#526982" }
    static let maximumWidth: Double = 32
    /// A három méret alapvastagsága (geometry.js lineBaseWidths; egyezniük kell).
    static let baseWidths: [Double] = [2, 5, 10.5]
    var sizeIndex: Int { min(3, max(1, size ?? 1)) - 1 }
    /// A vastagság a téma szorzójával (`scale`: vonaltípus neve → szorzó, akár megjelenésenként; híján 1); a vastag
    /// megjelenés mindig kétszeres.
    func scaledWidth(_ scale: [String: LineScale]?) -> Double {
        min(Self.maximumWidth, Self.baseWidths[sizeIndex] * (appearance == .thick ? 2 : 1) * (scale?[type.rawValue]?.factor(appearance) ?? 1))
    }
    var strokeWidth: Double { width ?? scaledWidth(nil) }
    var lineWidth: Double { min(Self.maximumWidth, strokeWidth * (appearance == .dotted ? 2 : 1)) }
    var pulseWidth: Double { min(Self.maximumWidth, lineWidth * 1.45) }
    var hasStartArrow: Bool { startArrow ?? false }
    var hasEndArrow: Bool { endArrow ?? true }
}

extension Connection {
    private enum LegacyKey: String, CodingKey { case style, w }
    private enum LegacyStyle: String, Decodable { case arrow, both, solid, dashed, rope }

    package init(from decoder: Decoder) throws {
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
        // Régi egyedi vastagság (`w`): a legközelebbi méretre vált (az eddigi alapértelmezett 2 a vékony).
        let oldWidth = try? decoder.container(keyedBy: LegacyKey.self).decodeIfPresent(Double.self, forKey: .w)
        size = (try? fields.decode(Int.self, forKey: .size)) ?? oldWidth.map { $0 <= 3.5 ? 1 : $0 <= 7.5 ? 2 : 3 }
        if size == 1 { size = nil }
        startArrow = (try? fields.decode(Bool.self, forKey: .startArrow)) ?? (legacy == .both ? true : nil)
        endArrow = (try? fields.decode(Bool.self, forKey: .endArrow)) ?? (legacy == .rope || legacy == .solid ? false : nil)
        label = (try? fields.decode(String.self, forKey: .label))
        labelInLine = try? fields.decode(Bool.self, forKey: .labelInLine)
    }
}

package struct Worksheet: Content, Equatable {
    package var appearance: Appearance?
    package var schemaVersion = Worksheet.currentSchema
    package var revision = 1
    package var resetRevision: Int?
    package var title: String
    package var text: String?
    var previewImage: String?
    package var textJustified: Bool?
    @OptionalPaint var background: String? = nil
    var gridSpacing: Double?
    package var creator: String?
    package var nodes: [Idea] = []
    package var edges: [Connection] = []

    // A memberwise inicializáló pontos mása: modulhatáron túl (ThinkNodes) a szintetizált `internal` maradna.
    package init(appearance: Appearance? = nil, schemaVersion: Int = Worksheet.currentSchema, revision: Int = 1,
                 resetRevision: Int? = nil, title: String, text: String? = nil, previewImage: String? = nil,
                 textJustified: Bool? = nil, background: String? = nil, gridSpacing: Double? = nil,
                 creator: String? = nil, nodes: [Idea] = [], edges: [Connection] = []) {
        self.appearance = appearance
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.resetRevision = resetRevision
        self.title = title
        self.text = text
        self.previewImage = previewImage
        self.textJustified = textJustified
        self.background = background
        self.gridSpacing = gridSpacing
        self.creator = creator
        self.nodes = nodes
        self.edges = edges
    }

    private enum CodingKeys: String, CodingKey {
        case appearance, schemaVersion, revision, resetRevision, title, text, textJustified, background
        case creator, nodes, edges, previewImage
        case gridSpacing = "gridStep"
    }

    /// 3: egységes objektumtípusok (docs/node-types.md). Régebbi munkalapot nem töltünk be, migráció nincs.
    static let currentSchema = 3

    package var backgroundColor: String { background ?? "#f5f8fc" }

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
        if let appearance {
            guard let theme = Themes.catalog.first(where: { $0.id == appearance.theme }),
                  theme.palettes.contains(where: { $0.id == appearance.palette }) else {
                throw Abort(.unprocessableEntity, reason: "Érvénytelen munkalaptéma, paletta vagy mód.")
            }
        }
        let nodeIDs = Set(nodes.map(\.id))
        guard schemaVersion == Worksheet.currentSchema, revision > 0, revision < Int.max, validTitle(title),
              (text?.utf8.count ?? 0) <= 100_000, validColor(backgroundColor),
              (6...160).contains(gridSpacing ?? 32),
              nodes.count <= 2_000, edges.count <= 4_000,
              nodeIDs.count == nodes.count, Set(edges.map(\.id)).count == edges.count,
              nodes.allSatisfy(\.isValid), edges.allSatisfy({
                  validSlug($0.id) && $0.origin.isValid(in: nodeIDs) && $0.target.isValid(in: nodeIDs)
                      && ($0.source == nil || $0.source != $0.target.node)
                      && validColor($0.strokeColor) && (1...3).contains($0.size ?? 1)
                      && validComment($0.label) && ($0.label?.utf16.count ?? 0) <= 120
              })
        else {
            throw Abort(.unprocessableEntity, reason: "Érvénytelen munkalapadat.")
        }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let degrees = junctionDegrees
        var checked = Set<String>()
        for node in nodes {
            if node.isJunction && degrees[node.id, default: 0] < 2 {
                throw Abort(.unprocessableEntity, reason: "A csomóponthoz legalább két vonal szükséges.")
            }
            var path = Set<String>()
            var current = node
            while let id = current.parent, !checked.contains(current.id) {
                guard path.insert(current.id).inserted, let parent = byID[id], parent.isBox else {
                    throw Abort(.unprocessableEntity, reason: "Érvénytelen konténerkapcsolat.")
                }
                current = parent
            }
            checked.formUnion(path)
        }
    }
}

package struct UserPreferences: Content {
    var snap = false
    var showGrid = true
    var panLocked = false
    package var avatar: Int?
    package var theme: String?

    // A memberwise inicializáló pontos mása (modulhatár).
    package init(snap: Bool = false, showGrid: Bool = true, panLocked: Bool = false, avatar: Int? = nil, theme: String? = nil) {
        self.snap = snap
        self.showGrid = showGrid
        self.panLocked = panLocked
        self.avatar = avatar
        self.theme = theme
    }
}

package func previewType(_ url: URL) -> String? {
    let ext = url.pathExtension.lowercased()
    let type = canvasMediaTypes[ext == "jpeg" ? "jpg" : ext]
    return type?.hasPrefix("image/") == true ? type : nil
}

package struct SiteSettings: Codable, Sendable {
    package var requireLogin = false
    package var preferences: [String: UserPreferences]?
    var users: [User]?
    /// Hozzáférés-kérés Google-fiókkal: a szabály (`nil` = kikapcsolva), a függő kérelmek és az elutasított címek.
    package var googleAccess: GoogleAccess?
    var accessRequests: [AccessRequest]?
    var rejectedGoogle: [String]?

    // A memberwise inicializáló pontos mása (modulhatár).
    package init(requireLogin: Bool = false, preferences: [String: UserPreferences]? = nil, users: [User]? = nil,
                 googleAccess: GoogleAccess? = nil) {
        self.requireLogin = requireLogin
        self.preferences = preferences
        self.users = users
        self.googleAccess = googleAccess
    }
}

/// Kérhet-e hozzáférést egy még ismeretlen Google-fiók, és mely e-mail-domainekről (üres lista = bármelyikről).
package struct GoogleAccess: Codable, Sendable, Equatable {
    package var requests = false
    package var domains: [String] = []

    package init(requests: Bool = false, domains: [String] = []) {
        self.requests = requests
        self.domains = domains
    }

    /// Szóközzel vagy vesszővel tagolt domainlista (pl. „ceg.hu, @masik.com”) egységes alakban.
    package static func domains(from text: String) throws -> [String] {
        let items = text.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
            .map { $0.hasPrefix("@") ? String($0.dropFirst()) : String($0) }
        guard items.count <= 50, items.allSatisfy({ item in
            item.utf8.count <= 253 && item.contains(".") && !item.hasPrefix(".") && !item.hasSuffix(".")
                && item.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }
        }) else { throw Abort(.unprocessableEntity, reason: "Az e-mail-domainek listája érvénytelen (példa: ceg.hu, masik.com).") }
        return Array(Set(items)).sorted()
    }

    func allows(_ email: String) -> Bool {
        guard requests else { return false }
        guard !domains.isEmpty else { return true }
        return email.split(separator: "@").last.map { domains.contains(String($0)) } ?? false
    }
}

/// Adminisztrátoroknak szóló, elintézendő jelzés: a fejléc Admin gombján jelvényként (összesített darabszám),
/// az adminoldal tetején listaként jelenik meg. Új fajta jelzéshez új `Kind` és egy új ág kell a
/// `WorksheetStore.adminMessages()` függvényben; a megjelenítés közös.
package struct AdminMessage: Sendable, Equatable {
    package enum Kind: String, Sendable {
        /// Elbírálásra váró hozzáférés-kérelmek (Google-fiókkal).
        case accessRequests
    }
    package var kind: Kind
    /// Hány elintézendő tétel van ebből a fajtából (ennyivel nő a jelvény).
    package var count: Int
    package var text: String
    /// Hová visz a jelzés (az adminoldalon belüli horgony vagy útvonal).
    package var link: String
}

/// Függő hozzáférés-kérelem: a Google által igazolt e-mail-cím és a kért felhasználónév.
package struct AccessRequest: Codable, Sendable, Equatable {
    package var email: String
    package var name: String
    /// A beadás ideje (másodperc 1970 óta).
    package var date: Double
}

package enum AccessRequestState: Sendable, Equatable {
    /// Ez a cím nem kérhet hozzáférést (kikapcsolva, vagy a domain nem engedélyezett).
    case closed
    case open
    case pending(AccessRequest)
    case rejected
}

package enum Role: String, Codable, Sendable {
    case editor, admin, guest
}

package struct User: Codable, Sendable {
    package var name: String
    package var role: Role
    package var passwordHash: String
    package var avatar: Int?
    /// A fiókhoz rendelt Google-fiók e-mail-címe (kisbetűs); ezzel a fiókkal jelszó nélkül is be lehet lépni.
    package var google: String?
    /// Adminnak szóló, elintézendő jelzések száma (`AdminMessage`); kérésenként számolódik, nem tárolódik.
    package var adminMessages = 0

    private enum CodingKeys: String, CodingKey { case name, role, passwordHash, avatar, google }

    // A memberwise inicializáló pontos mása (modulhatár).
    package init(name: String, role: Role, passwordHash: String, avatar: Int? = nil, google: String? = nil) {
        self.name = name
        self.role = role
        self.passwordHash = passwordHash
        self.avatar = avatar
        self.google = google
    }
}

/// A Google-fiók e-mail-címe egységes alakban (szóközök nélkül, kisbetűvel); üres bemenetre `nil`.
package func normalizedGoogleEmail(_ raw: String) throws -> String? {
    let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if email.isEmpty { return nil }
    let parts = email.split(separator: "@", omittingEmptySubsequences: false)
    guard email.utf8.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
          !email.contains(where: { $0.isWhitespace || $0 == "," || $0 == "<" || $0 == ">" || $0 == "\"" }) else {
        throw Abort(.unprocessableEntity, reason: "A Google-fiók e-mail-címe érvénytelen.")
    }
    return email
}

package func isTesterName(_ value: String) -> Bool {
    guard value.hasPrefix("Tester"), let number = Int(value.dropFirst(6)), number > 0 else { return false }
    return value == "Tester" + String(number)
}

package func validSlug(_ value: String) -> Bool {
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

package struct WorksheetPath: Sendable {
    package let parts: [String]
    package let name: String
    package let url: String

    /// Az első szegmensként foglalt nevek: a szerver saját címei, és a `common` (a közös könyvtár statikus címe, `/common/...`).
    private static let reserved = ["admin", "api", "common", "edit", "export", "login", "logout", "health", "open", "vendor"]

    package init(_ raw: [String]) throws {
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

package struct DocumentPolicy: Codable, Sendable, Equatable {
    package var hidden: Bool?
    package var frozen: Bool?
    package var owner: String?
    var editors: [String]?
    package var guestReadable: Bool?
    package var passwordHash: String?
    var mediaFiles: [String: String]?
    var archivedFiles: [String: String]?
    var worksheets: [String: PageSettings]?
    /// A mappa publikus fájljai (fájlnév): bejelentkezés nélkül is letölthetők.
    var publicFiles: [String]?
}

/// Tallózó: egy munkalap mappájának tartalma (csak a projekten belül).
package struct BrowseListing: Content {
    package struct Entry: Content {
        package let name: String
        let kind: String        // "folder", "file", "web"
        let publicAccess: Bool
        /// Kép/hang belső azonosítója (a mappa mediaFiles táblájából), ha van; a doboz ezzel hivatkozik rá.
        package var asset: String? = nil
    }
    let path: String            // munkalap-útvonal, pl. "projekt/allap"
    let parent: String?         // a szülő munkalap útvonala; a projekt gyökerénél nil
    package let manageable: Bool
    let entries: [Entry]
}

package struct PageSettings: Codable, Sendable, Equatable {
    package var hidden = false
    package var frozen: Bool?
}

package struct DocumentAccess: Sendable {
    package var readable = false
    package var editable = false
    package var manageable = false
    /// Hozzáadhat és eltávolíthat szerkesztőket a projektben: csak az admin és a projekt létrehozója (tulajdonosa).
    package var invitable = false
    var listed = false
    package var locked = false
    package var hidden = false
    package var projectRule = DocumentPolicy()
    package var sheetRule = DocumentPolicy()
    package var editorNames: [String] = []
    package var protectedByPassword = false
    package var frozen = false
    var passwordRequired = false
}

package struct DocumentAction: Content {
    package var scope: String
    var action: String
    var value: String?
    var filename: String? = nil
}

package final class WorksheetStore: @unchecked Sendable {
    let root: URL
    /// A data könyvtár (gyorsítótárakhoz, pl. a külső link-előnézetekhez).
    package var dataRoot: URL { root }
    package var dataDirectoryPath: String { root.path }
    package let testMode: Bool
    private var testerCount = 0

    package func nextTester() -> String {
        lock.withLock { testerCount += 1; return "Tester" + String(testerCount) }
    }

    let files = FileManager.default
    let lock = NSLock()
    private var pendingAttachments: [String: Date] = [:]

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    package init(root: URL, testMode: Bool = false) throws {
        self.testMode = testMode
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try files.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func folder(_ path: WorksheetPath) throws -> URL {
        var url = root
        for part in path.parts {
            url.appendPathComponent(part)
            try checkName(url)
        }
        return url
    }

    func checkName(_ url: URL) throws {
        try rejectLink(url)
        if files.fileExists(atPath: url.path),
           !(try files.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)).contains(url.lastPathComponent) {
            throw Abort(.notFound)
        }
    }

    func worksheetURL(_ path: WorksheetPath) throws -> URL {
        let url = try folder(path).appendingPathComponent(path.name).appendingPathExtension("thnode")
        try checkName(url)
        return url
    }

    func settingsURL(_ directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(".settings.json")
        try rejectLink(url)
        return url
    }

    package struct Context {
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

    func context(_ path: WorksheetPath) throws -> Context {
        let file = try worksheetURL(path)
        let parts = path.parts
        var chain: [URL] = [], rules: [URL: DocumentPolicy] = [:]
        var directory = root
        for part in parts {
            directory.appendPathComponent(part)
            let url = try settingsURL(directory)
            guard files.fileExists(atPath: url.path) else { throw Abort(.notFound) }
            var rule = try readPolicy(url)
            // Régi allapjelszó: már nem érvényes, a következő mentéskor kikerül a fájlból.
            if !chain.isEmpty { rule.passwordHash = nil }
            rules[directory] = rule
            chain.append(directory)
        }
        let key = (Array(parts.dropFirst()) + [file.lastPathComponent]).joined(separator: "/")
        return try Context(chain: chain, rules: rules, key: key, folderPath: WorksheetPath(parts).url)
    }

    func persist(_ next: Context, previous: Context) throws {
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

    func accessLocked(_ ctx: Context, user: User?, unlocks: Set<String>) -> DocumentAccess {
        let projectRule = ctx.rules[ctx.project]!
        let names = Set((projectRule.editors ?? []) + [projectRule.owner].compactMap { $0 })
        let admin = user?.role == .admin
        let member = user.map { $0.role == .editor && names.contains($0.name) } == true
        let owner = member && user?.name == projectRule.owner
        let guest = user == nil || user?.role == .guest
        let publicProject = projectRule.guestReadable == true
        let readable = admin || member || publicProject
        let editable = admin || member || (guest && publicProject)
        // Jelszó csak a projekten van; az allapok és a .web prezentációk ezt öröklik.
        let protected = projectRule.passwordHash != nil
        let locked = projectRule.passwordHash.map { !admin && !owner && !unlocks.contains($0) } ?? false
        var frozen = false
        for directory in ctx.chain { frozen = frozen || ctx.rules[directory]!.frozen == true }
        let page = ctx.page
        frozen = frozen || page.frozen == true
        var menu = ctx.local
        menu.hidden = page.hidden
        menu.frozen = ctx.local.frozen ?? page.frozen
        menu.passwordHash = projectRule.passwordHash
        menu.owner = projectRule.owner
        menu.guestReadable = projectRule.guestReadable
        return DocumentAccess(readable: readable && !locked, editable: editable && !locked && (!frozen || admin || owner),
            manageable: (admin || member) && !locked, invitable: (admin || owner) && !locked, listed: readable && !page.hidden,
            locked: readable && locked, hidden: page.hidden, projectRule: menu, sheetRule: menu,
            editorNames: names.sorted(), protectedByPassword: protected, frozen: frozen, passwordRequired: locked)
    }

    package func access(_ path: WorksheetPath, sheet: Worksheet, user: User?, unlocks: Set<String> = []) throws -> DocumentAccess {
        try lock.withLock { try accessLocked(context(path), user: user, unlocks: unlocks) }
    }

    func authorize(_ access: DocumentAccess, user: User?) throws {
        if access.locked { throw Abort(.locked, reason: "Ehhez a munkalaphoz jelszó szükséges.") }
        if !access.readable { throw Abort(user == nil ? .unauthorized : .forbidden) }
    }

    package func unlock(_ path: WorksheetPath, password: String, user: User?, attachment: String? = nil) throws -> [String] {
        let candidates = try lock.withLock {
            let ctx = try context(path)
            guard accessLocked(ctx, user: user, unlocks: []).locked else { throw Abort(.forbidden) }
            return [ctx.rules[ctx.project]?.passwordHash].compactMap { $0 }
        }
        // A bcrypt lassú; a záron kívül fut, hogy közben a többi kérés haladhasson.
        let hashes = try candidates.filter { try Bcrypt.verify(password, created: $0) }
        guard !hashes.isEmpty else { throw Abort(.forbidden) }
        return hashes
    }

    package func list(user: User?, childrenOf parent: WorksheetPath? = nil, rootsOnly: Bool = false, recursive: Bool = false, unlocks: Set<String> = []) throws -> [(path: WorksheetPath, worksheet: Worksheet)] {
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

    package func settings() throws -> SiteSettings {
        try lock.withLock { try readSettings() }
    }

    package func savePreferences(_ prefs: UserPreferences, for name: String) throws {
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

    package func assignAvatar(_ avatar: Int, to name: String) throws {
        try lock.withLock {
            var settings = try readSettings()
            guard (1...12).contains(avatar), settings.users?.contains(where: { $0.name == name }) == true else { throw Abort(.badRequest) }
            var entries = settings.preferences ?? [:]
            entries[name, default: UserPreferences()].avatar = avatar
            settings.preferences = entries
            try saveSiteSettings(settings)
        }
    }

    package func setSettings(_ settings: SiteSettings) throws {
        try lock.withLock {
            try rejectLink(settingsFile)
            var next = settings
            let existing = try readSettings()
            next.users = existing.users
            next.preferences = existing.preferences
            // A kérelmek megmaradnak; a kérés szabálya csak akkor változik, ha a hívó megadta.
            next.accessRequests = existing.accessRequests
            next.rejectedGoogle = existing.rejectedGoogle
            next.googleAccess = settings.googleAccess ?? existing.googleAccess
            try saveSiteSettings(next)
        }
    }

    package func open(_ path: WorksheetPath, user: User?, createOnly: Bool = false, unlocks: Set<String> = []) throws -> Worksheet {
        try lock.withLock { try openLocked(path, user: user, createOnly: createOnly, unlocks: unlocks) }
    }

    private func openLocked(_ path: WorksheetPath, user: User?, createOnly: Bool, unlocks: Set<String>, imported: Worksheet? = nil) throws -> Worksheet {
        if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
        let entry = try folder(path)
        if let url = try? worksheetURL(path), files.fileExists(atPath: url.path) {
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            if createOnly { throw Abort(.conflict) }
            return try reconcile(context: ctx, url: url, path: path)
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

    package enum Preview { case drawing(String), image(URL, String) }

    package func preview(_ path: WorksheetPath, user: User?, unlocks: Set<String> = [], mode: String? = nil) throws -> Preview {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let url = try worksheetURL(path)
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            let sheet = resolvedFileNames(try read(url), metadata: ctx.local, at: path, project: ctx.project)
            if let name = sheet.previewImage,
               let file = try attachments(at: url, named: name, metadata: ctx.local).first,
               let mime = previewType(file) { return .image(file, mime) }
            let suffix = mode == "dark" ? ".preview-v11-dark.svg" : ".preview-v11.svg"
            let cache = url.deletingLastPathComponent().appendingPathComponent("." + path.name + suffix)
            try rejectLink(cache)
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, let cached = try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               cached > modified && cached > Themes.loadedAt { return .drawing(try String(contentsOf: cache, encoding: .utf8)) }
            let texts = textContents(sheet, url: url, metadata: ctx.local)
            let svg = boardSVG(sheet, assetBase: "/" + path.url, mode: mode, fileText: { $0.file.flatMap { texts[$0.textKey] } })
            try Data(svg.utf8).write(to: cache, options: .atomic)
            return .drawing(svg)
        }
    }

    /// Szövegfájl-objektumok tartalma (asset → szöveg) a vászon rendereléséhez; legfeljebb 200 KB fájlonként.
    private func textContents(_ sheet: Worksheet, url: URL, metadata: DocumentPolicy, project: WorksheetPath? = nil,
                              commonDirectory: String? = nil) -> [String: String] {
        var result: [String: String] = [:]
        for node in sheet.nodes where node.isTextFile {
            guard let source = node.file, result[source.textKey] == nil else { continue }
            let asset = source.asset
            // Közös könyvtár (Public/common): bárki olvashatja; a projekt fájljai a tulajdonos lap mappájából.
            let located: URL? = source.isCommon ? commonDirectory.flatMap { CommonLibrary.file(source, publicDirectory: $0) }
                : source.source == nil ? try? attachments(at: url, named: asset, metadata: metadata).first
                : project.flatMap({ source.sheet(from: $0) }).flatMap({ try? sharedFile($0, named: asset) })
            guard let file = located,
                  let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            // A táblázat JSON-ja csak egészben olvasható; a többi szövegfájlnak elég az eleje.
            let bytes = (try? handle.read(upToCount: node.type == "table" ? TableLimits.maxBytes : 200_000)) ?? Data()
            result[source.textKey] = String(decoding: bytes, as: UTF8.self)
        }
        return result
    }

    package func fileTexts(_ path: WorksheetPath, sheet: Worksheet, user: User?, unlocks: Set<String>,
                           commonDirectory: String? = nil) throws -> [String: String] {
        try lock.withLock {
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            return textContents(sheet, url: try worksheetURL(path), metadata: ctx.local, project: path, commonDirectory: commonDirectory)
        }
    }

    package func pageExists(_ path: WorksheetPath) -> Bool {
        lock.withLock {
            guard let url = try? worksheetURL(path) else { return false }
            return files.fileExists(atPath: url.path)
        }
    }

    package func load(_ path: WorksheetPath, user: User?, unlocks: Set<String> = []) throws -> Worksheet {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            return try reconcile(context: ctx, url: worksheetURL(path), path: path)
        }
    }

    package func update(_ path: WorksheetPath, worksheet: Worksheet, user: User?, restoring: Bool = false, unlocks: Set<String> = [],
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
                if let link = node.link, !link.isValid || (link.worksheetLink != nil && link.worksheetLink?.destination(from: path) == nil) {
                    throw Abort(.unprocessableEntity, reason: "Érvénytelen link. Adj meg egy munkalapútvonalat, .web mappát vagy HTTP(S) webcímet.")
                }
            }
            restoreArchivedShared(worksheet, previous: current, at: path, user: user, unlocks: unlocks)
            var updated = worksheet
            if current.appearance != nil && updated.appearance == nil { throw Abort(.unprocessableEntity) }
            updated.creator = current.creator
            updated.revision = current.revision + 1
            updated.resetRevision = restoring ? updated.revision : current.resetRevision
            try updated.validate()
            updated.schemaVersion = Worksheet.currentSchema
            let url = try worksheetURL(path)
            let directory = ctx.directory
            var metadata = ctx.local
            var media = metadata.mediaFiles ?? [:]
            var archived = metadata.archivedFiles ?? [:]
            func sourceOf(_ ref: String) throws -> URL? {
                try attachments(at: url, named: ref, metadata: metadata).first
            }
            let previous = Dictionary(uniqueKeysWithValues: current.nodes.map { ($0.id, $0) })
            let currentRefs = Set(current.nodes.compactMap { $0.file?.source == nil ? $0.file?.asset : nil })
            var renames: [String: String] = [:]
            for index in updated.nodes.indices {
                let node = updated.nodes[index]
                guard let file = node.file, file.source == nil else { continue }
                let old = previous[node.id]
                let ref = file.asset
                guard let filename = file.filename, filename != old?.file?.filename else { continue }
                let source = try sourceOf(ref)
                guard let source else {
                    if archived[ref] == nil { throw Abort(.notFound, reason: "A fájl nem található.") }
                    continue
                }
                let ext = source.pathExtension
                let name = node.isImage ? filename + (ext.isEmpty ? "" : "." + ext) : filename
                guard (name as NSString).pathExtension == ext else {
                    throw Abort(.unprocessableEntity, reason: "A fájl kiterjesztése nem változtatható meg.")
                }
                if let prior = renames.updateValue(name, forKey: ref), prior != name {
                    throw Abort(.unprocessableEntity, reason: "Egy fájlhoz csak egy név tartozhat.")
                }
                updated.nodes[index].file?.asset = ref
            }
            let nextRefs = Set(updated.nodes.compactMap { $0.file?.source == nil ? $0.file?.asset : nil })
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
                    // A publikus jog a fájl új nevével marad érvényben.
                    if var names = metadata.publicFiles, let index = names.firstIndex(of: source.lastPathComponent) {
                        names[index] = name
                        metadata.publicFiles = names.sorted()
                        next.rules[directory] = metadata
                    }
                    if ref != updated.previewImage, source.lastPathComponent == updated.previewImage { updated.previewImage = name }
                }
                for index in updated.nodes.indices {
                    let node = updated.nodes[index]
                    guard node.file?.source == nil, let ref = node.file?.asset, let name = renames[ref] else { continue }
                    updated.nodes[index].file?.filename = node.isImage ? (name as NSString).deletingPathExtension : name
                }
                let keep = Set(nextRefs.map { media[$0] ?? $0 })
                for ref in currentRefs.subtracting(nextRefs).sorted() {
                    guard let source = try sourceOf(ref),
                          !keep.contains(source.lastPathComponent) else { continue }
                    // Más lap is használja: a fájl marad (a doboz törlése nem viszi lomtárba).
                    if !usageLocked(.file(owner: path.url, name: source.lastPathComponent), project: path.parts[0])
                        .filter({ $0.sheet != path.url }).isEmpty { continue }
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

    /// A „password” művelet hash-ét a hívó a zárakon kívül számolja ki (`passwordHash(for:)`).
    package static func passwordHash(for operation: DocumentAction) throws -> String? {
        guard operation.action == "password" else { return nil }
        let password = operation.value ?? ""
        guard password.utf8.count <= 72 else { throw Abort(.badRequest) }
        return password.isEmpty ? nil : try Bcrypt.hash(password)
    }

    package func manage(_ path: WorksheetPath, operation: DocumentAction, user: User, unlocks: Set<String>, passwordHash: String? = nil) throws -> WorksheetPath? {
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
                guard path.parts.count == 1 else {
                    throw Abort(.badRequest, reason: "Jelszót csak a projekt kaphat; az allapok a projekt jelszavát használják.")
                }
                let password = operation.value ?? ""
                guard password.utf8.count <= 72 else { throw Abort(.badRequest) }
                // Előre számolt hash hiányában (pl. tesztekből hívva) itt számolódik ki.
                next.rules[ctx.directory]?.passwordHash = password.isEmpty ? nil : try passwordHash ?? Bcrypt.hash(password)
            case "mode" where path.parts.count == 1:
                guard let mode = operation.value, ["public", "internal"].contains(mode) else { throw Abort(.badRequest) }
                next.rules[ctx.directory]?.guestReadable = mode == "public"
            case "grant", "revoke":
                guard path.parts.count == 1, let name = operation.value else { throw Abort(.badRequest) }
                // Meghívni csak a saját (általa létrehozott) projektbe lehet; az admin bármelyikbe. A meghívott fiók
                // szerepköre nem változik: szerkesztő szerepkört csak admin adhat (adminoldal), ezért csak ilyen fiók hívható meg.
                guard rights.invitable else {
                    throw Abort(.forbidden, reason: "Szerkesztőt csak a projekt létrehozója vagy adminisztrátor adhat hozzá és távolíthat el.")
                }
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

    /// Visszavonás után visszakerülő közös fájldoboz (másik lap mappájának fájlja): ha a fájl közben lomtárba került
    /// (a tulajdonos mappa `archivedFiles` listája szerint), visszaáll a helyére. A saját mappás fájlokat a mentés kezeli.
    private func restoreArchivedShared(_ worksheet: Worksheet, previous: Worksheet, at path: WorksheetPath, user: User?, unlocks: Set<String>) {
        func key(_ file: CanvasFile) -> String? {
            guard let source = file.source, !file.isCommon else { return nil }
            return source + "\u{0}" + file.asset
        }
        let known = Set(previous.nodes.compactMap { $0.file.flatMap(key) })
        var handled = Set<String>()
        for node in worksheet.nodes {
            guard let file = node.file, let id = key(file), !known.contains(id), handled.insert(id).inserted,
                  let owner = file.sheet(from: path), owner.url != path.url,
                  let ctx = try? context(owner), accessLocked(ctx, user: user, unlocks: unlocks).editable,
                  let relative = ctx.local.archivedFiles?[file.asset],
                  let url = try? worksheetURL(owner),
                  (try? attachments(at: url, named: file.asset, metadata: ctx.local).isEmpty) == true,
                  let source = try? projectTrashPath(relative, project: ctx.project, createParents: false),
                  files.fileExists(atPath: source.path),
                  let destination = try? unusedAttachment(ctx.local.mediaFiles?[file.asset] ?? file.asset, in: ctx.directory, metadata: nil)
            else { continue }
            var next = ctx
            var metadata = ctx.local
            metadata.archivedFiles?.removeValue(forKey: file.asset)
            if metadata.archivedFiles?.isEmpty == true { metadata.archivedFiles = nil }
            next.rules[ctx.directory] = metadata
            do {
                try files.moveItem(at: source, to: destination)
                do { try persist(next, previous: ctx) }
                catch { try? files.moveItem(at: destination, to: source) }
            } catch { continue }
        }
    }

    /// Olvasáskor a doboz a tulajdonos lap mappájának aktuális állapotát kapja: a fájl valódi nevét (átnevezés után
    /// a többi lapon is), és a publikus jogot (`webPublic`, a pillangó ikon) – fájlnál a tulajdonos mappa
    /// `publicFiles` listájából, .web hivatkozásnál a .web mappa beállításából. `path` nélkül csak a saját mappa nevei.
    private func resolvedFileNames(_ sheet: Worksheet, metadata: DocumentPolicy, at path: WorksheetPath? = nil, project: URL? = nil) -> Worksheet {
        var result = sheet
        var owners: [String: DocumentPolicy?] = [:]
        var webs: [String: Bool] = [:]
        func owner(of file: CanvasFile) -> DocumentPolicy? {
            guard let source = file.source else { return metadata }
            guard let path, !file.isCommon, let sheet = file.sheet(from: path) else { return nil }
            if let known = owners[source] { return known }
            let found = sheet.url == path.url ? metadata : (try? context(sheet))?.local
            owners[source] = .some(found)
            return found
        }
        for index in sheet.nodes.indices {
            let node = sheet.nodes[index]
            if let file = node.file {
                guard let policy = owner(of: file) else { continue }
                if let name = policy.mediaFiles?[file.asset] {
                    result.nodes[index].file?.filename = node.isImage ? (name as NSString).deletingPathExtension : name
                    if node.isImage { result.nodes[index].file?.fileExtension = (name as NSString).pathExtension }
                }
                if path != nil { result.nodes[index].webPublic = isPublic(file.asset, metadata: policy) ? true : nil }
            } else if let project, let reference = node.link?.webReference {
                let key = reference.relativePath
                let open = webs[key] ?? (((try? webPolicy(at: project.appendingPathComponent(key, isDirectory: true))) ?? nil)?.guestReadable == true)
                webs[key] = open
                result.nodes[index].webPublic = open ? true : nil
            }
        }
        return result
    }

    package func reconcileAtStartup() {
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
                    if let ctx = try? context(path) { _ = try? reconcile(context: ctx, url: url, path: path) }
                    visit(entry, parts: path.parts)
                }
            }
            visit(root, parts: [])
        }
    }

    private func copyReferencedAttachments(in sheet: Worksheet, from source: URL, metadata: DocumentPolicy, to folder: URL) throws -> DocumentPolicy {
        var refs = Set(sheet.nodes.compactMap { $0.file?.source == nil ? $0.file?.asset : nil })
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

    private func reconcile(context ctx: Context, url: URL, path: WorksheetPath) throws -> Worksheet {
        let current = resolvedFileNames(try read(url), metadata: ctx.local, at: path, project: ctx.project)
        guard current.nodes.count < 2_000 else { return current }
        let now = Date()
        pendingAttachments = pendingAttachments.filter { $0.value > now }
        var metadata = ctx.local
        var media = metadata.mediaFiles ?? [:]
        let archived = metadata.archivedFiles ?? [:]
        var referenced = Set(current.nodes.compactMap { $0.file?.source == nil ? $0.file?.asset : nil }.map { media[$0] ?? $0 })
        if let preview = current.previewImage { referenced.insert(media[preview] ?? preview) }
        var updated = current
        let x = current.nodes.isEmpty ? 0 : min(99_000, current.nodes.map { $0.position.x - $0.width / 2 }.min()! + 160)
        var bottom = current.nodes.map { $0.position.y + $0.height / 2 }.max() ?? -140
        func append(_ type: String, file: CanvasFile, height: Double) {
            let y = bottom + 55 + height / 2
            guard updated.nodes.count < 2_000, y <= 100_000 else { return }
            bottom = y + height / 2
            updated.nodes.append(Idea(id: UUID().uuidString.lowercased(), type: type, file: file,
                                      position: Point(x: x, y: y), width: 320, height: height,
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
            var canvasFile = CanvasFile(asset: existing.flatMap { canvasAssetType($0) == nil ? $0 : nil } ?? ("file-" + UUID().uuidString.lowercased()),
                                        filename: name, showFilename: true)
            var type = "document"
            var height = 120.0
            if let mime, let size, size <= 12 * 1024 * 1024,
               let bytes = try? Data(contentsOf: file), matchesMediaHeader(bytes, type: mime),
               let canonical = canvasMediaTypes.first(where: { $0.value == mime })?.key {
                type = mime.hasPrefix("image/") ? "image" : "audio"
                canvasFile.asset = existing.flatMap { canvasAssetType($0) == mime ? $0 : nil }
                    ?? (UUID().uuidString.lowercased() + "." + canonical)
                if type == "image" {
                    canvasFile.filename = file.deletingPathExtension().lastPathComponent
                    canvasFile.fileExtension = ext
                    canvasFile.showFilename = false
                }
                height = type == "image" ? 180 : 130
            } else if mime == nil, let size, size <= 12 * 1024 * 1024, let bytes = try? Data(contentsOf: file) {
                type = NodeTypes.classify(filename: name, bytes: bytes)
                if NodeTypes.root(type) == "text" { height = 220 }
            }
            let count = updated.nodes.count
            append(type, file: canvasFile, height: height)
            if updated.nodes.count != count { media[canvasFile.asset] = name }
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

    package func importWorksheet(_ bytes: Data, named name: String, at path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> WorksheetPath {
        try lock.withLock {
            guard bytes.count <= 12 * 1024 * 1024 else { throw Abort(.payloadTooLarge) }
            guard (name as NSString).pathExtension.lowercased() == "thnode",
                  var sheet = try? Worksheet.decodeFile(bytes) else {
                throw Abort(.unprocessableEntity, reason: "Érvénytelen ThinkNodes munkalapfájl.")
            }
            sheet.revision = 1
            sheet.resetRevision = nil
            try sheet.validate()
            let target = try WorksheetPath(path.parts + [(name as NSString).deletingPathExtension])
            _ = try openLocked(target, user: user, createOnly: true, unlocks: unlocks, imported: sheet)
            return target
        }
    }

    /// Weboldal-csomag (.zip) feltöltése a munkalap mappájába `név.web` néven; a hivatkozást adja vissza.
    package func importWebArchive(_ bytes: Data, named filename: String, at path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> WebPresentationInfo {
        guard bytes.count <= WebArchive.maximumArchive else { throw Abort(.payloadTooLarge, reason: "A ZIP legfeljebb 100 MiB lehet.") }
        guard bytes.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw Abort(.unsupportedMediaType, reason: "A fájl nem ZIP.") }
        let directory: URL = try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let ctx = try context(path)
            guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
            return ctx.directory
        }
        // A kicsomagolás lassú lehet, ezért a záron kívül, rejtett ideiglenes mappában fut.
        let token = ".tn-upload-" + UUID().uuidString
        let archive = directory.appendingPathComponent(token + ".zip"), staging = directory.appendingPathComponent(token)
        defer { try? files.removeItem(at: archive); try? files.removeItem(at: staging) }
        try bytes.write(to: archive, options: .withoutOverwriting)
        let site = try WebArchive.extract(archive, into: staging)
        return try lock.withLock {
            let ctx = try context(path)
            guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
            let folders = Array(path.parts.dropFirst())
            let base = WebArchive.folderName(filename)
            for attempt in 1...999 {
                let name = attempt == 1 ? base : base + "-" + String(attempt)
                guard let reference = try? WebPresentationReference((folders + [name + ".web"]).joined(separator: "/")) else {
                    throw Abort(.unprocessableEntity, reason: "Érvénytelen mappanév.")
                }
                let target = ctx.directory.appendingPathComponent(name + ".web")
                try rejectLink(target)
                if files.fileExists(atPath: target.path) { continue }
                try files.moveItem(at: site, to: target)
                let url = reference.url(in: path.parts[0])
                return WebPresentationInfo(reference: reference.relativePath, title: reference.name, url: url, preview: url + "_tn-preview",
                    manageable: true, publicWeb: false)
            }
            throw Abort(.conflict, reason: "Nincs szabad mappanév.")
        }
    }

    /// A .web mappa átnevezése (a mappa a saját .settings.json-jával együtt mozog); az új hivatkozást adja vissza.
    package func renameWeb(_ old: String, to newName: String, in path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> String {
        try lock.withLock {
            let ctx = try context(path)
            guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
            let project = path.parts[0]
            let reference = try WebPresentationReference(old)
            guard let web = try webContext(project: project, reference: reference, user: user, unlocks: unlocks),
                  web.access.readable || web.manageable else { throw Abort(.notFound) }
            let name = newName.trimmingCharacters(in: .whitespaces)
            guard name == WebArchive.folderName(name + ".zip"),
                  let renamed = try? WebPresentationReference((reference.folders + [name + ".web"]).joined(separator: "/")) else {
                throw Abort(.badRequest, reason: "A név csak betűt, számot, „_” és „-” jelet tartalmazhat.")
            }
            if renamed.name == reference.name { return reference.relativePath }
            let target = web.directory.deletingLastPathComponent().appendingPathComponent(name + ".web")
            try rejectLink(target)
            let names = try files.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)
            let caseOnly = names.contains(target.lastPathComponent) == false &&
                target.lastPathComponent.lowercased() == web.directory.lastPathComponent.lowercased()
            guard caseOnly || !files.fileExists(atPath: target.path) else {
                throw Abort(.conflict, reason: "Ilyen nevű weboldal már létezik.")
            }
            try files.moveItem(at: web.directory, to: target)
            // A régi néven tárolt előnézeti képek elavultak.
            let parent = target.deletingLastPathComponent()
            for name in names where name.hasPrefix("." + web.directory.lastPathComponent + WebScreenshot.marker) {
                try? files.removeItem(at: parent.appendingPathComponent(name))
            }
            return renamed.relativePath
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

    package func storeMedia(_ bytes: Data, type: String, imageName: String? = nil, filename: String? = nil,
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
    package func storeAttachment(_ bytes: Data, named name: String, at path: WorksheetPath, user: User?, unlocks: Set<String>, replaceText: Bool = false) throws -> String {
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
            // Táblázat: ellenőrzés és szerveres újraszámolás mentés előtt (docs/EXCEL.md).
            let bytes = ext == TableFiles.fileExtension ? try TableFiles.normalized(bytes) : bytes
            guard replaceText || matchesAttachmentType(bytes, extension: ext) else {
                throw Abort(.unsupportedMediaType, reason: "A fájltípus nem támogatott, vagy a tartalom eltér a kiterjesztéstől.")
            }
            let worksheet = try worksheetURL(path)
            let directory = ctx.directory
            var metadata = ctx.local
            if replaceText {
                guard let existing = try attachments(at: worksheet, named: name, metadata: metadata).first,
                      canvasMediaTypes[existing.pathExtension.lowercased()] == nil, NodeTypes.isPlainText(bytes),
                      NodeTypes.isPlainText(try Data(contentsOf: existing)) else { throw Abort(.badRequest) }
                // A név lehet azonosító (`file-…`); a táblázatot a tényleges fájlnév ismeri fel.
                let bytes = existing.pathExtension.lowercased() == TableFiles.fileExtension && ext != TableFiles.fileExtension
                    ? try TableFiles.normalized(bytes) : bytes
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

    package enum BoxFile { case disk(URL) }

    package func boxFile(_ path: WorksheetPath, id: String, user: User?, unlocks: Set<String>) throws -> BoxFile {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            let url = try worksheetURL(path)
            guard let node = try read(url).nodes.first(where: { $0.id == id }), let file = node.file else {
                throw Abort(.notFound)
            }
            if file.source != nil {
                // Közös fájl a projekt másik lapjáról: annak a lapnak a jogai érvényesek.
                guard let owner = file.sheet(from: path) else { throw Abort(.notFound) }
                let ownerContext = try context(owner)
                try authorize(accessLocked(ownerContext, user: user, unlocks: unlocks), user: user)
                guard let shared = try sharedFile(owner, named: file.asset) else { throw Abort(.notFound) }
                return .disk(shared)
            }
            guard let source = try attachments(at: url, named: file.asset, metadata: ctx.local).first else { throw Abort(.notFound) }
            return .disk(source)
        }
    }

    private func isPublic(_ name: String, metadata: DocumentPolicy) -> Bool {
        let filename = metadata.mediaFiles?[name] ?? name
        return metadata.publicFiles?.contains(filename) == true
    }

    /// Publikus jog ki/be egy fájlon (a lap mappájában, fájlnév szerint); a lap szerkesztői állíthatják.
    package func setFilePublic(_ name: String, publicAccess: Bool, in path: WorksheetPath, user: User?, unlocks: Set<String>) throws {
        try lock.withLock {
            let ctx = try context(path)
            guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
            guard let file = try attachments(at: worksheetURL(path), named: name, metadata: ctx.local).first else { throw Abort(.notFound) }
            var next = ctx
            var metadata = ctx.local
            var names = Set(metadata.publicFiles ?? [])
            if publicAccess { names.insert(file.lastPathComponent) } else { names.remove(file.lastPathComponent) }
            metadata.publicFiles = names.isEmpty ? nil : names.sorted()
            next.rules[ctx.directory] = metadata
            try persist(next, previous: ctx)
        }
    }

    /// Közösen használható elem: egy lap mappájában lévő fájl (valódi fájlnévvel) vagy .web mappa (projekt-relatív hivatkozás).
    package enum SharedTarget: Equatable {
        case file(owner: String, name: String)   // owner: a tulajdonos lap URL-útvonala
        case web(reference: String)
    }

    package struct Usage: Content {
        package let sheet: String       // munkalap URL-útvonala
        package let title: String
        package let nodes: [String]
    }

    /// A projekt összes munkalapja.
    private func projectSheetsLocked(_ project: String) -> [WorksheetPath] {
        var result: [WorksheetPath] = []
        func visit(_ parts: [String]) {
            guard let path = try? WorksheetPath(parts), let url = try? worksheetURL(path), files.fileExists(atPath: url.path) else { return }
            result.append(path)
            let directory = url.deletingLastPathComponent()
            let entries = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                           options: [.skipsHiddenFiles])) ?? []
            for entry in entries {
                guard let info = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      info.isDirectory == true, info.isSymbolicLink != true, entry.pathExtension != "web", parts.count < 11 else { continue }
                visit(parts + [entry.lastPathComponent])
            }
        }
        visit([project])
        return result
    }

    /// Egy doboz által használt közös elem (a közös könyvtár nem számít).
    private func targetLocked(of node: Idea, at sheet: WorksheetPath) -> SharedTarget? {
        if let link = node.link, link.kind == .web { return .web(reference: link.target) }
        guard let file = node.file, let owner = file.sheet(from: sheet) else { return nil }
        let media = (try? context(owner))?.local.mediaFiles
        return .file(owner: owner.url, name: media?[file.asset] ?? file.asset)
    }

    /// Mely lapok mely dobozai használják az elemet a projektben.
    private func usageLocked(_ target: SharedTarget, project: String) -> [Usage] {
        projectSheetsLocked(project).compactMap { sheet in
            guard let board = try? read(worksheetURL(sheet)) else { return nil }
            let ids = board.nodes.filter { targetLocked(of: $0, at: sheet) == target }.map(\.id)
            return ids.isEmpty ? nil : Usage(sheet: sheet.url, title: board.title, nodes: ids)
        }
    }

    /// .web hivatkozás használata a projekt lapjain (átnevezéskor ezek linkjei frissülnek).
    package func webUsage(_ reference: String, project: String) -> [Usage] {
        lock.withLock { usageLocked(.web(reference: reference), project: project) }
    }

    /// A doboz közös elemének használata (a projektben bárhol); `node` a saját lap egy doboza.
    package func usage(of nodeID: String, in path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> [Usage] {
        try lock.withLock {
            let ctx = try context(path)
            try authorize(accessLocked(ctx, user: user, unlocks: unlocks), user: user)
            guard let node = try read(worksheetURL(path)).nodes.first(where: { $0.id == nodeID }),
                  let target = targetLocked(of: node, at: path) else { return [] }
            return usageLocked(target, project: path.parts[0])
        }
    }

    /// A doboz közös elemét a lomtárba teszi (fájl a tulajdonos lap mappájából, vagy .web mappa).
    package func trashTarget(of nodeID: String, in path: WorksheetPath, user: User?, unlocks: Set<String>) throws {
        let target: SharedTarget? = try lock.withLock {
            let ctx = try context(path)
            guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
            guard let node = try read(worksheetURL(path)).nodes.first(where: { $0.id == nodeID }) else { throw Abort(.notFound) }
            return targetLocked(of: node, at: path)
        }
        switch target {
        case .web(let reference): try trashWeb(reference, in: path, user: user, unlocks: unlocks)
        case .file(let ownerURL, let name):
            try lock.withLock {
                let owner = try WorksheetPath(ownerURL.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) })
                let ownerContext = try context(owner)
                guard accessLocked(ownerContext, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
                let source = ownerContext.directory.appendingPathComponent(name)
                try rejectLink(source)
                guard files.fileExists(atPath: source.path) else { return }
                let destination = try trashDestination(source, in: ownerContext)
                try files.moveItem(at: source, to: destination)
                // A lomtárbeli hely feljegyzése: ha a doboz visszavonással visszakerül, a mentés visszaállítja a fájlt.
                let media = ownerContext.local.mediaFiles ?? [:]
                let references = media.filter { $0.value == name }.keys.sorted()
                let relative = String(destination.path.dropFirst(ownerContext.project.path.count + "/.trash/".count))
                var next = ownerContext
                var metadata = ownerContext.local
                var archived = metadata.archivedFiles ?? [:]
                for reference in references.isEmpty ? [name] : references { archived[reference] = relative }
                metadata.archivedFiles = archived
                next.rules[ownerContext.directory] = metadata
                try? persist(next, previous: ownerContext)
            }
        case nil: return
        }
    }

    /// Törölt projekt a gyökér lomtárában (`.trash/<UUID>-<név>`); a projekt a saját beállításaival együtt kerül oda.
    package struct DeletedProject: Sendable, Equatable {
        package let id: String      // a lomtárbeli mappa neve
        package let name: String    // az eredeti projektnév
        package let date: Date?     // a mappa utolsó módosítása (tájékoztató)
    }

    private func deletedProjectURL(_ id: String) throws -> URL {
        guard !id.isEmpty, !id.hasPrefix("."), !id.contains("/"), !id.contains("\\") else { throw Abort(.badRequest) }
        let trash = root.appendingPathComponent(".trash", isDirectory: true)
        try rejectLink(trash)
        let url = trash.appendingPathComponent(id, isDirectory: true)
        try rejectLink(url)
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw Abort(.notFound) }
        return url
    }

    private static func deletedProjectName(_ id: String) -> String {
        let prefix = String(id.prefix(36))
        return id.count > 37 && UUID(uuidString: prefix) != nil ? String(id.dropFirst(37)) : id
    }

    /// A gyökér lomtárában lévő törölt projektek, név szerint. Csak adminisztrátornak (a hívó ellenőrzi).
    package func deletedProjects() -> [DeletedProject] {
        lock.withLock {
            let trash = root.appendingPathComponent(".trash", isDirectory: true)
            guard (try? rejectLink(trash)) != nil else { return [] }
            let entries = (try? files.contentsOfDirectory(at: trash, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])) ?? []
            return entries.compactMap { entry -> DeletedProject? in
                guard let info = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                      info.isDirectory == true, info.isSymbolicLink != true, !entry.lastPathComponent.hasPrefix(".") else { return nil }
                let id = entry.lastPathComponent.precomposedStringWithCanonicalMapping
                return DeletedProject(id: id, name: Self.deletedProjectName(id), date: info.contentModificationDate)
            }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        }
    }

    /// Törölt projekt visszaállítása az eredeti nevén; ha a név közben foglalt lett vagy érvénytelen, hiba.
    @discardableResult
    package func restoreProject(_ id: String) throws -> WorksheetPath {
        try lock.withLock {
            let source = try deletedProjectURL(id)
            let name = Self.deletedProjectName(source.lastPathComponent.precomposedStringWithCanonicalMapping)
            guard let path = try? WorksheetPath([name]) else {
                throw Abort(.conflict, reason: "A projekt neve (\(name)) már nem használható; a mappát kézzel kell átnevezni.")
            }
            let destination = root.appendingPathComponent(name, isDirectory: true)
            guard !files.fileExists(atPath: destination.path) else {
                throw Abort(.conflict, reason: "Már van „\(name)” nevű projekt; előbb azt kell átnevezni.")
            }
            guard files.fileExists(atPath: source.appendingPathComponent(name + ".thnode").path) else {
                throw Abort(.conflict, reason: "A lomtárbeli mappa nem ThinkNodes-projekt.")
            }
            try files.moveItem(at: source, to: destination)
            return path
        }
    }

    /// Törölt projekt végleges törlése; `id` nélkül a gyökér lomtárának minden törölt projektje.
    package func purgeDeletedProjects(_ id: String? = nil) throws {
        try lock.withLock {
            if let id { try files.removeItem(at: try deletedProjectURL(id)); return }
            let trash = root.appendingPathComponent(".trash", isDirectory: true)
            try rejectLink(trash)
            for entry in (try? files.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
            where !entry.lastPathComponent.hasPrefix(".") {
                try files.removeItem(at: entry)
            }
        }
    }

    /// A projekt lomtára (`projekt/.trash`): az elemek az eredeti, projekt-relatív helyükkel.
    package struct TrashEntry: Content {
        let path: String        // a lomtáron belüli relatív útvonal
        let original: String    // eredeti hely a projektben
        let kind: String        // "file", "web", "folder"
    }

    private func trashRoot(_ project: String, user: User?, unlocks: Set<String>) throws -> (URL, Context) {
        let ctx = try context(try WorksheetPath([project]))
        guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
        let trash = ctx.project.appendingPathComponent(".trash", isDirectory: true)
        try rejectLink(trash)
        return (trash, ctx)
    }

    /// Lomtár tartalma: fájlok, .web mappák és törölt munkalapok (mappák) az eredeti helyükkel.
    package func trashContents(_ project: String, user: User?, unlocks: Set<String>) throws -> [TrashEntry] {
        try lock.withLock {
            let (trash, _) = try trashRoot(project, user: user, unlocks: unlocks)
            var result: [TrashEntry] = []
            func original(_ relative: [String]) -> String {
                // `.versions/<UUID>/…`: ugyanaz a hely többször törölve.
                (relative.first == ".versions" ? Array(relative.dropFirst(2)) : relative).joined(separator: "/")
            }
            func visit(_ directory: URL, _ relative: [String]) {
                let entries = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
                for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let name = entry.lastPathComponent
                    guard let info = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), info.isSymbolicLink != true,
                          name != ".DS_Store", !(name.hasPrefix(".") && name != ".versions") else { continue }
                    let path = relative + [name]
                    if info.isDirectory == true {
                        if entry.pathExtension == "web" {
                            result.append(.init(path: path.joined(separator: "/"), original: original(path), kind: "web"))
                        } else if files.fileExists(atPath: entry.appendingPathComponent(name + ".thnode").path) {
                            result.append(.init(path: path.joined(separator: "/"), original: original(path), kind: "folder"))
                        } else if path.count < 14 {
                            visit(entry, path)
                        }
                    } else {
                        result.append(.init(path: path.joined(separator: "/"), original: original(path), kind: "file"))
                    }
                }
            }
            visit(trash, [])
            return result
        }
    }

    /// Visszaállítás az eredeti helyre (ha a szülőmappa létezik és a hely szabad).
    package func restoreTrash(_ project: String, path: String, user: User?, unlocks: Set<String>) throws {
        try lock.withLock {
            let (trash, ctx) = try trashRoot(project, user: user, unlocks: unlocks)
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }) else { throw Abort(.badRequest) }
            var source = trash
            for part in parts { source.appendPathComponent(part); try rejectLink(source) }
            guard files.fileExists(atPath: source.path) else { throw Abort(.notFound) }
            let target = parts.first == ".versions" ? Array(parts.dropFirst(2)) : parts
            guard !target.isEmpty else { throw Abort(.badRequest) }
            var destination = ctx.project
            for part in target { destination.appendPathComponent(part); try rejectLink(destination) }
            guard files.fileExists(atPath: destination.deletingLastPathComponent().path) else {
                throw Abort(.conflict, reason: "Az eredeti mappa már nem létezik.")
            }
            guard !files.fileExists(atPath: destination.path) else { throw Abort(.conflict, reason: "Az eredeti helyen már van ilyen nevű elem.") }
            try files.moveItem(at: source, to: destination)
            forgetArchived(in: project) { $0 == path }
        }
    }

    /// Lomtár ürítése: végleges törlés. A lapok visszavonási hivatkozásai (archivedFiles) is törlődnek,
    /// kivéve azokat a fájlokat, amelyekre a lap valamelyik mentett állapota (`.version`) még hivatkozik:
    /// ezek a lomtárban maradnak, hogy a verzió visszaállításakor visszakerülhessenek.
    package func emptyTrash(_ project: String, user: User?, unlocks: Set<String>) throws {
        try lock.withLock {
            let (trash, _) = try trashRoot(project, user: user, unlocks: unlocks)
            let kept = versionProtectedTrashLocked(project)
            func clear(_ directory: URL, _ relative: [String]) throws {
                for entry in (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                    let path = relative + [entry.lastPathComponent]
                    let joined = path.joined(separator: "/")
                    if kept.contains(joined) { continue }
                    let isLink = (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
                    if !isLink, kept.contains(where: { $0.hasPrefix(joined + "/") }) {
                        try clear(entry, path)
                    } else {
                        try files.removeItem(at: entry)
                    }
                }
            }
            try clear(trash, [])
            forgetArchived(in: project) { !kept.contains($0) }
        }
    }

    /// A lomtárban lévő (archivedFiles) fájlok közül azok relatív útvonala, amelyekre valamelyik lap
    /// valamelyik mentett állapota még hivatkozik (zár alatt).
    private func versionProtectedTrashLocked(_ project: String) -> Set<String> {
        var kept = Set<String>()
        for sheet in projectSheetsLocked(project) {
            guard let ctx = try? context(sheet), let archived = ctx.local.archivedFiles, !archived.isEmpty,
                  let directory = try? versionFolder(sheet) else { continue }
            var refs = Set<String>()
            for entry in versionFiles(directory) {
                guard let data = try? Data(contentsOf: entry.url), let version = try? Worksheet.decodeFile(data) else { continue }
                for node in version.nodes { if let file = node.file, file.source == nil { refs.insert(file.asset) } }
                if let preview = version.previewImage { refs.insert(preview) }
            }
            for (ref, relative) in archived where refs.contains(ref) { kept.insert(relative) }
        }
        return kept
    }

    /// A lomtárra mutató visszavonási hivatkozások törlése a projekt lapjainak házirendjéből (zár alatt).
    private func forgetArchived(in project: String, where matches: (String) -> Bool) {
        for sheet in projectSheetsLocked(project) {
            guard let ctx = try? context(sheet), let archived = ctx.local.archivedFiles else { continue }
            let kept = archived.filter { !matches($0.value) }
            guard kept.count != archived.count else { continue }
            var next = ctx
            var metadata = ctx.local
            metadata.archivedFiles = kept.isEmpty ? nil : kept
            next.rules[ctx.directory] = metadata
            try? persist(next, previous: ctx)
        }
    }

    /// Másik lap mappájában lévő fájl (zár alatt hívandó).
    func sharedFile(_ owner: WorksheetPath, named name: String) throws -> URL? {
        let ctx = try context(owner)
        return try attachments(at: worksheetURL(owner), named: name, metadata: ctx.local).first
    }

    /// Tallózó: a munkalap mappájában lévő almappák (munkalapok), fájlok és .web oldalak.
    /// Csak a projekt fáján belül mozoghat: a WorksheetPath nem enged `..`-t, a linkeket a rejectLink kizárja.
    package func browse(_ path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> BrowseListing {
        try lock.withLock {
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let ctx = try context(path)
            let access = accessLocked(ctx, user: user, unlocks: unlocks)
            try authorize(access, user: user)
            let directory = ctx.directory
            try rejectLink(directory)
            let publicFiles = Set(ctx.local.publicFiles ?? [])
            var entries: [BrowseListing.Entry] = []
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
                let info = try url.resourceValues(forKeys: Set(keys))
                guard info.isSymbolicLink != true else { continue }
                let name = url.lastPathComponent
                if info.isDirectory == true {
                    if url.pathExtension == "web" {
                        let publicWeb = (try? webPolicy(at: url))??.guestReadable == true
                        entries.append(.init(name: name, kind: "web", publicAccess: publicWeb))
                    } else if (try? WorksheetPath(path.parts + [name])) != nil,
                              files.fileExists(atPath: url.appendingPathComponent(".settings.json").path) {
                        entries.append(.init(name: name, kind: "folder", publicAccess: false))
                    }
                } else if info.isRegularFile == true, url.pathExtension.lowercased() != "thnode", validImageStem(name) {
                    let ref = ctx.local.mediaFiles?.first(where: { $0.value == name })?.key
                    entries.append(.init(name: name, kind: "file", publicAccess: publicFiles.contains(name), asset: ref))
                }
            }
            let order = ["folder": 0, "web": 1, "file": 2]
            entries.sort { (order[$0.kind]!, $0.name.lowercased()) < (order[$1.kind]!, $1.name.lowercased()) }
            let parent = path.parts.count > 1 ? (try? WorksheetPath(Array(path.parts.dropLast())))?.url : nil
            return BrowseListing(path: path.url, parent: parent, manageable: access.editable, entries: entries)
        }
    }

    package func contents(_ path: WorksheetPath, user: User?, unlocks: Set<String>, named name: String? = nil) throws -> [URL] {
        try lock.withLock {
            let url = try worksheetURL(path)
            let ctx = try context(path)
            _ = try read(worksheetURL(path))
            if let name, isPublic(name, metadata: ctx.local) {
                // Publikus fájl: bárki letöltheti, bejelentkezés és jelszó nélkül is.
                return try attachments(at: url, named: name, metadata: ctx.local)
            }
            if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
            let access = accessLocked(ctx, user: user, unlocks: unlocks)
            try authorize(access, user: user)
            return try attachments(at: url, named: name, metadata: ctx.local)
        }
    }

    func attachments(at url: URL, named name: String?, metadata: DocumentPolicy?) throws -> [URL] {
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

    // MARK: Mentett állapotok (verziók)
    // Minden lap a saját mappájában, a `.version` alkönyvtárban tárolja:
    // `0001_20261123-142530.thnode` (sorszám, UTC időbélyeg). Nincs darabszám-korlát.

    package struct VersionEntry: Content {
        let number: Int
        let created: Date
        package let user: String?
    }

    package struct VersionList: Content {
        package let versions: [VersionEntry]
        let changed: Bool
    }

    private func versionFolder(_ path: WorksheetPath) throws -> URL {
        let url = try folder(path).appendingPathComponent(".version")
        try rejectLink(url)
        return url
    }

    private func versionFiles(_ directory: URL) -> [(number: Int, url: URL)] {
        let names = (try? files.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name -> (Int, URL)? in
            guard name.hasSuffix(".thnode"), let number = Int(name.prefix { $0.isNumber }), number > 0 else { return nil }
            return (number, directory.appendingPathComponent(name))
        }.sorted { $0.0 < $1.0 }
    }

    private static let versionStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private func versionEntry(_ number: Int, _ url: URL) -> VersionEntry {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "_", maxSplits: 2).map(String.init)
        let created = parts.count > 1 ? Self.versionStamp.date(from: parts[1]) : nil
        return VersionEntry(number: number,
                            created: created ?? ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast),
                            user: parts.count > 2 ? parts[2].removingPercentEncoding : nil)
    }

    private func sameContent(_ a: Worksheet, _ b: Worksheet) -> Bool {
        var a = a, b = b
        a.revision = 0; b.revision = 0
        a.resetRevision = nil; b.resetRevision = nil
        a.schemaVersion = 0; b.schemaVersion = 0
        return a == b
    }

    private func editableContext(_ path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> Context {
        if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
        let ctx = try context(path)
        guard accessLocked(ctx, user: user, unlocks: unlocks).editable else { throw Abort(.forbidden) }
        return ctx
    }

    package func versions(_ path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> VersionList {
        try lock.withLock {
            _ = try editableContext(path, user: user, unlocks: unlocks)
            let list = versionFiles(try versionFolder(path))
            let current = try read(worksheetURL(path))
            let changed = try list.last.map { !sameContent(try Worksheet.decodeFile(Data(contentsOf: $0.url)), current) } ?? true
            return VersionList(versions: list.reversed().map { versionEntry($0.number, $0.url) }, changed: changed)
        }
    }

    /// A lap aktuális (lemezen lévő) állapotát új sorszámú másolatként menti.
    package func saveVersion(_ path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> VersionEntry {
        try lock.withLock {
            _ = try editableContext(path, user: user, unlocks: unlocks)
            let directory = try versionFolder(path)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let number = (versionFiles(directory).last?.number ?? 0) + 1
            let now = Date()
            var name = String(format: "%04d", number) + "_" + Self.versionStamp.string(from: now)
            if let author = user?.name { name += "_" + WorksheetPath.encodeSegment(author) }
            let url = directory.appendingPathComponent(name + ".thnode")
            let data = try Data(contentsOf: worksheetURL(path))
            try data.write(to: url, options: .withoutOverwriting)
            return versionEntry(number, url)
        }
    }

    /// Egy mentett állapot tartalma; a visszaállítást a hívó a szokásos mentéssel végzi (`restoring: true`).
    package func version(_ path: WorksheetPath, number: Int, user: User?, unlocks: Set<String>) throws -> Worksheet {
        try lock.withLock {
            _ = try editableContext(path, user: user, unlocks: unlocks)
            guard let entry = versionFiles(try versionFolder(path)).first(where: { $0.number == number }) else {
                throw Abort(.notFound, reason: "A mentett állapot nem található.")
            }
            return try Worksheet.decodeFile(Data(contentsOf: entry.url))
        }
    }

    package func archive(_ path: WorksheetPath, expected: Int) throws {
        try lock.withLock {
            let ctx = try context(path)
            guard try read(worksheetURL(path)).revision == expected else { throw Abort(.preconditionFailed) }
            _ = try moveDocument(path, ctx, name: nil)
        }
    }

    package func allUsers() throws -> [User] {
        try lock.withLock { try readUsers().sorted { $0.name < $1.name } }
    }

    package func user(named name: String) throws -> User? {
        try lock.withLock {
            let settings = try readSettings()
            var user = settings.users?.first { $0.name == name }
            user?.avatar = settings.preferences?[name]?.avatar
            return user
        }
    }

    /// A Google-fiók e-mail-címe alapján keresi a fiókot (a cím egy fiókhoz tartozhat).
    package func user(google email: String) throws -> User? {
        guard let email = try? normalizedGoogleEmail(email) else { return nil }
        return try lock.withLock {
            let settings = try readSettings()
            guard var user = settings.users?.first(where: { $0.google == email }) else { return nil }
            user.avatar = settings.preferences?[user.name]?.avatar
            return user
        }
    }

    /// `google`: `nil` = a hozzárendelt Google-fiók változatlan; `.some(nil)` vagy üres szöveg = leválasztás;
    /// e-mail-cím = hozzárendelés. Új fiók jelszó nélkül csak Google-fiókkal hozható létre (ekkor a jelszavas
    /// belépés egy véletlen, senki által nem ismert jelszó miatt nem használható, amíg az admin nem ad jelszót).
    package func setUser(name: String, role: Role, passwordHash: String?, google: String?? = nil, initialOnly: Bool = false) throws {
        guard validSlug(name) else {
            throw Abort(.unprocessableEntity, reason: "A felhasználónév kisbetűket, számokat és kötőjelet tartalmazhat.")
        }
        let requested = try google.map { try $0.flatMap(normalizedGoogleEmail) }
        try lock.withLock {
            var users = try readUsers()
            if initialOnly && !users.isEmpty { throw Abort(.conflict) }
            let existing = users.first { $0.name == name }
            let email = requested ?? existing?.google
            if let email, users.contains(where: { $0.name != name && $0.google == email }) {
                throw Abort(.conflict, reason: "Ez a Google-fiók már egy másik felhasználóhoz tartozik.")
            }
            guard let hash = try passwordHash ?? existing?.passwordHash
                    ?? (email == nil ? nil : Bcrypt.hash(Data([UInt8].random(count: 32)).base64EncodedString())) else {
                throw Abort(.unprocessableEntity, reason: "Az új fiókhoz jelszót vagy Google-fiókot kell megadni.")
            }
            users.removeAll { $0.name == name }
            users.append(User(name: name, role: role, passwordHash: hash, google: email))
            try writeUsers(users)
        }
    }

    // MARK: Adminisztrátori jelzések

    /// Az adminokra váró teendők, fajtánként egy jelzés (ami nem áll fenn, az nincs a listában).
    package func adminMessages(now: Date = Date()) throws -> [AdminMessage] {
        let settings = try lock.withLock { try readSettings() }
        var messages: [AdminMessage] = []
        let pending = liveRequests(settings, now: now).count
        if pending > 0 {
            messages.append(AdminMessage(kind: .accessRequests, count: pending,
                                         text: "\(pending) hozzáférési kérelem vár elbírálásra", link: "/admin#access-requests"))
        }
        return messages
    }

    // MARK: Hozzáférés-kérés Google-fiókkal

    /// Ennyi ideig él egy elbírálatlan kérelem, és ennyi függő kérelem lehet egyszerre.
    static let accessRequestLifetime: Double = 30 * 24 * 3600
    static let accessRequestLimit = 50

    private func liveRequests(_ settings: SiteSettings, now: Date) -> [AccessRequest] {
        (settings.accessRequests ?? []).filter { $0.date > now.timeIntervalSince1970 - Self.accessRequestLifetime }
    }

    private func requestState(_ email: String, in settings: SiteSettings, now: Date) -> AccessRequestState {
        guard settings.googleAccess?.allows(email) == true else { return .closed }
        if settings.rejectedGoogle?.contains(email) == true { return .rejected }
        if let request = liveRequests(settings, now: now).first(where: { $0.email == email }) { return .pending(request) }
        return .open
    }

    package func accessRequestState(email: String, now: Date = Date()) throws -> AccessRequestState {
        guard let email = try? normalizedGoogleEmail(email) else { return .closed }
        return try lock.withLock { requestState(email, in: try readSettings(), now: now) }
    }

    /// A függő kérelmek (a legrégebbi elöl) és az elutasított címek az adminoldalhoz.
    package func accessRequests(now: Date = Date()) throws -> (pending: [AccessRequest], rejected: [String]) {
        try lock.withLock {
            let settings = try readSettings()
            return (liveRequests(settings, now: now).sorted { $0.date < $1.date }, (settings.rejectedGoogle ?? []).sorted())
        }
    }

    /// Kérelem beadása a Google által igazolt címmel; címenként egy kérelem él (az új a régit váltja).
    package func requestAccess(email raw: String, name: String, now: Date = Date()) throws {
        guard let email = try normalizedGoogleEmail(raw) else { throw Abort(.badRequest) }
        guard validSlug(name) else {
            throw Abort(.unprocessableEntity, reason: "A felhasználónév kisbetűket, számokat és kötőjelet tartalmazhat.")
        }
        try lock.withLock {
            var settings = try readSettings()
            let users = settings.users ?? []
            guard !users.contains(where: { $0.google == email }) else { throw Abort(.conflict, reason: "Ehhez a Google-fiókhoz már tartozik fiók.") }
            switch requestState(email, in: settings, now: now) {
            case .closed: throw Abort(.forbidden, reason: "Ezzel a Google-fiókkal nem kérhető hozzáférés.")
            case .rejected: throw Abort(.forbidden, reason: "A kérelmedet az adminisztrátor elutasította.")
            case .open, .pending: break
            }
            guard !users.contains(where: { $0.name == name }) else {
                throw Abort(.unprocessableEntity, reason: "Ez a felhasználónév már foglalt, válassz másikat.")
            }
            var requests = liveRequests(settings, now: now).filter { $0.email != email }
            guard requests.count < Self.accessRequestLimit else {
                throw Abort(.tooManyRequests, reason: "Most túl sok kérelem vár elbírálásra. Próbáld később, vagy szólj az adminisztrátornak.")
            }
            requests.append(AccessRequest(email: email, name: name, date: now.timeIntervalSince1970))
            settings.accessRequests = requests
            try saveSiteSettings(settings)
        }
    }

    /// Jóváhagyás: új fiók jön létre a megadott névvel és szerepkörrel (jelszó nélkül, csak Google-belépéssel),
    /// vagy ha a név egy meglévő, Google-fiók nélküli felhasználóé, a cím hozzá kapcsolódik (a szerepköre marad).
    package func approveAccess(email raw: String, name: String, role: Role, now: Date = Date()) throws {
        guard let email = try normalizedGoogleEmail(raw) else { throw Abort(.badRequest) }
        guard validSlug(name) else {
            throw Abort(.unprocessableEntity, reason: "A felhasználónév kisbetűket, számokat és kötőjelet tartalmazhat.")
        }
        try lock.withLock {
            var users = try readUsers()
            guard liveRequests(try readSettings(), now: now).contains(where: { $0.email == email }) else {
                throw Abort(.notFound, reason: "A kérelem már nem található.")
            }
            guard !users.contains(where: { $0.google == email }) else { throw Abort(.conflict, reason: "Ehhez a Google-fiókhoz már tartozik fiók.") }
            if let index = users.firstIndex(where: { $0.name == name }) {
                guard users[index].google == nil else {
                    throw Abort(.conflict, reason: "Ehhez a felhasználóhoz már másik Google-fiók tartozik.")
                }
                users[index].google = email
            } else {
                let hash = try Bcrypt.hash(Data([UInt8].random(count: 32)).base64EncodedString())
                users.append(User(name: name, role: role, passwordHash: hash, google: email))
            }
            try writeUsers(users)
        }
    }

    /// Elutasítás: a kérelem törlődik, és a cím nem kérhet újra, amíg az admin fel nem oldja.
    package func rejectAccess(email raw: String) throws {
        guard let email = try normalizedGoogleEmail(raw) else { throw Abort(.badRequest) }
        try lock.withLock {
            var settings = try readSettings()
            settings.accessRequests?.removeAll { $0.email == email }
            var rejected = (settings.rejectedGoogle ?? []).filter { $0 != email }
            rejected.append(email)
            settings.rejectedGoogle = Array(rejected.suffix(500))
            try saveSiteSettings(settings)
        }
    }

    /// Az elutasítás feloldása: a cím újra kérhet hozzáférést.
    package func forgetRejectedAccess(email raw: String) throws {
        guard let email = try normalizedGoogleEmail(raw) else { throw Abort(.badRequest) }
        try lock.withLock {
            var settings = try readSettings()
            settings.rejectedGoogle?.removeAll { $0 == email }
            try saveSiteSettings(settings)
        }
    }

    package func removeUser(named name: String) throws {
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

    func readSettings() throws -> SiteSettings {
        try rejectLink(settingsFile)
        guard files.fileExists(atPath: settingsFile.path) else { return SiteSettings() }
        return try cached(settingsFile, in: &settingsCache) { try JSONDecoder().decode(SiteSettings.self, from: $0) }
    }

    // MARK: Memóriabeli gyorsítótár (docs/PLAN.md A1)
    // A munkalapok, a mappánkénti házirendek és a webhely-beállítások dekódolt (és validált) példánya a fájl
    // módosítási ideje és mérete szerint érvényes. Az adatkönyvtárat egyelőre csak a szerver írja; ha kézzel
    // módosul, a megváltozott időbélyeg miatt újraolvasódik. A tárolón keresztüli írás azonnal érvényteleníti.
    // Minden hozzáférés a tároló zárja alatt történik.
    private struct FileStamp: Equatable { let modified: Date?; let size: Int? }
    private var sheetCache: [String: (stamp: FileStamp, value: Worksheet)] = [:]
    private var policyCache: [String: (stamp: FileStamp, value: DocumentPolicy)] = [:]
    private var settingsCache: [String: (stamp: FileStamp, value: SiteSettings)] = [:]

    private func stamp(_ url: URL) -> FileStamp? {
        guard let attributes = try? files.attributesOfItem(atPath: url.path) else { return nil }
        return FileStamp(modified: attributes[.modificationDate] as? Date, size: (attributes[.size] as? NSNumber)?.intValue)
    }

    private func cached<Value>(_ url: URL, in cache: inout [String: (stamp: FileStamp, value: Value)],
                               decode: (Data) throws -> Value) throws -> Value {
        let key = url.standardizedFileURL.path
        let current = stamp(url)
        if let current, let hit = cache[key], hit.stamp == current { return hit.value }
        let value = try decode(Data(contentsOf: url))
        if cache.count > 1_000 { cache.removeAll() }
        if let current { cache[key] = (current, value) }
        return value
    }

    private func invalidate(_ url: URL) {
        let key = url.standardizedFileURL.path
        sheetCache.removeValue(forKey: key)
        policyCache.removeValue(forKey: key)
        settingsCache.removeValue(forKey: key)
    }

    func readPolicy(_ url: URL) throws -> DocumentPolicy {
        try cached(url, in: &policyCache) { try JSONDecoder().decode(DocumentPolicy.self, from: $0) }
    }

    func readUsers() throws -> [User] {
        try readSettings().users ?? []
    }

    private func writeUsers(_ users: [User]) throws {
        guard users.contains(where: { $0.role == .admin }) else {
            throw Abort(.unprocessableEntity, reason: "Legalább egy adminisztrátori fióknak meg kell maradnia.")
        }
        var settings = try readSettings()
        settings.users = users
        // Amelyik Google-fiók már egy felhasználóé, ahhoz nem tartozhat függő kérelem vagy elutasítás.
        let linked = Set(users.compactMap(\.google))
        settings.accessRequests?.removeAll { linked.contains($0.email) }
        settings.rejectedGoogle?.removeAll { linked.contains($0) }
        try saveSiteSettings(settings)
    }

    private func saveSiteSettings(_ settings: SiteSettings) throws {
        invalidate(settingsFile)
        defer { invalidate(settingsFile) }
        try encoder.encode(settings).write(to: settingsFile, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsFile.path)
    }

    func read(_ url: URL) throws -> Worksheet {
        guard files.fileExists(atPath: url.path) else { throw Abort(.notFound, reason: "A munkalap nem található.") }
        return try cached(url, in: &sheetCache) { data in
            let worksheet = try Worksheet.decodeFile(data)
            guard worksheet.schemaVersion == Worksheet.currentSchema else {
                throw Abort(.unprocessableEntity, reason: "Régi formátumú munkalap (\(worksheet.schemaVersion). verzió). Az új objektumtípusok miatt nem tölthető be; törölhető.")
            }
            try worksheet.validate()
            return worksheet
        }
    }

    func write(_ value: some Encodable, to url: URL) throws {
        invalidate(url)
        defer { invalidate(url) }
        try (encoder.encode(value) + Data([10])).write(to: url, options: .atomic)
    }

    func rejectLink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw Abort(.notFound)
        }
    }
}

extension Idea {
    package init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        type = try fields.decode(String.self, forKey: .type)
        text = (try? fields.decode(String.self, forKey: .text)) ?? ""
        file = try fields.decodeIfPresent(CanvasFile.self, forKey: .file)
        hideText = try? fields.decode(Bool.self, forKey: .hideText)
        position = (try? fields.decode(Point.self, forKey: .position)) ?? Point(x: 0, y: 0)
        let junction = NodeTypes.root(type) == "junction"
        width = (try? fields.decode(Double.self, forKey: .width)) ?? (junction ? 12 : 176)
        height = (try? fields.decode(Double.self, forKey: .height)) ?? (junction ? width : 80)
        shape = (try? fields.decode(Shape.self, forKey: .shape)) ?? .rounded
        fill = (try? fields.decode(StoredPaint.self, forKey: .fill).wrappedValue) ?? "#dce9ff"
        // Ismeretlen mód (pl. a megszűnt "blurred") kitöltött háttérként töltődik be.
        backgroundMode = (try? fields.decodeIfPresent(String.self, forKey: .backgroundMode)).flatMap { $0 }.flatMap(BoxBackgroundMode.init(rawValue:))
        animation = try? fields.decode(BoxAnimation.self, forKey: .animation)
        textColor = (try? fields.decode(StoredPaint.self, forKey: .textColor).wrappedValue) ?? "#182335"
        fitText = try? fields.decode(Bool.self, forKey: .fitText)
        fontSize = (try? fields.decode(Double.self, forKey: .fontSize)) ?? 16
        bold = try? fields.decode(Bool.self, forKey: .bold)
        italic = try? fields.decode(Bool.self, forKey: .italic)
        underline = try? fields.decode(Bool.self, forKey: .underline)
        font = try? fields.decode(Int.self, forKey: .font)
        justified = try? fields.decode(Bool.self, forKey: .justified)
        alignment = (try? fields.decode(LabelAlignment.self, forKey: .alignment)) ?? .center
        verticalAlignment = try? fields.decode(VerticalAlignment.self, forKey: .verticalAlignment)
        link = try fields.decodeIfPresent(NodeLink.self, forKey: .link)
        angle = try? fields.decode(Double.self, forKey: .angle)
        parent = try? fields.decode(String.self, forKey: .parent)
        container = try? fields.decode(Bool.self, forKey: .container)
        locked = try? fields.decode(Bool.self, forKey: .locked)
        enum FormerKey: String, CodingKey { case autoLayout }
        textFlow = (try? fields.decode(Bool.self, forKey: .textFlow))
            ?? (try? decoder.container(keyedBy: FormerKey.self).decode(Bool.self, forKey: .autoLayout))
        elevated = try? fields.decode(Bool.self, forKey: .elevated)
        staticPreview = try? fields.decode(Bool.self, forKey: .staticPreview)
        webPublic = try? fields.decode(Bool.self, forKey: .webPublic)
        uppercase = try? fields.decode(Bool.self, forKey: .uppercase)
        frame = try? fields.decode(Bool.self, forKey: .frame)
        frameWidth = try? fields.decode(Double.self, forKey: .frameWidth)
        scroll = try? fields.decode(Point.self, forKey: .scroll)
        chart = try? fields.decode(ChartSettings.self, forKey: .chart)
        normalizePreview()
    }

    /// Előnézetes link-doboz (`preview`): minden linkes doboz ez, mindig téglalap (5 px lekerekítés), animáció nélkül.
    /// A régi, linkes `box` betöltéskor átáll; link nélkül a `preview` visszaáll `box`-ra.
    mutating func normalizePreview() {
        if type == "box", link != nil { type = "preview" }
        if type == "preview", link == nil { type = "box" }
        if type == "preview" { shape = .rectangle; animation = nil }
    }
}

extension Worksheet {
    package init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try fields.decodeIfPresent(Appearance.self, forKey: .appearance)
        schemaVersion = (try? fields.decode(Int.self, forKey: .schemaVersion)) ?? 0
        revision = (try? fields.decode(Int.self, forKey: .revision)) ?? 1
        resetRevision = try? fields.decode(Int.self, forKey: .resetRevision)
        title = (try? fields.decode(String.self, forKey: .title)) ?? "Munkalap"
        text = try? fields.decode(String.self, forKey: .text)
        previewImage = try? fields.decode(String.self, forKey: .previewImage)
        textJustified = try? fields.decode(Bool.self, forKey: .textJustified)
        background = try? fields.decode(StoredPaint.self, forKey: .background).wrappedValue
        gridSpacing = try? fields.decode(Double.self, forKey: .gridSpacing)
        creator = try? fields.decode(String.self, forKey: .creator)
        if schemaVersion != Worksheet.currentSchema {
            throw Abort(.unprocessableEntity, reason: "Régi formátumú vagy ismeretlen sémájú munkalap.")
        }
        nodes = try fields.decode([Idea].self, forKey: .nodes)
        edges = fields.contains(.edges) ? try fields.decode([Connection].self, forKey: .edges) : []
    }
}

extension Point {
    package init(from decoder: Decoder) throws {
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
        package var readable: Bool
        var publicRead: Bool
        var hashes: [String] = []

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
        package let access: WebAccess
        package let manageable: Bool
    }

    private func webPolicy(at directory: URL) throws -> DocumentPolicy? {
        let url = try settingsURL(directory)
        guard files.fileExists(atPath: url.path) else { return nil }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard info.isRegularFile == true else { throw Abort(.notFound) }
        return try readPolicy(url)
    }

    private func webDirectory(_ name: String, in parent: URL) throws -> URL? {
        let url = parent.appendingPathComponent(name)
        try checkName(url)
        guard files.fileExists(atPath: url.path),
              try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { return nil }
        return url
    }

    /// .web jogok (egyszerűsített): a projekt adminja és szerkesztői kezelik (átnevezés, publikussá tétel, törlés);
    /// olvasni az tudja, aki a projektet; publikus projektnél vagy publikussá tett .web-nél bárki, bejelentkezés nélkül is.
    private func webContext(project: String, reference: WebPresentationReference, user: User?, unlocks: Set<String>) throws -> WebContext? {
        let requiresLogin = try readSettings().requireLogin
        guard var directory = try webDirectory(project, in: root), let rootRule = try webPolicy(at: directory) else { return nil }
        for folder in reference.folders {
            guard let next = try webDirectory(folder, in: directory) else { return nil }
            directory = next
        }
        guard let presentation = try webDirectory(reference.name + ".web", in: directory) else { return nil }
        let policy = try webPolicy(at: presentation) ?? DocumentPolicy()
        let publicWeb = policy.guestReadable == true
        let member = user.map { user in
            user.role == .editor && (user.name == rootRule.owner || rootRule.editors?.contains(user.name) == true)
        } == true
        let admin = user?.role == .admin
        let publicProject = rootRule.guestReadable == true && !(requiresLogin && user == nil)
        var access = WebAccess(admin: admin, projectMember: member, projectOwner: member && user?.name == rootRule.owner,
            readable: admin || member || publicProject || publicWeb,
            publicRead: publicWeb || (!requiresLogin && rootRule.guestReadable == true && rootRule.passwordHash == nil))
        if !publicWeb { access.protect(rootRule.passwordHash) }
        guard access.readable else { throw Abort(user == nil ? .unauthorized : .forbidden) }
        return WebContext(directory: presentation, policy: policy, access: access, manageable: admin || member)
    }

    /// `size`: a doboz mérete; `live`: generálhat-e új előnézetet. Az előnézet keresési sorrendje: WebPreview.find.
    package func webAsset(_ request: WebPresentationRequest, user: User?, unlocks: Set<String>, size: (width: Int, height: Int)? = nil, live: Bool = true) throws -> (asset: WebAsset?, directory: Bool, publicRead: Bool)? {
        var preview: (URL, Bool)?
        let found: (asset: WebAsset?, directory: Bool, publicRead: Bool)? = try lock.withLock {
            guard let context = try webContext(project: request.project, reference: request.reference, user: user, unlocks: unlocks) else { return nil }
            try context.access.authorize(user, unlocks: unlocks)
            let dirs = [request.project] + request.reference.folders + [request.reference.name + ".web"]
            if request.asset == ["_tn-preview"] {
                guard !request.trailingSlash else { throw Abort(.notFound) }
                preview = (context.directory, context.access.publicRead)
                return (nil, false, context.access.publicRead)
            }
            let (asset, directory) = try WebAsset.open(in: root, folders: dirs, asset: request.asset, trailingSlash: request.trailingSlash)
            return (asset, directory, context.access.publicRead)
        }
        // A keresés és a böngészős renderelés lassú lehet, ezért a záron kívül fut.
        if let (directory, publicRead) = preview {
            return (WebScreenshot.find(in: directory, size: live ? size : nil), false, publicRead)
        }
        return found
    }

    /// .web előnézet állapota: fut-e a háttérben renderelés, és a kész kép változata (a kliens ezzel tölti újra).
    package func webPreviewState(_ request: WebPresentationRequest, user: User?, unlocks: Set<String>) throws -> (pending: Bool, version: String)? {
        let directory: URL? = try lock.withLock {
            guard let context = try webContext(project: request.project, reference: request.reference, user: user, unlocks: unlocks) else { return nil }
            try context.access.authorize(user, unlocks: unlocks)
            return context.directory
        }
        return directory.map { (WebScreenshot.isPending($0), WebScreenshot.version($0)) }
    }

    package func unlockWeb(_ requests: [WebPresentationRequest], password: String, user: User?, unlocks: Set<String>) throws -> (WebPresentationRequest, [String]) {
        let (request, required) = try lock.withLock { () throws -> (WebPresentationRequest, Set<String>) in
            for request in requests {
                guard let context = try webContext(project: request.project, reference: request.reference, user: user, unlocks: unlocks) else { continue }
                guard context.access.readable else { throw Abort(.forbidden) }
                return (request, Set(context.access.hashes).subtracting(unlocks))
            }
            throw Abort(.notFound)
        }
        // A bcrypt a záron kívül fut.
        let matches = try required.filter { try Bcrypt.verify(password, created: $0) }
        guard !matches.isEmpty else { throw Abort(.forbidden) }
        return (request, Array(matches))
    }

    package func webPresentations(in path: WorksheetPath, user: User?, unlocks: Set<String>) throws -> [WebPresentationInfo] {
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
                        let unlocked = access.access.readable && access.access.hashes.allSatisfy(unlocks.contains)
                        let publicWeb = access.policy.guestReadable == true
                        presentations.append(WebPresentationInfo(reference: reference.relativePath, title: String(reference.name.prefix(120)), url: url,
                            preview: unlocked ? url + "_tn-preview" : nil, manageable: access.manageable,
                            publicWeb: publicWeb))
                    } else if relative.count < 11, (try? WorksheetPath([project] + relative)) != nil {
                        try visit(entry, folders: relative)
                    }
                }
            }
            try visit(ctx.project, folders: [])
            return presentations.sorted { $0.reference.localizedStandardCompare($1.reference) == .orderedAscending }
        }
    }

    /// Publikus jog ki/be (a .web mappa .settings.json-jában); csak a projekt adminja és szerkesztői állíthatják.
    package func setWebPresentation(_ settings: WebPresentationSettings, in path: WorksheetPath, user: User, unlocks: Set<String>) throws {
        try lock.withLock {
            let reference = try WebPresentationReference(settings.reference)
            guard let context = try webContext(project: path.parts[0], reference: reference, user: user, unlocks: unlocks),
                  context.manageable else { throw Abort(.forbidden) }
            var policy = DocumentPolicy()
            policy.guestReadable = settings.publicWeb ? true : nil
            try write(policy, to: settingsURL(context.directory))
        }
    }

    /// A .web mappa a projekt lomtárába kerül (a dobozát törölték a lapról).
    package func trashWeb(_ reference: String, in path: WorksheetPath, user: User?, unlocks: Set<String>) throws {
        try lock.withLock {
            let ctx = try context(path)
            let web = try WebPresentationReference(reference)
            guard let context = try webContext(project: path.parts[0], reference: web, user: user, unlocks: unlocks),
                  context.manageable else { throw Abort(.forbidden) }
            let destination = try trashDestination(context.directory, in: ctx)
            try files.moveItem(at: context.directory, to: destination)
            let parent = context.directory.deletingLastPathComponent()
            for name in (try? files.contentsOfDirectory(atPath: parent.path)) ?? []
                where name.hasPrefix("." + context.directory.lastPathComponent + WebScreenshot.marker) {
                try? files.removeItem(at: parent.appendingPathComponent(name))
            }
        }
    }

}
