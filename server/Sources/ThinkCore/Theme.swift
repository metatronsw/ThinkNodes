import Foundation
import Vapor

// Color references travel as integers. Old documents may still contain literal colors.
@propertyWrapper package struct StoredPaint: Codable, Equatable, Sendable {
    package var wrappedValue: String
    package init(wrappedValue: String) { self.wrappedValue = wrappedValue }
    package init(from decoder: Decoder) throws {
        let field = try decoder.singleValueContainer()
        if let id = try? field.decode(Int.self), (0..<64).contains(id) { wrappedValue = "@\(id)" }
        else { wrappedValue = try field.decode(String.self) }
    }
    package func encode(to encoder: Encoder) throws {
        var field = encoder.singleValueContainer()
        if let id = paintID(wrappedValue) { try field.encode(id) }
        else { try field.encode(wrappedValue) }
    }
}

func paintID(_ value: String) -> Int? {
    guard value.first == "@", let id = Int(value.dropFirst()), (0..<64).contains(id) else { return nil }
    return id
}

@propertyWrapper package struct OptionalPaint: Codable, Equatable, Sendable {
    package var wrappedValue: String?
    package init(wrappedValue: String?) { self.wrappedValue = wrappedValue }
    package init(from decoder: Decoder) throws { wrappedValue = try StoredPaint(from: decoder).wrappedValue }
    package func encode(to encoder: Encoder) throws {
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
    package mutating func encode(_ paint: OptionalPaint, forKey key: Key) throws {
        if let value = paint.wrappedValue { try encode(StoredPaint(wrappedValue: value), forKey: key) }
    }
}

package struct Appearance: Codable, Equatable, Sendable {
    package var theme = 1
    var palette = 1
}
package struct VisualTheme: Content, Equatable {
    package struct Color: Codable, Equatable, Sendable { var id: Int; var name: String; var light: String?; var dark: String? }
    package struct Palette: Codable, Equatable, Sendable {
        var id: Int; var name: String; var colors: [Color]
        /// Van-e a palettának esti színe; ha nincs, sötét módban is a nappali színek látszanak.
        var hasDark: Bool { colors.contains { $0.dark != nil } }
    }
    package struct Graphics: Codable, Equatable, Sendable {
        var glow: Double?
        package var selection: Int?
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
        /// Vonalvastagság-szorzók vonaltípusonként (straight, sCurve, zigzag, lightning, arc, rope) és megjelenésenként
        /// (plain, thick, dashed, dotted). Egy típus értéke egyetlen szám (minden megjelenésre) vagy megjelenésenkénti
        /// szorzók. A vonal vastagsága = a méret alapvastagsága × a szorzó (vastag megjelenésnél ennek kétszerese).
        var lineScale: [String: LineScale]?
        /// A lekerekített doboz sarkának sugara vászonegységben (alap: 12).
        var boxRadius: Double?
        /// A doboz kerete a témából (nélküle: 1,6 vastag, a kitöltésből számolt színnel). `width`: vastagság; `color`:
        /// "fill" = a doboz saját színe, kitöltött dobozon is; `fillOpacity`: a kitöltött felület átlátszatlansága
        /// (áttetsző módban a fele); `halo`: a keret körüli fényudvar átlátszatlansága (háromszoros vastagságú körvonal).
        package struct Frame: Codable, Equatable, Sendable {
            var width: Double?
            var color: String?
            var fillOpacity: Double?
            var halo: Double?
            var valid: Bool {
                (0.5...16.0).contains(width ?? 1.6) && ["auto", "fill"].contains(color ?? "auto")
                    && (0.0...1.0).contains(fillOpacity ?? 1) && (0.0...1.0).contains(halo ?? 0)
            }
        }
        var frame: Frame?
        /// Szabadkézi rajz (sketch.js, Rendering.swift SketchPen): `roughness` a remegés mértéke vászonegységben (0–5,
        /// alap 1,2), `passes` a körvonal húzásainak száma (1–3, alap 2). Sötét módban ugyanígy rajzol, csak a színek mások.
        package struct Sketch: Codable, Equatable, Sendable {
            var roughness: Double?
            var passes: Int?
            var valid: Bool { (0.0...5.0).contains(roughness ?? 1.2) && (1...3).contains(passes ?? 2) }
        }
        var sketch: Sketch?
        /// Papírfelületek: `grid` (táblázat, CSV) "sticky" = cetli, `text` (szöveg- és kódfájl) "notebook" = füzetlap;
        /// `sheet` a füzetlap, `ink` a papíron álló szöveg, `rule` a sorvonalak, `margin` a margóvonal színe.
        package struct Paper: Codable, Equatable, Sendable {
            var grid: String?
            var text: String?
            var sheet: String?
            var ink: String?
            var rule: String?
            var margin: String?
            var valid: Bool {
                ["sticky", "plain"].contains(grid ?? "plain") && ["notebook", "plain"].contains(text ?? "plain")
                    && [sheet, ink, rule, margin].allSatisfy { color in
                        color.map { $0.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil } ?? true
                    }
            }
        }
        var paper: Paper?
        /// Látványcsomag (jelenleg: "liquid"): gazdagabb dobozfelület, háttérfények, rámutatás-, kattintás- és
        /// kijelöléseffektek. A csomag stílusai az app.css `[data-effects]` szabályaiban vannak; téma nélküle nem fizet értük.
        var effects: String?
        var motionSpeed: Double?
        /// Három betűtípus (CSS font-family): alap, valamint két jól eltérő választható.
        var fonts: [String]?
    }
    package var version: Int
    package var id: Int
    package var name: String
    /// A támogatott módok. Elhagyható: ilyenkor "light", és ha bármelyik színnek van esti változata, "dark" is.
    var modes: [String]
    var palettes: [Palette]
    package var graphics: Graphics?

    private enum CodingKeys: String, CodingKey { case version, id, name, modes, palettes, graphics }
    package init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        version = try fields.decode(Int.self, forKey: .version)
        id = try fields.decode(Int.self, forKey: .id)
        name = try fields.decode(String.self, forKey: .name)
        palettes = try fields.decode([Palette].self, forKey: .palettes)
        graphics = try fields.decodeIfPresent(Graphics.self, forKey: .graphics)
        let hasDark = palettes.contains { $0.colors.contains { $0.dark != nil } }
        modes = try fields.decodeIfPresent([String].self, forKey: .modes) ?? (hasDark ? ["light", "dark"] : ["light"])
    }
    // Lépésenkénti guard: az egyetlen hosszú `&&`-lánc típusellenőrzése ~2 s fordítási időt vitt el.
    var valid: Bool {
        guard version == 1, !name.isEmpty, !modes.isEmpty, !palettes.isEmpty else { return false }
        let modeSet = Set<String>(modes)
        guard modeSet.count == modes.count, modeSet.isSubset(of: ["light", "dark"]) else { return false }
        let paletteIDs = Set<Int>(palettes.map(\.id))
        guard paletteIDs.count == palettes.count, palettes.allSatisfy(Self.validPalette) else { return false }
        guard let graphics else { return true }
        return Self.validGraphics(graphics)
    }

    private static func validPalette(_ palette: Palette) -> Bool {
        let ids = Set<Int>(palette.colors.map(\.id))
        guard (16...64).contains(palette.colors.count), ids.count == palette.colors.count else { return false }
        guard Set<Int>(0..<16).isSubset(of: ids), ids.isSubset(of: Set<Int>(0..<64)) else { return false }
        return palette.colors.allSatisfy(validColor)
    }

    private static func validColor(_ color: Color) -> Bool {
        let variants: [String] = [color.light, color.dark].compactMap { $0 }
        guard !color.name.isEmpty, !variants.isEmpty else { return false }
        return variants.allSatisfy { (value: String) -> Bool in
            value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
        }
    }

    private static func validGraphics(_ graphics: Graphics) -> Bool {
        guard graphics.validGeometry else { return false }
        let boxChamfer: Double = graphics.boxChamfer ?? 0
        let glow: Double = graphics.glow ?? 3
        let selection: Int = graphics.selection ?? 4
        let junctionSize: Double = graphics.junctionSize ?? 12
        let lineArc: Double = graphics.lineArc ?? 0
        let motionSpeed: Double = graphics.motionSpeed ?? 1
        guard (0.0...24.0).contains(boxChamfer), (0.0...24.0).contains(glow), (0..<8).contains(selection),
              (4.0...128.0).contains(junctionSize), (0.0...0.25).contains(lineArc), (0.1...5.0).contains(motionSpeed)
        else { return false }
        for (name, scale) in graphics.lineScale ?? [:] {
            guard ConnectionType(rawValue: name) != nil, scale.valid else { return false }
        }
        guard graphics.frame?.valid ?? true, graphics.sketch?.valid ?? true, graphics.paper?.valid ?? true else { return false }
        guard (0.0...40.0).contains(graphics.boxRadius ?? 12), ["liquid"].contains(graphics.effects ?? "liquid") else { return false }
        let grids: [String] = ["dots", "lines", "drafting"]
        guard grids.contains(graphics.grid ?? "dots") else { return false }
        let junctions: [Shape] = [.rectangle, .ellipse, .diamond]
        guard junctions.contains(graphics.junction ?? .ellipse) else { return false }
        guard let fonts = graphics.fonts else { return true }
        return fonts.count == 3 && fonts.allSatisfy(validFont)
    }

    private static func validFont(_ font: String) -> Bool {
        let forbidden: Set<Character> = ["<", ">", "\"", ";", "{", "}"]
        return !font.isEmpty && font.count <= 200 && !font.contains(where: forbidden.contains)
    }
}

