import Foundation
import Testing
import VaporTesting
@testable import ThinkCore
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
    try write("export-screenshot", prezi, "screen.png")
    try write("hidden", prezi, ".private")
    try write(#"{"guestReadable":true}"#, prezi, ".settings.json")
    try write(#"{"guestReadable":false}"#, nested.deletingLastPathComponent(), ".settings.json")
    try write(#"{"guestReadable":true}"#, nested, ".settings.json")
    try write("nested-private", nested, "index.html")
    try write("private-presentation", other, "index.html")
    let exported = root.appendingPathComponent("demoproject/export.web")
    try directory.createDirectory(at: exported, withIntermediateDirectories: true)
    try write("<title>Stitch export</title>", exported, "code.html")
    try write("window.protectedResource = true;", other, "app.js")
    try write(#"{"passwordHash":"\#(hash)"}"#, other, ".settings.json")
    try write("outside-secret", root, "outside.txt")
    try directory.createSymbolicLink(at: prezi.appendingPathComponent("symlink.txt"), withDestinationURL: root.appendingPathComponent("outside.txt"))
    try directory.createSymbolicLink(at: prezi.appendingPathComponent("symlink-dir"), withDestinationURL: root)
    try directory.createSymbolicLink(at: root.appendingPathComponent("demoproject/link.web"), withDestinationURL: prezi)

    board.nodes = [Idea(id: "webbox", text: "Bemutató", position: Point(x: 0, y: 0),
                        link: NodeLink(kind: .web, target: "anyagok/nested.web"))]
    _ = try store.update(project, worksheet: board, user: owner)

    try await withApp(configure: { app in configure(app, store: store, secureCookies: true) }) { app in
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
        #expect(csp.contains("https:") && csp.contains("'unsafe-eval'"))
        let hosted = try await browser.sendRequest(.GET, base, headers: ["Host": "192.168.1.20:8080"])
        #expect(hosted.headers.first(name: "Content-Security-Policy")?.contains("img-src 'self' http://192.168.1.20:8080 ") == true)
        #expect(csp.contains("script-src") && csp.contains("frame-ancestors 'none'"))
        let export = try await browser.sendRequest(.GET, "/demoproject/web/export/")
        #expect(export.status == .ok && export.body.string.contains("Stitch export"))
        let fallback = try await browser.sendRequest(.GET, "/demoproject/web/export/_tn-preview")
        #expect(fallback.status == .ok && fallback.headers.first(name: .contentType) == "image/svg+xml")
        let slide = try await browser.sendRequest(.GET, base + "slides/")
        #expect(slide.status == .ok && slide.body.string.contains("Nested slide"))
        let preview = try await browser.sendRequest(.GET, base + "_tn-preview")
        #expect(preview.status == .ok && preview.body.string == "export-screenshot")
        #expect(preview.headers.first(name: .contentType) == "image/png")
        try write("preferred-screenshot", prezi, "preview.png")
        #expect(try await browser.sendRequest(.GET, base + "_tn-preview").body.string == "preferred-screenshot")
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
        // Egyszerűsített jogok: a mappák és a .web oldalak saját korlátozásai (szerkesztők, jelszó) nem számítanak;
        // a publikusnak jelölt .web bárkinek elérhető.
        let publicNested = try await browser.sendRequest(.GET, "/demoproject/anyagok/web/nested/")
        #expect(publicNested.status == .ok && publicNested.body.string.contains("nested-private"))

        let projectURL = "/demoproject/web/masik/"
        let opened = try await browser.sendRequest(.GET, projectURL + "app.js")
        #expect(opened.status == .ok && opened.body.string.contains("protectedResource"))
        let page = try await browser.sendRequest(.GET, "/demoproject")
        #expect(page.body.string.contains(#"href="/demoproject/anyagok/web/nested/" data-web-presentation="true" target="_blank""#))
        _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "mode", value: "internal"), user: owner, unlocks: [])
        // Zárt projektben a publikusnak jelölt .web kívülről is elérhető marad, a többi nem.
        let stillPublic = try await browser.sendRequest(.GET, base + "css/main.css")
        #expect(stillPublic.status == .ok && stillPublic.body.string.contains("color:red"))
        let newlyPrivate = try await browser.sendRequest(.GET, projectURL + "app.js")
        #expect(newlyPrivate.status == .seeOther && !newlyPrivate.body.string.contains("protectedResource"))

    }
}

@Test func protectedPresentationAssetsLoadOverPlainHTTP() async throws {
    let directory = FileManager.default
    let root = directory.temporaryDirectory.appendingPathComponent("thinknodes-web-http-\(UUID())")
    defer { try? directory.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let hash = try Bcrypt.hash("owner-password", cost: 4)
    try store.setUser(name: "owner", role: .admin, passwordHash: hash)
    let owner = try #require(try store.user(named: "owner"))
    let project = try WorksheetPath(["lan"])
    _ = try store.open(project, user: owner)
    let prezi = root.appendingPathComponent("lan/prezi.web")
    try directory.createDirectory(at: prezi, withIntermediateDirectories: true)
    try Data("<!doctype html><img src=\"pic.png\">".utf8).write(to: prezi.appendingPathComponent("index.html"))
    try Data("png-bytes".utf8).write(to: prezi.appendingPathComponent("pic.png"))

    try await withApp(configure: { app in configure(app, store: store, secureCookies: false) }) { app in
        let browser = try app.testing()
        let login = try await browser.sendRequest(.GET, "/login")
        let cookie = try #require(login.headers.first(name: .setCookie)).split(separator: ";")[0]
        let csrf = try #require(login.body.string.components(separatedBy: #"name="csrf" value=""#).last).split(separator: "\"")[0]
        let signIn = try await browser.sendRequest(.POST, "/login", headers: ["Cookie": String(cookie)]) { request in
            try request.content.encode(["csrf": String(csrf), "name": "owner", "password": "owner-password", "next": "/"], as: .urlEncodedForm)
        }
        let session = (signIn.headers.first(name: .setCookie)?.split(separator: ";")[0]).map(String.init) ?? String(cookie)
        let page = try await browser.sendRequest(.GET, "/lan/web/prezi/", headers: ["Cookie": session])
        #expect(page.status == .ok)
        #expect(!page.headers[.setCookie].contains { $0.hasPrefix("thinknodes_web_asset=") })
        let basePart = try #require(page.body.string.components(separatedBy: #"<base href=""#).dropFirst().first)
        let assetURL = String(basePart.split(separator: "\"")[0]) + "pic.png"
        // A sandboxed page sends no cookies on plain HTTP; the session-bound lease alone must work.
        let image = try await browser.sendRequest(.GET, assetURL)
        #expect(image.status == .ok && image.body.string == "png-bytes")
        #expect(try await browser.sendRequest(.GET, "/lan/web/prezi/pic.png").status != .ok)
    }
}

/// `../` hivatkozás a .web oldalból: a projektmappán belül feloldódik, fölötte nem; a projekt saját joga érvényes.
@Test func presentationParentReferencesStayInsideProject() async throws {
    let directory = FileManager.default
    let root = directory.temporaryDirectory.appendingPathComponent("thinknodes-web-parent-\(UUID())")
    defer { try? directory.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let hash = try Bcrypt.hash("owner-password", cost: 4)
    try store.setUser(name: "owner", role: .admin, passwordHash: hash)
    let owner = try #require(try store.user(named: "owner"))
    let project = try WorksheetPath(["proj"])
    _ = try store.open(project, user: owner)
    let projectDir = root.appendingPathComponent("proj")
    let prezi = projectDir.appendingPathComponent("anyag/prezi.web")
    try directory.createDirectory(at: prezi.appendingPathComponent("sub"), withIntermediateDirectories: true)
    try directory.createDirectory(at: projectDir.appendingPathComponent("kepek"), withIntermediateDirectories: true)
    func write(_ text: String, _ path: String) throws { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
    try write("<!doctype html><img src=\"../../kepek/logo.png\">", "proj/anyag/prezi.web/index.html")
    try write("<title>Sub</title>", "proj/anyag/prezi.web/sub/index.html")
    try write("own-pic", "proj/anyag/prezi.web/pic.png")
    try write("sibling-pic", "proj/anyag/sibling.png")
    try write("top-pic", "proj/top.png")
    try write("logo-pic", "proj/kepek/logo.png")
    try write("<script>steal()</script>", "proj/page.html")
    try write("hidden", "proj/kepek/.secret.png")
    try write("outside-secret", "outside.txt")
    try directory.createSymbolicLink(at: projectDir.appendingPathComponent("kepek/link.png"), withDestinationURL: root.appendingPathComponent("outside.txt"))

    /// A böngésző feloldása: relatív cím a `<base>`-hez képest.
    func resolve(_ reference: String, against base: String) throws -> String {
        let url = try #require(URL(string: reference, relativeTo: URL(string: "http://host" + base)))
        return String(url.absoluteString.dropFirst("http://host".count))
    }
    func baseHref(_ body: String) throws -> String {
        let part = try #require(body.components(separatedBy: #"<base href=""#).dropFirst().first)
        return String(part.split(separator: "\"")[0])
    }

    try await withApp(configure: { app in configure(app, store: store, secureCookies: false) }) { app in
        let browser = try app.testing()
        let login = try await browser.sendRequest(.GET, "/login")
        let cookie = try #require(login.headers.first(name: .setCookie)).split(separator: ";")[0]
        let csrf = try #require(login.body.string.components(separatedBy: #"name="csrf" value=""#).last).split(separator: "\"")[0]
        let signIn = try await browser.sendRequest(.POST, "/login", headers: ["Cookie": String(cookie)]) { request in
            try request.content.encode(["csrf": String(csrf), "name": "owner", "password": "owner-password", "next": "/"], as: .urlEncodedForm)
        }
        let session = (signIn.headers.first(name: .setCookie)?.split(separator: ";")[0]).map(String.init) ?? String(cookie)
        let page = try await browser.sendRequest(.GET, "/proj/anyag/web/prezi/", headers: ["Cookie": session])
        #expect(page.status == .ok)
        let base = try baseHref(page.body.string)
        #expect(base.hasSuffix("/anyag/prezi.web/"))
        // A homokozó cookie nélkül kér: a bérletes cím önmagában elég.
        for (reference, body) in [("pic.png", "own-pic"), ("../sibling.png", "sibling-pic"), ("../../top.png", "top-pic"),
                                  ("../../kepek/logo.png", "logo-pic"), ("../prezi.web/pic.png", "own-pic")] {
            let response = try await browser.sendRequest(.GET, try resolve(reference, against: base))
            #expect(response.status == .ok && response.body.string == body, "\(reference)")
        }
        for reference in ["../../../outside.txt", "../../../../outside.txt", "../../../../../x", "../../proj.thnode",
                          "../../.settings.json", "../../kepek/.secret.png", "../../kepek/link.png", "../../page.html",
                          "../../kepek/", "../../kepek", "../../%2E%2E/outside.txt"] {
            let response = try await browser.sendRequest(.GET, try resolve(reference, against: base))
            #expect(response.status != .ok, "\(reference)")
            #expect(!response.body.string.contains("outside-secret") && !response.body.string.contains("steal"))
        }
        // Almappa oldala: a base az almappát tükrözi.
        let sub = try await browser.sendRequest(.GET, "/proj/anyag/web/prezi/sub/", headers: ["Cookie": session])
        let subBase = try baseHref(sub.body.string)
        #expect(subBase.hasSuffix("/anyag/prezi.web/sub/"))
        #expect(try await browser.sendRequest(.GET, try resolve("../../../top.png", against: subBase)).body.string == "top-pic")
        // Bérletes HTML-cím visszairányít a természetes címre.
        let mirroredPage = try await browser.sendRequest(.GET, try resolve("sub/index.html", against: base))
        #expect(mirroredPage.status == .seeOther || mirroredPage.status == .found || mirroredPage.status == .temporaryRedirect)

        // Zárt projekt: publikus jelölővel, bejelentkezés nélkül a projekt fájljai nem érhetők el.
        #expect(try await browser.sendRequest(.GET, "/proj/anyag/web/prezi/_tn-assets/public/top.png").status != .ok)
        #expect(try await browser.sendRequest(.GET, "/proj/anyag/web/prezi/_tn-assets/public/anyag/prezi.web/pic.png").status != .ok)

        // Publikus .web zárt projektben: a saját fájljai igen, a projekt többi fájlja nem.
        try write(#"{"guestReadable":true}"#, "proj/anyag/prezi.web/.settings.json")
        let publicWeb = try await browser.sendRequest(.GET, "/proj/anyag/web/prezi/")
        let publicBase = try baseHref(publicWeb.body.string)
        #expect(publicBase.contains("/_tn-assets/public/"))
        #expect(try await browser.sendRequest(.GET, try resolve("pic.png", against: publicBase)).body.string == "own-pic")
        #expect(try await browser.sendRequest(.GET, try resolve("../../top.png", against: publicBase)).status != .ok)

        // Publikus projekt: bárki számára feloldódik a `../`.
        _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "mode", value: "public"), user: owner, unlocks: [])
        #expect(try await browser.sendRequest(.GET, try resolve("../../top.png", against: publicBase)).body.string == "top-pic")
        #expect(try await browser.sendRequest(.GET, try resolve("../../../outside.txt", against: publicBase)).status != .ok)
    }
}
