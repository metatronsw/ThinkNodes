import Foundation
import Testing
import VaporTesting
@testable import ThinkNodes

// Munkalap: teljes HTTP-körút, formátum, útvonalak, első adminisztrátor.

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
        #expect(guestOpen.status == .notFound)
        #expect(guestOpen.body.string.contains("Ez az oldal nem létezik"))
        #expect(guestOpen.body.string.contains("href=\"/login\""))
        let invalid = try await browser.sendRequest(.GET, "/nincs.ilyen")
        #expect(invalid.status == .notFound)
        #expect(invalid.headers.first(name: .contentType)?.hasPrefix("text/html") == true)
        #expect(invalid.body.string.contains("href=\"/\""))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let creator = try #require(try store.user(named: "editor"))
        let project = try WorksheetPath(["gondolatok"])
        _ = try store.open(project, user: creator)
        for (action, value) in [("mode", "public"), ("grant", "shared")] {
            _ = try store.manage(project, operation: DocumentAction(scope: "project", action: action, value: value), user: creator, unlocks: [])
        }
        _ = try store.open(route, user: creator)
        let editor = try await login(browser, name: "editor", password: password, path: path)
        let newParent = try await browser.sendRequest(.GET, "/gondolatok", headers: ["Cookie": editor.cookie])
        #expect(newParent.status == .ok)
        // A fő munkalap mappa-ikonja megszűnt; a cím sorában a létrehozó és a szerkesztők névsora áll.
        #expect(!newParent.body.string.contains("main-worksheet-indicator") && newParent.body.string.contains("viewer-heading-credits"))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok/gondolatok.thnode").path))
        let index = try await browser.sendRequest(.GET, "/")
        #expect(index.body.string.contains("project-card panel layers-1"))
        #expect(index.body.string.contains("class=\"button header-button\" href=\"/utmutato.html\""))
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
            Idea(id: "elso", text: "# Első <ötlet>\n\n## Próba\n\n**Szöveg**",
                 hideText: false, position: Point(x: -250, y: 0), width: 260, height: 160),
            Idea(id: "masodik", text: "Második ötlet", position: Point(x: 250, y: 0), shape: .ellipse)
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
        let flatDocument = file.deletingLastPathComponent().appendingPathComponent("terv/adat.json")
        #expect(try String(contentsOf: flatDocument, encoding: .utf8) == source)
        #expect(!FileManager.default.fileExists(atPath: flatDocument.deletingLastPathComponent().appendingPathComponent(".attachments").path))
        #expect(try await browser.sendRequest(.POST, "/api/subworksheet/" + path + "/terv/adat", headers: headers).status == .ok)
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
        withAnimation.nodes = [Idea(id: "animation", type: "image", file: CanvasFile(asset: svgAsset), position: Point(x: 0, y: 0))]
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
        withArchive.nodes = [Idea(id: "archive", type: "document", file: CanvasFile(asset: "Ötletek.zip"), position: Point(x: 0, y: 0))]
        try withArchive.validate()
        let archiveSVG = boardSVG(withArchive, assetBase: "/" + path + "/terv")
        #expect(archiveSVG.contains("/api/box-file/" + path + "/terv?id=archive"))
        #expect(archiveSVG.contains("<span>Ötletek.zip</span>"))
        withArchive.nodes[0].file?.showFilename = false
        let iconOnly = boardSVG(withArchive, assetBase: "/" + path + "/terv")
        #expect(iconOnly.contains("/api/box-file/" + path + "/terv?id=archive"))
        #expect(!iconOnly.contains("<span>Ötletek.zip</span>"))
        withArchive.nodes[0].file?.asset = "../Ötletek.zip"
        #expect(throws: Abort.self) { try withArchive.validate() }
        let preview = try await browser.sendRequest(.GET, "/api/preview/" + path + "/terv")
        #expect(preview.status == .ok && preview.body.string.contains("<svg"))
        #expect(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent("terv/.terv.preview-v11.svg").path))
        try await checkPreviewAndPreferences(browser, path: path + "/terv", sheet: child, session: shared, png: png)
        let parent = try await browser.sendRequest(.GET, "/" + path)
        #expect(parent.body.string.contains("További munkalapok") && parent.body.string.contains("Létrehozó: shared"))
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
        let accounts = try await browser.sendRequest(.GET, "/api/worksheet-users/" + project.url, headers: ["Cookie": shared.cookie])
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
        #expect(page.body.string.contains(#"class="button header-button brand" href="/""#))
        #expect(page.body.string.contains("• </span>mégnincsilyen</h1>"))
        #expect(page.body.string.contains(#"title="Szülő munkalap" href="/gondolatok""#))
        #expect(!page.body.string.contains("main-worksheet-indicator"))
        #expect(page.body.string.contains("/icons.svg#download"))
        #expect(!page.body.string.contains("worksheet-grid"))
        #expect(page.body.string.contains("canvas-background"))
        #expect(page.body.string.contains("viewer-downloads"))
        let html = page.body.string
        let fullscreen = try #require(html.range(of: #"class="button fullscreen""#))
        let meta = try #require(html.range(of: #"class="viewer-meta""#))
        let roster = try #require(html.range(of: #"aria-label="Jelenlévők""#))
        let notes = try #require(html.range(of: "data-viewer-notes"))
        // The roster sits inside the canvas frame (lower right); the credits row follows the worksheet text.
        #expect(fullscreen.lowerBound < roster.lowerBound && roster.lowerBound < notes.lowerBound && notes.lowerBound < meta.lowerBound)

        let svg = try await browser.sendRequest(.GET, "/export/svg/\(path)")
        #expect(svg.status == .ok)
        #expect(svg.headers.first(name: .contentDisposition)?.contains(".svg") == true)
        // A kép kerete a tartalom széleihez igazodik (a szabad vonal -410…810 között fut), nem az origó köré szimmetrikus.
        #expect(svg.body.string.contains("viewBox=\"-450.000 -285.000 1300.000 480.000\""))
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
        #expect(blockedCreate.status == .notFound)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok/masik/masik.thnode").path))
        let missingAuthenticated = try await browser.sendRequest(.GET, "/gondolatok/masik", headers: ["Cookie": editor.cookie])
        #expect(missingAuthenticated.status == .notFound)
        let authenticatedCreate = try await browser.sendRequest(.POST, "/api/subworksheet/gondolatok/masik",
            headers: ["Cookie": editor.cookie, "X-CSRF-Token": editor.csrf])
        #expect(authenticatedCreate.status == .ok)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("gondolatok/masik/masik.thnode").path))

        let adminDelete = try await remove(browser, path: path, session: admin)
        #expect(adminDelete.status == .noContent)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let archived = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("gondolatok/.trash").path)
        #expect(archived.count == 1)
    }
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

