import Foundation
import Testing
import VaporTesting
@testable import ThinkNodes

// Csatolmányok: átnevezés, mappahatárok, külső és közös fájlok, .web átnevezés.

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
        Idea(id: "one", type: "image", text: "Csak mutatáskor", file: CanvasFile(asset: asset, filename: "Eredeti"), position: Point(x: 0, y: 0)),
        Idea(id: "two", type: "image", file: CanvasFile(asset: asset, filename: "Eredeti"), position: Point(x: 400, y: 0)),
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
    #expect(!needsTextTooltip(sheet.nodes[0]))
    let svg = boardSVG(sheet, noteBase: "/image")
    #expect(svg.contains("<span>Új név.png</span>"))
    #expect(svg.contains("node-comment") && svg.contains("Csak mutatáskor"))
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
    _ = try store.open(folder, user: admin)
    _ = try store.open(side, user: editor)
    let payload = Data(#"{"title":"this is still an attachment","nodes":[]}"#.utf8)
    try store.storeAttachment(payload, named: "Draft.json", at: side, user: editor, unlocks: [])
    #expect(try store.contents(folder, user: editor, unlocks: []).isEmpty)
    #expect(try store.contents(side, user: editor, unlocks: []).map(\.lastPathComponent) == ["Draft.json"])
    for name in [".settings.json", "Draft.thnode", "../.settings.json"] {
        #expect(try store.contents(side, user: editor, unlocks: [], named: name).isEmpty)
    }
    try change(side, "hide")
    #expect(try store.list(user: editor, childrenOf: folder).isEmpty)
    #expect(try store.load(side, user: editor).creator == editor.name)
    let settings = try String(contentsOf: root.appendingPathComponent("Team/.settings.json"), encoding: .utf8)
    #expect(settings.contains("Sub/Draft/Draft.thnode"))
    #expect(throws: Abort.self) { try change(folder, "revoke", editor.name) }
    #expect(!(try store.contents(side, user: editor, unlocks: [], named: "Draft.json")).isEmpty)
    try change(project, "revoke", editor.name)
    #expect(throws: Abort.self) { try store.preview(side, user: editor) }
    #expect(throws: Abort.self) { try store.contents(side, user: editor, unlocks: [], named: "Draft.json") }
    #expect(throws: Abort.self) { try change(folder, "grant", editor.name) }
    #expect(throws: Abort.self) { try store.open(WorksheetPath(["Team","Sub","Other"]), user: editor) }
    try change(project, "grant", editor.name)
    try store.removeUser(named: editor.name)
    try store.setUser(name: editor.name, role: .editor, passwordHash: "new")
    #expect(throws: Abort.self) { try store.load(side, user: editor) }
    try change(project, "grant", editor.name)
    #expect(try store.load(side, user: editor).creator == editor.name)
}

@Test func externalFilesAreListedRenamedTrashedAndRestored() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-external-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let owner = User(name: "owner", role: .admin, passwordHash: "")
    let folder = try WorksheetPath(["project", "folder"])
    _ = try store.open(folder, user: owner)
    let directory = root.appendingPathComponent("project/folder")
    let original = directory.appendingPathComponent("adat.bin")
    try Data([1, 2, 3]).write(to: original)
    try Data("Szöveg".utf8).write(to: directory.appendingPathComponent("jegyzet.txt"))
    store.reconcileAtStartup()
    var sheet = try store.load(folder, user: owner)
    #expect(sheet.nodes.map { $0.file?.filename } == ["adat.bin", "jegyzet.txt"])
    #expect(sheet.nodes[0].position.x == sheet.nodes[1].position.x)
    #expect(sheet.nodes[0].position.y < sheet.nodes[1].position.y)
    #expect(sheet.nodes.map(\.type) == ["document", "text"])
    let externalFolder = directory.appendingPathComponent("ujmappa")
    try FileManager.default.createDirectory(at: externalFolder, withIntermediateDirectories: false)
    try Data([7]).write(to: externalFolder.appendingPathComponent("kulso.dat"))
    sheet = try store.load(folder, user: owner)
    #expect(sheet.nodes.allSatisfy { $0.link == nil })
    #expect(throws: Abort.self) { try store.load(WorksheetPath(["project", "folder", "ujmappa"]), user: owner) }
    let id = sheet.nodes[0].id
    sheet.nodes[0].file?.filename = "rossz.txt"
    #expect(throws: Abort.self) { try store.update(folder, worksheet: sheet, user: owner) }
    sheet.nodes[0].file?.filename = "új.bin"
    sheet = try store.update(folder, worksheet: sheet, user: owner)
    let renamed = directory.appendingPathComponent("új.bin")
    #expect(FileManager.default.fileExists(atPath: renamed.path))
    #expect(!FileManager.default.fileExists(atPath: original.path))
    if case .disk(let download) = try store.boxFile(folder, id: id, user: owner, unlocks: []) {
        #expect(download.lastPathComponent == "új.bin")
    } else { Issue.record("A bináris fájl nem tölthető le.") }
    let removed = sheet.nodes.removeFirst()
    sheet = try store.update(folder, worksheet: sheet, user: owner)
    #expect(!FileManager.default.fileExists(atPath: renamed.path))
    let archived = root.appendingPathComponent("project/.trash/folder/új.bin")
    #expect(try Data(contentsOf: archived) == Data([1, 2, 3]))
    #expect(try store.load(folder, user: owner).nodes.count == 1)
    sheet.nodes.insert(removed, at: 0)
    _ = try store.update(folder, worksheet: sheet, user: owner, restoring: true)
    #expect(try Data(contentsOf: renamed) == Data([1, 2, 3]))
    #expect(!FileManager.default.fileExists(atPath: archived.path))
}

