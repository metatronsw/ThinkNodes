import Foundation
import Testing
import VaporTesting
@testable import ThinkCore
@testable import ThinkNodes

@Test func themeProjectRoundTrip() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let creator = User(name: "creator", role: .editor, passwordHash: "")
    let other = User(name: "other", role: .admin, passwordHash: "")
    let path = try WorksheetPath(["ThemeDemo"])
    var sheet = try store.open(path, user: creator)
    sheet.background = "@0"
    sheet.nodes = [Idea(id: "box", text: "Vázlat", position: Point(x: 0, y: 0), fill: "@2", textColor: "@1")]
    sheet.appearance = Appearance(theme: 3, palette: 1)
    sheet.gridSpacing = 24
    sheet.edges = [Connection(id: "wire", sourcePoint: Point(x: 0, y: 80),
                              target: ConnectionTarget(point: Point(x: 120, y: 80)))]
    let saved = try store.update(path, worksheet: sheet, user: other)
    #expect(saved.creator == creator.name)
    let reopened = try store.load(path, user: creator)
    #expect(reopened == saved)
    let data = try Data(contentsOf: root.appendingPathComponent("ThemeDemo/ThemeDemo.thnode"))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["background"] as? Int == 0)
    #expect((json["nodes"] as? [[String: Any]])?.first?["fill"] as? Int == 2)
    let dark = boardSVG(reopened, mode: "dark")
    let light = boardSVG(reopened, mode: "light")
    #expect(dark.contains("#14273a") && light.contains("#f2f7fa"))
    #expect(dark.contains(#"points="-83.000,-40.000 83.000,-40.000 88.000,-35.000 "#))
    #expect(dark.contains(##"<pattern id="draft-grid" x="-12.000" y="-12.000" width="120.000" height="120.000""##))
    #expect(dark.contains(##"M0 36.000 H120.000 M36.000 0 V120.000"##))
    #expect(dark.contains(##"M0 108.000 H120.000 M108.000 0 V120.000" stroke="#789bb0" stroke-opacity=".08""##))
    #expect(dark.contains(##"M0 12.000 H120.000 M12.000 0 V120.000" stroke="#789bb0" stroke-opacity=".22""##))
    #expect(reopened.painted(mode: "dark").edges[0].type == .straight)
    #expect(!dark.contains("fill=\"@"))
    var vectorStudio = reopened
    vectorStudio.appearance = Appearance(theme: 2, palette: 1)
    vectorStudio.edges.append(Connection(id: "curved", sourcePoint: Point(x: 0, y: 100),
                                         target: ConnectionTarget(point: Point(x: 120, y: 140)), type: .sCurve))
    let glass = boardSVG(vectorStudio, mode: "dark")
    #expect(glass.contains(##"fill="url(#glass-sheen)" pointer-events="none""##))
    #expect(glass.contains(##"fill="#282534" stroke="url(#glass-rim)" stroke-width="1.6" fill-opacity=".66""##))
    #expect(glass.contains("data-wire-taper"))
    var withoutArrows = vectorStudio
    withoutArrows.edges[0].startArrow = false
    withoutArrows.edges[0].endArrow = false
    #expect(boardSVG(withoutArrows, mode: "dark").contains("M 0.000 80.000 Q 60.000 56.000 120.000 80.000"))
    #expect(glass.contains("M 0.000 100.000 C 60.000 100.000 60.000 140.000 106.500 140.000"))
    #expect(!glass.contains("glass-ambient"))
    vectorStudio.edges = [
        Connection(id: "bolt", sourcePoint: Point(x: 0, y: 80),
                   target: ConnectionTarget(point: Point(x: 140, y: 80)), type: .zigzag),
        Connection(id: "zigzag", sourcePoint: Point(x: 0, y: 100),
                   target: ConnectionTarget(point: Point(x: 140, y: 100)), type: .lightning, label: "Zigzag"),
    ]
    let rounded = boardSVG(vectorStudio, mode: "dark")
    #expect(rounded.components(separatedBy: " Q ").count - 1 == 8)
    #expect(rounded.contains(">Zigzag</text>"))
    var otherEdit = reopened
    otherEdit.title = "Közös szerkesztés"
    _ = try store.update(path, worksheet: otherEdit, user: other)
}

@Test func themePaletteBoundaries() throws {
    var theme = try #require(Themes.catalog.first { $0.id == 1 })
    theme.modes = ["dark"]
    var colors = (0..<64).map { VisualTheme.Color(id: $0, name: "Tinta", light: "#123456", dark: nil) }
    theme.palettes[0].colors = colors
    #expect(theme.valid)
    var sheet = Worksheet(appearance: Appearance(theme: theme.id, palette: theme.palettes[0].id), title: "Paletta")
    sheet.background = "@63"
    #expect(sheet.painted(mode: "light", catalog: [theme]).background == "#123456")
    colors[0].light = nil
    colors[0].dark = "#456789"
    colors.removeLast(48)
    theme.palettes[0].colors = colors
    #expect(theme.valid)
    #expect(sheet.painted(mode: "light", catalog: [theme]).background == "#456789")
    #expect(sheet.background == "@63")
    theme.palettes[0].colors.removeLast()
    #expect(!theme.valid)
}

