import Foundation
import Testing
import VaporTesting
@testable import ThinkCore
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
    // Meghívni csak a projekt létrehozója és az admin tud: a meghívott szerkesztő nem hívhat és nem távolíthat el mást.
    try store.setUser(name: "third", role: .editor, passwordHash: "unused")
    try store.setUser(name: "visitor", role: .guest, passwordHash: "unused")
    func membership(_ action: String, _ name: String, by user: User) throws {
        _ = try store.manage(project, operation: DocumentAction(scope: "project", action: action, value: name), user: user, unlocks: [])
    }
    #expect(throws: Abort.self) { try membership("grant", "third", by: editor) }
    #expect(throws: Abort.self) { try membership("revoke", editor.name, by: editor) }
    #expect(try !store.access(project, sheet: worksheet, user: editor).invitable)
    #expect(try store.access(project, sheet: worksheet, user: editor).manageable)
    #expect(try store.access(project, sheet: worksheet, user: creator).invitable)
    // Szerkesztő szerepkört csak admin ad: vendég fiók nem hívható meg szerkesztőnek.
    #expect(throws: Abort.self) { try membership("grant", "visitor", by: creator) }
    try membership("grant", "third", by: creator)
    try membership("revoke", "third", by: User(name: "admin", role: .admin, passwordHash: ""))
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

// Google-bejelentkezés: a tesztben a „code” maga az ID token, a kódbeváltás (a Google token-végpontja) helyett.

private func googleToken(_ claims: [String: Any]) throws -> String {
    let payload = try JSONSerialization.data(withJSONObject: claims)
    return "e30." + GoogleSignIn.base64URL(payload) + ".alairas"
}

private func queryValue(_ name: String, in url: String) -> String? {
    URLComponents(string: url)?.queryItems?.first { $0.name == name }?.value
}

