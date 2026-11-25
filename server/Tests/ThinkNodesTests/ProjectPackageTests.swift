import Foundation
import Testing
import VaporTesting
@testable import ThinkCore
@testable import ThinkNodes

private func makeStore() throws -> (WorksheetStore, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-package-\(UUID())")
    let store = try WorksheetStore(root: root)
    try store.setUser(name: "admin", role: .admin, passwordHash: "unused")
    try store.setUser(name: "owner", role: .editor, passwordHash: "unused")
    try store.setUser(name: "member", role: .editor, passwordHash: "unused")
    return (store, store.dataRoot)
}

private func entries(_ zip: URL) throws -> Set<String> { Set(try WebArchive.entries(zip)) }

@Test func packageRoundTripAsProjectAndSubsheet() throws {
    let (store, root) = try makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let owner = User(name: "owner", role: .editor, passwordHash: "")
    let member = User(name: "member", role: .editor, passwordHash: "")
    let project = try WorksheetPath(["proj"])
    let sub = try WorksheetPath(["proj", "sub"])
    var board = try store.open(project, user: owner)
    _ = try store.open(sub, user: owner)
    _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "grant", value: member.name), user: owner, unlocks: [])
    try Data("jegyzet".utf8).write(to: root.appendingPathComponent("proj/sub/note.txt"))
    try Data("ékezet".utf8).write(to: root.appendingPathComponent("proj/sub/árvíztűrő.txt"))
    try FileManager.default.createDirectory(at: root.appendingPathComponent("proj/w.web"), withIntermediateDirectories: true)
    try Data("<title>web</title>".utf8).write(to: root.appendingPathComponent("proj/w.web/index.html"))
    try Data("cache".utf8).write(to: root.appendingPathComponent("proj/.proj.preview-v11.svg"))
    board.nodes = [
        Idea(id: "tosub", text: "Allap", position: Point(x: 0, y: 0), link: NodeLink(kind: .sheet, target: "/proj/sub")),
        Idea(id: "toweb", text: "Web", position: Point(x: 0, y: 200), link: NodeLink(kind: .web, target: "w.web")),
    ]
    _ = try store.update(project, worksheet: board, user: owner)
    let subSheet = try store.load(sub, user: owner)
    #expect(subSheet.nodes.contains { $0.file?.filename == "note.txt" })

    // Export: a teljes projekt, rejtett gyorsítótár és hash nélkül.
    let zip = try store.exportPackage(project, options: PackageExportRequest(), user: member, unlocks: [])
    let listed = try entries(zip)
    #expect(listed.isSuperset(of: ["proj/proj.thnode", "proj/.settings.json", "proj/sub/sub.thnode", "proj/sub/note.txt", "proj/w.web/index.html"]))
    #expect(!listed.contains("proj/.proj.preview-v11.svg"))
    let bytes = try Data(contentsOf: zip)
    try FileManager.default.removeItem(at: zip)
    #expect(throws: Abort.self) { try store.exportPackage(project, options: PackageExportRequest(), user: nil, unlocks: []) }

    // Import új projektként.
    let report = try store.uploadPackage(bytes, target: nil, user: member, unlocks: [])
    #expect(report.name == "proj-2" && report.sheets == 2 && !report.needsPassword)
    #expect(report.editors?.map(\.name) == ["owner"])
    let copy = try store.commitPackage(PackageCommit(token: report.token, name: "masolat", editors: ["owner": "owner"]), user: member, unlocks: [])
    #expect(copy.url == "masolat")
    let copied = try store.load(copy, user: member)
    #expect(copied.creator == "member" && copied.revision == 1)
    #expect(copied.nodes.first { $0.id == "tosub" }?.link?.target == "sub")
    #expect(copied.nodes.first { $0.id == "toweb" }?.link?.target == "w.web")
    let copiedSub = try store.load(try WorksheetPath(["masolat", "sub"]), user: member)
    #expect(copiedSub.nodes.contains { $0.file?.filename == "note.txt" })
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("masolat/sub/árvíztűrő.txt").path))
    #expect(try store.load(copy, user: owner).title == copied.title)
    let settings = try String(contentsOf: root.appendingPathComponent("masolat/.settings.json"), encoding: .utf8)
    #expect(settings.contains("\"owner\" : \"member\"") && settings.contains("\"owner\"\n"))

    // Import allapként egy másik projekt lapja alá.
    let nested = try store.uploadPackage(bytes, target: try WorksheetPath(["masolat", "sub"]), user: member, unlocks: [])
    #expect(nested.target == "sheet" && nested.editors == nil)
    // „web” nevű allap nem hivatkozhat .web prezentációra: érthető hiba, a csomag érintetlen marad, más névvel mehet.
    #expect(throws: Abort.self) { try store.commitPackage(PackageCommit(token: nested.token, name: "web"), user: member, unlocks: []) }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("masolat/sub/web").path))
    let placed = try store.commitPackage(PackageCommit(token: nested.token, name: "belso"), user: member, unlocks: [])
    #expect(placed.parts == ["masolat", "sub", "belso"])
    let inner = try store.load(placed, user: member)
    #expect(inner.nodes.first { $0.id == "toweb" }?.link?.target == "sub/belso/w.web")
    #expect(inner.nodes.first { $0.id == "tosub" }?.link?.target == "sub")
    #expect(try store.load(try WorksheetPath(["masolat", "sub", "belso", "sub"]), user: member).nodes.contains { $0.file?.filename == "note.txt" })
    let innerSettings = try String(contentsOf: root.appendingPathComponent("masolat/sub/belso/.settings.json"), encoding: .utf8)
    #expect(!innerSettings.contains("owner") && !innerSettings.contains("passwordHash"))
}