@Test func themeChangesPreserveLiteralColorsOnDisk() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let creator = User(name: "creator", role: .editor, passwordHash: "")
    let path = try WorksheetPath(["MixedPaint"])
    var sheet = try store.open(path, user: creator)
    sheet.background = "#213a57"
    sheet.nodes = [Idea(id: "box", text: "Vázlat", position: Point(x: 0, y: 0),
                        fill: "@2", textColor: "#aBcDeF")]
    sheet.edges = [Connection(id: "wire", sourcePoint: Point(x: 0, y: 80),
                              target: ConnectionTarget(point: Point(x: 120, y: 80)), color: "#9022AA")]
    sheet = try store.update(path, worksheet: sheet, user: creator)
    let originalFill = sheet.painted(mode: "light").nodes[0].fill
    sheet.appearance = Appearance(theme: 3, palette: 1)
    _ = try store.update(path, worksheet: sheet, user: creator)
    let reopened = try store.load(path, user: creator)
    let data = try Data(contentsOf: root.appendingPathComponent("MixedPaint/MixedPaint.thnode"))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let box = try #require((json["nodes"] as? [[String: Any]])?.first)
    #expect(json["background"] as? String == "#213a57")
    #expect(box["fill"] as? Int == 2)
    #expect(box["textCol"] as? String == "#aBcDeF")
    #expect((json["edges"] as? [[String: Any]])?.first?["color"] as? String == "#9022AA")
    #expect(reopened.painted(mode: "light").nodes[0].fill != originalFill)
    for mode in ["light", "dark"] {
        let display = reopened.painted(mode: mode)
        #expect(display.nodes[0].textColor == "#aBcDeF")
        #expect(display.edges[0].color == "#9022AA")
        #expect(reopened.resolvedBackground(mode: mode) == "#213a57")
    }
}