@Test func googleSignInOpensTheLinkedAccount() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-google-\(UUID().uuidString)")
    let store = try WorksheetStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }
    try store.setUser(name: "admin", role: .admin, passwordHash: try Bcrypt.hash("titkos-jelszo"))
    // Jelszó nélküli fiók csak Google-fiókkal jöhet létre; egy Google-fiók egy felhasználóhoz tartozhat.
    #expect(throws: Abort.self) { try store.setUser(name: "anna", role: .editor, passwordHash: nil) }
    try store.setUser(name: "anna", role: .editor, passwordHash: nil, google: " Anna@Example.com ")
    #expect(try store.user(named: "anna")?.google == "anna@example.com")
    #expect(throws: Abort.self) { try store.setUser(name: "admin", role: .admin, passwordHash: nil, google: "anna@example.com") }
    #expect(throws: Abort.self) { try store.setUser(name: "admin", role: .admin, passwordHash: nil, google: "nem e-mail") }
    // A hozzárendelés megmarad, ha a hívó nem nyúl hozzá (pl. szerepkörváltás).
    try store.setUser(name: "anna", role: .guest, passwordHash: nil)
    #expect(try store.user(google: "ANNA@example.com")?.role == .guest)

    let google = GoogleSignIn(clientID: "kliens.apps.googleusercontent.com", clientSecret: "titok") { _, form in
        #expect(form["client_secret"] == "titok")
        #expect(form["redirect_uri"] == "http://localhost:8080/login/google/callback")
        #expect(form["code_verifier"]?.isEmpty == false)
        return form["code"] ?? ""
    }
    let host: HTTPHeaders = ["Host": "localhost:8080"]

    try await withApp(configure: { app in configure(app, store: store, secureCookies: false, google: google) }) { app in
        let browser = try app.testing()
        #expect(try await browser.sendRequest(.GET, "/login").body.string.contains("/login/google?next="))

        func start(next: String = "/") async throws -> (cookie: String, state: String, nonce: String) {
            let started = try await browser.sendRequest(.GET, "/login/google?next=" + next, headers: host)
            #expect(started.status == .seeOther)
            let location = try #require(started.headers.first(name: .location))
            #expect(location.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth?"))
            #expect(queryValue("client_id", in: location) == google.clientID)
            #expect(queryValue("redirect_uri", in: location) == "http://localhost:8080/login/google/callback")
            #expect(queryValue("code_challenge_method", in: location) == "S256")
            return (try cookie(started), try #require(queryValue("state", in: location)), try #require(queryValue("nonce", in: location)))
        }
        func finish(_ flow: (cookie: String, state: String, nonce: String), claims: [String: Any], state: String? = nil) async throws -> TestingHTTPResponse {
            var headers = host
            headers.add(name: "Cookie", value: flow.cookie)
            return try await browser.sendRequest(.GET, "/login/google/callback?state=\(state ?? flow.state)&code=\(try googleToken(claims))", headers: headers)
        }
        func claims(_ nonce: String, email: String = "Anna@example.com") -> [String: Any] {
            ["iss": "https://accounts.google.com", "aud": google.clientID, "exp": Date().timeIntervalSince1970 + 600,
             "nonce": nonce, "email": email, "email_verified": true]
        }

        // Sikeres belépés: új munkamenet, a kért oldalra jut.
        var flow = try await start(next: "/admin")
        let signedIn = try await finish(flow, claims: claims(flow.nonce))
        #expect(signedIn.status == .seeOther)
        #expect(signedIn.headers.first(name: .location) == "/admin")
        let session = try cookie(signedIn)
        #expect(session != flow.cookie)
        #expect(try await browser.sendRequest(.GET, "/admin", headers: ["Cookie": session]).status == .forbidden)
        // A kód nem váltható be újra ugyanazzal a state értékkel.
        #expect(try await finish(flow, claims: claims(flow.nonce)).status == .unauthorized)

        // Hibás state, nonce, címzett, lejárt token, nem igazolt cím, ismeretlen fiók: nincs belépés.
        flow = try await start()
        #expect(try await finish(flow, claims: claims(flow.nonce), state: "hamis").status == .unauthorized)
        var rejected: [[String: Any]] = []
        flow = try await start()
        rejected.append(claims("masik-nonce"))
        for (key, value) in [("aud", "idegen-kliens" as Any), ("exp", Date().timeIntervalSince1970 - 5), ("email_verified", false), ("iss", "https://evil.example")] {
            var changed = claims("NONCE")
            changed[key] = value
            rejected.append(changed)
        }
        for var item in rejected {
            flow = try await start()
            if item["nonce"] as? String == "NONCE" { item["nonce"] = flow.nonce }
            #expect(try await finish(flow, claims: item).status == .unauthorized)
        }
        flow = try await start()
        let unknown = try await finish(flow, claims: claims(flow.nonce, email: "idegen@example.com"))
        #expect(unknown.status == .unauthorized)
        #expect(unknown.body.string.contains("idegen@example.com"))

        // A Google-fiók leválasztása a Google-lal indult munkamenetet is lezárja.
        try store.setUser(name: "anna", role: .guest, passwordHash: nil, google: .some(nil))
        #expect(try await browser.sendRequest(.GET, "/admin", headers: ["Cookie": session]).status == .seeOther)
    }

    // Beállítás nélkül nincs Google-gomb és útvonal.
    try await withApp(configure: { app in configure(app, store: store, secureCookies: false) }) { app in
        let browser = try app.testing()
        #expect(try await !browser.sendRequest(.GET, "/login").body.string.contains("/login/google"))
        #expect(try await browser.sendRequest(.GET, "/login/google").status != .seeOther)
    }
}

