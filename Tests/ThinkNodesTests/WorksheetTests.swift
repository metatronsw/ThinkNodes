import Foundation
import Testing
import VaporTesting
@testable import ThinkNodes

@Test func worksheetRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-\(UUID().uuidString)")
    let store = try WorksheetStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let route = try WorksheetPath(["gondolatok", "mégnincsilyen"])
    let path = route.url
    let file = root.appendingPathComponent("gondolatok/mégnincsilyen/mégnincsilyen.thnode")
    let password = UUID().uuidString
    let hash = try Bcrypt.hash(password, cost: 4)
    try store.setUser(name: "admin", role: .admin, passwordHash: hash)
    try store.setUser(name: "editor", role: .editor, passwordHash: hash)
    try store.setUser(name: "shared", role: .editor, passwordHash: hash)
    try store.setUser(name: "outsider", role: .editor, passwordHash: hash)

    try await withApp(configure: { app in configure(app, store: store) }) { app in
        let browser = try app.testing()
        let beforeOpen = try await browser.sendRequest(.GET, "/api/worksheet/\(path)")
        #expect(beforeOpen.status == .notFound)
        let guestOpen = try await browser.sendRequest(.GET, "/\(path)")
        #expect(guestOpen.status == .seeOther)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let creator = try #require(try store.user(named: "editor"))
        let project = try WorksheetPath(["gondolatok"])
        _ = try store.open(project, user: creator)
        for (action, value) in [("mode", "public"), ("grant", "shared")] {
            _ = try store.manage(project, operation: DocumentAction(scope: "project", action: action, value: value), user: creator, unlocks: [])
        }
        _ = try store.open(route, user: creator, directory: true)
        let editor = try await login(browser, name: "editor", password: password, path: path)
        let newParent = try await browser.sendRequest(.GET, "/gondolatok", headers: ["Cookie": editor.cookie])
        #expect(newParent.status == .ok)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok/gondolatok.thnode").path))
        let index = try await browser.sendRequest(.GET, "/")
        #expect(index.body.string.contains("project-card panel layers-1"))
        #expect(index.body.string.contains("class=\"button small\" href=\"/utmutato.html\""))
        let guide = try await browser.sendRequest(.GET, "/utmutato.html")
        #expect(guide.status == .ok && guide.body.string.contains("Példák a vásznon"))
        #expect(guide.body.string.contains("<kbd>Ctrl</kbd>") && guide.body.string.contains("/site-mode.js"))
        let openedAgain = try await browser.sendRequest(.GET, "/\(path)", headers: ["Cookie": editor.cookie])
        #expect(openedAgain.status == .ok)
        let guestPrivate = try await browser.sendRequest(.GET, "/export/svg/\(path)")
        #expect(guestPrivate.status == .ok)

        let owner = try #require(try store.user(named: "editor"))
        var worksheet = try store.load(route, user: owner)
        #expect(worksheet.title == "mégnincsilyen")
        #expect(worksheet.revision == 1)
        worksheet.background = "@0"
        worksheet.text = "**A munkalap bevezetője**"
        worksheet.nodes = [
            Idea(id: "elso", title: "Első <ötlet>", text: "## Próba\n\n**Szöveg**",
                 hideText: false, position: Point(x: -250, y: 0), height: 140),
            Idea(id: "masodik", title: "Második ötlet", position: Point(x: 250, y: 0), shape: .ellipse)
        ]
        worksheet.edges = [
            Connection(id: "kapcsolat", source: "elso", target: ConnectionTarget(node: "masodik"), startArrow: true),
            Connection(id: "szabad", source: "masodik", target: ConnectionTarget(point: Point(x: 810, y: 12)), appearance: .dashed),
            Connection(id: "szabad-kezdet", sourcePoint: Point(x: -410, y: -170),
                       target: ConnectionTarget(point: Point(x: -250, y: -70)), type: .rope,
                       color: "@4", width: 5, startArrow: true, endArrow: false, label: "Szabad vonal")
        ]
        let noLogin = try await browser.sendRequest(.PUT, "/api/worksheet/\(path)")
        #expect(noLogin.status == .unauthorized)
        let admin = try await login(browser, name: "admin", password: password, path: path)
        let saved = try await save(browser, path: path, worksheet: worksheet, session: editor)
        #expect(saved.status == .ok)
        #expect(saved.headers.first(name: .eTag) == "\"2\"")
        #expect(try store.load(route, user: nil).nodes.count == 2)
        let stale = try await save(browser, path: path, worksheet: worksheet, session: editor)
        #expect(stale.status == .preconditionFailed)

        let shared = try await login(browser, name: "shared", password: password, path: path)
        let outsider = try await login(browser, name: "outsider", password: password, path: path, canEdit: false)
        let childURL = "/api/subworksheet/" + path + "/terv"
        let headers: HTTPHeaders = ["Cookie": shared.cookie, "X-CSRF-Token": shared.csrf]
        let created = try await browser.sendRequest(.POST, childURL, headers: headers)
        #expect(created.status == .ok)
        let child = try created.content.decode(Worksheet.self)
        #expect(child.title == "terv" && child.nodes.isEmpty && child.edges.isEmpty)
        #expect(child.creator == "shared")
        #expect(child.background == worksheet.background)
        #expect(child.creator == "shared")
        let attachmentURL = "/api/attachment/" + path + "/terv?name="
        let source = #"{"title":"Táblázat","rows":[]}"#
        let attachmentHeaders: HTTPHeaders = [
            "Cookie": shared.cookie, "X-CSRF-Token": shared.csrf, "Content-Type": "application/octet-stream"
        ]
        func upload(_ name: String, headers: HTTPHeaders) async throws -> HTTPStatus {
            try await browser.sendRequest(.POST, attachmentURL + encodeQuery(name), headers: headers) { request in
                request.body = ByteBuffer(string: source)
            }.status
        }
        #expect(try await upload("adat.json", headers: [:]) == .unauthorized)
        #expect(try await upload("adat.json", headers: ["Cookie": shared.cookie]) == .forbidden)
        #expect(try await upload("../adat.json", headers: attachmentHeaders) == .badRequest)
        #expect(try await upload("hamis.png", headers: attachmentHeaders) == .unsupportedMediaType)
        #expect(try await upload("adat.json", headers: attachmentHeaders) == .created)
        #expect(try await upload("adat.json", headers: attachmentHeaders) == .conflict)
        let downloaded = try await browser.sendRequest(.GET, attachmentURL + "adat.json&inline=1")
        #expect(downloaded.status == .ok && downloaded.body.string == source)
        #expect(downloaded.headers.first(name: .contentDisposition)?.hasPrefix("attachment;") == true)
        #expect(try await browser.sendRequest(.GET, "/api/worksheet/" + path + "/terv/adat").status == .notFound)
        let flatDocument = file.deletingLastPathComponent().appendingPathComponent("adat.json")
        #expect(try String(contentsOf: flatDocument, encoding: .utf8) == source)
        #expect(!FileManager.default.fileExists(atPath: flatDocument.deletingLastPathComponent().appendingPathComponent(".attachments").path))
        #expect(try await browser.sendRequest(.POST, "/api/subworksheet/" + path + "/terv/adat", headers: headers).status == .conflict)
        let childView = try await browser.sendRequest(.GET, "/" + path + "/terv")
        #expect(childView.body.string.contains("adat.json"))
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII="))
        var mediaHeaders = headers
        mediaHeaders.replaceOrAdd(name: .contentType, value: "image/png")
        let media = try await browser.sendRequest(.POST, "/api/media/" + path + "/terv?filename=K%C3%A9p.png", headers: mediaHeaders) { request in
            request.body = ByteBuffer(bytes: png)
        }
        let mediaAsset = try #require(try media.content.decode([String: String].self)["asset"])
        let inline = try await browser.sendRequest(.GET, attachmentURL + encodeQuery(mediaAsset) + "&inline=1")
        #expect(inline.status == .ok && inline.headers.first(name: .contentType) == "image/png")
        #expect(try Data(contentsOf: flatDocument.deletingLastPathComponent().appendingPathComponent("Kép.png")) == png)
        let animation = """
            <?xml version="1.0"?>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10">
              <style>@keyframes fade { to { opacity: .2 } } rect { animation: fade 1s infinite }</style>
              <rect width="10" height="10">
                <animate attributeName="x" from="0" to="10" dur="1s" repeatCount="indefinite"/>
              </rect>
            </svg>
            """
        mediaHeaders.replaceOrAdd(name: .contentType, value: "image/svg+xml")
        let svgUpload = try await browser.sendRequest(.POST, "/api/media/" + path + "/terv?filename=Mozgas.SVG", headers: mediaHeaders) { request in
            request.body = ByteBuffer(string: animation)
        }
        #expect(svgUpload.status == .ok)
        let svgAsset = try #require(try svgUpload.content.decode([String: String].self)["asset"])
        #expect(svgAsset.hasSuffix(".svg"))
        let inlineSVG = try await browser.sendRequest(.GET, attachmentURL + encodeQuery(svgAsset) + "&inline=1")
        #expect(inlineSVG.body.string == animation)
        #expect(inlineSVG.headers.first(name: .contentType) == "image/svg+xml")
        #expect(inlineSVG.headers.first(name: .contentDisposition) == "inline")
        #expect(inlineSVG.headers.first(name: "Content-Security-Policy")?.hasPrefix("sandbox; default-src 'none'; style-src 'unsafe-inline'") == true)
        var withAnimation = child
        withAnimation.nodes = [Idea(id: "animation", title: "", file: CanvasFile(type: .image, asset: svgAsset), position: Point(x: 0, y: 0))]
        try withAnimation.validate()
        let animatedCanvas = boardSVG(withAnimation, noteBase: "/" + path + "/terv")
        #expect(animatedCanvas.contains("<img alt=") && animatedCanvas.contains("name=" + encodeQuery(svgAsset)))
        for invalid in ["<html/>", "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect></svg>"] {
            let rejected = try await browser.sendRequest(.POST, "/api/media/" + path + "/terv?filename=hibas.svg", headers: mediaHeaders) { request in
                request.body = ByteBuffer(string: invalid)
            }
            #expect(rejected.status == .unsupportedMediaType)
        }
        var withArchive = child
        withArchive.nodes = [Idea(id: "archive", title: "Anyag", file: CanvasFile(type: .attachment, asset: "Ötletek.zip"), position: Point(x: 0, y: 0))]
        try withArchive.validate()
        let archiveSVG = boardSVG(withArchive, assetBase: "/" + path + "/terv")
        #expect(archiveSVG.contains("?name=%C3%96tletek%2Ezip"))
        withArchive.nodes[0].file?.asset = "../Ötletek.zip"
        #expect(throws: Abort.self) { try withArchive.validate() }
        let preview = try await browser.sendRequest(.GET, "/api/preview/" + path + "/terv")
        #expect(preview.status == .ok && preview.body.string.contains("<svg"))
        #expect(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent(".terv.preview-v8.svg").path))
        try await checkPreviewAndPreferences(browser, path: path + "/terv", sheet: child, session: shared, png: png)
        let parent = try await browser.sendRequest(.GET, "/" + path)
        #expect(parent.body.string.contains("További oldalak:") && parent.body.string.contains("Létrehozó: shared"))
        #expect(try await browser.sendRequest(.POST, childURL, headers: headers).status == .conflict)
        for cookie in [editor.cookie, admin.cookie, shared.cookie] {
            let home = try await browser.sendRequest(.GET, "/", headers: ["Cookie": cookie])
            #expect(!home.body.string.contains("href=\"/" + path + "\""))
        }
        let outsidersView = try await browser.sendRequest(.GET, "/\(path)", headers: ["Cookie": outsider.cookie])
        #expect(outsidersView.status == .ok)
        #expect(!outsidersView.body.string.contains("aria-label=\"Szerkesztés\""))
        let tampered = try await save(browser, path: path, worksheet: worksheet, session: outsider)
        #expect(tampered.status == .forbidden)
        let accounts = try await browser.sendRequest(.GET, "/api/worksheet-users/\(path)", headers: ["Cookie": editor.cookie])
        #expect(accounts.status == .ok)
        #expect(try accounts.content.decode([String].self).contains("shared"))
        let blockedAccounts = try await browser.sendRequest(.GET, "/api/worksheet-users/\(path)", headers: ["Cookie": shared.cookie])
        #expect(blockedAccounts.status == .forbidden)

        let page = try await browser.sendRequest(.GET, "/\(path)?note=elso")
        #expect(page.status == .ok)
        #expect(page.body.string.contains("<svg"))
        #expect(page.body.string.contains("Első &lt;ötlet&gt;"))
        #expect(page.body.string.contains("<strong>Szöveg</strong>"))
        #expect(page.body.string.contains("<strong>A munkalap bevezetője</strong>"))
        #expect(page.body.string.contains("/viewer.js"))
        #expect(!page.body.string.contains("<h1>"))
        #expect(page.body.string.contains("/icons.svg#download"))
        #expect(!page.body.string.contains("worksheet-grid"))
        #expect(page.body.string.contains("passive-backdrop"))
        #expect(page.body.string.contains("viewer-downloads"))

        let svg = try await browser.sendRequest(.GET, "/export/svg/\(path)")
        #expect(svg.status == .ok)
        #expect(svg.headers.first(name: .contentDisposition)?.contains(".svg") == true)
        #expect(svg.body.string.contains("viewBox=\"-850.000 -240.000 1700.000 480.000\""))
        #expect(svg.body.string.contains("marker-start="))
        #expect(svg.body.string.contains("stroke-dasharray="))
        #expect(svg.body.string.contains("font-weight=\"700\">Szöveg</tspan>"))
        #expect(svg.body.string.contains("fill=\"#f9f9fb\""))
        #expect(svg.body.string.contains("stroke=\"#0090ff\" stroke-width=\"5.000\""))
        #expect(svg.body.string.contains("rotate(49.931)"))
        #expect(svg.body.string.contains(">Szabad vonal</text>"))
        #expect(!svg.body.string.contains("<a href="))

        let markdown = try await browser.sendRequest(.GET, "/export/text/\(path)")
        #expect(markdown.status == .ok)
        #expect(markdown.body.string.contains("**Szöveg**"))
        #expect(markdown.body.string.contains("**A munkalap bevezetője**"))
        #expect(markdown.body.string.contains("↔"))
        #expect(markdown.body.string.contains("· Egyenes"))
        #expect(markdown.body.string.contains("810.000, 12.000"))

        let canvasNotes = try await browser.sendRequest(.POST, "/api/text/canvas", headers: [
            "Cookie": editor.cookie, "X-CSRF-Token": editor.csrf
        ]) { request in
            try request.content.encode(["sources": ["## Próba\n\n**Szöveg**"]])
        }
        #expect(canvasNotes.status == .ok)
        let blocks = try canvasNotes.content.decode([String: [[MarkdownBlock]]].self)["blocks"]?.first
        #expect(blocks?.first?.kind == .heading)
        #expect(blocks?.last?.runs.first?.format.bold == true)

        let json = try await browser.sendRequest(.GET, "/export/json/\(path)")
        #expect(try json.content.decode(Worksheet.self).nodes.count == 2)
        #expect(json.body.string.contains("\"pos\""))
        #expect(!json.body.string.contains("\"position\""))
        #expect(!json.body.string.contains("\"boards\""))
        #expect(!json.body.string.contains("\"editors\""))
        #expect(!json.body.string.contains("\"owner\""))

        let unauthorizedAdmin = try await browser.sendRequest(.GET, "/admin", headers: ["Cookie": editor.cookie])
        #expect(unauthorizedAdmin.status == .forbidden)
        let adminPage = try await browser.sendRequest(.GET, "/admin", headers: ["Cookie": admin.cookie])
        #expect(adminPage.status == .ok)
        #expect(adminPage.body.string.contains("Felhasználók"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("admin.json").path))

        let newAccount = try await browser.sendRequest(.POST, "/admin/users", headers: ["Cookie": admin.cookie]) { request in
            try request.content.encode(["name": "uj", "role": "editor", "password": password, "csrf": admin.csrf], as: .urlEncodedForm)
        }
        #expect(newAccount.status == .seeOther)
        #expect(try store.user(named: "uj")?.role == .editor)
        let removedAccount = try await browser.sendRequest(.POST, "/admin/users/delete", headers: ["Cookie": admin.cookie]) { request in
            try request.content.encode(["name": "uj", "csrf": admin.csrf], as: .urlEncodedForm)
        }
        #expect(removedAccount.status == .seeOther)
        #expect(try store.user(named: "uj") == nil)

        let editorDelete = try await remove(browser, path: path, session: editor)
        #expect(editorDelete.status == .forbidden)
        let settings = try await browser.sendRequest(.POST, "/admin/settings", headers: ["Cookie": admin.cookie]) { request in
            try request.content.encode(["requireLogin": "on", "csrf": admin.csrf], as: .urlEncodedForm)
        }
        #expect(settings.status == .seeOther)
        let privateExport = try await browser.sendRequest(.GET, "/export/json/\(path)")
        #expect(privateExport.status == .unauthorized)
        let privatePage = try await browser.sendRequest(.GET, "/\(path)")
        #expect(privatePage.status == .seeOther)
        let blockedCreate = try await browser.sendRequest(.GET, "/gondolatok/masik")
        #expect(blockedCreate.status == .seeOther)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok/masik.thnode").path))
        let authenticatedCreate = try await browser.sendRequest(.GET, "/gondolatok/masik", headers: ["Cookie": editor.cookie])
        #expect(authenticatedCreate.status == .seeOther)
        #expect(authenticatedCreate.headers.first(name: .location) == "/edit/gondolatok/masik")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok/masik.thnode").path))

        let adminDelete = try await remove(browser, path: path, session: admin)
        #expect(adminDelete.status == .noContent)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let archived = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".trash").path)
        #expect(archived.count == 1)
    }
}

