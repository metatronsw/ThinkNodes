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
        let index = try await browser.sendRequest(.GET, "/")
        #expect(index.body.string.contains("project-card panel layers-1"))
        let openedAgain = try await browser.sendRequest(.GET, "/\(path)", headers: ["Cookie": editor.cookie])
        #expect(openedAgain.status == .ok)
        let guestPrivate = try await browser.sendRequest(.GET, "/export/svg/\(path)")
        #expect(guestPrivate.status == .ok)

        let owner = try #require(try store.user(named: "editor"))
        var worksheet = try store.load(route, user: owner)
        #expect(worksheet.title == "mégnincsilyen")
        #expect(worksheet.revision == 1)
        #expect(worksheet.owner == "editor")
        #expect(worksheet.isPublic == true)
        worksheet.background = "#e7eef3"
        worksheet.isPublic = true
        worksheet.editors = ["shared"]
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
        let outsider = try await login(browser, name: "outsider", password: password, path: path)
        let childURL = "/api/subworksheet/" + path + "/terv"
        let headers: HTTPHeaders = ["Cookie": shared.cookie, "X-CSRF-Token": shared.csrf]
        let created = try await browser.sendRequest(.POST, childURL, headers: headers)
        #expect(created.status == .ok)
        let child = try created.content.decode(Worksheet.self)
        #expect(child.title == "terv" && child.nodes.isEmpty && child.edges.isEmpty)
        #expect(child.owner == owner.name && child.editors == nil && child.isPublic == true)
        #expect(child.background == worksheet.background)
        #expect(child.creator == "shared")
        let preview = try await browser.sendRequest(.GET, "/api/preview/" + path + "/terv")
        #expect(preview.status == .ok && preview.body.string.contains("<svg"))
        #expect(FileManager.default.fileExists(atPath: file.deletingPathExtension().appendingPathComponent(".terv.preview-v8.svg").path))
        let parent = try await browser.sendRequest(.GET, "/" + path)
        #expect(parent.body.string.contains("További oldalak:") && parent.body.string.contains("Létrehozó: shared"))
        #expect(try await browser.sendRequest(.POST, childURL, headers: headers).status == .conflict)
        for cookie in [editor.cookie, admin.cookie, shared.cookie] {
            let home = try await browser.sendRequest(.GET, "/", headers: ["Cookie": cookie])
            #expect(!home.body.string.contains("href=\"/" + path + "\""))
        }
        let outsidersView = try await browser.sendRequest(.GET, "/\(path)", headers: ["Cookie": outsider.cookie])
        #expect(outsidersView.status == .ok)
        #expect(outsidersView.body.string.contains("aria-label=\"Szerkesztés\""))
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
        #expect(svg.body.string.contains("fill=\"#e7eef3\""))
        #expect(svg.body.string.contains("stroke=\"#6b3273\" stroke-width=\"5.000\""))
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
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok/masik.json").path))
        let authenticatedCreate = try await browser.sendRequest(.GET, "/gondolatok/masik", headers: ["Cookie": editor.cookie])
        #expect(authenticatedCreate.status == .seeOther)
        #expect(authenticatedCreate.headers.first(name: .location) == "/edit/gondolatok/masik")
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
    #expect(editor.body.string.contains("site-header"))
    #expect(editor.body.string.contains("brand-icon"))
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
    let child = Idea(id: "child", title: "Ötlet", text: "**törzs**", hideText: false,
                     position: origin, parent: "group", italic: true, underline: true,
                     textStyle: TextStyle(color: "#663300", size: 17, italic: true, alignment: .left))
    let junction = Idea(id: "joint", title: "Kapocs", position: Point(x: 200, y: 80), width: 34, height: 34,
                        shape: .ellipse, kind: .connectionPoint)
    let line = Connection(id: "line", source: child.id, target: ConnectionTarget(node: junction.id))
    let second = Connection(id: "other-line", source: junction.id, target: ConnectionTarget(point: origin), endArrow: false)
    var board = Worksheet(title: "Ábra", gridColor: "#006699", gridSpacing: 32,
                          nodes: [child, junction, container], edges: [line, second])
    try board.validate()
    var largeTitle = board
    largeTitle.nodes[0].fontSize = 1000
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
    board.nodes[1].title = ""
    try board.validate()
    let groupStart = try #require(svg.range(of: "aria-label=\"Konténer\" transform="))
    let edgeStart = try #require(svg.range(of: "marker-end=\"url(#arrow-line)"))
    let childStart = try #require(svg.range(of: "aria-label=\"Ötlet\" transform="))
    #expect(groupStart.lowerBound < childStart.lowerBound && childStart.lowerBound < edgeStart.lowerBound)
    board.gridVisible = false
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
    sheet.isPublic = true
    sheet = try live.update(path, sheet: sheet, user: user, client: "second")
    #expect(throws: Abort.self) { try action("viewer", "resign", pinned.checkpointRevision) }
    #expect(throws: Abort.self) { try action("first", "resign", restored) }
    _ = try action("second", "resign", pinned.checkpointRevision)
    sheet = try store.load(path, user: user)
    #expect(sheet.title == "Rögzített" && sheet.isPublic == true)
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
    #expect(try store.access(child, sheet: worksheet, user: editor).editable)
    func action(_ action: String, _ value: String? = nil) throws {
        _ = try store.manage(project, operation: DocumentAction(scope: "project", action: action, value: value), user: creator, unlocks: [])
    }
    func listed(for user: User?) throws -> Bool {
        try store.list(user: user, rootsOnly: true).contains { $0.path.url == project.url }
    }
    #expect(try listed(for: nil))
    let memberChild = try WorksheetPath(["main", "member-child"])
    let memberSheet = try store.open(memberChild, user: editor)
    try action("hide")
    #expect(try !listed(for: editor))
    #expect(try store.load(child, user: nil).title == worksheet.title)
    #expect(try !listed(for: nil))
    try action("mode", "internal")
    #expect(try !listed(for: editor))
    #expect(try listed(for: creator))
    #expect(throws: Abort.self) { try store.load(child, user: editor) }
    try action("grant", editor.name)
    #expect(try listed(for: editor))
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
    #expect(!((try String(contentsOf: root.appendingPathComponent("uj/child.json"), encoding: .utf8)).contains("\"owner\":")))
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
    try files.removeItem(at: root.appendingPathComponent("project.json"))
    #expect(try store.previewSVG(project, user: owner).contains("<svg"))
    _ = try store.manage(child, operation: DocumentAction(scope: "sheet", action: "freeze"), user: owner, unlocks: [])
    try store.archive(child, expected: sheet.revision)
    let recreated = try store.open(child, user: owner)
    #expect(try !store.access(child, sheet: recreated, user: owner).frozen)
}

