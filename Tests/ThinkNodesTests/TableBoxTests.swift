import Foundation
import Testing
import ThinkTable
@testable import ThinkNodes

/// A táblázat forrásfájlja nem kap automatikusan saját dobozt (EXCEL.md 7. fejezet).
@Test func tableSourceAttachmentIsNotAutoAdded() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let path = try WorksheetPath(["tabla"])
    let user = User(name: "owner", role: .admin, passwordHash: "")
    var sheet = try store.open(path, user: user)
    let csv = Data("a;b\n1;2\n".utf8)
    let source = try store.storeAttachment(csv, named: "lista.csv", at: path, user: user, unlocks: [])
    var document = TableCSV.importCSV(csv, name: "lista").document
    document.source = TableSource(name: source, hash: TableFiles.hash(csv))
    let asset = try store.storeAttachment(document.encoded(), named: "lista.tntable", at: path, user: user, unlocks: [])
    sheet.nodes = [Idea(id: "t", type: "table", file: CanvasFile(asset: asset, filename: "lista.tntable"), position: Point(x: 0, y: 0))]
    _ = try store.update(path, worksheet: sheet, user: user)
    store.forgetPendingAttachmentsForTesting()
    let loaded = try store.load(path, user: user)
    #expect(loaded.nodes.map(\.type) == ["table"], "\(loaded.nodes.map { ($0.type, $0.file?.filename ?? "") })")
}

/// A forrás a táblázattal marad, ha a CSV-dobozát törlik; a táblázat törlésekor vele együtt lomtárba kerül.
@Test func tableSourceFollowsTheTable() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorksheetStore(root: root)
    let path = try WorksheetPath(["tabla"])
    let user = User(name: "owner", role: .admin, passwordHash: "")
    var sheet = try store.open(path, user: user)
    let csv = Data("a;b\n1;2\n".utf8)
    let source = try store.storeAttachment(csv, named: "lista.csv", at: path, user: user, unlocks: [])
    var document = TableCSV.importCSV(csv, name: "lista").document
    document.source = TableSource(name: source, hash: TableFiles.hash(csv))
    let asset = try store.storeAttachment(document.encoded(), named: "lista.tntable", at: path, user: user, unlocks: [])
    let table = Idea(id: "t", type: "table", file: CanvasFile(asset: asset, filename: "lista.tntable"), position: Point(x: 0, y: 0))
    let csvBox = Idea(id: "c", type: "csv", file: CanvasFile(asset: source, filename: "lista.csv"), position: Point(x: 0, y: 300))
    sheet.nodes = [table, csvBox]
    sheet = try store.update(path, worksheet: sheet, user: user)
    sheet.nodes = [table]
    sheet = try store.update(path, worksheet: sheet, user: user)
    let folder = root.appendingPathComponent("tabla")
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("lista.csv").path))
    sheet.nodes = []
    _ = try store.update(path, worksheet: sheet, user: user)
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("lista.csv").path))
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("lista.tntable").path))
}