private func remove(_ browser: some TestingApplicationTester, path: String, session: (cookie: String, csrf: String)) async throws -> TestingHTTPResponse {
    try await browser.sendRequest(.DELETE, "/api/worksheet/\(path)", headers: [
        "Cookie": session.cookie, "If-Match": "\"2\"", "X-CSRF-Token": session.csrf
    ])
}

private struct Credentials: Content {
    var name: String
    var password: String
    var csrf: String
}

private func login(_ browser: some TestingApplicationTester, name: String, password: String, path: String, canEdit: Bool = true) async throws -> (cookie: String, csrf: String) {
    let loginPage = try await browser.sendRequest(.GET, "/login")
    let sessionCookie = try cookie(loginPage)
    let initialToken = try attribute("name=\"csrf\" value=\"", in: loginPage.body.string)
    let signedIn = try await browser.sendRequest(.POST, "/login", headers: ["Cookie": sessionCookie]) { request in
        try request.content.encode(Credentials(name: name, password: password, csrf: initialToken), as: .urlEncodedForm)
    }
    #expect(signedIn.status == .seeOther)
    let signedInCookie = try cookie(signedIn)
    #expect(sessionCookie != signedInCookie)
    let editor = try await browser.sendRequest(.GET, "/edit/\(path)", headers: ["Cookie": signedInCookie])
    if !canEdit {
        #expect(editor.status == .forbidden)
        let viewer = try await browser.sendRequest(.GET, "/" + path, headers: ["Cookie": signedInCookie])
        return (signedInCookie, try attribute("data-csrf=\"", in: viewer.body.string))
    }
    #expect(editor.status == .ok)
    #expect(editor.body.string.contains("worksheet-nav"))
    #expect(editor.body.string.contains("brand-icon"))
    let token = try attribute("data-csrf=\"", in: editor.body.string)
    return (signedInCookie, token)
}

