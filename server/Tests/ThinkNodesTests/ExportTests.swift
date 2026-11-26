import Foundation
import Testing
import VaporTesting
@testable import ThinkCore
@testable import ThinkNodes

/// A letöltött SVG önálló: a kép, a fájldoboz letöltése és az ikonok a fájlba ágyazva, a szerverre mutató cím nem marad
/// (Server.swift selfContainedSVG). A beágyazás a letöltő munkamenetével történik.
@Test func svgExportIsSelfContained() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-export-\(UUID().uuidString)")
    let store = try WorksheetStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let password = UUID().uuidString
    try store.setUser(name: "admin", role: .admin, passwordHash: try Bcrypt.hash(password, cost: 4))
    let admin = try #require(try store.user(named: "admin"))
    let project = try WorksheetPath(["exportpro"])
    var sheet = try store.open(project, user: admin)
    // 1×1-es PNG.
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="))
    let image = try store.storeMedia(png, type: "image/png", filename: "kep.png", at: project, user: admin, unlocks: [])
    let note = try store.storeAttachment(Data("# Jegyzet".utf8), named: "jegyzet.md", at: project, user: admin, unlocks: [])
    sheet.nodes = [
        Idea(id: "kep", type: "image", file: CanvasFile(asset: image, filename: "kep"), position: Point(x: 0, y: 0)),
        Idea(id: "jegyzet", type: "text", file: CanvasFile(asset: note, filename: "jegyzet.md"), position: Point(x: 400, y: 0), width: 340, height: 240),
    ]
    _ = try store.update(project, worksheet: sheet, user: admin)

    try await withApp(configure: { app in configure(app, store: store, secureCookies: false) }) { app in
        let browser = try app.testing()
        let session = try await login(browser, name: "admin", password: password, path: project.url)
        let response = try await browser.sendRequest(.GET, "/export/svg/" + project.url, headers: ["Cookie": session.cookie])
        #expect(response.status == .ok)
        let svg = response.body.string
        #expect(!svg.contains(#"src="/"#) && !svg.contains(#"href="/"#))
        #expect(svg.contains("src=\"data:image/png;base64," + png.base64EncodedString() + "\""))
        #expect(svg.contains(#"download="jegyzet.md""#) && svg.contains(#"<symbol id="package""#) && svg.contains(##"href="#package""##))
    }
}
