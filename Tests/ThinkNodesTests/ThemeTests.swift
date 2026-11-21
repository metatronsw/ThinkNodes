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
    sheet.nodes = [Idea(id: "box", title: "Vázlat", position: Point(x: 0, y: 0), fill: "@2", textColor: "@1")]
    sheet.appearance = Appearance(theme: 3, palette: 1)
    #expect(throws: Abort.self) { try store.update(path, worksheet: sheet, user: other) }
    let saved = try store.update(path, worksheet: sheet, user: creator)
    #expect(saved.creator == creator.name)
    let reopened = try store.load(path, user: creator)
    #expect(reopened == saved)
    let data = try Data(contentsOf: root.appendingPathComponent("ThemeDemo/ThemeDemo.thnode"))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["background"] as? Int == 0)
    #expect((json["nodes"] as? [[String: Any]])?.first?["fill"] as? Int == 2)
    let dark = boardSVG(reopened, mode: "dark")
    let light = boardSVG(reopened, mode: "light")
    #expect(dark.contains("#111a27") && light.contains("#f1fafd"))
    #expect(dark.contains("draft-grid") && !dark.contains("fill=\"@"))
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
