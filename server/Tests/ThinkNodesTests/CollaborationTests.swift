import Foundation
import Testing
import VaporTesting
@testable import ThinkCore
@testable import ThinkNodes

// Közös szerkesztés: kijelölés, munkamenetek, élő frissítés, vendégek.

@Test func exclusiveSelectionAndCableChanges() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let live = Collaboration(store: store)
    let path = try WorksheetPath(["main", "lab"])
    let a = User(name: "anna", role: .admin, passwordHash: "")
    let b = User(name: "bela", role: .admin, passwordHash: "")
    var sheet = try store.open(path, user: a)
    sheet.nodes = [Idea(id: "box", text: "Doboz", position: Point(x: 0, y: 0))]
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
        let csrf = try attribute("data-csrf=\"", in: first.body.string)
        let created = try await browser.sendRequest(.POST, "/api/subworksheet/proba", headers: ["Cookie": cookie, "X-CSRF-Token": csrf])
        #expect(created.status == .ok)
        let page = try await browser.sendRequest(.GET, "/edit/proba", headers: ["Cookie": cookie])
        #expect(page.status == .ok && page.body.string.contains("data-user=\"Tester1\""))
        #expect(page.body.string.contains("data-role=\"admin\""))
        #expect(try store.allUsers().isEmpty)
    }
}

@Test func publishedProjectsAndViewerChangesWakeOpenPages() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-live-pages-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let password = UUID().uuidString
    let hash = try Bcrypt.hash(password, cost: 4)
    try store.setUser(name: "admin", role: .admin, passwordHash: hash)
    try store.setUser(name: "member", role: .editor, passwordHash: hash)
    let admin = try #require(try store.user(named: "admin"))
    let project = try WorksheetPath(["live-project"])
    let child = try WorksheetPath(["live-project", "child"])
    _ = try store.open(child, user: admin)

    func watchURL(_ page: TestingHTTPResponse) throws -> String {
        let html = page.body.string
        let id = try attribute(#"name="thinknodes-updates" data-id=""#, in: html)
        let version = try attribute(#"data-id=""# + id + #"" content=""#, in: html)
        return "/api/page-changes/" + id + "?since=" + version
    }

    try await withApp(configure: { app in configure(app, store: store) }) { app in
        let browser = try app.testing()
        let administrator = try await login(browser, name: "admin", password: password, path: project.url)
        let loginForm = try await browser.sendRequest(.GET, "/login")
        let loginCookie = try cookie(loginForm)
        let loginToken = try attribute(#"name="csrf" value=""#, in: loginForm.body.string)
        let memberLogin = try await browser.sendRequest(.POST, "/login", headers: ["Cookie": loginCookie]) { request in
            try request.content.encode(Credentials(name: "member", password: password, csrf: loginToken), as: .urlEncodedForm)
        }
        let memberCookie = try cookie(memberLogin)
        let guestHome = try await browser.sendRequest(.GET, "/")
        let memberHome = try await browser.sendRequest(.GET, "/", headers: ["Cookie": memberCookie])
        #expect(!guestHome.body.string.contains("href=\"/live-project\""))
        #expect(!memberHome.body.string.contains("href=\"/live-project\""))

        let homeWatch = try watchURL(guestHome)
        async let homeEvent = browser.sendRequest(.GET, homeWatch)
        let published = try await browser.sendRequest(.POST, "/api/document/" + project.url, headers: [
            "Cookie": administrator.cookie, "X-CSRF-Token": administrator.csrf,
        ]) { request in
            try request.content.encode(DocumentAction(scope: "project", action: "mode", value: "public"))
        }
        #expect(published.status == .ok)
        let notice = try await homeEvent
        #expect(notice.status == .ok && !homeWatch.hasSuffix(notice.body.string))
        let freshGuest = try await browser.sendRequest(.GET, "/")
        let freshMember = try await browser.sendRequest(.GET, "/", headers: ["Cookie": memberCookie])
        #expect(freshGuest.body.string.contains("href=\"/live-project\""))
        #expect(freshMember.body.string.contains("href=\"/live-project\""))

        let childPage = try await browser.sendRequest(.GET, "/" + child.url)
        let html = childPage.body.string
        #expect(!html.contains("<h2>További munkalapok</h2>"))
        #expect(!html.contains("<h2>Mappa tartalma</h2>"))
        #expect(!html.contains("<h2>Külső hivatkozások</h2>"))
        #expect(html.contains("viewer-edit-slot"))
        let projectPage = try await browser.sendRequest(.GET, "/" + project.url)
        let projectWatch = try watchURL(projectPage)
        async let projectEvent = browser.sendRequest(.GET, projectWatch)
        var changed = try store.load(child, user: admin)
        changed.title = "Élő előnézet"
        #expect(try await save(browser, path: child.url, worksheet: changed, session: administrator).status == .ok)
        let parentNotice = try await projectEvent
        #expect(parentNotice.status == .ok && !projectWatch.hasSuffix(parentNotice.body.string))
        #expect(try await browser.sendRequest(.GET, "/" + project.url).body.string.contains("Élő előnézet"))
    }
}

@Test func publicGuestCanEditWithoutProjectManagement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-guest-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let admin = User(name: "admin", role: .admin, passwordHash: "")
    let project = try WorksheetPath(["project"])
    let folder = try WorksheetPath(["project", "folder"])
    let draft = try store.open(folder, user: admin)
    _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "mode", value: "public"), user: admin, unlocks: [])

    try await withApp(configure: { app in configure(app, store: store) }) { app in
        let browser = try app.testing()
        let page = try await browser.sendRequest(.GET, "/edit/" + folder.url)
        #expect(page.status == .ok)
        let session = (cookie: try cookie(page), csrf: try attribute("data-csrf=\"", in: page.body.string))
        let headers: HTTPHeaders = ["Cookie": session.cookie, "X-CSRF-Token": session.csrf]
        var edited = draft
        edited.title = "Vendég szerkesztése"
        #expect(try await save(browser, path: folder.url, worksheet: edited, session: session).status == .ok)
        #expect(try await browser.sendRequest(.POST, "/api/subworksheet/" + folder.url + "/new-page", headers: headers).status == .ok)
        #expect(try await browser.sendRequest(.POST, "/api/subworksheet/new-project", headers: headers).status == .unauthorized)
        #expect(try await remove(browser, path: project.url, session: session).status == .unauthorized)

        _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "mode", value: "internal"), user: admin, unlocks: [])
        edited.revision += 1
        #expect(try await save(browser, path: folder.url, worksheet: edited, session: session).status == .forbidden)
    }
}