private func checkPreviewAndPreferences(_ browser: some TestingApplicationTester, path: String, sheet: Worksheet,
                                        session: (cookie: String, csrf: String), png: Data) async throws {
    let headers: HTTPHeaders = ["Cookie": session.cookie, "X-CSRF-Token": session.csrf]
    let options = try await browser.sendRequest(.GET, "/api/preview-images/" + path, headers: headers)
    #expect(try options.content.decode([String].self).contains("Kép.png"))
    var selected = sheet
    selected.previewImage = "Kép.png"
    let saved = try await save(browser, path: path, worksheet: selected, session: session)
    #expect(saved.status == .ok)
    let image = try await browser.sendRequest(.GET, "/api/preview/" + path)
    #expect(image.headers.first(name: .contentType) == "image/png")
    #expect(Data(image.body.readableBytesView) == png)
    selected.revision += 1
    selected.previewImage = "hiányzó.svg"
    #expect(try await save(browser, path: path, worksheet: selected, session: session).status == .ok)
    #expect(try await browser.sendRequest(.GET, "/api/preview/" + path).body.string.contains("<svg"))
    let preferences = UserPreferences(snap: true, showGrid: false, panLocked: true, avatar: 12)
    let result = try await browser.sendRequest(.POST, "/api/preferences", headers: headers) { request in
        try request.content.encode(preferences)
    }
    #expect(result.status == .noContent)
    let page = try await browser.sendRequest(.GET, "/edit/" + path, headers: headers)
    #expect(!page.body.string.contains("&quot;avatar&quot;:12"))
}