/// Egy vonaltípus vastagságszorzója: egyetlen szám, vagy megjelenésenként (plain, thick, dashed, dotted) külön szám.
package enum LineScale: Codable, Equatable, Sendable {
    case uniform(Double)
    case byAppearance([String: Double])
    package init(from decoder: Decoder) throws {
        let field = try decoder.singleValueContainer()
        if let factor = try? field.decode(Double.self) { self = .uniform(factor) }
        else { self = .byAppearance(try field.decode([String: Double].self)) }
    }
    package func encode(to encoder: Encoder) throws {
        var field = encoder.singleValueContainer()
        switch self {
        case .uniform(let factor): try field.encode(factor)
        case .byAppearance(let factors): try field.encode(factors)
        }
    }
    func factor(_ appearance: ConnectionAppearance) -> Double {
        switch self {
        case .uniform(let factor): factor
        case .byAppearance(let factors): factors[appearance.rawValue] ?? 1
        }
    }
    var valid: Bool {
        switch self {
        case .uniform(let factor): (0.1...10.0).contains(factor)
        case .byAppearance(let factors):
            factors.allSatisfy { ConnectionAppearance(rawValue: $0.key) != nil && (0.1...10.0).contains($0.value) }
        }
    }
}

extension VisualTheme.Graphics {
    static let defaultFonts = ["system-ui, sans-serif", "Georgia, 'Times New Roman', serif", "'Chalkboard SE', 'Comic Sans MS', cursive"]
    /// A doboz betűtípusa a téma három betűtípusa közül (1-től számozva).
    func fontFamily(_ index: Int?) -> String {
        let list = fonts ?? Self.defaultFonts
        return list[min(max((index ?? 1) - 1, 0), list.count - 1)]
    }
}