@Test func codeBlockWhitespace() throws {
    let block = try #require(canvasMarkdown("```\n  a  b\n\n c\n```").first)
    let rows = wrapMarkdown(block.runs, columns: 40, preformatted: true)
    #expect(rows.map { $0.map(\.text).joined() } == ["  a  b", "", " c"])
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
    let data = Data(##"{"nodes":[{"id":"a","shape":"unknown","pos":{"x":42},"border":"#ffffff","textFill":"#ffffff","textBorder":"#663344","extra":true}]}"##.utf8)
    let board = try JSONDecoder().decode(Worksheet.self, from: data)
    try board.validate()
    let node = try #require(board.nodes.first)
    #expect(node.position == Point(x: 42, y: 0))
    #expect(node.shape == .rounded)
    let encoded = String(decoding: try JSONEncoder().encode(board), as: UTF8.self)
    for key in ["border", "textFill", "textBorder", "extra"] { #expect(!encoded.contains(key)) }
}

@Test func privateCanvasMediaRequiresWorksheetAccess() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-media-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let path = try WorksheetPath(["media"])
    let owner = User(name: "owner", role: .admin, passwordHash: "")
    let other = User(name: "other", role: .editor, passwordHash: "")
    var sheet = try store.open(path, user: owner)
    sheet.isPublic = false
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
    let asset = try store.storeMedia(png, type: "image/png", imageName: "Eredeti", at: path, user: owner, unlocks: [])
    let original = try #require(store.contents(path, user: owner, unlocks: [], named: asset).first)
    #expect(original.lastPathComponent == "Eredeti.png")
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
    #expect(attachmentName(renamed) == asset)
    #expect(sheet.nodes[1].file?.filename == "Új név")
    #expect(needsTextTooltip(sheet.nodes[0]))
    let svg = boardSVG(sheet, noteBase: "/image")
    #expect(svg.contains("<span>Új név</span>"))
    #expect(!svg.contains("Csak mutatáskor"))
    sheet.nodes[0].file?.filename = "../tiltott"
    #expect(throws: Abort.self) { try store.update(path, worksheet: sheet, user: owner) }
    #expect(FileManager.default.fileExists(atPath: renamed.path))
}