private func save(_ browser: some TestingApplicationTester, path: String, worksheet: Worksheet,
                  session: (cookie: String, csrf: String)) async throws -> TestingHTTPResponse {
    try await browser.sendRequest(.PUT, "/api/worksheet/\(path)", headers: [
        "Cookie": session.cookie, "If-Match": "\"\(worksheet.revision)\"", "X-CSRF-Token": session.csrf
    ]) { request in
        try request.content.encode(worksheet)
    }
}

private func cookie(_ response: TestingHTTPResponse) throws -> String {
    let header = try #require(response.headers.first(name: .setCookie))
    return String(header.prefix { $0 != ";" })
}

private func attribute(_ prefix: String, in html: String) throws -> String {
    let range = try #require(html.range(of: prefix))
    return String(html[range.upperBound...].prefix { $0 != "\"" })
}

@Test func firstAdminCanBeCreatedFromLoopback() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-setup-\(UUID().uuidString)")
    let store = try WorksheetStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    try await withApp(configure: { app in configure(app, store: store) }) { app in
        _ = try app.testing()
        let form = try await setupRequest(app, .GET, "/admin")
        #expect(form.status == .ok)
        let html = try #require(try await form.body.collect(on: app.eventLoopGroup.next()).get()).string
        let csrf = try attribute("name=\"csrf\" value=\"", in: html)
        let cookie = try #require(form.headers.first(name: .setCookie)).prefix { $0 != ";" }
        let formBody = "name=localadmin&password=\(UUID().uuidString)&csrf=\(csrf)"
        let grant = try await setupRequest(app, .POST, "/admin/setup", headers: [
            "Host": "localhost:8080", "Cookie": String(cookie), "Content-Type": "application/x-www-form-urlencoded"
        ], body: ByteBuffer(string: formBody))
        #expect(grant.status == .seeOther)
        #expect(grant.headers.first(name: .location) == "/admin")
        #expect(try store.user(named: "localadmin")?.role == .admin)
        let unsafe = try await setupRequest(app, .POST, "/admin/setup", headers: ["Host": "another-host.example"])
        #expect(unsafe.status == .forbidden)
    }
}

private func setupRequest(_ app: Application, _ method: HTTPMethod, _ path: String,
                          headers: HTTPHeaders = ["Host": "localhost:8080"], body: ByteBuffer? = nil) async throws -> Response {
    let eventLoop = app.eventLoopGroup.next()
    let req = Request(application: app, method: method, url: .init(path: path), headers: headers,
                      collectedBody: body, remoteAddress: try .some(.init(ipAddress: "127.0.0.1", port: 12345)),
                      logger: app.logger, on: eventLoop)
    return try await app.responder.respond(to: req).get()
}

@Test func autoSizeSurvivesRoundTripAndFitsSVGText() throws {
    let idea = Idea(id: "fit", title: "Cím", text: "Törzs", position: Point(x: 0, y: 0),
                    width: 240, height: 100, shape: .rectangle, backgroundEnabled: false, fitText: true)
    let board = Worksheet(title: "AutoSize", nodes: [idea])
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(board))
    #expect(saved.nodes[0].fitText == true)
    #expect(saved.nodes[0].backgroundEnabled == false)
    #expect(saved.nodes[0].fontSize == 16)
    let svg = boardSVG(saved)
    #expect(svg.contains("rx=\"0\" fill=\"none\" stroke=\"none\" pointer-events=\"fill\""))
    #expect(svg.contains("font-size=\"33.600\" font-weight=\"650\">Cím</tspan>"))
    #expect(svg.contains("font-size=\"24.000\" font-weight=\"400\">Törzs</tspan>"))
}

@Test func svgShortensBoxLabelsWithoutClipping() throws {
    var node = Idea(id: "box", title: "Hosszú cím", text: "**Nagy szöveg**", position: Point(x: 0, y: 0),
                    width: 64, height: 40, shape: .ellipse, fontSize: 80, textStyle: TextStyle(size: 120))
    let bounded = boardSVG(Worksheet(title: "Doboz", nodes: [node]))
    #expect(!bounded.contains("<clipPath"))
    #expect(!bounded.contains("clip-path="))
    #expect(bounded.contains("…</tspan>"))
    node.backgroundEnabled = false
    let board = Worksheet(title: "Doboz", nodes: [node])
    try board.validate()
    let free = boardSVG(board)
    #expect(!free.contains("<clipPath"))
    #expect(!free.contains("textLength"))
    #expect(free.contains(">Hosszú cím</tspan>"))
    #expect(free.contains(">Nagy</tspan> <tspan font-weight=\"700\">szöveg</tspan>"))
}

@Test func containerStylesAndJunctionsSurviveRoundTrip() throws {
    let origin = Point(x: 0, y: 0)
    var container = Idea(id: "group", title: "Konténer", position: origin, link: "aloldal", kind: .container, locked: true)
    let child = Idea(id: "child", title: "Ötlet", text: "**törzs**", hideText: false,
                     position: origin, parent: "group", italic: true, underline: true,
                     textStyle: TextStyle(color: "#663300", size: 17, italic: true, alignment: .left))
    let junction = Idea(id: "joint", title: "Kapocs", position: Point(x: 200, y: 80), width: 34, height: 34,
                        shape: .ellipse, kind: .connectionPoint)
    let line = Connection(id: "line", source: child.id, target: ConnectionTarget(node: junction.id))
    let second = Connection(id: "other-line", source: junction.id, target: ConnectionTarget(point: origin), endArrow: false)
    var board = Worksheet(title: "Ábra", gridSpacing: 32,
                          nodes: [child, junction, container], edges: [line, second])
    try board.validate()
    var largeTitle = board
    largeTitle.nodes[0].fontSize = 10000
    largeTitle.nodes[0].textStyle?.size = 1
    try largeTitle.validate()
    var legacy = board
    var duplicate = line
    duplicate.id = "parallel"
    legacy.edges.append(duplicate)
    #expect(throws: Abort.self) { try legacy.validate() }
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(board))
    try saved.validate()
    #expect(saved.nodes.first?.parent == container.id)
    #expect(saved.nodes.first?.textStyle?.size == 17)
    #expect(saved.nodes.last?.locked == true)
    let svg = boardSVG(saved)
    #expect(!svg.contains("worksheet-grid"))
    #expect(!svg.contains("<pattern"))
    #expect(svg.contains("text-anchor=\"start\""))
    #expect(svg.contains("font-style=\"italic\" text-decoration=\"underline\""))
    #expect(svg.contains("r=\"17.000\" fill=\"#dce9ff\" aria-label=\"Kapocs\""))
    #expect(svg.contains(">Kapocs</text>"))
    #expect(svg.contains("stroke-width=\"6.4\" data-locked-outline=\"\""))
    #expect(svg.contains("font-size=\"16\" fill=\"#182335\">aloldal</text>"))
    board.nodes[1].title = ""
    try board.validate()
    let groupStart = try #require(svg.range(of: "aria-label=\"Konténer\" transform="))
    let edgeStart = try #require(svg.range(of: "marker-end=\"url(#arrow-line)"))
    let childStart = try #require(svg.range(of: "aria-label=\"Ötlet\" transform="))
    #expect(groupStart.lowerBound < edgeStart.lowerBound && edgeStart.lowerBound < childStart.lowerBound)
    let plain = boardSVG(board)
    #expect(!plain.contains("worksheet-grid"))
    #expect(!plain.contains("stroke=\"none\"/>"))
    board.edges = [line]
    #expect(throws: Abort.self) { try board.validate() }
    board.edges = []
    board.nodes = [container]
    container.parent = container.id
    board.nodes[0] = container
    #expect(throws: Abort.self) { try board.validate() }
    board.nodes[0].parent = "missing"
    #expect(throws: Abort.self) { try board.validate() }
}