@Test func lineScaleByTypeAndAppearance() throws {
    let scale = try JSONDecoder().decode([String: LineScale].self,
        from: Data(#"{"straight": 2, "arc": {"plain": 0.5, "thick": 1.5}}"#.utf8))
    var wire = Connection(id: "wire", sourcePoint: Point(x: 0, y: 0), target: ConnectionTarget(point: Point(x: 100, y: 0)))
    #expect(wire.scaledWidth(scale) == 4)
    wire.type = .arc
    #expect(wire.scaledWidth(scale) == 1)
    wire.appearance = .thick
    #expect(wire.scaledWidth(scale) == 6)
    // Megjelenés, amelyhez a téma nem ad szorzót: 1.
    wire.appearance = .dashed
    #expect(wire.scaledWidth(scale) == 2)
    let allValid = scale.values.allSatisfy { $0.valid }
    #expect(allValid)
    #expect(!LineScale.byAppearance(["wavy": 1]).valid && !LineScale.uniform(0).valid)
}

@Test func liquidGlassTheme() throws {
    let theme = try #require(Themes.catalog.first { $0.name == "Liquid Glass" })
    let colorCounts = theme.palettes.map(\.colors.count)
    #expect(theme.valid && colorCounts == [21, 21, 21, 21, 21])
    var sheet = Worksheet(title: "Liquid")
    sheet.background = "@0"
    sheet.appearance = Appearance(theme: theme.id, palette: 2)
    sheet.nodes = [Idea(id: "box", text: "Üveg", position: Point(x: 0, y: 0), fill: "@2", textColor: "@1")]
    let svg = boardSVG(sheet, mode: "dark")
    #expect(svg.contains(#"data-effects="liquid""#) && svg.contains(#"stroke="url(#fx-rim)""#))
    #expect(svg.contains(#"class="fx-sheen" fill="url(#fx-sheen)""#) && svg.contains(#"class="fx-shadow""#))
    #expect(svg.contains(#"rx="22.000""#) && svg.contains("fx-aurora-2"))
    // Más témában a látványcsomag egyetlen eleme sem jelenik meg.
    sheet.appearance = Appearance(theme: 1, palette: 1)
    #expect(!boardSVG(sheet, mode: "dark").contains("fx-"))
}

@Test func themedBoxFrame() throws {
    let theme = try #require(Themes.catalog.first { $0.name == "NeonGlow" })
    #expect(theme.valid && theme.graphics?.frame?.width == 4)
    var sheet = Worksheet(title: "Neon")
    sheet.background = "@0"
    sheet.appearance = Appearance(theme: theme.id, palette: 1)
    sheet.nodes = [Idea(id: "box", text: "Neon", position: Point(x: 0, y: 0), fill: "@4", textColor: "@1")]
    let svg = boardSVG(sheet, mode: "dark")
    // A keret a doboz saját színe, a téma vastagságával; alatta háromszoros vastagságú fényudvar.
    #expect(svg.contains(##"fill="#fe0ca9" stroke="#fe0ca9" stroke-width="4.000" fill-opacity="0.140""##))
    #expect(svg.contains(##"class="node-halo" fill="none" stroke="#fe0ca9" stroke-width="12.000" stroke-opacity="0.280""##))
    let bad = VisualTheme.Graphics.Frame(width: 40, color: "fill", fillOpacity: nil, halo: nil)
    #expect(!bad.valid)
    // Keret nélküli témában a doboz változatlan.
    sheet.appearance = Appearance(theme: 1, palette: 1)
    let plain = boardSVG(sheet, mode: "dark")
    #expect(plain.contains(#"stroke-width="1.6""#) && !plain.contains("node-halo"))
}

/// Szabadkézi rajz: a szerver (Sketch.swift) ugyanazt rajzolja, mint a szerkesztő (Public/sketch.js). Közös esetek:
/// Tests/Fixtures/sketch.json (kliensoldali párja: Tests/Editor/sketch.mjs). A két oldal trigonometriája egy-egy
/// utolsó jegyben eltérhet, ezért a számok 0,11-es tűréssel egyeznek.
@Test func sketchMatchesSharedFixtures() throws {
    struct Case: Decodable {
        var id: String; var shape: String; var width: Double; var height: Double; var roughness: Double; var passes: Int
        var vertices: [[Double]]?; var fill: [Token]; var strokes: [[Token]]; var shift: [Double]
    }
    enum Token: Decodable {
        case command(String), number(Double)
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Double.self) { self = .number(number) } else { self = .command(try value.decode(String.self)) }
        }
    }
    struct Fixture: Decodable { var seed: UInt32; var sticky: String; var cases: [Case] }
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/sketch.json")
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    #expect(sketchSeed("box-a") == fixture.seed && stickyColor("#f0bd23") == fixture.sticky)
    func tokens(_ d: String) -> [Token] {
        var result: [Token] = [], number = ""
        func flush() { if !number.isEmpty { result.append(.number(Double(number)!)); number = "" } }
        for character in d {
            if character.isLetter { flush(); result.append(.command(String(character))) }
            else if character == " " { flush() }
            else if character == "-" { flush(); number = "-" }
            else { number.append(character) }
        }
        flush()
        return result
    }
    func same(_ a: [Token], _ b: [Token]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { pair in
            switch pair {
            case let (.command(x), .command(y)): x == y
            case let (.number(x), .number(y)): abs(x - y) <= 0.11
            default: false
            }
        }
    }
    for item in fixture.cases {
        let shape = try #require(Shape(rawValue: item.shape))
        let outline = sketchOutline(shape, width: item.width, height: item.height, vertices: item.vertices?.map { ($0[0], $0[1]) })
        let drawn = SketchPen.paths(seed: sketchSeed(item.id), outline: outline, rough: item.roughness, passes: item.passes)
        #expect(same(tokens(drawn.fill), item.fill), "kitöltés: \(item.id)")
        #expect(drawn.strokes.count == item.strokes.count && zip(drawn.strokes, item.strokes).allSatisfy { same(tokens($0), $1) }, "körvonal: \(item.id)")
        let shift = sketchShift(sketchSeed(item.id), rough: item.roughness)
        #expect(abs(shift.0 - item.shift[0]) <= 0.11 && abs(shift.1 - item.shift[1]) <= 0.11, "eltolás: \(item.id)")
    }
}

@Test func whiteBoardTheme() throws {
    let theme = try #require(Themes.catalog.first { $0.name == "WhiteBoard" })
    #expect(theme.valid && theme.graphics?.sketch != nil && theme.graphics?.paper?.grid == "sticky")
    var sheet = Worksheet(title: "Tábla")
    sheet.background = "@0"
    sheet.appearance = Appearance(theme: theme.id, palette: 1)
    sheet.nodes = [Idea(id: "box", text: "Filc", position: Point(x: 0, y: 0), fill: "@4", textColor: "@1")]
    for mode in ["light", "dark"] {
        let svg = boardSVG(sheet, mode: mode)
        // A kattintható felület a szabályos alak (láthatatlan), fölötte a szabadkézi kitöltés és egyetlen folytonos vonal.
        #expect(svg.contains(#"class="node-surface""#) && svg.contains(#"fill-opacity="0" stroke="none""#))
        #expect(svg.contains("sketch-fill") && svg.components(separatedBy: "class=\"sketch-stroke\"").count - 1 == 1)
        #expect(svg.contains("sketch-smudges") && !svg.contains("stroke-dasharray"))
    }
    // Más témában semmi szabadkézi elem nincs.
    sheet.appearance = Appearance(theme: 1, palette: 1)
    let plain = boardSVG(sheet, mode: "light")
    #expect(!plain.contains("sketch-") && !plain.contains("paper-"))
}