/// Közös fájl: másik lapról is hivatkozható; lomtárba tételkor a többi lap doboza üres dobozzá válik.
@Test func sharedFileReleaseUnlinksOtherSheets() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-release-\(UUID().uuidString)")
    let store = try WorksheetStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let password = UUID().uuidString
    try store.setUser(name: "admin", role: .admin, passwordHash: try Bcrypt.hash(password, cost: 4))
    let admin = try #require(try store.user(named: "admin"))
    let project = try WorksheetPath(["kozos"]), child = try WorksheetPath(["kozos", "al"])
    var parent = try store.open(project, user: admin)
    var sub = try store.open(child, user: admin)
    let asset = try store.storeAttachment(Data("# Jegyzet".utf8), named: "jegyzet.md", at: project, user: admin, unlocks: [])
    parent.nodes = [Idea(id: "parentfile", type: "text", file: CanvasFile(asset: asset, filename: "jegyzet.md"), position: Point(x: 0, y: 0), width: 340, height: 240)]
    parent = try store.update(project, worksheet: parent, user: admin)
    sub.nodes = [Idea(id: "childfile", type: "text", file: CanvasFile(asset: asset, source: "", filename: "jegyzet.md"), position: Point(x: 0, y: 0), width: 340, height: 240)]
    sub = try store.update(child, worksheet: sub, user: admin)
    #expect(try store.usage(of: "childfile", in: child, user: admin, unlocks: []).map(\.sheet).sorted() == ["kozos", "kozos/al"])

    // Az allap dobozának törlése (mentéssel) nem viszi lomtárba a szülőlap fájlját.
    var trimmed = sub
    trimmed.nodes = []
    _ = try store.update(child, worksheet: trimmed, user: admin)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("kozos/jegyzet.md").path))
    sub = try store.update(child, worksheet: { var restored = sub; restored.revision += 1; return restored }(), user: admin)

    try await withApp(configure: { app in configure(app, store: store, secureCookies: false) }) { app in
        let browser = try app.testing()
        let session = try await login(browser, name: "admin", password: password, path: child.url)
        let response = try await browser.sendRequest(.POST, "/api/release/" + child.url,
            headers: ["Cookie": session.cookie, "X-CSRF-Token": session.csrf, "Content-Type": "application/json"]) { request in
            try request.content.encode(["id": "childfile", "mode": "unlink"])
        }
        #expect(response.status == .ok)
        let updated = try store.load(project, user: admin)
        #expect(updated.nodes.first?.type == "box" && updated.nodes.first?.file == nil && updated.nodes.first?.text.contains("lomtárban") == true)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("kozos/jegyzet.md").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("kozos/.trash/jegyzet.md").path))
    }
}

/// .web átnevezése: a projekt többi lapjának linkje is az új nevet kapja.
@Test func webRenameUpdatesOtherSheets() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-rename-\(UUID().uuidString)")
    let store = try WorksheetStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let password = UUID().uuidString
    try store.setUser(name: "admin", role: .admin, passwordHash: try Bcrypt.hash(password, cost: 4))
    let admin = try #require(try store.user(named: "admin"))
    let project = try WorksheetPath(["nevek"]), child = try WorksheetPath(["nevek", "al"])
    var parent = try store.open(project, user: admin)
    var sub = try store.open(child, user: admin)
    let site = root.appendingPathComponent("nevek/regi.web")
    try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
    try Data("<title>x</title>".utf8).write(to: site.appendingPathComponent("index.html"))
    parent.nodes = [Idea(id: "parentweb", text: "regi", position: Point(x: 0, y: 0), link: NodeLink(kind: .web, target: "regi.web"))]
    parent = try store.update(project, worksheet: parent, user: admin)
    sub.nodes = [Idea(id: "childweb", text: "regi", position: Point(x: 0, y: 0), link: NodeLink(kind: .web, target: "regi.web"))]
    sub = try store.update(child, worksheet: sub, user: admin)

    try await withApp(configure: { app in configure(app, store: store, secureCookies: false) }) { app in
        let browser = try app.testing()
        let session = try await login(browser, name: "admin", password: password, path: project.url)
        let response = try await browser.sendRequest(.POST, "/api/web-rename/" + project.url,
            headers: ["Cookie": session.cookie, "X-CSRF-Token": session.csrf, "Content-Type": "application/json"]) { request in
            try request.content.encode(["reference": "regi.web", "name": "uj"])
        }
        #expect(response.status == .ok)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("nevek/uj.web/index.html").path))
        #expect(try store.load(child, user: admin).nodes.first?.link?.target == "uj.web")
    }
}