@Test func worksheetLinkPaths() throws {
    let path = try WorksheetPath(["main", "lab"])
    for (value, expected) in [("notes", "/main/lab/notes"), ("./ötlet", "/main/lab/%C3%B6tlet"),
                              ("/..", "/main"), ("../other", "/main/other"), ("/top", "/top"),
                              ("../../..", "/"), ("https://example.org", "https://example.org")] {
        #expect(WorksheetLink(value)?.destination(from: path) == expected)
    }
    for value in ["javascript:alert(1)", "//example.org", "data:text/html,test", "foo%2Fbar", "a\\b"] {
        #expect(WorksheetLink(value) == nil)
    }
}

@Test func exclusiveSelectionAndCableChanges() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let live = Collaboration(store: store)
    let path = try WorksheetPath(["main", "lab"])
    let a = User(name: "anna", role: .admin, passwordHash: "")
    let b = User(name: "bela", role: .admin, passwordHash: "")
    var sheet = try store.open(path, user: a)
    sheet.nodes = [Idea(id: "box", title: "Doboz", position: Point(x: 0, y: 0))]
    sheet = try store.update(path, worksheet: sheet, user: a)
    let eventLoop = MultiThreadedEventLoopGroup.singleton.next()
    func select(_ user: User, node: String?) throws -> LiveState {
        try live.presence(path, user: user, client: user.name, action: "select", node: node, since: nil, loop: eventLoop).0
    }
    _ = try store.manage(WorksheetPath(["main"]), operation: DocumentAction(scope: "project", action: "mode", value: "public"), user: a, unlocks: [])
    let viewer = User(name: "viewer", role: .editor, passwordHash: "")
    _ = try live.presence(path, user: viewer, client: viewer.name, action: "view-select", node: "box", since: nil, loop: eventLoop)
    let first = try select(a, node: "box")
    #expect(first.participants.map(\.name) == ["anna", "viewer"])
    #expect(first.participants.last?.node == "box" && first.participants.last?.viewing == true)
    let poll = try #require(try live.presence(path, user: a, client: a.name, action: "poll", node: nil,
                                             since: first.version, loop: eventLoop).1)
    let both = try select(b, node: nil)
    try await poll.get()
    #expect(Set(both.participants.map(\.color)).count == 3)
    #expect(throws: Abort.self) { try select(b, node: "box") }
    var moved = sheet
    moved.nodes[0].position.x = 40
    #expect(throws: Abort.self) { try live.update(path, sheet: moved, user: b, client: b.name) }
    #expect(throws: Abort.self) { try live.update(path, sheet: moved, user: b, client: nil) }
    #expect(throws: Abort.self) { try live.update(path, sheet: moved, user: b, client: a.name) }
    sheet.edges = [Connection(id: "wire", source: "box", target: ConnectionTarget(point: Point(x: 0, y: 50)), endArrow: false)]
    sheet = try live.update(path, sheet: sheet, user: b, client: b.name)
    sheet.edges[0].source = nil
    sheet.edges[0].sourcePoint = Point(x: 0, y: 10)
    sheet = try live.update(path, sheet: sheet, user: b, client: b.name)
    _ = try live.presence(path, user: a, client: a.name, action: "leave", node: nil, since: nil, loop: eventLoop)
    #expect(try select(b, node: "box").participants.first?.mine == true)
    sheet.nodes[0].position.x = 40
    #expect(try live.update(path, sheet: sheet, user: b, client: b.name).nodes[0].position.x == 40)
}

@Test func sharedSessionCheckpoint() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-checkpoint-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let live = Collaboration(store: store)
    let path = try WorksheetPath(["snapshot"])
    let user = User(name: "anna", role: .admin, passwordHash: "")
    var sheet = try store.open(path, user: user)
    let loop = MultiThreadedEventLoopGroup.singleton.next()
    func action(_ client: String, _ action: String, _ checkpoint: Int? = nil) throws -> LiveState {
        try live.presence(path, user: user, client: client, action: action, node: nil, since: nil,
                          loop: loop, editing: client != "viewer", revision: sheet.revision, checkpointRevision: checkpoint).0
    }
    #expect(try action("viewer", "poll").checkpointRevision == nil)
    let initial = sheet
    _ = try action("first", "poll")
    sheet.title = "Piszkozat"
    sheet = try live.update(path, sheet: sheet, user: user, client: "first")
    #expect(try action("second", "poll").checkpointChanged)
    #expect(try action("second", "poll").checkpointRevision == initial.revision)
    _ = try action("second", "resign", initial.revision)
    sheet = try store.load(path, user: user)
    #expect(sheet.title == initial.title && sheet.resetRevision == sheet.revision)
    let restored = sheet.revision
    sheet.title = "Rögzített"
    sheet = try live.update(path, sheet: sheet, user: user, client: "first")
    let pinned = try action("first", "checkpoint", restored)
    #expect(!pinned.checkpointChanged)
    sheet.title = "Eldobott"
    sheet = try live.update(path, sheet: sheet, user: user, client: "second")
    #expect(throws: Abort.self) { try action("viewer", "resign", pinned.checkpointRevision) }
    #expect(throws: Abort.self) { try action("first", "resign", restored) }
    _ = try action("second", "resign", pinned.checkpointRevision)
    sheet = try store.load(path, user: user)
    #expect(sheet.title == "Rögzített")
    _ = try action("first", "leave")
    #expect(try action("second", "leave").checkpointRevision == nil)
    #expect(try action("new", "poll").checkpointRevision == sheet.revision)
}

@Test func testerSessions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-testers-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root, testMode: true)
    try await withApp(configure: { app in configure(app, store: store) }) { app in
        let browser = try app.testing()
        let first = try await browser.sendRequest(.GET, "/")
        let second = try await browser.sendRequest(.GET, "/")
        #expect(first.body.string.contains("Tester1") && second.body.string.contains("Tester2"))
        let cookie = try cookie(first)
        let page = try await browser.sendRequest(.GET, "/edit/proba", headers: ["Cookie": cookie])
        #expect(page.status == .ok && page.body.string.contains("data-user=\"Tester1\""))
        #expect(page.body.string.contains("data-role=\"admin\""))
        #expect(try store.allUsers().isEmpty)
    }
}