// Felhasználói színek: automatikus (a paletta szabad színeiből, fiókonként eltérő) vagy az admin által megadott #hex;
// a jelenlévők között a szín és az, hogy ki nem nézi éppen a lapot.
@Test func userColorsAndAwayPeers() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-colors-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    for name in ["anna", "bela", "cili"] { try store.setUser(name: name, role: .admin, passwordHash: "x") }
    let automatic = try ["anna", "bela", "cili"].map { try #require(try store.user(named: $0)?.color) }
    #expect(Set(automatic).count == 3 && automatic.allSatisfy(userPalette.contains))
    try store.assignColor("#ABCDEF", to: "bela")
    #expect(try store.user(named: "bela")?.color == "#abcdef")
    #expect(throws: Abort.self) { try store.assignColor("red", to: "bela") }
    #expect(throws: Abort.self) { try store.assignColor("#123456", to: "nincs") }
    try store.assignColor(userPalette[0], to: "cili")
    #expect(try store.user(named: "anna")?.color != userPalette[0])
    try store.savePreferences(UserPreferences(snap: true), for: "bela")
    #expect(try store.user(named: "bela")?.color == "#abcdef")
    try store.assignColor(nil, to: "bela")
    #expect(try store.user(named: "bela")?.color != "#abcdef")
    #expect(throws: Abort.self) { try store.assignAvatar(avatarCount + 1, to: "anna") }
    try store.assignAvatar(avatarCount, to: "anna")
    let avatars = try FileManager.default.contentsOfDirectory(atPath: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("../../Public/icons").standardized.path).filter { $0.hasPrefix("avatar-") }
    #expect(avatars.count == avatarCount)

    let live = Collaboration(store: store)
    let path = try WorksheetPath(["main", "szinek"])
    let anna = try #require(try store.user(named: "anna")), cili = try #require(try store.user(named: "cili"))
    _ = try store.open(path, user: anna)
    let loop = MultiThreadedEventLoopGroup.singleton.next()
    func poll(_ user: User, away: Bool? = nil) throws -> LiveState {
        try live.presence(path, user: user, client: user.name, action: "poll", node: nil, since: nil, loop: loop, away: away).0
    }
    _ = try poll(anna)
    let state = try poll(cili, away: true)
    #expect(state.participants.first { $0.name == "cili" }?.color == userPalette[0])
    #expect(state.participants.first { $0.name == "cili" }?.away == true)
    #expect(Set(state.participants.map(\.id)).count == 2 && !state.participants.contains { $0.id.isEmpty })
    #expect(state.participants.first { $0.name == "anna" }?.color == anna.color && state.participants.first { $0.name == "anna" }?.away == false)
    #expect(try poll(cili).participants.first { $0.name == "cili" }?.away == true)
    let back = try live.presence(path, user: cili, client: cili.name, action: "status", node: nil, since: nil, loop: loop, away: false).0
    #expect(back.participants.first { $0.name == "cili" }?.away == false)
}

