import Foundation
import Vapor

// Color references travel as integers. Old documents may still contain literal colors.
@propertyWrapper struct StoredPaint: Codable, Equatable, Sendable {
    var wrappedValue: String
    init(wrappedValue: String) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let field = try decoder.singleValueContainer()
        if let id = try? field.decode(Int.self), (0..<64).contains(id) { wrappedValue = "@\(id)" }
        else { wrappedValue = try field.decode(String.self) }
    }
    func encode(to encoder: Encoder) throws {
        var field = encoder.singleValueContainer()
        if let id = paintID(wrappedValue) { try field.encode(id) }
        else { try field.encode(wrappedValue) }
    }
}

func paintID(_ value: String) -> Int? {
    guard value.first == "@", let id = Int(value.dropFirst()), (0..<64).contains(id) else { return nil }
    return id
}

@propertyWrapper struct OptionalPaint: Codable, Equatable, Sendable {
    var wrappedValue: String?
    init(wrappedValue: String?) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws { wrappedValue = try StoredPaint(from: decoder).wrappedValue }
    func encode(to encoder: Encoder) throws {
        if let wrappedValue { try StoredPaint(wrappedValue: wrappedValue).encode(to: encoder) }
        else { var field = encoder.singleValueContainer(); try field.encodeNil() }
    }
}
extension KeyedDecodingContainer {
    func decode(_ type: OptionalPaint.Type, forKey key: Key) throws -> OptionalPaint {
        try decodeIfPresent(type, forKey: key) ?? OptionalPaint(wrappedValue: nil)
    }
}
extension KeyedEncodingContainer {
    mutating func encode(_ paint: OptionalPaint, forKey key: Key) throws {
        if let value = paint.wrappedValue { try encode(StoredPaint(wrappedValue: value), forKey: key) }
    }
}

struct Appearance: Codable, Equatable, Sendable {
    var theme = 1
    var palette = 1
}
struct VisualTheme: Content, Equatable {
    struct Color: Codable, Equatable, Sendable { var id: Int; var name: String; var light: String?; var dark: String? }
    struct Palette: Codable, Equatable, Sendable { var id: Int; var name: String; var colors: [Color] }
    struct Graphics: Codable, Equatable, Sendable {
        var glow: Double?
        var selection: Int?
        // Clockwise convex contour in units of half the box dimensions.
        var contour: [Point]?
        var linePoints: [Point]?
        var box: Shape?
        var boxChamfer: Double?
        var validGeometry: Bool {
            if let linePoints, linePoints.isEmpty || linePoints.count > 12 ||
                !linePoints.allSatisfy({ (0...1).contains($0.x) && (-1...1).contains($0.y) }) { return false }
            guard let contour else { return true }
            guard [.diamond,.triangle,.pentagon,.hexagon,.parallelogram].contains(box),
                  (3...32).contains(contour.count),
                  contour.allSatisfy({ abs($0.x) <= 1 && abs($0.y) <= 1 }) else { return false }
            for i in contour.indices {
                let a = contour[i], b = contour[(i+1) % contour.count]
                guard a.x*b.y-a.y*b.x > 0.0001 else { return false }
                for p in contour where (b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x) < -0.0001 { return false }
            }
            return true
        }
        var line: ConnectionType?
        var lineArc: Double?
        var roundedWires: Bool?
        var junction: Shape?
        var grid: String?
        var glass: Bool?
        var junctionSize: Double?
        var motionSpeed: Double?
    }
    var version: Int
    var id: Int
    var name: String
    var modes: [String]
    var palettes: [Palette]
    var graphics: Graphics?
    var valid: Bool {
        (graphics?.validGeometry ?? true) && (0...24).contains(graphics?.boxChamfer ?? 0)
        && version == 1 && !name.isEmpty && !modes.isEmpty && Set(modes).isSubset(of: ["light","dark"])
        && Set(modes).count == modes.count && !palettes.isEmpty && Set(palettes.map(\.id)).count == palettes.count
        && palettes.allSatisfy { palette in
            let ids = Set(palette.colors.map(\.id))
            return (16...64).contains(palette.colors.count) && ids.count == palette.colors.count
                && Set(0..<16).isSubset(of: ids) && ids.isSubset(of: Set(0..<64))
                && palette.colors.allSatisfy { color in
                    let variants = [color.light, color.dark].compactMap { $0 }
                    return !color.name.isEmpty && !variants.isEmpty && variants.allSatisfy { $0.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }
                }
        } && (0...24).contains(graphics?.glow ?? 3)
        && (0..<8).contains(graphics?.selection ?? 4) && (4...128).contains(graphics?.junctionSize ?? 12)
        && ["dots","lines","drafting"].contains(graphics?.grid ?? "dots")
        && (0...0.25).contains(graphics?.lineArc ?? 0)
        && [.rectangle, .ellipse, .diamond].contains(graphics?.junction ?? .ellipse)
        && (0.1...5).contains(graphics?.motionSpeed ?? 1)
    }
}

