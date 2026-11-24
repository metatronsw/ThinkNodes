import Foundation
import Testing
import Vapor
import VaporTesting
@testable import ThinkCore
@testable import ThinkNodes

/// Publikus fájl: belső projektben is bárki letöltheti; a többi fájlhoz jogosultság kell.
@Test func publicFilesAreReadableWithoutLogin() throws {
    let directory = FileManager.default
    let root = directory.temporaryDirectory.appendingPathComponent("thinknodes-shared-\(UUID())")
    defer { try? directory.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    try store.setUser(name: "owner", role: .admin, passwordHash: try Bcrypt.hash("x", cost: 4))
    let owner = try #require(try store.user(named: "owner"))
    let project = try WorksheetPath(["belso"])
    _ = try store.open(project, user: owner)
    _ = try store.storeAttachment(Data("nyilvános".utf8), named: "kozos.txt", at: project, user: owner, unlocks: [])
    _ = try store.storeAttachment(Data("titkos".utf8), named: "titkos.txt", at: project, user: owner, unlocks: [])

    #expect(throws: Abort.self) { try store.contents(project, user: nil, unlocks: [], named: "kozos.txt") }
    try store.setFilePublic("kozos.txt", publicAccess: true, in: project, user: owner, unlocks: [])
    #expect(try store.contents(project, user: nil, unlocks: [], named: "kozos.txt").count == 1)
    #expect(throws: Abort.self) { try store.contents(project, user: nil, unlocks: [], named: "titkos.txt") }
    #expect(try store.browse(project, user: owner, unlocks: []).entries.first { $0.name == "kozos.txt" }?.publicAccess == true)
    #expect(throws: Abort.self) { try store.setFilePublic("kozos.txt", publicAccess: false, in: project, user: nil, unlocks: []) }
    try store.setFilePublic("kozos.txt", publicAccess: false, in: project, user: owner, unlocks: [])
    #expect(throws: Abort.self) { try store.contents(project, user: nil, unlocks: [], named: "kozos.txt") }
}

/// Lomtár: lista az eredeti hellyel, visszaállítás, ürítés; jogosultság nélkül nem érhető el.
@Test func projectTrashRestoresAndEmpties() throws {
    let directory = FileManager.default
    let root = directory.temporaryDirectory.appendingPathComponent("thinknodes-trash-\(UUID())")
    defer { try? directory.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    try store.setUser(name: "owner", role: .admin, passwordHash: try Bcrypt.hash("x", cost: 4))
    let owner = try #require(try store.user(named: "owner"))
    let project = try WorksheetPath(["lomtar"])
    _ = try store.open(project, user: owner)
    let trash = root.appendingPathComponent("lomtar/.trash")
    try directory.createDirectory(at: trash.appendingPathComponent("regi.web"), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: trash.appendingPathComponent("kep.png"))

    #expect(throws: Abort.self) { try store.trashContents("lomtar", user: nil, unlocks: []) }
    let entries = try store.trashContents("lomtar", user: owner, unlocks: [])
    #expect(Set(entries.map(\.path)) == ["kep.png", "regi.web"])
    try store.restoreTrash("lomtar", path: "kep.png", user: owner, unlocks: [])
    #expect(directory.fileExists(atPath: root.appendingPathComponent("lomtar/kep.png").path))
    #expect(throws: Abort.self) { try store.restoreTrash("lomtar", path: "../../kivul", user: owner, unlocks: []) }
    try store.emptyTrash("lomtar", user: owner, unlocks: [])
    #expect(try store.trashContents("lomtar", user: owner, unlocks: []).isEmpty)
}

/// Törölt projekt: a gyökér lomtárába kerül, onnan visszaállítható (ha a név szabad) vagy véglegesen törölhető.
@Test func deletedProjectsRestoreAndPurge() throws {
    let directory = FileManager.default
    let root = directory.temporaryDirectory.appendingPathComponent("thinknodes-deleted-\(UUID())")
    defer { try? directory.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    try store.setUser(name: "owner", role: .admin, passwordHash: try Bcrypt.hash("x", cost: 4))
    let owner = try #require(try store.user(named: "owner"))
    for name in ["egyik", "masik"] {
        let project = try WorksheetPath([name])
        let sheet = try store.open(project, user: owner)
        try store.archive(project, expected: sheet.revision)
    }
    #expect(store.deletedProjects().map(\.name) == ["egyik", "masik"])
    #expect(!directory.fileExists(atPath: root.appendingPathComponent("egyik").path))

    let first = try #require(store.deletedProjects().first)
    #expect(throws: Abort.self) { try store.restoreProject("../" + first.id) }
    #expect(throws: Abort.self) { try store.restoreProject("nincs-ilyen") }
    // Foglalt név: a visszaállítás nem írja felül az azonos nevű új projektet.
    _ = try store.open(try WorksheetPath(["egyik"]), user: owner)
    #expect(throws: Abort.self) { try store.restoreProject(first.id) }
    #expect(try store.restoreProject(store.deletedProjects()[1].id).url == "masik")
    #expect(directory.fileExists(atPath: root.appendingPathComponent("masik/masik.thnode").path))
    #expect(try store.open(try WorksheetPath(["masik"]), user: owner).revision >= 1)

    try store.purgeDeletedProjects(first.id)
    #expect(store.deletedProjects().isEmpty)
}

/// Adminoldal: a törölt projekt megjelenik a „Törölt projektek” panelen; visszaállítás és (megerősítéssel) végleges törlés.
@Test func adminPageManagesDeletedProjects() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-admintrash-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let password = UUID().uuidString
    try store.setUser(name: "admin", role: .admin, passwordHash: try Bcrypt.hash(password, cost: 4))
    let admin = try #require(try store.user(named: "admin"))
    for name in ["marad", "torolt"] { _ = try store.open(try WorksheetPath([name]), user: admin) }
    try store.archive(try WorksheetPath(["torolt"]), expected: 1)
    let id = try #require(store.deletedProjects().first?.id)
    struct Form: Content { var id: String?; var action: String; var confirm: String?; var csrf: String }

    try await withApp(configure: { app in configure(app, store: store, secureCookies: false) }) { app in
        let browser = try app.testing()
        let session = try await login(browser, name: "admin", password: password, path: "marad")
        func post(_ form: Form) async throws -> HTTPStatus {
            try await browser.sendRequest(.POST, "/admin/trash", headers: ["Cookie": session.cookie]) { request in
                try request.content.encode(form, as: .urlEncodedForm)
            }.status
        }
        let page = try await browser.sendRequest(.GET, "/admin", headers: ["Cookie": session.cookie]).body.string
        #expect(page.contains("Törölt projektek (1)") && page.contains("<strong>torolt</strong>"))
        // Megerősítés nélkül nincs végleges törlés; hibás CSRF-fel semmi.
        #expect(try await post(Form(id: id, action: "purge", confirm: nil, csrf: session.csrf)) == .badRequest)
        #expect(try await post(Form(id: id, action: "restore", confirm: nil, csrf: "hibas")) != .seeOther)
        #expect(store.deletedProjects().count == 1)
        #expect(try await post(Form(id: id, action: "restore", confirm: nil, csrf: session.csrf)) == .seeOther)
        let restored = try WorksheetPath(["torolt"])
        #expect(store.deletedProjects().isEmpty && store.pageExists(restored))
        let after = try await browser.sendRequest(.GET, "/admin", headers: ["Cookie": session.cookie]).body.string
        #expect(!after.contains("Törölt projektek"))

        try store.archive(restored, expected: try store.load(restored, user: admin).revision)
        let again = try #require(store.deletedProjects().first?.id)
        #expect(try await post(Form(id: again, action: "purge", confirm: "on", csrf: session.csrf)) == .seeOther)
        #expect(store.deletedProjects().isEmpty && !store.pageExists(restored))
    }
}

/// A `common` első szegmens foglalt: a közös könyvtár címe (`/common/...`), projekt nem kaphatja meg.
@Test func commonIsNotAProjectName() {
    #expect(throws: Abort.self) { try WorksheetPath(["common"]) }
    #expect(throws: Abort.self) { try WorksheetPath(["Common", "lap"]) }
    #expect((try? WorksheetPath(["commons"])) != nil)
    #expect((try? WorksheetPath(["projekt", "common"])) != nil)
    #expect(CanvasFile.validSource("@common/ikonok"))
}

/// Közös könyvtár (Public/common): a szövegfájl tartalma a megtekintőnek is megvan; a könyvtáron kívülre nem lát.
@Test func commonLibraryTextIsReadForTheViewer() throws {
    let directory = FileManager.default
    let root = directory.temporaryDirectory.appendingPathComponent("thinknodes-common-\(UUID())")
    defer { try? directory.removeItem(at: root) }
    let assets = root.appendingPathComponent("Public")
    try directory.createDirectory(at: assets.appendingPathComponent("common/leirasok"), withIntermediateDirectories: true)
    try Data("# Közös leírás".utf8).write(to: assets.appendingPathComponent("common/leirasok/leiras.md"))
    try Data("titok".utf8).write(to: assets.appendingPathComponent("kulso.md"))
    let store = try WorksheetStore(root: root.appendingPathComponent("projects"))
    try store.setUser(name: "owner", role: .admin, passwordHash: try Bcrypt.hash("x", cost: 4))
    let owner = try #require(try store.user(named: "owner"))
    let project = try WorksheetPath(["lap"])
    var sheet = try store.open(project, user: owner)
    sheet.nodes = [Idea(id: "kozos", type: "text", file: CanvasFile(asset: "leiras.md", source: "@common/leirasok", filename: "leiras.md"),
                        position: Point(x: 0, y: 0), width: 340, height: 240)]
    sheet = try store.update(project, worksheet: sheet, user: owner)
    #expect(try store.fileTexts(project, sheet: sheet, user: owner, unlocks: [], commonDirectory: assets.path) == ["leiras.md": "# Közös leírás"])
    #expect(try store.fileTexts(project, sheet: sheet, user: owner, unlocks: []).isEmpty)
    #expect(CommonLibrary.file(CanvasFile(asset: "../kulso.md", source: "@common"), publicDirectory: assets.path) == nil)
    #expect(CommonLibrary.file(CanvasFile(asset: "kulso.md", source: "@common/.."), publicDirectory: assets.path) == nil)
}

/// Markdown HTML: a sima sortörés új sor, és ahány üres sor van a forrásban, annyi látszik (kódblokkon kívül).
@Test func markdownKeepsLineBreaksAndBlankLines() {
    #expect(markdownHTML("a\nb").contains("a<br />"))
    let html = markdownHTML("a\n\n\n\nb")
    #expect(html.components(separatedBy: "\u{00A0}").count - 1 == 2)
    #expect(preservingBlankLines("```\nx\n\n\ny\n```") == "```\nx\n\n\ny\n```")
}

/// Mentett állapotok: sorszámozott mentés, visszaállítás; a lomtár ürítése megtartja a mentésben hivatkozott fájlt.
@Test func versionsRestoreAndProtectTrashedFiles() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("thinknodes-versions-\(UUID())")
    defer { try? fm.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let owner = User(name: "owner", role: .admin, passwordHash: "")
    let project = try WorksheetPath(["verzio"])
    _ = try store.open(project, user: owner)
    let kept = try store.storeAttachment(Data("marad".utf8), named: "marad.txt", at: project, user: owner, unlocks: [])
    let gone = try store.storeAttachment(Data("torlodik".utf8), named: "torlodik.txt", at: project, user: owner, unlocks: [])
    var sheet = try store.load(project, user: owner)
    sheet.nodes = [Idea(id: "a", type: "text", file: CanvasFile(asset: kept, filename: "marad.txt"), position: Point(x: 0, y: 0))]
    sheet = try store.update(project, worksheet: sheet, user: owner)
    #expect(try store.versions(project, user: owner, unlocks: []).changed)
    #expect(try store.saveVersion(project, user: owner, unlocks: []).number == 1)
    #expect(try !store.versions(project, user: owner, unlocks: []).changed)

    // Egy másik fájl is lomtárba kerül, de arra egyik mentés sem hivatkozik.
    sheet.nodes = [Idea(id: "b", type: "text", file: CanvasFile(asset: gone, filename: "torlodik.txt"), position: Point(x: 0, y: 0))]
    sheet = try store.update(project, worksheet: sheet, user: owner)
    sheet.nodes = []
    sheet = try store.update(project, worksheet: sheet, user: owner)
    #expect(try store.saveVersion(project, user: owner, unlocks: []).number == 2)
    #expect(try store.versions(project, user: owner, unlocks: []).versions.map(\.number) == [2, 1])
    #expect(!fm.fileExists(atPath: root.appendingPathComponent("verzio/marad.txt").path))

    try store.emptyTrash("verzio", user: owner, unlocks: [])
    #expect(try store.trashContents("verzio", user: owner, unlocks: []).map(\.path) == ["marad.txt"])

    var restored = try store.version(project, number: 1, user: owner, unlocks: [])
    restored.revision = sheet.revision
    _ = try store.update(project, worksheet: restored, user: owner, restoring: true)
    #expect(fm.fileExists(atPath: root.appendingPathComponent("verzio/marad.txt").path))
    #expect(try store.load(project, user: owner).nodes.map(\.id) == ["a"])
}