@Test func projectPoliciesFollowDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-policy-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let creator = User(name: "owner", role: .editor, passwordHash: "")
    let editor = User(name: "member", role: .editor, passwordHash: "")
    try store.setUser(name: "admin", role: .admin, passwordHash: "unused")
    try store.setUser(name: editor.name, role: .editor, passwordHash: "unused")
    let project = try WorksheetPath(["main"])
    let child = try WorksheetPath(["main", "child"])
    _ = try store.open(project, user: creator)
    let worksheet = try store.open(child, user: creator)
    #expect(throws: Abort.self) { try store.load(child, user: editor) }
    func action(_ action: String, _ value: String? = nil) throws {
        _ = try store.manage(project, operation: DocumentAction(scope: "project", action: action, value: value), user: creator, unlocks: [])
    }
    func listed(for user: User?) throws -> Bool {
        try store.list(user: user, rootsOnly: true).contains { $0.path.url == project.url }
    }
    try action("mode", "public")
    #expect(try listed(for: nil))
    let memberChild = try WorksheetPath(["main", "member-child"])
    let memberSheet = try store.open(memberChild, user: creator)
    try action("hide")
    #expect(try !listed(for: editor))
    #expect(try store.load(child, user: nil).title == worksheet.title)
    #expect(try !listed(for: nil))
    try action("mode", "internal")
    #expect(try !listed(for: editor))
    #expect(try !listed(for: creator))
    #expect(throws: Abort.self) { try store.load(child, user: editor) }
    try action("grant", editor.name)
    #expect(try !listed(for: editor))
    try action("password", "abcdefgh")
    #expect(throws: Abort.self) { try store.load(memberChild, user: editor) }
    #expect(throws: Abort.self) { try store.load(child, user: editor) }
    #expect(throws: Abort.self) { try store.update(child, worksheet: worksheet, user: editor) }
    #expect(try store.load(child, user: creator).creator == creator.name)
    let keys = Set(try store.unlock(child, password: "abcdefgh", user: editor))
    #expect(try store.load(child, user: editor, unlocks: keys).creator == creator.name)
    try action("freeze")
    #expect(try !store.access(memberChild, sheet: memberSheet, user: editor, unlocks: keys).editable)
    #expect(throws: Abort.self) { try store.update(child, worksheet: worksheet, user: editor, unlocks: keys) }
    try action("rename", "uj")
    let renamed = try WorksheetPath(["uj", "child"])
    #expect(try store.load(renamed, user: editor, unlocks: keys).creator == creator.name)
    #expect(!((try String(contentsOf: root.appendingPathComponent("uj/child.thnode"), encoding: .utf8)).contains("\"owner\":")))
}

@Test func virtualPreviewAndRecreatedLeaf() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let owner = User(name: "owner", role: .editor, passwordHash: "")
    let project = try WorksheetPath(["project"])
    let child = try WorksheetPath(["project", "child"])
    let sheet = try store.open(child, user: owner)
    #expect(files.fileExists(atPath: root.appendingPathComponent("project/project.thnode").path))
    if case .drawing(let svg) = try store.preview(project, user: owner) { #expect(svg.contains("<svg")) } else { Issue.record("Expected worksheet SVG") }
    _ = try store.manage(child, operation: DocumentAction(scope: "sheet", action: "freeze"), user: owner, unlocks: [])
    try store.archive(child, expected: sheet.revision)
    let recreated = try store.open(child, user: owner)
    #expect(try !store.access(child, sheet: recreated, user: owner).frozen)
}

@Test func codeBlockWhitespace() throws {
    let block = try #require(canvasMarkdown("```\n  a  b\n\n c\n```").first)
    let rows = wrapMarkdown(block.runs, columns: 40, preformatted: true)
    #expect(rows.map { $0.pieces.map(\.text).joined() } == ["  a  b", "", " c"])
}

@Test func bodyJustificationSurvivesRoundTrip() throws {
    let node = Idea(id: "box", title: "Cím", text: "Ez egy rövid példa több szövegsorral.",
                    position: Point(x: 0, y: 0), width: 130, height: 180, textStyle: TextStyle(justified: true))
    let board = Worksheet(title: "Munkalap", text: "Bevezetés", textJustified: true, nodes: [node])
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(board))
    #expect(saved.textJustified == true)
    #expect(saved.nodes[0].textStyle?.justified == true)
    let svg = boardSVG(saved)
    #expect(svg.contains("word-spacing="))
    #expect(!svg.contains("class=\"link-label\" word-spacing="))
}

@Test func compactWorksheetKeysRoundTrip() throws {
    let node = Idea(id: "idea", title: "Ötlet", position: Point(x: 12, y: 34),
                    alignment: .left, verticalAlignment: .top,
                    textStyle: TextStyle(alignment: .right, verticalAlignment: .bottom))
    let edge = Connection(id: "wire", sourcePoint: Point(x: 0, y: 0),
                          target: ConnectionTarget(node: node.id), width: 3)
    let sheet = Worksheet(title: "Teszt", gridSpacing: 25, nodes: [node], edges: [edge])
    let compact = try JSONEncoder().encode(sheet)
    #expect(try JSONDecoder().decode(Worksheet.self, from: compact) == sheet)
    let longKeys = String(decoding: compact, as: UTF8.self).replacingOccurrences(of: "\"pos\"", with: "\"position\"")
    #expect(try JSONDecoder().decode(Worksheet.self, from: Data(longKeys.utf8)).nodes.first?.position == Point(x: 0, y: 0))
    let keys = String(decoding: compact, as: UTF8.self)
    for key in ["pos", "align", "textCol", "w", "h", "vAlign", "srcPt", "gridStep"] {
        #expect(keys.contains("\"\(key)\""))
    }
}

@Test func connectionTypesAndAppearances() throws {
    let from = Point(x: -100, y: 0)
    let to = Point(x: 100, y: 0)
    var edge = Connection(id: "wire", sourcePoint: from, target: ConnectionTarget(point: to), endArrow: false)
    func render() -> String { boardSVG(Worksheet(title: "Vonalak", edges: [edge])) }

    edge.type = .sCurve
    #expect(render().contains("M -100.000 0.000 L 100.000 0.000"))
    edge.target.point?.y = 60
    edge.appearance = .dotted
    let curve = render()
    #expect(curve.contains("C 0.000 0.000 0.000 60.000"))
    #expect(curve.contains("stroke-linecap=\"round\" stroke-dasharray=\"0 16.000\""))

    edge.type = .lightning
    edge.target.point = to
    edge.appearance = .thick
    let lightning = render()
    #expect(lightning.contains("L -20.000 -23.094 20.000 23.094 100.000 0.000"))
    #expect(lightning.contains("stroke-width=\"4.000\""))
    edge.type = .arc
    #expect(render().contains("Q 0.000 -56.000"))
    edge.type = .rope
    #expect(render().contains("Q 0.000 170.000"))

    let previous = #"{"id":"wire","srcPt":{"x":0,"y":0},"target":{"point":{"x":50,"y":20}},"style":"rope"}"#
    let decoded = try JSONDecoder().decode(Connection.self, from: Data(previous.utf8))
    #expect(decoded.type == .rope && decoded.appearance == .plain && !decoded.hasEndArrow)
    let saved = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
    #expect(!saved.contains("\"style\""))
}