enum Themes {
    // Theme files are reloaded on startup; previews from a previous catalog must be redrawn.
    static let loadedAt = Date()
    static let catalog: [VisualTheme] = {
        let dir = URL(fileURLWithPath: DirectoryConfiguration.detect().publicDirectory).appendingPathComponent("themes")
        var result = [VisualTheme]()
        for url in ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) where url.pathExtension == "json" {
            do {
                let theme = try JSONDecoder().decode(VisualTheme.self, from: Data(contentsOf: url))
                guard theme.valid, !result.contains(where: { $0.id == theme.id }) else { throw Abort(.unprocessableEntity) }
                result.append(theme)
            } catch { print("ThinkNodes: invalid theme \(url.lastPathComponent): \(error)") }
        }
        return result.sorted { $0.id < $1.id }
    }()
}

extension VisualTheme {
    fileprivate func paintResolver(paletteID: Int, mode: String?) -> ((String?, Int) -> String)? {
        guard let palette = palettes.first(where: { $0.id == paletteID }) else { return nil }
        let dark = (mode.flatMap { modes.contains($0) ? $0 : nil } ?? modes[0]) == "dark"
        let colors = Dictionary(uniqueKeysWithValues: palette.colors.map { ($0.id, $0) })
        return { value, role in
            if let value, value.hasPrefix("#") { return value }
            let color = value.flatMap(paintID).flatMap { colors[$0] } ?? colors[role]!
            return (dark ? color.dark ?? color.light : color.light ?? color.dark)!
        }
    }
}

extension Worksheet {
    func resolvedBackground(mode: String?) -> String {
        let appearance = self.appearance ?? Appearance()
        return Themes.catalog.first(where: { $0.id == appearance.theme })?
            .paintResolver(paletteID: appearance.palette, mode: mode)?(background, 0) ?? backgroundColor
    }

    func painted(mode: String?, catalog: [VisualTheme] = Themes.catalog) -> Worksheet {
        let appearance = self.appearance ?? Appearance()
        guard let theme = catalog.first(where: { $0.id == appearance.theme }),
              let resolve = theme.paintResolver(paletteID: appearance.palette, mode: mode) else { return self }
        var sheet = self
        sheet.background = resolve(background, 0)
        for i in sheet.nodes.indices {
            let node = nodes[i]
            if node.isJunction { sheet.nodes[i].shape = theme.graphics?.junction ?? .ellipse }
            else if node.shape == .rounded { sheet.nodes[i].shape = theme.graphics?.box ?? .rounded }
            sheet.nodes[i].fill = resolve(node.fill, 2)
            sheet.nodes[i].textColor = resolve(node.textColor, 1)
            if let color = node.file?.alphaBackground { sheet.nodes[i].file?.alphaBackground = resolve(color, 2) }
        }
        for i in sheet.edges.indices {
            sheet.edges[i].color = resolve(edges[i].color, 3)
            if edges[i].type == .straight { sheet.edges[i].type = theme.graphics?.line ?? .straight }
        }
        return sheet
    }
}