@Test func protectedProjectsExportOnlyEncrypted() throws {
    let (store, root) = try makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let owner = User(name: "owner", role: .editor, passwordHash: "")
    let project = try WorksheetPath(["titok"])
    _ = try store.open(project, user: owner)
    _ = try store.manage(project, operation: DocumentAction(scope: "project", action: "password", value: "projekt-jelszo-1"), user: owner, unlocks: [])
    #expect(throws: Abort.self) { try store.exportPackage(project, options: PackageExportRequest(), user: owner, unlocks: []) }
    #expect(throws: Abort.self) { try store.exportPackage(project, options: PackageExportRequest(password: "projekt-jelszo-1"), user: owner, unlocks: []) }
    #expect(throws: Abort.self) { try store.exportPackage(project, options: PackageExportRequest(password: "rovid"), user: owner, unlocks: []) }
    let zip = try store.exportPackage(project, options: PackageExportRequest(password: "csomag-jelszo-99"), user: owner, unlocks: [])
    #expect(try entries(zip) == [PackageCrypto.headerName, PackageCrypto.contentName])
    let bytes = try Data(contentsOf: zip)
    try FileManager.default.removeItem(at: zip)
    #expect(!String(decoding: bytes, as: UTF8.self).contains("$2b$"))

    let report = try store.uploadPackage(bytes, target: nil, user: owner, unlocks: [])
    #expect(report.needsPassword)
    #expect(throws: Abort.self) { try store.unlockPackage(PackageUnlock(token: report.token, password: "rossz-jelszo-123"), user: owner, unlocks: []) }
    #expect(throws: Abort.self) { try store.commitPackage(PackageCommit(token: report.token, name: "uj"), user: owner, unlocks: []) }
    let opened = try store.unlockPackage(PackageUnlock(token: report.token, password: "csomag-jelszo-99"), user: owner, unlocks: [])
    #expect(opened.sheets == 1)
    let path = try store.commitPackage(PackageCommit(token: report.token, name: "uj", projectPassword: "uj-projekt-jelszo"), user: owner, unlocks: [])
    let other = User(name: "member", role: .editor, passwordHash: "")
    _ = try store.manage(path, operation: DocumentAction(scope: "project", action: "grant", value: other.name), user: owner, unlocks: [])
    #expect(throws: Abort.self) { try store.load(path, user: other) }
    let keys = Set(try store.unlock(path, password: "uj-projekt-jelszo", user: other))
    #expect(try store.load(path, user: other, unlocks: keys).title == "titok")
}