package enum Themes {
    // Theme files are reloaded on startup; previews from a previous catalog must be redrawn.
    static let loadedAt = Date()
    package static let catalog: [VisualTheme] = {
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
        // Esti színek nélküli paletta sötét módban is a nappali színeket adja (editor.js mode).
        let dark = (mode.flatMap { modes.contains($0) ? $0 : nil } ?? modes[0]) == "dark" && palette.hasDark
        let colors = Dictionary(uniqueKeysWithValues: palette.colors.map { ($0.id, $0) })
        return { value, role in
            if let value, value.hasPrefix("#") { return value }
            let color = value.flatMap(paintID).flatMap { colors[$0] } ?? colors[role]!
            return (dark ? color.dark ?? color.light : color.light ?? color.dark)!
        }
    }
}

extension Worksheet {
    /// Törölt (a katalógusban nem szereplő) téma helyett az alaptéma: a ThinkDefault (1), ennek híján a katalógus első
    /// témája, annak első palettája; meglévő témánál a hiányzó paletta helyett a téma első palettája. A színek
    /// paletta-ID-k, így az új palettán a megfelelő szerepszínt kapják. Téma nélküli (régi) munkalap változatlan marad.
    package mutating func repairAppearance(catalog: [VisualTheme] = Themes.catalog) {
        guard let current = appearance, !catalog.isEmpty else { return }
        if let theme = catalog.first(where: { $0.id == current.theme }) {
            if !theme.palettes.contains(where: { $0.id == current.palette }), let first = theme.palettes.first { appearance?.palette = first.id }
            return
        }
        let fallback = catalog.first { $0.id == 1 } ?? catalog[0]
        appearance = Appearance(theme: fallback.id, palette: fallback.palettes.first?.id ?? 1)
    }

