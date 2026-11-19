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
    let file = root.appendingPathComponent("gondolatok/mégnincsilyen.json")
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
        let editor = try await login(browser, name: "editor", password: password, path: path)
        let newParent = try await browser.sendRequest(.GET, "/gondolatok", headers: ["Cookie": editor.cookie])
        #expect(newParent.status == .ok)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok.json").path))
        let openedAgain = try await browser.sendRequest(.GET, "/\(path)", headers: ["Cookie": editor.cookie])
        #expect(openedAgain.status == .ok)
        let guestPrivate = try await browser.sendRequest(.GET, "/export/svg/\(path)")
        #expect(guestPrivate.status == .unauthorized)

        let owner = try #require(try store.user(named: "editor"))
        var worksheet = try store.load(route, user: owner)
        #expect(worksheet.title == "mégnincsilyen")
        #expect(worksheet.revision == 1)
        #expect(worksheet.owner == "editor")
        #expect(worksheet.isPublic == false)
        worksheet.background = "#e7eef3"
        worksheet.isPublic = true
        worksheet.editors = ["shared"]
        worksheet.comment = "A munkalap megjegyzése"
        worksheet.markdown = "**A munkalap bevezetője**"
        worksheet.nodes = [
            Idea(id: "elso", title: "Első <ötlet>", markdown: "## Próba\n\n**Szöveg**",
                 comment: "A doboz megjegyzése", showMarkdown: true, position: Point(x: -250, y: 0)),
            Idea(id: "masodik", title: "Második ötlet", position: Point(x: 250, y: 0), shape: .ellipse)
        ]
        worksheet.edges = [
            Connection(id: "kapcsolat", source: "elso", target: ConnectionTarget(node: "masodik"), style: .both),
            Connection(id: "szabad", source: "masodik", target: ConnectionTarget(point: Point(x: 810, y: 12)), style: .dashed),
            Connection(id: "szabad-kezdet", sourcePoint: Point(x: -410, y: -170),
                       target: ConnectionTarget(point: Point(x: -250, y: -70)), style: .rope,
                       color: "#6b3273", width: 5, startArrow: true, endArrow: false, label: "Szabad vonal")
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
        let outsidersView = try await browser.sendRequest(.GET, "/\(path)", headers: ["Cookie": outsider.cookie])
        #expect(outsidersView.status == .ok)
        #expect(!outsidersView.body.string.contains(">Szerkesztés"))
        var accessTamper = try saved.content.decode(Worksheet.self)
        accessTamper.editors = ["outsider"]
        let tampered = try await save(browser, path: path, worksheet: accessTamper, session: shared)
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
        #expect(page.body.string.contains("A munkalap megjegyzése"))
        #expect(page.body.string.contains("<strong>A munkalap bevezetője</strong>"))
        #expect(page.body.string.contains("A doboz megjegyzése"))
        #expect(!page.body.string.contains("<script"))
        #expect(!page.body.string.contains("<h1>"))
        #expect(page.body.string.contains("/icons.svg#download"))

        let svg = try await browser.sendRequest(.GET, "/export/svg/\(path)")
        #expect(svg.status == .ok)
        #expect(svg.headers.first(name: .contentDisposition)?.contains(".svg") == true)
        #expect(svg.body.string.contains("viewBox=\"-850.000 -240.000 1700.000 480.000\""))
        #expect(svg.body.string.contains("marker-start="))
        #expect(svg.body.string.contains("stroke-dasharray="))
        #expect(svg.body.string.contains("A doboz megjegyzése"))
        #expect(svg.body.string.contains("font-weight=\"700\">Szöveg</tspan>"))
        #expect(svg.body.string.contains("fill=\"#e7eef3\""))
        #expect(svg.body.string.contains("stroke=\"#6b3273\" stroke-width=\"5.000\""))
        #expect(svg.body.string.contains("rotate(32.005)"))
        #expect(svg.body.string.contains(">Szabad vonal</text>"))
        #expect(svg.body.string.contains("fill=\"#131d2b\""))
        #expect(!svg.body.string.contains("<a href="))

        let markdown = try await browser.sendRequest(.GET, "/export/markdown/\(path)")
        #expect(markdown.status == .ok)
        #expect(markdown.body.string.contains("**Szöveg**"))
        #expect(markdown.body.string.contains("A munkalap megjegyzése"))
        #expect(markdown.body.string.contains("**A munkalap bevezetője**"))
        #expect(markdown.body.string.contains("A doboz megjegyzése"))
        #expect(markdown.body.string.contains("Kétirányú nyíl"))
        #expect(markdown.body.string.contains("810.000, 12.000"))

        let canvasNotes = try await browser.sendRequest(.POST, "/api/markdown/canvas", headers: [
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
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok/masik.json").path))
        let authenticatedCreate = try await browser.sendRequest(.GET, "/gondolatok/masik", headers: ["Cookie": editor.cookie])
        #expect(authenticatedCreate.status == .ok)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok/masik.json").path))

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
        return (signedInCookie, "")
    }
    #expect(editor.status == .ok)
    #expect(!editor.body.string.contains("site-header"))
    let token = try attribute("data-csrf=\"", in: editor.body.string)
    return (signedInCookie, token)
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

@Test func containerStylesAndJunctionsSurviveRoundTrip() throws {
    let origin = Point(x: 0, y: 0)
    var container = Idea(id: "group", title: "Konténer", position: origin, kind: .container, locked: true)
    let child = Idea(id: "child", title: "Ötlet", markdown: "**törzs**", comment: "jegyzet", showMarkdown: true,
                     position: origin, parent: "group", italic: true, underline: true,
                     commentStyle: TextStyle(color: "#006688", size: 18, alignment: .right),
                     markdownStyle: TextStyle(color: "#663300", size: 17, italic: true, alignment: .left),
                     markdownFill: "#eecc99", markdownBorder: "#663344", autoMinWidth: 320)
    let junction = Idea(id: "joint", title: "Kapocs", position: Point(x: 200, y: 80), width: 14, height: 14,
                        shape: .ellipse, kind: .connectionPoint)
    let line = Connection(id: "line", source: child.id, target: ConnectionTarget(node: junction.id), style: .arrow)
    var board = Worksheet(schemaVersion: 1, title: "Ábra", gridColor: "#006699", gridSpacing: 32,
                          nodes: [child, junction, container], edges: [line])
    try board.validate()
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(board))
    try saved.validate()
    #expect(saved.nodes.first?.parent == container.id)
    #expect(saved.nodes.first?.markdownStyle?.size == 17)
    #expect(saved.nodes.last?.locked == true)
    let svg = boardSVG(saved)
    #expect(svg.contains("patternUnits=\"userSpaceOnUse\" width=\"32.000\""))
    #expect(svg.contains("fill=\"#006699\""))
    #expect(svg.contains("fill=\"#eecc99\" stroke=\"#663344\""))
    #expect(svg.contains("text-anchor=\"end\""))
    #expect(svg.contains("font-style=\"italic\" text-decoration=\"underline\""))
    #expect(svg.contains("r=\"7\" fill=\"#dce9ff\" aria-label=\"Kapocs\""))
    let groupStart = try #require(svg.range(of: "<title>Konténer</title>"))
    let edgeStart = try #require(svg.range(of: "marker-end=\"url(#arrow-line)"))
    let childStart = try #require(svg.range(of: "<title>Ötlet</title>"))
    #expect(groupStart.lowerBound < edgeStart.lowerBound && edgeStart.lowerBound < childStart.lowerBound)
    board.gridVisible = false
    board.nodes[0].markdownFill = board.nodes[0].fill
    board.nodes[0].markdownBorder = board.nodes[0].border
    let plain = boardSVG(board)
    #expect(!plain.contains("worksheet-grid"))
    #expect(!plain.contains("stroke=\"none\"/>"))
    board.edges = []
    #expect(throws: Abort.self) { try board.validate() }
    board.nodes = [container]
    container.parent = container.id
    board.nodes[0] = container
    #expect(throws: Abort.self) { try board.validate() }
    board.nodes[0].parent = "missing"
    #expect(throws: Abort.self) { try board.validate() }
}