@Test func packageImportRejectsNewerSchemaAndForeignZips() throws {
    let (store, root) = try makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let owner = User(name: "owner", role: .editor, passwordHash: "")
    let work = root.appendingPathComponent("work-\(UUID())")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    func zip(_ items: [(String, String)]) throws -> Data {
        let url = work.appendingPathComponent(UUID().uuidString + ".zip")
        try ZipWriter.write(items.map { ZipWriter.Entry(path: $0.0, source: .data(Data($0.1.utf8))) }, to: url)
        return try Data(contentsOf: url)
    }
    let future = try zip([("jovo/jovo.thnode", #"{"schemaVersion":99,"title":"Jövő","nodes":[],"edges":[]}"#)])
    #expect(throws: Abort.self) { try store.uploadPackage(future, target: nil, user: owner, unlocks: []) }
    let foreign = try zip([("valami/index.html", "<p>x</p>")])
    #expect(throws: Abort.self) { try store.uploadPackage(foreign, target: nil, user: owner, unlocks: []) }
    #expect(throws: Abort.self) { try store.uploadPackage(future, target: nil, user: User(name: "vendeg", role: .guest, passwordHash: ""), unlocks: []) }
    // Kézzel csomagolt, mappa nélküli lap (régi, 2-es sémával) importálható.
    let flat = try zip([("regi.thnode", #"{"schemaVersion":2,"revision":7,"title":"Régi","nodes":[],"edges":[]}"#)])
    let report = try store.uploadPackage(flat, target: nil, user: owner, unlocks: [])
    #expect(report.name == "regi")
    let path = try store.commitPackage(PackageCommit(token: report.token, name: "regi"), user: owner, unlocks: [])
    let sheet = try store.load(path, user: owner)
    #expect(sheet.title == "Régi" && sheet.revision == 1 && sheet.schemaVersion == Worksheet.currentSchema)
}

/// Darabolt feltöltés: a darabok sorban fűződnek, megszakadás után a szerver megmondja, hol tart; a végén ugyanaz az
/// import készül elő, mint az egyben feltöltött csomagnál. A közvetlen letöltés csak a készítőjének jár.
@Test func packageUploadsInChunksAndResumes() async throws {
    let (store, root) = try makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let password = UUID().uuidString
    try store.setUser(name: "owner", role: .editor, passwordHash: try Bcrypt.hash(password, cost: 4))
    let owner = User(name: "owner", role: .editor, passwordHash: ""), member = User(name: "member", role: .editor, passwordHash: "")
    let project = try WorksheetPath(["darabolt"])
    _ = try store.open(project, user: owner)
    try Data(repeating: 7, count: 300_000).write(to: root.appendingPathComponent("darabolt/nagy.bin"))
    _ = try store.load(project, user: owner)
    let zip = try store.exportPackage(project, options: PackageExportRequest(), user: owner, unlocks: [])
    let bytes = try Data(contentsOf: zip)

    // Tároló: munkamenet, darabok, rossz folytatási pont, más felhasználó, folytatás.
    #expect(throws: Abort.self) { try store.beginPackageUpload(size: 0, target: nil, user: owner, unlocks: []) }
    #expect(throws: Abort.self) { try store.beginPackageUpload(size: Int64(WorksheetStore.maximumPackage) + 1, target: nil, user: owner, unlocks: []) }
    #expect(throws: Abort.self) { try store.beginPackageUpload(size: 10, target: nil, user: nil, unlocks: []) }
    let session = try store.beginPackageUpload(size: Int64(bytes.count), target: nil, user: owner, unlocks: [])
    #expect(session.received == 0 && session.chunk == WorksheetStore.packageChunk)
    let half = bytes.count / 2
    #expect(throws: Abort.self) { try store.appendPackageUpload(session.id, offset: 0, bytes: Data("nem zip".utf8), user: owner) }
    #expect(try store.appendPackageUpload(session.id, offset: 0, bytes: bytes.prefix(half), user: owner).received == Int64(half))
    #expect(throws: Abort.self) { try store.appendPackageUpload(session.id, offset: 0, bytes: bytes.prefix(half), user: owner) }
    #expect(throws: Abort.self) { try store.appendPackageUpload(session.id, offset: Int64(half), bytes: bytes.suffix(from: half), user: member) }
    #expect(throws: Abort.self) { try store.finishPackageUpload(session.id, user: owner, unlocks: []) }
    // Megszakadás után: az állapot lekérdezése (az újraindításkori takarítás a félbemaradt feltöltést megtartja).
    store.cleanPackageStaging(all: true)
    #expect(try store.packageUploadState(session.id, user: owner).received == Int64(half))
    #expect(throws: Abort.self) { try store.appendPackageUpload(session.id, offset: Int64(half), bytes: bytes.suffix(from: half) + Data([0]), user: owner) }
    #expect(try store.appendPackageUpload(session.id, offset: Int64(half), bytes: bytes.suffix(from: half), user: owner).received == Int64(bytes.count))
    let report = try store.finishPackageUpload(session.id, user: owner, unlocks: [])
    #expect(report.sheets == 1 && !report.needsPassword)
    #expect(throws: Abort.self) { try store.packageUploadState(session.id, user: owner) }
    let copy = try store.commitPackage(PackageCommit(token: report.token, name: "masolat"), user: owner, unlocks: [])
    #expect(try Data(contentsOf: root.appendingPathComponent("masolat/nagy.bin")).count == 300_000)
    #expect(copy.url == "masolat")

    // Megszakítás: a munkamenet eltűnik.
    let dropped = try store.beginPackageUpload(size: Int64(bytes.count), target: nil, user: owner, unlocks: [])
    try store.cancelPackageUpload(dropped.id, user: owner)
    #expect(throws: Abort.self) { try store.packageUploadState(dropped.id, user: owner) }

    // HTTP: előkészített letöltés (részleges kéréssel is), és feltöltés darabokban.
    try await withApp(configure: { app in configure(app, store: store, secureCookies: false) }) { app in
        let browser = try app.testing()
        let login = try await login(browser, name: "owner", password: password, path: "darabolt")
        let headers: HTTPHeaders = ["Cookie": login.cookie, "X-CSRF-Token": login.csrf, "Content-Type": "application/json"]
        struct Prepared: Content { let url: String; let name: String; let size: Int64 }
        let prepared = try await browser.sendRequest(.POST, "/api/package/export/darabolt?prepare=1", headers: headers) { request in
            try request.content.encode(PackageExportRequest())
        }
        #expect(prepared.status == .ok)
        let link = try prepared.content.decode(Prepared.self)
        #expect(link.size == Int64(bytes.count) && link.name == "darabolt.zip")
        let whole = try await browser.sendRequest(.GET, link.url, headers: ["Cookie": login.cookie])
        #expect(whole.status == .ok && whole.body.readableBytes == bytes.count)
        #expect(whole.headers.first(name: .contentDisposition)?.contains("darabolt.zip") == true)
        let tail = try await browser.sendRequest(.GET, link.url, headers: ["Cookie": login.cookie, "Range": "bytes=\(bytes.count - 100)-"])
        #expect(tail.status == .partialContent && tail.body.readableBytes == 100)
        #expect(try await browser.sendRequest(.GET, link.url).status != .ok)

        struct Begin: Content { let size: Int64; let target: String? }
        let begun = try await browser.sendRequest(.POST, "/api/package/uploads", headers: headers) { request in
            try request.content.encode(Begin(size: Int64(bytes.count), target: nil))
        }
        let state = try begun.content.decode(WorksheetStore.PackageUploadState.self)
        let binary: HTTPHeaders = ["Cookie": login.cookie, "X-CSRF-Token": login.csrf, "Content-Type": "application/octet-stream"]
        let first = try await browser.sendRequest(.PUT, "/api/package/uploads/\(state.id)?offset=0", headers: binary, body: ByteBuffer(data: bytes.prefix(half)))
        #expect(first.status == .ok)
        // Ugyanaz a darab még egyszer (a kliens nem kapta meg a választ): 409 és a tényleges állás.
        let repeated = try await browser.sendRequest(.PUT, "/api/package/uploads/\(state.id)?offset=0", headers: binary, body: ByteBuffer(data: bytes.prefix(half)))
        #expect(repeated.status == .conflict && repeated.headers.first(name: "X-ThinkNodes-Received") == String(half))
        let status = try await browser.sendRequest(.GET, "/api/package/uploads/\(state.id)", headers: ["Cookie": login.cookie])
        #expect(try status.content.decode(WorksheetStore.PackageUploadState.self).received == Int64(half))
        let second = try await browser.sendRequest(.PUT, "/api/package/uploads/\(state.id)?offset=\(half)", headers: binary, body: ByteBuffer(data: bytes.suffix(from: half)))
        #expect(second.status == .ok)
        let finished = try await browser.sendRequest(.POST, "/api/package/uploads/\(state.id)/finish", headers: headers)
        #expect(finished.status == .ok)
        #expect(try finished.content.decode(PackageReport.self).sheets == 1)
    }
}