@Test func compactWorksheetKeysRoundTrip() throws {
    let node = Idea(id: "idea", text: "Ötlet", position: Point(x: 12, y: 34),
                    alignment: .left, verticalAlignment: .top)
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

@Test func malformedWorksheetNodesRejectTheWholeDocument() {
    let bytes = Data(#"{"schemaVersion":3,"nodes":[{"id":"good","type":"box"},{"id":"bad"}],"edges":[]}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Worksheet.self, from: bytes) }
}

@Test func incompleteWorksheetUsesDefaultsAndDropsUnknownKeys() throws {
    let data = Data(##"{"schemaVersion":3,"gridCol":"#ff0000","gridVisible":false,"nodes":[{"id":"a","type":"box","shape":"unknown","pos":{"x":42},"border":"#ffffff","textFill":"#ffffff","textBorder":"#663344","extra":true}]}"##.utf8)
    let board = try JSONDecoder().decode(Worksheet.self, from: data)
    try board.validate()
    let node = try #require(board.nodes.first)
    #expect(node.position == Point(x: 42, y: 0))
    #expect(node.shape == .rounded)
    let encoded = String(decoding: try JSONEncoder().encode(board), as: UTF8.self)
    for key in ["border", "textFill", "textBorder", "extra", "gridCol", "gridVisible"] { #expect(!encoded.contains(key)) }
}

@Test func uploadedWorksheetsUseTheirOwnFolder() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-import-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let owner = User(name: "owner", role: .editor, passwordHash: "")
    let project = try WorksheetPath(["project"])
    _ = try store.open(project, user: owner)
    let attachment = try store.storeAttachment(Data("peldaszoveg".utf8), named: "note.txt", at: project, user: owner, unlocks: [])
    let note = Idea(id: "note", type: "text", file: CanvasFile(asset: attachment, filename: "note.txt"),
                    position: Point(x: 0, y: 0))
    let source = try JSONEncoder().encode(Worksheet(title: "Importált", nodes: [note]))
    let imported = try store.importWorksheet(source, named: "lap.thnode", at: project, user: owner, unlocks: [])
    #expect(imported.url == "project/lap")
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("project/lap/lap.thnode").path))
    #expect(try store.load(project, user: owner).nodes.isEmpty)
    #expect(try store.list(user: owner, childrenOf: project).map(\.path.url) == [imported.url])
    #expect(try store.contents(imported, user: owner, unlocks: [], named: attachment).first?.lastPathComponent == "note.txt")
    let renamed = try #require(try store.manage(imported, operation: DocumentAction(scope: "sheet", action: "rename", value: "uj"), user: owner, unlocks: []))
    #expect(try store.load(renamed, user: owner).title == "Importált")
    #expect(try store.load(project, user: owner).nodes.isEmpty)
    try store.archive(renamed, expected: 1)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("project/.trash/uj/uj.thnode").path))
}

