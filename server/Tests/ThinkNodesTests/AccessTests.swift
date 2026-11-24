import Foundation
import Testing
import VaporTesting
@testable import ThinkNodes

// Jogosultságok: projekt-házirendek, jelszavak, védett médiafájlok.

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
    let subfolder = try WorksheetPath(["main", "subfolder"])
    let nested = try WorksheetPath(["main", "subfolder", "nested"])
    _ = try store.open(subfolder, user: creator)
    let nestedSheet = try store.open(nested, user: creator)
    try action("grant", editor.name)
    #expect(try !listed(for: editor))
    #expect(try store.access(nested, sheet: nestedSheet, user: editor).editable)
    #expect(try store.list(user: editor, childrenOf: subfolder).map(\.path.url) == [nested.url])
    #expect(throws: Abort.self) {
        try store.manage(subfolder, operation: DocumentAction(scope: "sheet", action: "revoke", value: editor.name), user: editor, unlocks: [])
    }
    try action("revoke", editor.name)
    #expect(throws: Abort.self) { try store.load(nested, user: editor) }
    try action("grant", editor.name)
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
    #expect(!((try String(contentsOf: root.appendingPathComponent("uj/child/child.thnode"), encoding: .utf8)).contains("\"owner\":")))
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

@Test func onlyProjectsHavePasswords() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-password-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let owner = User(name: "owner", role: .editor, passwordHash: "")
    let member = User(name: "member", role: .editor, passwordHash: "")
    try store.setUser(name: "admin", role: .admin, passwordHash: "unused")
    try store.setUser(name: member.name, role: .editor, passwordHash: "unused")
    let project = try WorksheetPath(["main"])
    let child = try WorksheetPath(["main", "child"])
    _ = try store.open(project, user: owner)
    _ = try store.open(child, user: owner)
    _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "grant", value: member.name), user: owner, unlocks: [])
    #expect(throws: Abort.self) {
        try store.manage(child, operation: DocumentAction(scope: "sheet", action: "password", value: "abcdefgh"), user: owner, unlocks: [])
    }
    // Régi, allapon tárolt jelszó: nem zár.
    let legacy = try Bcrypt.hash("legacy-pass", cost: 4)
    try Data(#"{"passwordHash":"\#(legacy)"}"#.utf8).write(to: root.appendingPathComponent("main/child/.settings.json"))
    #expect(try store.load(child, user: member).nodes.isEmpty)
    // A projekt jelszava az allapot is zárja, és ugyanazzal oldható fel.
    _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "password", value: "project-pass"), user: owner, unlocks: [])
    #expect(throws: Abort.self) { try store.load(child, user: member) }
    #expect(throws: Abort.self) { try store.unlock(child, password: "legacy-pass", user: member) }
    let keys = Set(try store.unlock(child, password: "project-pass", user: member))
    #expect(try store.load(child, user: member, unlocks: keys).nodes.isEmpty)
}
