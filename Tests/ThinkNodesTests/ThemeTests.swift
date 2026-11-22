import Foundation
import Testing
import VaporTesting
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
    #expect(glass.contains(##"fill="#282534" stroke="url(#glass-rim)" stroke-width="3" fill-opacity=".66""##))
    #expect(glass.contains("data-wire-taper"))
    var withoutArrows = vectorStudio
    withoutArrows.edges[0].startArrow = false
    withoutArrows.edges[0].endArrow = false
    #expect(boardSVG(withoutArrows, mode: "dark").contains("M 0.000 80.000 Q 60.000 56.000 120.000 80.000"))
    #expect(glass.contains("M 0.000 100.000 C 60.000 100.000 60.000 140.000 120.000 140.000"))
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