// Előadás: egyszerre egy előadó; nem admin nem veheti át, admin igen; az előadó távozásával véget ér.
@Test func presentationOwnership() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-present-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let live = Collaboration(store: store)
    let path = try WorksheetPath(["main", "eloadas"])
    let anna = User(name: "anna", role: .editor, passwordHash: ""), bela = User(name: "bela", role: .editor, passwordHash: "")
    let admin = User(name: "admin", role: .admin, passwordHash: "")
    _ = try store.open(path, user: admin)
    _ = try store.manage(WorksheetPath(["main"]), operation: DocumentAction(scope: "project", action: "mode", value: "public"), user: admin, unlocks: [])
    let loop = MultiThreadedEventLoopGroup.singleton.next()
    func act(_ user: User, _ action: String, mode: String? = nil) throws -> LiveState {
        try live.presence(path, user: user, client: user.name, action: action, node: nil, since: nil, loop: loop, mode: mode).0
    }
    _ = try act(bela, "poll")
    #expect(throws: Abort.self) { try act(anna, "present", mode: "slides") }
    let started = try act(anna, "present", mode: "forced")
    let annaID = try #require(started.participants.first { $0.name == "anna" }?.id)
    #expect(started.presentation?.presenter == annaID && started.presentation?.mode == "forced" && started.presentation?.name == "anna")
    #expect(throws: Abort.self) { try act(bela, "present", mode: "invite") }
    _ = try act(bela, "unpresent")
    #expect(try act(bela, "poll").presentation?.presenter == annaID)
    let takeover = try act(admin, "present", mode: "invite")
    #expect(takeover.presentation?.name == "admin" && takeover.presentation?.mode == "invite")
    _ = try act(admin, "leave")
    #expect(try act(bela, "poll").presentation == nil)
}

// Csevegés: csak bejelentkezve; az üzenet a munkalap mappájában tárolódik (vele mozog), a szerző színével / avatarjával
// olvasható; törölni a szerző vagy admin tud; üres és túl hosszú üzenet nem megy.
@Test func worksheetChat() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-chat-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    try store.setUser(name: "admin", role: .admin, passwordHash: "x")
    for name in ["anna", "bela"] { try store.setUser(name: name, role: .editor, passwordHash: "x") }
    let anna = try #require(try store.user(named: "anna")), bela = try #require(try store.user(named: "bela"))
    let admin = try #require(try store.user(named: "admin"))
    let path = try WorksheetPath(["main", "beszelgetes"])
    _ = try store.open(path, user: admin)
    _ = try store.manage(WorksheetPath(["main"]), operation: DocumentAction(scope: "project", action: "mode", value: "public"), user: admin, unlocks: [])
    #expect(throws: Abort.self) { try store.chat(path, user: nil) }
    #expect(throws: Abort.self) { try store.postChat(path, text: "szia", user: nil) }
    #expect(throws: Abort.self) { try store.postChat(path, text: "   ", user: anna) }
    #expect(throws: Abort.self) { try store.postChat(path, text: String(repeating: "a", count: chatMessageLimit + 1), user: anna) }
    let first = try store.postChat(path, text: "  Szia @bela!\nMásodik sor  ", user: anna)
    #expect(first.text == "Szia @bela!\nMásodik sor" && first.author == "anna" && first.color == anna.color)
    let second = try store.postChat(path, text: "Helló", user: bela)
    #expect(try store.chat(path, user: bela).map(\.id) == [first.id, second.id])
    #expect(throws: Abort.self) { try store.deleteChat(path, id: first.id, user: bela) }
    try store.deleteChat(path, id: second.id, user: bela)
    try store.deleteChat(path, id: first.id, user: admin)
    #expect(try store.chat(path, user: anna).isEmpty)
    _ = try store.postChat(path, text: "Marad", user: anna)
    #expect(FileManager.default.fileExists(atPath: try store.folder(path).appendingPathComponent(".chat.jsonl").path))
}
