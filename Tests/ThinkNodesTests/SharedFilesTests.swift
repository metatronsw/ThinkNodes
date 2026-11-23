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