@Test func unknownGoogleAccountCanRequestAccess() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("thinknodes-google-request-\(UUID().uuidString)")
    let store = try WorksheetStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }
    try store.setUser(name: "admin", role: .admin, passwordHash: try Bcrypt.hash("titkos-jelszo"))
    try store.setUser(name: "regi", role: .editor, passwordHash: "unused")

    // Tároló: kikapcsolva senki nem kérhet; domainszűrés; címenként egy kérelem; lejárat; elutasítás és feloldás.
    #expect(try store.accessRequestState(email: "uj@ceg.hu") == .closed)
    #expect(throws: Abort.self) { try store.requestAccess(email: "uj@ceg.hu", name: "uj") }
    #expect(throws: Abort.self) { try GoogleAccess.domains(from: "nem domain!") }
    try store.setSettings(SiteSettings(googleAccess: GoogleAccess(requests: true, domains: try GoogleAccess.domains(from: "@Ceg.hu, masik.com"))))
    #expect(try store.settings().googleAccess?.domains == ["ceg.hu", "masik.com"])
    #expect(try store.accessRequestState(email: "valaki@idegen.org") == .closed)
    #expect(try store.accessRequestState(email: "Uj@Ceg.hu") == .open)
    #expect(throws: Abort.self) { try store.requestAccess(email: "uj@ceg.hu", name: "admin") }
    #expect(throws: Abort.self) { try store.requestAccess(email: "uj@ceg.hu", name: "Rossz Név") }
    let old = Date(timeIntervalSinceNow: -31 * 24 * 3600)
    try store.requestAccess(email: "uj@ceg.hu", name: "elso", now: old)
    #expect(try store.accessRequests().pending.isEmpty)
    #expect(try store.accessRequests(now: old).pending.map(\.name) == ["elso"])
    try store.requestAccess(email: "uj@ceg.hu", name: "elso")
    try store.requestAccess(email: "uj@ceg.hu", name: "uj")
    #expect(try store.accessRequests().pending.map(\.name) == ["uj"])
    // A beállítások mentése (Google-mezők nélkül) nem törli sem a szabályt, sem a kérelmeket.
    try store.setSettings(SiteSettings(requireLogin: false))
    #expect(try store.settings().googleAccess?.requests == true)
    #expect(try store.accessRequests().pending.count == 1)
    try store.rejectAccess(email: "uj@ceg.hu")
    #expect(try store.accessRequestState(email: "uj@ceg.hu") == .rejected)
    #expect(throws: Abort.self) { try store.requestAccess(email: "uj@ceg.hu", name: "uj") }
    #expect(throws: Abort.self) { try store.approveAccess(email: "uj@ceg.hu", name: "uj", role: .guest) }
    try store.forgetRejectedAccess(email: "uj@ceg.hu")
    #expect(try store.accessRequestState(email: "uj@ceg.hu") == .open)
    // Meglévő, Google-fiók nélküli felhasználó nevével jóváhagyva a cím hozzá kapcsolódik, a szerepköre marad.
    try store.requestAccess(email: "regi@masik.com", name: "valami")
    try store.approveAccess(email: "regi@masik.com", name: "regi", role: .guest)
    #expect(try store.user(google: "regi@masik.com")?.role == .editor)
    #expect(try store.accessRequests().pending.isEmpty)
    // Kézi hozzárendelés a függő kérelmet is lezárja.
    try store.requestAccess(email: "kezi@ceg.hu", name: "kezi")
    try store.setUser(name: "kezi", role: .guest, passwordHash: nil, google: "kezi@ceg.hu")
    #expect(try store.accessRequests().pending.isEmpty)

    let google = GoogleSignIn(clientID: "kliens", clientSecret: "titok") { _, form in form["code"] ?? "" }
    let host: HTTPHeaders = ["Host": "localhost:8080"]
    try await withApp(configure: { app in configure(app, store: store, secureCookies: false, google: google) }) { app in
        let browser = try app.testing()
        func signIn(_ email: String) async throws -> (response: TestingHTTPResponse, cookie: String) {
            let started = try await browser.sendRequest(.GET, "/login/google", headers: host)
            let location = try #require(started.headers.first(name: .location))
            let session = try cookie(started)
            let token = try googleToken(["iss": "https://accounts.google.com", "aud": "kliens", "exp": Date().timeIntervalSince1970 + 600,
                                         "nonce": try #require(queryValue("nonce", in: location)), "email": email, "email_verified": true])
            var headers = host
            headers.add(name: "Cookie", value: session)
            let done = try await browser.sendRequest(.GET, "/login/google/callback?state=\(try #require(queryValue("state", in: location)))&code=\(token)", headers: headers)
            return (done, (try? cookie(done)) ?? session)
        }
        // Kérelem oldal csak a Google-től visszatért munkamenetben van.
        #expect(try await browser.sendRequest(.GET, "/login/request").headers.first(name: .location) == "/login")
        #expect(try await signIn("valaki@idegen.org").response.status == .unauthorized)

        let visitor = try await signIn("Anna.Kis@ceg.hu")
        #expect(visitor.response.headers.first(name: .location) == "/login/request")
        let page = try await browser.sendRequest(.GET, "/login/request", headers: ["Cookie": visitor.cookie])
        #expect(page.body.string.contains("anna.kis@ceg.hu"))
        #expect(page.body.string.contains(#"value="anna-kis""#))
        let csrf = try attribute("name=\"csrf\" value=\"", in: page.body.string)
        struct RequestForm: Content { var name: String; var csrf: String }
        func submit(_ name: String, csrf: String) async throws -> TestingHTTPResponse {
            try await browser.sendRequest(.POST, "/login/request", headers: ["Cookie": visitor.cookie]) { request in
                try request.content.encode(RequestForm(name: name, csrf: csrf), as: .urlEncodedForm)
            }
        }
        #expect(try await submit("anna", csrf: "hamis").status == .forbidden)
        let taken = try await submit("admin", csrf: csrf)
        #expect(taken.status == .unprocessableEntity)
        #expect(taken.body.string.contains("foglalt"))
        #expect(try await submit("anna", csrf: csrf).status == .seeOther)
        #expect(try await browser.sendRequest(.GET, "/login/request", headers: ["Cookie": visitor.cookie]).body.string.contains("elbírálásra vár"))
        // A kérelem önmagában nem ad hozzáférést.
        #expect(try await browser.sendRequest(.GET, "/admin", headers: ["Cookie": visitor.cookie]).status == .seeOther)

        // Az admin látja és jóváhagyja; utána a Google-belépés sikerül.
        _ = try store.open(try WorksheetPath(["main"]), user: User(name: "admin", role: .admin, passwordHash: ""))
        let admin = try await login(browser, name: "admin", password: "titkos-jelszo", path: "main")
        let adminPage = try await browser.sendRequest(.GET, "/admin", headers: ["Cookie": admin.cookie])
        #expect(adminPage.body.string.contains("Hozzáférési kérelmek (1)"))
        #expect(adminPage.body.string.contains("anna.kis@ceg.hu"))
        // Adminisztrátori jelzés: jelvény a fejléc Admin gombján (minden oldalon) és teendőlista az adminoldalon.
        #expect(try store.adminMessages() == [AdminMessage(kind: .accessRequests, count: 1, text: "1 hozzáférési kérelem vár elbírálásra", link: "/admin#access-requests")])
        #expect(adminPage.body.string.contains(#"id="admin-messages""#))
        let index = try await browser.sendRequest(.GET, "/", headers: ["Cookie": admin.cookie])
        #expect(index.body.string.contains(#"href="/admin#admin-messages""#))
        #expect(index.body.string.contains("admin-badge"))
        #expect(try await !browser.sendRequest(.GET, "/", headers: ["Cookie": visitor.cookie]).body.string.contains("admin-badge"))
        struct Decision: Content { var email: String; var name: String?; var role: String?; var action: String; var csrf: String }
        func decide(_ decision: Decision, cookie: String) async throws -> HTTPStatus {
            try await browser.sendRequest(.POST, "/admin/requests", headers: ["Cookie": cookie]) { request in
                try request.content.encode(decision, as: .urlEncodedForm)
            }.status
        }
        #expect(try await decide(Decision(email: "anna.kis@ceg.hu", name: "anna", role: "admin", action: "approve", csrf: csrf), cookie: visitor.cookie) == .unauthorized)
        #expect(try await decide(Decision(email: "anna.kis@ceg.hu", name: "anna", role: "editor", action: "approve", csrf: admin.csrf), cookie: admin.cookie) == .seeOther)
        #expect(try store.user(named: "anna")?.role == .editor)
        #expect(try store.adminMessages().isEmpty)
        #expect(try await !browser.sendRequest(.GET, "/", headers: ["Cookie": admin.cookie]).body.string.contains("admin-badge"))
        #expect(try await browser.sendRequest(.GET, "/login/request", headers: ["Cookie": visitor.cookie]).headers.first(name: .location) == "/login/google")
        #expect(try await signIn("anna.kis@ceg.hu").response.headers.first(name: .location) == "/")

        // Elutasítás: a cím nem kérhet újra, amíg az admin fel nem oldja.
        let other = try await signIn("bela@ceg.hu")
        #expect(other.response.headers.first(name: .location) == "/login/request")
        try store.requestAccess(email: "bela@ceg.hu", name: "bela")
        #expect(try await decide(Decision(email: "bela@ceg.hu", action: "reject", csrf: admin.csrf), cookie: admin.cookie) == .seeOther)
        #expect(try await browser.sendRequest(.GET, "/login/request", headers: ["Cookie": other.cookie]).body.string.contains("elutasította"))
        #expect(try await decide(Decision(email: "bela@ceg.hu", action: "forget", csrf: admin.csrf), cookie: admin.cookie) == .seeOther)
        #expect(try store.accessRequestState(email: "bela@ceg.hu") == .open)

        // Az adminoldal beállítása: kikapcsolva az ismeretlen fiók újra csak elutasítást kap.
        struct Settings: Content { var googleDomains: String; var csrf: String }
        let saved = try await browser.sendRequest(.POST, "/admin/settings", headers: ["Cookie": admin.cookie]) { request in
            try request.content.encode(Settings(googleDomains: "ceg.hu", csrf: admin.csrf), as: .urlEncodedForm)
        }
        #expect(saved.status == .seeOther)
        #expect(try store.settings().googleAccess == GoogleAccess(requests: false, domains: ["ceg.hu"]))
        #expect(try await signIn("bela@ceg.hu").response.status == .unauthorized)
    }
}