@Test func animatedConnectionsRoundTripAndRenderSVG() throws {
    var edge = Connection(id: "animated", sourcePoint: Point(x: 0, y: 0),
                          target: ConnectionTarget(point: Point(x: 100, y: 0)),
                          animated: true, startArrow: true, endArrow: true)
    edge = try JSONDecoder().decode(Connection.self, from: JSONEncoder().encode(edge))
    #expect(edge.animated == true)
    func render() -> String { boardSVG(Worksheet(title: "Animáció", edges: [edge])) }
    #expect(render().contains("stroke=\"url(#wire-gradient-animated)\""))
    #expect(render().contains("dur=\"12s\" repeatCount=\"indefinite\""))
    #expect(render().contains("<stop offset=\".25\" stop-color=\"currentColor\"/>"))
    #expect(render().contains("<stop offset=\".5\" stop-color=\"currentColor\" stop-opacity=\".5\"/>"))
    #expect(render().contains("<stop offset=\".75\" stop-color=\"currentColor\"/>"))
    edge.appearance = .thick
    #expect(render().contains("attributeName=\"stroke-width\" values=\"4.000;5.800;4.000\""))
    #expect(render().contains("type=\"scale\" additive=\"sum\""))
    edge.appearance = .dashed
    #expect(render().contains("attributeName=\"stroke-dashoffset\" values=\"0;-12.000;0\""))
    edge.appearance = .dotted
    edge.endArrow = false
    #expect(render().contains("attributeName=\"stroke-dashoffset\" values=\"0;16.000\""))
    edge.animated = false
    #expect(!render().contains("<animate"))
}

@Test func boxAnimationsRoundTripAndRenderSVG() throws {
    var box = Idea(id: "box", title: "Doboz", position: Point(x: 0, y: 0))
    for (mode, track): (BoxAnimation, String) in [
        (.pulse, "type=\"scale\""), (.blink, "attributeName=\"opacity\""),
        (.rock, "type=\"rotate\""), (.hop, "type=\"translate\""),
    ] {
        box.animation = mode
        let saved = try JSONDecoder().decode(Idea.self, from: JSONEncoder().encode(box))
        #expect(saved.animation == mode)
        let svg = boardSVG(Worksheet(title: "Animáció", nodes: [saved]))
        #expect(svg.contains("data-box-animation=\"\(mode.rawValue)\""))
        #expect(svg.contains(track))
        #expect(svg.contains("repeatCount=\"indefinite\""))
    }
    box.animation = BoxAnimation.none
    #expect(!boardSVG(Worksheet(title: "Animáció", nodes: [box])).contains("data-box-animation"))
}

@Test func connectedWiresRenderBelowTheirEndpointsInsideContainers() throws {
    let container = Idea(id: "container", title: "Konténer", position: Point(x: 0, y: 0),
                         width: 600, height: 320, kind: .container)
    let source = Idea(id: "source", title: "Kezdőpont", position: Point(x: -120, y: 0), parent: container.id)
    let target = Idea(id: "target", title: "Végpont", position: Point(x: 120, y: 0), animation: .pulse, parent: container.id)
    let edge = Connection(id: "wire", source: source.id, target: ConnectionTarget(node: target.id))
    let svg = boardSVG(Worksheet(title: "Rétegek", nodes: [source, target, container], edges: [edge]), noteBase: "/retegek")
    let containerOffset = try #require(svg.range(of: "id=\"object-container\"")).lowerBound
    let wireOffset = try #require(svg.range(of: "data-wire-group=")).lowerBound
    let sourceOffset = try #require(svg.range(of: "id=\"object-source\"")).lowerBound
    let targetOffset = try #require(svg.range(of: "id=\"object-target\"")).lowerBound
    #expect(containerOffset < wireOffset && wireOffset < sourceOffset && wireOffset < targetOffset)
}

@Test(arguments: [
    (Shape.triangle, 3, "30.000"),
    (.pentagon, 5, "55.587"),
    (.hexagon, 6, "60.000"),
    (.parallelogram, 4, "46.500"),
])
func polygonBoxesRoundTrip(shape: Shape, corners: Int, borderX: String) throws {
    let box = Idea(id: "box", title: "Doboz", position: Point(x: 0, y: 0), width: 120, height: 80, shape: shape)
    let edge = Connection(id: "wire", source: box.id, target: ConnectionTarget(point: Point(x: 200, y: 0)), endArrow: false)
    let sheet = Worksheet(title: "Sokszögek", nodes: [box], edges: [edge])
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(sheet))
    #expect(saved.nodes.first?.shape == shape)
    let svg = boardSVG(saved, noteBase: "/polygons")
    let polygon = try #require(svg.components(separatedBy: "<polygon points=\"").dropFirst().first)
    #expect(polygon.prefix(while: { $0 != "\"" }).split(separator: " ").count == corners)
    #expect(svg.contains("data-shape=\"\(shape.rawValue)\""))
    #expect(svg.contains("M \(borderX) 0.000 L 200.000 0.000"))
}

