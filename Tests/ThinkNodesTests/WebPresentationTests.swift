import Foundation
import Testing
import VaporTesting
@testable import ThinkNodes

@Test func webPresentationsUseScopedAccessAndSafeFiles() async throws {
    let directory = FileManager.default
    let root = directory.temporaryDirectory.appendingPathComponent("thinknodes-web-\(UUID())")
    defer { try? directory.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let password = "presentation-password"
    let hash = try Bcrypt.hash(password, cost: 4)
    try store.setUser(name: "owner", role: .admin, passwordHash: hash)
    try store.setUser(name: "outsider", role: .editor, passwordHash: hash)
    let owner = try #require(try store.user(named: "owner"))
    let project = try WorksheetPath(["demoproject"])
    var board = try store.open(project, user: owner)
    _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "mode", value: "public"), user: owner, unlocks: [])
    let ordinary = try WorksheetPath(["demoproject", "web", "ordinary"])
    _ = try store.open(ordinary, user: owner)
    let prezi = root.appendingPathComponent("demoproject/prezi.web")
    let other = root.appendingPathComponent("demoproject/masik.web")
    let nested = root.appendingPathComponent("demoproject/anyagok/nested.web")
    for folder in [prezi, other, nested] { try directory.createDirectory(at: folder, withIntermediateDirectories: true) }
    func write(_ text: String, _ place: URL, _ filename: String) throws {
        try Data(text.utf8).write(to: place.appendingPathComponent(filename))
    }
    try directory.createDirectory(at: prezi.appendingPathComponent("css"), withIntermediateDirectories: false)
    try directory.createDirectory(at: prezi.appendingPathComponent("slides"), withIntermediateDirectories: false)
    try write("<!doctype html><title>Public prezi</title><link rel=\"stylesheet\" href=\"css/main.css\">", prezi, "index.html")
    try write("body{color:red}", prezi, "css/main.css")
    try write("<title>Nested slide</title>", prezi, "slides/index.html")
    try write("0123456789", prezi, "clip.webm")
    try write("hidden", prezi, ".private")
    try write(#"{"guestReadable":true}"#, prezi, ".settings.json")
    try write(#"{"guestReadable":false}"#, nested.deletingLastPathComponent(), ".settings.json")
    try write(#"{"guestReadable":true}"#, nested, ".settings.json")
    try write("nested-private", nested, "index.html")
    try write("private-presentation", other, "index.html")
    try write("window.protectedResource = true;", other, "app.js")
    try write(#"{"passwordHash":"\#(hash)"}"#, other, ".settings.json")
    try write("outside-secret", root, "outside.txt")
    try directory.createSymbolicLink(at: prezi.appendingPathComponent("symlink.txt"), withDestinationURL: root.appendingPathComponent("outside.txt"))
    try directory.createSymbolicLink(at: prezi.appendingPathComponent("symlink-dir"), withDestinationURL: root)
    try directory.createSymbolicLink(at: root.appendingPathComponent("demoproject/link.web"), withDestinationURL: prezi)

    board.nodes = [Idea(id: "webbox", title: "Bemutató", file: CanvasFile(type: .web, webPath: "anyagok/nested.web"),
                        position: Point(x: 0, y: 0))]
    _ = try store.update(project, worksheet: board, user: owner)

    try await withApp(configure: { app in configure(app, store: store) }) { app in
        let browser = try app.testing()
        let base = "/demoproject/web/prezi/"
        let index = try await browser.sendRequest(.GET, base + "index.html")
        #expect(index.status == .ok && index.body.string.contains("Public prezi"))
        #expect(index.headers.first(name: .cacheControl) == "no-store")
        #expect(index.headers.first(name: "X-Content-Type-Options") == "nosniff")
        let csp = try #require(index.headers.first(name: "Content-Security-Policy"))
        #expect(csp.contains("sandbox allow-scripts") && !csp.contains("allow-same-origin"))
        let directoryIndex = try await browser.sendRequest(.GET, String(base.dropLast()))
        #expect(directoryIndex.headers.first(name: .location) == base)
        let slide = try await browser.sendRequest(.GET, base + "slides/")
        #expect(slide.status == .ok && slide.body.string.contains("Nested slide"))
        let css = try await browser.sendRequest(.GET, base + "css/main.css")
        #expect(css.status == .ok && css.body.string == "body{color:red}")
        #expect(css.headers.first(name: .contentType)?.hasPrefix("text/css") == true)
        let clip = try await browser.sendRequest(.GET, base + "clip.webm", headers: ["Range": "bytes=2-5"])
        #expect(clip.status == .partialContent && clip.body.string == "2345")
        #expect(clip.headers.first(name: .contentType) == "video/webm")
        for file in [".settings.json", ".private", "%2E%2E/outside.txt", "css%2fmain.css", "css%5Cmain.css",
                     "css%00main.css", "css//main.css", "missing", "css/", "symlink.txt", "symlink-dir/outside.txt"] {
            let response = try await browser.sendRequest(.GET, base + file)
            #expect(response.status == .notFound || response.status == .forbidden)
            #expect(!response.body.string.contains("outside-secret"))
        }
        let linkedFolder = try await browser.sendRequest(.GET, "/demoproject/web/link/index.html")
        #expect(linkedFolder.status == .notFound || linkedFolder.status == .forbidden)
        #expect(try await browser.sendRequest(.GET, "/demoproject/web/ordinary").status == .ok)
        let privateNested = try await browser.sendRequest(.GET, "/demoproject/anyagok/web/nested/")
        #expect(privateNested.status == .seeOther && !privateNested.body.string.contains("nested-private"))

        let protectedURL = "/demoproject/web/masik/"
        let locked = try await browser.sendRequest(.GET, protectedURL + "app.js")
        #expect(locked.status == .locked && locked.body.string.contains("Prezentáció feloldása"))
        #expect(!locked.body.string.contains("protectedResource"))
        let cookie = try #require(locked.headers.first(name: .setCookie)).split(separator: ";")[0]
        let csrf = try #require(locked.body.string.components(separatedBy: #"name="csrf" value=""#).last).split(separator: "\"")[0]
        let unlock = try await browser.sendRequest(.POST, "/api/web-unlock", headers: ["Cookie": String(cookie)]) { request in
            try request.content.encode(["csrf": String(csrf), "target": protectedURL + "app.js", "password": password], as: .urlEncodedForm)
        }
        #expect(unlock.status == .seeOther && unlock.headers.first(name: .location) == protectedURL + "app.js")
        let opened = try await browser.sendRequest(.GET, protectedURL, headers: ["Cookie": String(cookie)])
        #expect(opened.body.string.contains("private-presentation"))
        let basePart = try #require(opened.body.string.components(separatedBy: #"<base href=""#).dropFirst().first)
        let assetURL = String(basePart.split(separator: "\"")[0]) + "app.js"
        let webCookie = try #require(opened.headers[.setCookie].first(where: { $0.hasPrefix("thinknodes_web_asset=") }))
        #expect(webCookie.lowercased().contains("httponly") && webCookie.lowercased().contains("secure") && webCookie.contains("SameSite=None"))
        #expect(try await browser.sendRequest(.GET, assetURL).status == .notFound)
        let resource = try await browser.sendRequest(.GET, assetURL, headers: ["Cookie": String(webCookie.split(separator: ";")[0])])
        #expect(resource.status == .ok && resource.body.string.contains("protectedResource"))
        let page = try await browser.sendRequest(.GET, "/demoproject")
        #expect(page.body.string.contains(#"href="/demoproject/anyagok/web/nested/" data-web-presentation="true" target="_blank""#))
        _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "mode", value: "internal"), user: owner, unlocks: [])
        let newlyPrivate = try await browser.sendRequest(.GET, base + "css/main.css")
        #expect(newlyPrivate.status == .seeOther && !newlyPrivate.body.string.contains("color:red"))
        let revokedResource = try await browser.sendRequest(.GET, assetURL, headers: ["Cookie": String(webCookie.split(separator: ";")[0])])
        #expect(revokedResource.status == .unauthorized)

    }
}