    package func resolvedBackground(mode: String?) -> String {
        let appearance = self.appearance ?? Appearance()
        return Themes.catalog.first(where: { $0.id == appearance.theme })?
            .paintResolver(paletteID: appearance.palette, mode: mode)?(background, 0) ?? backgroundColor
    }

    package func painted(mode: String?, catalog: [VisualTheme] = Themes.catalog) -> Worksheet {
        let appearance = self.appearance ?? Appearance()
        guard let theme = catalog.first(where: { $0.id == appearance.theme }),
              let resolve = theme.paintResolver(paletteID: appearance.palette, mode: mode) else { return self }
        var sheet = self
        sheet.background = resolve(background, 0)
        // A téma tintájának két változata: ezek közül kap a doboz szövege, ha a beállított szín nem olvasható (labelInk).
        let inks = ["light", "dark"].compactMap { theme.paintResolver(paletteID: appearance.palette, mode: $0)?("@1", 1) }
        for i in sheet.nodes.indices {
            let node = nodes[i]
            if node.isJunction { sheet.nodes[i].shape = theme.graphics?.junction ?? .ellipse }
            else if node.shape == .rounded { sheet.nodes[i].shape = theme.graphics?.box ?? .rounded }
            sheet.nodes[i].fill = resolve(node.fill, 2)
            // A paletta 0. színe kitöltésként: vászonszínű felület (a munkalap háttere, rács nélkül; editor.js canvasSurface).
            if node.fill == "@0", !node.isJunction, [.solid, .translucent].contains(node.resolvedBackgroundMode) { sheet.nodes[i].backgroundMode = .canvas }
            sheet.nodes[i].textColor = resolve(node.textColor, 1)
            if let color = node.file?.alphaBackground { sheet.nodes[i].file?.alphaBackground = resolve(color, 2) }
            // Papírfelület: a cetli színe a doboz színe fehérrel keverve (alapszínnél a paletta sárgája, 6); a papíron
            // a szöveg a téma tintája, hacsak a doboz szövegszínét külön nem állították be (editor.js paperColor, paperInk).
            // A papír mindkét módban világos: a paletta színeinek nappali változata számít.
            if let kind = paperKind(node, theme.graphics), let day = theme.paintResolver(paletteID: appearance.palette, mode: "light") {
                if kind == "sticky" { sheet.nodes[i].fill = stickyColor(node.fill == "@2" ? day("@6", 6) : day(node.fill, 2)) }
                sheet.nodes[i].paperInk = node.textColor == "@1" ? theme.graphics?.paper?.ink ?? "#25314d" : day(node.textColor, 1)
            }
            sheet.nodes[i].labelInk = labelInk(sheet.nodes[i], background: sheet.background ?? resolve(nil, 0), graphics: theme.graphics, candidates: inks)
        }
        for i in sheet.edges.indices {
            sheet.edges[i].color = resolve(edges[i].color, 3)
            if edges[i].type == .straight { sheet.edges[i].type = theme.graphics?.line ?? .straight }
        }
        return sheet
    }
}