@Test func experimentalAnchorsLoadAsAutomaticConnections() throws {
    let box = Idea(id: "box", title: "Doboz", position: Point(x: 0, y: 0), width: 120, height: 80, shape: .rectangle)
    var second = box
    second.id = "second"
    second.position = Point(x: 200, y: 60)
    let data = Data(#"{"id":"wire","source":"box","sourceAnchor":"n","target":{"node":"second","anchor":"sw"}}"#.utf8)
    let edge = try JSONDecoder().decode(Connection.self, from: data)
    let sheet = Worksheet(title: "Pontok", nodes: [box, second], edges: [edge])
    try sheet.validate()
    #expect(boardSVG(sheet).contains("M 60.000 18.000 L 140.000 42.000"))
    let encoded = String(decoding: try JSONEncoder().encode(edge), as: UTF8.self)
    #expect(!encoded.lowercased().contains("anchor"))
}

@Test func incompleteWorksheetUsesDefaultsAndDropsUnknownKeys() throws {
    let data = Data(##"{"gridCol":"#ff0000","gridVisible":false,"nodes":[{"id":"a","shape":"unknown","pos":{"x":42},"border":"#ffffff","textFill":"#ffffff","textBorder":"#663344","extra":true}]}"##.utf8)
    let board = try JSONDecoder().decode(Worksheet.self, from: data)
    try board.validate()
    let node = try #require(board.nodes.first)
    #expect(node.position == Point(x: 42, y: 0))
    #expect(node.shape == .rounded)
    let encoded = String(decoding: try JSONEncoder().encode(board), as: UTF8.self)
    for key in ["border", "textFill", "textBorder", "extra", "gridCol", "gridVisible"] { #expect(!encoded.contains(key)) }
}

@Test func privateCanvasMediaRequiresWorksheetAccess() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-media-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let path = try WorksheetPath(["media"])
    let owner = User(name: "owner", role: .admin, passwordHash: "")
    let other = User(name: "other", role: .editor, passwordHash: "")
    var sheet = try store.open(path, user: owner)
    _ = try store.update(path, worksheet: sheet, user: owner)
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII="))
    let name = try store.storeMedia(png, type: "image/png", at: path, user: owner, unlocks: [])
    #expect(canvasAssetType(name) == "image/png")
    #expect(try store.contents(path, user: owner, unlocks: [], named: name).count == 1)
    #expect(throws: Abort.self) { try store.contents(path, user: nil, unlocks: [], named: name) }
    #expect(throws: Abort.self) { try store.contents(path, user: other, unlocks: [], named: name) }
    #expect(throws: Abort.self) { try store.storeMedia(png, type: "image/png", at: path, user: other, unlocks: []) }
    #expect(throws: Abort.self) { try store.storeMedia(Data("szöveg".utf8), type: "image/png", at: path, user: owner, unlocks: []) }
    #expect(try store.contents(path, user: owner, unlocks: []).count == 1)
}

@Test func canvasImageRenamePreservesAttachmentIdentity() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-image-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let path = try WorksheetPath(["image"])
    let owner = User(name: "owner", role: .admin, passwordHash: "")
    var sheet = try store.open(path, user: owner)
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII="))
    let asset = try store.storeMedia(png, type: "image/png", filename: "Eredeti.png", at: path, user: owner, unlocks: [])
    let original = try #require(store.contents(path, user: owner, unlocks: [], named: asset).first)
    #expect(original.lastPathComponent == "Eredeti.png")
    let directory = root.resolvingSymlinksInPath().appendingPathComponent("image")
    #expect(original == directory.appendingPathComponent("Eredeti.png"))
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".canvas-images").path))
    #expect(throws: Abort.self) {
        try store.storeMedia(png, type: "image/png", filename: "Eredeti.png", at: path, user: owner, unlocks: [])
    }
    sheet.nodes = [
        Idea(id: "one", title: "", text: "Csak mutatáskor", file: CanvasFile(type: .image, asset: asset, filename: "Eredeti"), position: Point(x: 0, y: 0)),
        Idea(id: "two", title: "", file: CanvasFile(type: .image, asset: asset, filename: "Eredeti"), position: Point(x: 400, y: 0)),
    ]
    sheet = try store.update(path, worksheet: sheet, user: owner)
    sheet.nodes[0].file?.filename = "Új név"
    sheet.nodes[0].file?.showFilename = true
    sheet = try store.update(path, worksheet: sheet, user: owner)
    let renamed = try #require(store.contents(path, user: owner, unlocks: [], named: asset).first)
    #expect(renamed.lastPathComponent == "Új név.png")
    #expect(!FileManager.default.fileExists(atPath: original.path))
    #expect(try Data(contentsOf: renamed) == png)
    #expect(renamed == directory.appendingPathComponent("Új név.png"))
    let named = try #require(store.contents(path, user: owner, unlocks: [], named: "Új név.png").first)
    let namedAttributes = try FileManager.default.attributesOfItem(atPath: named.path)
    let renamedAttributes = try FileManager.default.attributesOfItem(atPath: renamed.path)
    #expect(namedAttributes[.systemFileNumber] as? NSNumber == renamedAttributes[.systemFileNumber] as? NSNumber)
    try store.storeAttachment(png, named: "Foglalt.png", at: path, user: owner, unlocks: [])
    var collision = sheet
    collision.nodes[0].file?.filename = "Foglalt"
    #expect(throws: Abort.self) { try store.update(path, worksheet: collision, user: owner) }
    #expect(try Data(contentsOf: directory.appendingPathComponent("Foglalt.png")) == png)
    #expect(FileManager.default.fileExists(atPath: renamed.path))
    #expect(sheet.nodes[1].file?.filename == "Új név")
    #expect(needsTextTooltip(sheet.nodes[0]))
    let svg = boardSVG(sheet, noteBase: "/image")
    #expect(svg.contains("<span>Új név</span>"))
    #expect(!svg.contains("Csak mutatáskor"))
    sheet.nodes[0].file?.filename = "../tiltott"
    #expect(throws: Abort.self) { try store.update(path, worksheet: sheet, user: owner) }
    #expect(FileManager.default.fileExists(atPath: renamed.path))
}

@Test func folderBoundariesAndSharedAttachments() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let admin = User(name: "admin", role: .admin, passwordHash: "unused")
    let editor = User(name: "member", role: .editor, passwordHash: "unused")
    try store.setUser(name: admin.name, role: .admin, passwordHash: "unused")
    try store.setUser(name: editor.name, role: .editor, passwordHash: "unused")
    let project = try WorksheetPath(["Team"])
    let folder = try WorksheetPath(["Team", "Sub"])
    let side = try WorksheetPath(["Team", "Sub", "Draft"])
    func change(_ path: WorksheetPath, _ action: String, _ value: String? = nil) throws {
        _ = try store.manage(path, operation: DocumentAction(scope: "sheet", action: action, value: value), user: admin, unlocks: [])
    }
    _ = try store.open(project, user: admin)
    try change(project, "grant", editor.name)
    _ = try store.open(folder, user: admin, directory: true)
    _ = try store.open(side, user: editor)
    let payload = Data(#"{"title":"this is still an attachment","nodes":[]}"#.utf8)
    try store.storeAttachment(payload, named: "Draft.json", at: side, user: editor, unlocks: [])
    #expect(try store.contents(folder, user: editor, unlocks: []).map(\.lastPathComponent) == ["Draft.json"])
    for name in [".settings.json", "Draft.thnode", "../.settings.json"] {
        #expect(try store.contents(side, user: editor, unlocks: [], named: name).isEmpty)
    }
    try change(side, "hide")
    #expect(try store.list(user: editor, childrenOf: folder).isEmpty)
    #expect(try store.load(side, user: editor).creator == editor.name)
    let settings = try String(contentsOf: root.appendingPathComponent("Team/.settings.json"), encoding: .utf8)
    #expect(settings.contains("Sub/Draft.thnode"))
    try change(folder, "revoke", editor.name)
    #expect(throws: Abort.self) { try store.preview(side, user: editor) }
    #expect(throws: Abort.self) { try store.contents(side, user: editor, unlocks: [], named: "Draft.json") }
    try change(folder, "grant", editor.name)
    try change(project, "revoke", editor.name)
    #expect(throws: Abort.self) { try store.load(side, user: editor) }
    #expect(throws: Abort.self) { try change(folder, "grant", editor.name) }
    #expect(throws: Abort.self) { try store.open(WorksheetPath(["Team","Sub","Other"]), user: editor) }
    try change(project, "grant", editor.name)
    try store.removeUser(named: editor.name)
    try store.setUser(name: editor.name, role: .editor, passwordHash: "new")
    try change(project, "grant", editor.name)
    #expect(throws: Abort.self) { try store.load(side, user: editor) }
}
