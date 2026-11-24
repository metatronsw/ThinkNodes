import Foundation
import Testing
import Vapor
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