@Test func legacyWorksheetsOpenInCurrentSchema() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-legacy-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let owner = User(name: "owner", role: .admin, passwordHash: "")
    let project = try WorksheetPath(["project"])
    _ = try store.open(project, user: owner)
    try Data("""
        {"schemaVersion":2,"title":"Régi lap","nodes":[{"id":"note","title":"Jegyzet","pos":{"x":0,"y":0}}]}
        """.utf8).write(to: root.appendingPathComponent("project/project.thnode"))
    let loaded = try store.load(project, user: owner)
    #expect(loaded.schemaVersion == Worksheet.currentSchema)
    #expect(loaded.nodes.first?.text == "Jegyzet")
    #expect(throws: Abort.self) { try store.importWorksheet(Data(#"{"title":"Régi","nodes":[]}"#.utf8), named: "regi.thnode", at: project, user: owner, unlocks: []) }
}

@Test func nodeTypeRegistryClassifiesFiles() throws {
    #expect(NodeTypes.classify(filename: "kép.PNG", bytes: Data()) == "image")
    #expect(NodeTypes.classify(filename: "dal.flac", bytes: Data()) == "audio")
    #expect(NodeTypes.classify(filename: "app.swift", bytes: Data("let a = 1".utf8)) == "code")
    #expect(NodeTypes.classify(filename: "adat.csv", bytes: Data("a,b\n1,2".utf8)) == "csv")
    #expect(NodeTypes.classify(filename: "jegyzet", bytes: Data("szöveg".utf8)) == "text")
    #expect(NodeTypes.classify(filename: "doc.pdf", bytes: Data([0x25, 0x50, 0x00, 0x01])) == "document")
    #expect(NodeTypes.classify(filename: "ascii.pdf", bytes: Data("%PDF-1.4 szöveg".utf8)) == "document")
    #expect(NodeTypes.root("code") == "text" && NodeTypes.has("code", "fileText") && !NodeTypes.has("text", "link"))
    #expect(NodeTypes.has("image", "link") && NodeTypes.has("box", "children"))
    #expect(parseCSV("a,\"b,c\"\n1,\"x\"\"y\"") == [["a", "b,c"], ["1", "x\"y"]])
    #expect(plainFirstLine("\n# **Cím** [link](https://x)\nmásodik") == "Cím link")
}
