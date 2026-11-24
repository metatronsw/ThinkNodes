import Foundation
import Testing
import Vapor
@testable import ThinkNodes

@Test func textNoteSaveReplacesOnlyAnExistingTextAttachment() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let path = try WorksheetPath(["notes"])
    let user = User(name: "owner", role: .admin, passwordHash: "")
    _ = try store.open(path, user: user)
    let data = Data("Második változat".utf8)
    try store.storeAttachment(Data("Első".utf8), named: "próba.md", at: path, user: user, unlocks: [])
    try store.storeAttachment(data, named: "próba.md", at: path, user: user, unlocks: [], replaceText: true)
    let file = try #require(store.contents(path, user: user, unlocks: [], named: "próba.md").first)
    #expect(try Data(contentsOf: file) == data)
    #expect(throws: Abort.self) { try store.storeAttachment(data, named: "másik.txt", at: path, user: user, unlocks: [], replaceText: true) }
}
