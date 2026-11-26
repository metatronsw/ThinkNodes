import Foundation
import ThinkCore
import NIOSSL
import Vapor

@main
enum ThinkNodes {
    static func main() async {
        do {
            try await run()
        } catch {
            let description = (error as? any AbortError)?.reason ?? String(describing: error)
            FileHandle.standardError.write(Data(("thinknodes: " + description + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let options: LaunchOptions
        do {
            options = try LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
        } catch let problem as LaunchOptions.Problem {
            throw Abort(.badRequest, reason: problem.description)
        }
        if options.command == .help {
            print(LaunchOptions.help)
            return
        }
        // A relatív alapértékek (Public, ../projects, .thinknodes-tls) a szerver mappájához képest értendők.
        ServerFolder.enter()
        let dataFolder = URL(fileURLWithPath: options.project, isDirectory: true)
        warnIfNewDataFolder(dataFolder)
        let store = try WorksheetStore(root: dataFolder, testMode: options.test)
        if case let .user(name, role) = options.command {
            try addUser(name: name, role: role, store: store)
            return
        }

        let port = options.effectivePort
        let addresses = NetworkAddresses.list(bindHost: options.host)
        var tls: TLSConfiguration?
        if !options.http {
            let certificate: String, key: String
            if let own = options.tlsCertificate, let ownKey = options.tlsKey {
                (certificate, key) = (own, ownKey)
            } else {
                let files = try LANCertificate.prepare(directory: options.tlsDirectory, addresses: addresses)
                (certificate, key) = (files.certificate, files.key)
                print("Trust this root certificate on client devices: \(files.authority)")
            }
            let chain = try NIOSSLCertificate.fromPEMFile(certificate)
            guard !chain.isEmpty else { throw Abort(.internalServerError, reason: "Empty TLS certificate chain: \(certificate)") }
            let configuration = TLSConfiguration.makeServerConfiguration(
                certificateChain: chain.map { .certificate($0) },
                privateKey: .privateKey(try NIOSSLPrivateKey(file: key, format: .pem))
            )
            _ = try NIOSSLContext(configuration: configuration)
            tls = configuration
        }
        print("Data folder: \(store.dataDirectoryPath)")
        if options.test {
            print("Test mode: every connecting browser gets admin rights.")
        } else if try store.allUsers().isEmpty {
            // Új (üres) adatmappa: a korábbi fiókok a régi mappa .settings.json fájljában maradtak.
            let scheme = options.http ? "http" : "https"
            print("""
                No accounts in this data folder yet, so nobody can sign in. Create the first admin with
                  ./run.sh user NAME admin --project:\(store.dataDirectoryPath)
                or open \(scheme)://localhost:\(port)/admin in a browser on this machine.
                """)
        }
        let google = options.test ? nil : GoogleSignIn.fromEnvironment()
        if google != nil { print("Google sign-in: enabled (callback path \(GoogleSignIn.callbackPath))") }
        for address in addresses {
            print("\(options.http ? "HTTP" : "HTTPS"): \(NetworkAddresses.url(scheme: options.http ? "http" : "https", address: address, port: port))")
        }

        let command = [CommandLine.arguments[0], "serve", "--hostname", options.host, "--port", String(port)] + options.vapor
        var environment = try Environment.detect(arguments: command)
        try LoggingSystem.bootstrap(from: &environment)
        let app = try await Application.make(environment)
        do {
            app.http.server.configuration.tlsConfiguration = tls
            // Tömörített válaszok a szöveges típusokra (HTML, JS, CSS, JSON, SVG): a szerkesztő első betöltése
            // tömörítés nélkül kb. 1 MB; a képek és más, eleve tömörített fájlok változatlanul mennek.
            app.http.server.configuration.responseCompression = .enabledForCompressibleTypes
            store.reconcileAtStartup()
            store.cleanPackageStaging(all: true)
            configure(app, store: store, motionRate: options.rate, google: google)
            try await app.execute()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// A nem létező adatmappát a tároló csendben létrehozza; egy elírt `--project:` így üres mappát nyitna
    /// (fiókok és projektek nélkül). Indításkor ezt jelezzük, és megmutatjuk a közelben lévő valódi adatmappákat.
    private static func warnIfNewDataFolder(_ folder: URL) {
        let files = FileManager.default
        var isDirectory: ObjCBool = false
        guard !files.fileExists(atPath: folder.path, isDirectory: &isDirectory) else { return }
        print("Data folder does not exist yet, creating a new, empty one: \(folder.path)")
        // Testvérmappák, amelyekben már van .settings.json (pl. ThinkProject helyett ThinkProjects).
        let parent = folder.deletingLastPathComponent()
        let siblings = ((try? files.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { files.fileExists(atPath: $0.appendingPathComponent(".settings.json").path) }
            .map(\.path).sorted()
        if !siblings.isEmpty {
            print("Existing ThinkNodes data folders next to it (did you mean one of these?):")
            siblings.forEach { print("  \($0)") }
        }
    }

    private static func addUser(name: String, role rawRole: String, store: WorksheetStore) throws {
        guard validSlug(name), let role = Role(rawValue: rawRole),
              let password = readLine(), (8...72).contains(password.utf8.count) else {
            throw Abort(.badRequest, reason: "Usage: thinknodes user NAME admin|editor|guest (password on stdin, 8-72 bytes).")
        }
        let hash = try Bcrypt.hash(password)
        try store.setUser(name: name, role: role, passwordHash: hash)
        print("Account saved: \(name) (\(role.rawValue)) in \(store.dataDirectoryPath)")
    }
}

private struct LoginForm: Content {
    var name: String
    var password: String
    var csrf: String
    var next: String?
}

private struct MarkdownForm: Content {
    var text: String
    /// A forrás sorai pontosan (.md fájldoboz): markdownHTML(exactLines:).
    var lines: Bool?
}

private struct CanvasMarkdownRequest: Content {
    var sources: [String]
}

private struct CanvasMarkdownResponse: Content {
    var blocks: [[MarkdownBlock]]
}

private struct SessionInfo: Sendable {
    var user: User?
    var csrf: String?
    var unlocks: Set<String> = []

    func editor() throws -> User {
        guard let user else { throw Abort(.unauthorized, reason: "A szerkesztéshez jelentkezz be.") }
        return user
    }
}

private func authenticatedUser(_ data: SessionData, store: WorksheetStore) throws -> User? {
    if store.testMode, let name = data["tester"], isTesterName(name) {
        let settings = try store.settings()
        var tester = User(name: name, role: .admin, passwordHash: "", avatar: settings.preferences?[name]?.avatar)
        tester.color = settings.color(for: name)
        tester.adminMessages = try store.adminMessages().reduce(0) { $0 + $1.count }
        return tester
    }
    guard let name = data["user"], var user = try store.user(named: name),
          data["credential"] == user.passwordHash else { return nil }
    // Google-lal indult munkamenet: csak addig él, amíg ugyanaz a Google-fiók tartozik a felhasználóhoz.
    if let google = data["google"], google != user.google { return nil }
    // Adminnak: a fejléc jelvénye (hány jelzés vár).
    if user.role == .admin { user.adminMessages = try store.adminMessages().reduce(0) { $0 + $1.count } }
    return user
}

private func documentUnlocks(_ data: SessionData) -> Set<String> {
    Set((data["document-unlocks"] ?? "").split(separator: "\n").map(String.init))
}

private func session(_ req: Request, store: WorksheetStore) throws -> SessionInfo {
    guard req.hasSession, let user = try authenticatedUser(req.session.data, store: store) else {
        if req.hasSession && req.session.data["user"] != nil { req.session.data = .init() }
        if store.testMode {
            let name = store.nextTester()
            req.session.data["tester"] = name
            return SessionInfo(user: User(name: name, role: .admin, passwordHash: ""), csrf: token(req))
        }
        return SessionInfo(user: nil, csrf: nil, unlocks: req.hasSession ? documentUnlocks(req.session.data) : [])
    }
    return SessionInfo(user: user, csrf: token(req), unlocks: documentUnlocks(req.session.data))
}

private func token(_ req: Request) -> String {
    if let existing = req.session.data["csrf"] { return existing }
    let value = UUID().uuidString + UUID().uuidString
    req.session.data["csrf"] = value
    return value
}

private func verify(_ req: Request, token submitted: String?) throws {
    guard let submitted, submitted == req.session.data["csrf"] else {
        throw Abort(.forbidden, reason: "A munkamenet megváltozott. Nyisd meg újra a lapot.")
    }
}

private func redirect(_ destination: String) -> Response {
    Response(status: .seeOther, headers: ["Location": destination, "Cache-Control": "no-store"])
}

private func worksheetPath(_ raw: String) throws -> WorksheetPath {
    let value = raw.hasPrefix("/") ? raw.dropFirst() : raw[...]
    let parts = value.split(separator: "/", omittingEmptySubsequences: false).map {
        String($0).removingPercentEncoding ?? String($0)
    }
    return try WorksheetPath(parts)
}

private func safeNext(_ value: String?) -> String {
    guard let value, value.hasPrefix("/") else { return "/" }
    if value == "/admin" { return value }
    if let presentation = (try? WebPresentationRequest.candidates(value))?.first { return presentation.url }
    if value.hasPrefix("/edit/"), let path = try? worksheetPath(String(value.dropFirst(6))) {
        return "/edit/" + path.url
    }
    guard let path = try? worksheetPath(value) else { return "/" }
    return "/" + path.url
}

private func signIn(_ req: Request, user: User, google: String? = nil) async throws {
    if let oldID = req.session.id {
        try await req.application.sessions.driver.deleteSession(oldID, for: req).get()
        req.session.id = nil
    }
    req.session.data = .init()
    req.session.data["user"] = user.name
    req.session.data["credential"] = user.passwordHash
    req.session.data["google"] = google
    _ = token(req)
}

private let statusUpdatesScript = #"<script type="module" src="/status-updates.js"></script>"#

private func loginPage(_ req: Request, next: String, message: String? = nil, noAccounts: Bool = false,
                       google: Bool = false, updates: PageUpdates.Subscription? = nil) -> Response {
    let googleLogin = !google ? "" : """
        <div class="stack panel google-login">
          <a class="button" href="/login/google?next=\(encodeQuery(next))">\(uiIcon("login"))Belépés Google-fiókkal</a>
        </div>
        """
    let problem = message.map { "<p class=\"error\" role=\"alert\">\(escaped($0))</p>" } ?? ""
    // Üres adatmappa (pl. új --project:): senki nem tud belépni, amíg nincs fiók.
    let setup = !noAccounts ? "" : localSetup(req)
        ? "<p class=\"error\" role=\"status\">Ebben az adatmappában még nincs felhasználói fiók. Az első adminisztrátort az <a href=\"/admin\">Adminisztráció</a> oldalon hozhatod létre.</p>"
        : "<p class=\"error\" role=\"status\">Ebben az adatmappában még nincs felhasználói fiók. Az első adminisztrátort a szervergépen hozhatod létre: helyi böngészőből az /admin oldalon, vagy a <code>./run.sh user NÉV admin</code> paranccsal.</p>"
    return htmlPage(title: "Bejelentkezés", body: """
        \(siteHeader(user: nil, csrf: nil))
        <main class="shell narrow" data-page-status="login" data-watch-next="\(escaped(next))">
          <h1>Bejelentkezés</h1>
          \(setup)
          \(problem)
          <form method="post" action="/login" class="stack panel">
            \(csrfInput(token(req)))
            <input type="hidden" name="next" value="\(escaped(next))">
            <label>Felhasználónév<input name="name" autocomplete="username" required autofocus></label>
            <label>Jelszó<input name="password" type="password" autocomplete="current-password" required></label>
            <button class="button primary" type="submit">\(uiIcon("login"))Belépés</button>
          </form>
          \(googleLogin)
        </main>
        \(updates == nil ? "" : statusUpdatesScript)
        """, updates: updates)
}

/// Hozzáférés-kérés oldala: ismeretlen, de a Google által igazolt címmel belépett látogatónak.
private func accessRequestPage(_ req: Request, email: String, state: AccessRequestState, message: String? = nil,
                               name: String? = nil) -> Response {
    let problem = message.map { "<p class=\"error\" role=\"alert\">\(escaped($0))</p>" } ?? ""
    // Javasolt felhasználónév az e-mail-cím elejéből (kisbetű, szám, kötőjel).
    let local = email.split(separator: "@").first.map(String.init) ?? ""
    let suggested = String(local.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        .split(separator: "-").joined(separator: "-")
    let body: String
    switch state {
    case .pending(let request):
        body = "<p role=\"status\">A kérelmed (<strong>\(escaped(request.name))</strong>) elbírálásra vár. Ha az adminisztrátor jóváhagyta, a <a href=\"/login/google\">Google-fiókoddal</a> tudsz belépni.</p>"
    case .rejected:
        body = "<p class=\"error\" role=\"status\">A kérelmedet az adminisztrátor elutasította.</p>"
    case .closed:
        body = "<p class=\"error\" role=\"status\">Ezzel a Google-fiókkal nem kérhető hozzáférés.</p>"
    case .open:
        body = """
            <p>Ehhez a Google-fiókhoz még nem tartozik ThinkNodes-fiók. Kérhetsz hozzáférést; az adminisztrátor jóváhagyása után a Google-fiókoddal tudsz belépni.</p>
            <form method="post" action="/login/request" class="stack panel">
              \(csrfInput(token(req)))
              <label>Kért felhasználónév<input name="name" pattern="[a-z0-9-]+" maxlength="64" value="\(escaped(name ?? suggested))" required autofocus></label>
              <button class="button primary" type="submit">\(uiIcon("login"))Hozzáférés kérése</button>
            </form>
            """
    }
    return htmlPage(title: "Hozzáférés kérése", body: """
        \(siteHeader(user: nil, csrf: nil))
        <main class="shell narrow" data-page-status="access-request">
          <h1>Hozzáférés kérése</h1>
          <p class="muted">Google-fiók: \(escaped(email))</p>
          \(problem)
          \(body)
          <p><a href="/login">Vissza a bejelentkezéshez</a></p>
        </main>
        """)
}

private func missingPage(_ identity: SessionInfo, updates: PageUpdates.Subscription? = nil) -> Response {
    let account = identity.user?.role == .guest ? ""
        : identity.user == nil ? "<p><a href=\"/login\">Jelentkezz be</a> új oldal létrehozásához. Ha még nincs fiókod, kérj regisztrációt az adminisztrátortól.</p>"
        : "<p>A főoldalon az Új projekt gombbal hozhatsz létre oldalt.</p>"
    let page = htmlPage(title: "Az oldal nem létezik", body: """
        <main class="shell narrow" data-page-status="missing">
          <h1>Ez az oldal nem létezik</h1>
          <p><a href="/">Vissza a főoldalra</a></p>
          \(account)
        </main>
        \(updates == nil ? "" : statusUpdatesScript)
        """, updates: updates)
    page.status = .notFound
    return page
}

private func accessDeniedPage(_ identity: SessionInfo, updates: PageUpdates.Subscription) -> Response {
    let page = htmlPage(title: "Hozzáférés szükséges", body: """
        \(siteHeader(user: identity.user, csrf: identity.csrf))
        <main class="shell narrow" data-page-status="denied">
          <h1>Hozzáférés szükséges</h1>
          <p><a href="/">Vissza a főoldalra</a></p>
        </main>
        \(statusUpdatesScript)
        """, updates: updates)
    page.status = .forbidden
    return page
}

func configure(_ application: Application, store: WorksheetStore, secureCookies: Bool? = nil, motionRate rate: Int = 33,
               google: GoogleSignIn? = nil) {
    let live = Collaboration(store: store)
    let assets = application.directory.publicDirectory
    let themeJSON = String(decoding: (try? JSONEncoder().encode(Themes.catalog)) ?? Data(), as: UTF8.self)
    let motionRate = (1...999_999_999).contains(rate) ? rate : 33
    let secure = secureCookies ?? (application.http.server.configuration.tlsConfiguration != nil)
    // Without HTTPS the browser drops the SameSite=None asset cookie, so the lease URL alone grants access.
    let webSessions = WebPresentationSessions(requireCookie: secure)
    // Tartós munkamenetek (FileSessions): újraindítás után sem lép ki senki, a token sem változik (nincs lapújratöltés).
    let sessionStore = FileSessions(directory: store.dataRoot)
    application.sessions.use { _ in sessionStore }
    application.sessions.configuration = .init(cookieName: "thinknodes_session") { sessionID in
        .init(string: sessionID.string, path: "/", isSecure: secure, isHTTPOnly: true, sameSite: .lax)
    }
    #if !DEBUG
    var middlewares = Middlewares()
    for middleware in application.middleware.resolve() where !(middleware is RouteLoggingMiddleware) {
        middlewares.use(middleware)
    }
    application.middleware = middlewares
    #endif
    application.middleware.use(ThinkNodesPublicFiles(directory: assets))
    let app = application.grouped(application.sessions.middleware)
    application.routes.defaultMaxBodySize = "16mb"

    app.get("health") { _ in "ok" }

    /// Hosszú lekérdezés várt „lejárt” esete (410): a kliens közben elhagyta a lapot, vagy a csatornája lejárt (pl. szerver-
    /// újraindítás után). Nem hiba, ezért nem dobjuk: a Vapor hibakezelője minden dobott hibát figyelmeztetésként naplózott
    /// (lapbezárásonként egy sor). A kliens ugyanúgy kezeli (jelenlét: újracsatlakozik, lapváltozás: újratölti az oldalt).
    @Sendable func goneResponse() -> Response { Response(status: .gone, headers: ["Cache-Control": "no-store"]) }
    @Sendable func quietGone(_ body: () async throws -> Response) async throws -> Response {
        do { return try await body() } catch let error as Abort where error.status == .gone { return goneResponse() }
    }
    application.get("api", "page-changes", ":id") { req async throws -> Response in
        guard let id = req.parameters.get("id").flatMap(UUID.init(uuidString:)),
              let since = req.query[String.self, at: "since"].flatMap(UUID.init(uuidString:)) else { throw Abort(.badRequest) }
        return try await quietGone {
            let version = try await live.pages.wait(id, since: since, on: req.eventLoop)
            return response(version.uuidString, type: "text/plain; charset=utf-8")
        }
    }

    // Nincs-e még egyetlen fiók sem az adatmappában (tesztmódban nem számít: ott mindenki admin).
    @Sendable func withoutAccounts(_ req: Request) async throws -> Bool {
        guard !store.testMode else { return false }
        return try await req.application.threadPool.runIfActive { try store.allUsers().isEmpty }
    }

    app.get("login") { req async throws -> Response in
        let next = safeNext(req.query[String.self, at: "next"])
        let updates = next == "/" || next == "/admin" ? nil : live.pages.subscribe(.index)
        return loginPage(req, next: next, noAccounts: try await withoutAccounts(req), google: google != nil, updates: updates)
    }

    // Google-bejelentkezés (GoogleSignIn.swift): indítás, majd visszatérés a Google-től.
    let googleKeys = ["google-state", "google-nonce", "google-verifier", "google-next"]
    app.get("login", "google") { req async throws -> Response in
        guard let google else { throw Abort(.notFound) }
        let state = GoogleSignIn.secret(), nonce = GoogleSignIn.secret(), verifier = GoogleSignIn.secret()
        for (key, value) in zip(googleKeys, [state, nonce, verifier, safeNext(req.query[String.self, at: "next"])]) {
            req.session.data[key] = value
        }
        return redirect(google.authorizationURL(redirect: google.redirect(for: req, secure: secure),
                                                state: state, nonce: nonce, verifier: verifier))
    }

    app.get("login", "google", "callback") { req async throws -> Response in
        guard let google else { throw Abort(.notFound) }
        let pending = req.hasSession ? googleKeys.map { req.session.data[$0] } : [nil, nil, nil, nil]
        if req.hasSession { googleKeys.forEach { req.session.data[$0] = nil } }
        let next = safeNext(pending[3])
        func failed(_ message: String) async throws -> Response {
            let response = loginPage(req, next: next, message: message, noAccounts: try await withoutAccounts(req), google: true)
            response.status = .unauthorized
            return response
        }
        guard let state = pending[0], let nonce = pending[1], let verifier = pending[2],
              req.query[String.self, at: "state"] == state else {
            return try await failed("A Google-bejelentkezés lejárt vagy megszakadt. Próbáld újra.")
        }
        guard let code = req.query[String.self, at: "code"], !code.isEmpty else {
            return try await failed("A Google-bejelentkezés megszakadt.")
        }
        let email: String
        do {
            let form = google.tokenRequest(code: code, redirect: google.redirect(for: req, secure: secure), verifier: verifier)
            email = try google.verifiedEmail(idToken: try await google.exchange(req, form), nonce: nonce)
        } catch {
            req.logger.warning("Google sign-in failed: \((error as? any AbortError)?.reason ?? String(describing: error))")
            return try await failed("A Google-bejelentkezés nem sikerült. Próbáld újra.")
        }
        guard let user = try await req.application.threadPool.runIfActive({ try store.user(google: email) }) else {
            // Ismeretlen fiók: ha a hozzáférés-kérés be van kapcsolva, a kérelem oldalára jut (a cím a munkamenetben marad).
            if try await req.application.threadPool.runIfActive({ try store.accessRequestState(email: email) }) != .closed {
                req.session.data["google-request"] = email
                return redirect("/login/request")
            }
            return try await failed("A(z) \(email) Google-fiókhoz nem tartozik ThinkNodes-fiók. Kérd meg az adminisztrátort, hogy rendelje hozzá a fiókodhoz.")
        }
        try await signIn(req, user: user, google: email)
        return redirect(next)
    }

    // Hozzáférés-kérés: csak a Google-től visszatért, igazolt címmel (a munkamenet „google-request” értéke).
    app.get("login", "request") { req async throws -> Response in
        guard google != nil, req.hasSession, let email = req.session.data["google-request"] else { return redirect("/login") }
        let (known, state) = try await req.application.threadPool.runIfActive {
            (try store.user(google: email) != nil, try store.accessRequestState(email: email))
        }
        // Közben jóváhagyták: a Google-belépés már sikerülni fog.
        if known { return redirect("/login/google") }
        return accessRequestPage(req, email: email, state: state)
    }

    app.post("login", "request") { req async throws -> Response in
        struct Form: Content { var name: String; var csrf: String }
        guard google != nil, req.hasSession, let email = req.session.data["google-request"] else { return redirect("/login") }
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        do {
            try await req.application.threadPool.runIfActive { try store.requestAccess(email: email, name: form.name) }
        } catch let error as any AbortError {
            let state = try await req.application.threadPool.runIfActive { try store.accessRequestState(email: email) }
            let response = accessRequestPage(req, email: email, state: state, message: error.reason, name: form.name)
            response.status = error.status
            return response
        }
        live.accountChanged()
        return redirect("/login/request")
    }

    app.post("login") { req async throws -> Response in
        let form = try req.content.decode(LoginForm.self)
        try verify(req, token: form.csrf)
        let next = safeNext(form.next)
        let user = try await req.application.threadPool.runIfActive { () throws -> User? in
            guard validSlug(form.name), (1...72).contains(form.password.utf8.count),
                  let user = try store.user(named: form.name),
                  try Bcrypt.verify(form.password, created: user.passwordHash) else { return nil }
            return user
        }
        guard let user else {
            let response = loginPage(req, next: next, message: "Hibás felhasználónév vagy jelszó.",
                                     noAccounts: try await withoutAccounts(req), google: google != nil)
            response.status = .unauthorized
            return response
        }
        try await signIn(req, user: user)
        return redirect(next)
    }

    app.post("logout") { req -> Response in
        struct Form: Content { var csrf: String }
        try verify(req, token: req.content.decode(Form.self).csrf)
        req.session.destroy()
        return redirect("/")
    }

    app.get { req async throws -> Response in
        let identity = try session(req, store: store)
        if try await req.application.threadPool.runIfActive({ try store.settings().requireLogin }) && identity.user == nil { return redirect("/login") }
        let updates = live.pages.subscribe(.index)
        let projects = try await req.application.threadPool.runIfActive {
            try store.list(user: identity.user, rootsOnly: true, unlocks: identity.unlocks).map { item -> ProjectCard in
                let access = try store.access(item.path, sheet: item.worksheet, user: identity.user, unlocks: identity.unlocks)
                return ProjectCard(path: item.path, worksheet: item.worksheet, access: access,
                                   count: access.readable ? try store.list(user: identity.user, childrenOf: item.path, recursive: true, unlocks: identity.unlocks).count : 0)
            }
        }
        // `?previews=svg`: a régi háttérkép (SVG-előnézet + CSS-elmosás) – a betöltési idő összehasonlításához (Tests/Perf/main-page.py).
        let raster = PreviewRaster.available && req.query[String.self, at: "previews"] != "svg"
        return indexPage(projects, session: identity, dataFolder: store.dataDirectoryPath, updates: updates, raster: raster)
    }

    app.get("open") { req -> Response in
        guard let input = req.query[String.self, at: "path"],
              let path = try? worksheetPath(input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return missingPage(try session(req, store: store))
        }
        return redirect("/" + path.url)
    }

    configureAdmin(app, store: store, live: live, google: google != nil)

    app.get("edit", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        guard let path = try? WorksheetPath(req.parameters.getCatchall()) else { return missingPage(identity, updates: live.pages.subscribe(.index)) }
        guard try await req.application.threadPool.runIfActive({ store.pageExists(path) }) else { return missingPage(identity, updates: live.pages.subscribe(.index)) }
        let updates = live.pages.subscribe(.editor(path.url))
        let user = identity.user
        let worksheet: Worksheet
        do {
            worksheet = try await req.application.threadPool.runIfActive { try store.load(path, user: user, unlocks: identity.unlocks) }
        } catch let error as Abort where error.status == .notFound {
            return missingPage(identity, updates: live.pages.subscribe(.index))
        } catch let error as Abort where error.status == .unauthorized {
            return redirect("/login?next=/edit/" + path.url)
        } catch let error as Abort where error.status == .forbidden {
            return accessDeniedPage(identity, updates: live.pages.subscribe(.index))
        } catch let error as Abort where error.status == .locked {
            return unlockPage(req, path: path, identity: identity, editing: true, updates: live.pages.subscribe(.index))
        }
        let (access, local, storedPrefs) = try await req.application.threadPool.runIfActive {
            (try store.access(path, sheet: worksheet, user: user, unlocks: identity.unlocks),
             [assets + "vendor/vue.js", assets + "lib/d3-zoom.js"].allSatisfy { FileManager.default.fileExists(atPath: $0) },
             try user.flatMap { try store.settings().preferences?[$0.name] })
        }
        guard access.editable else { return accessDeniedPage(identity, updates: live.pages.subscribe(.index)) }
        let csrf = token(req)
        // Nagy szövegfájl külön ablakos szerkesztője (docs/node-types.md, text típus 5. pont): `?text=<doboz>`.
        if let nodeID = req.query[String.self, at: "text"] {
            guard validSlug(nodeID), let node = worksheet.nodes.first(where: { $0.id == nodeID }), let file = node.file,
                  node.isTextFile, node.type != "table", !file.isCommon else {
                return missingPage(identity, updates: live.pages.subscribe(.index))
            }
            let name = file.displayName(image: false)
            return htmlPage(title: name, body: """
                <div class="editor-root">
                \(siteHeader(path: path.url, project: worksheet.title, user: user, csrf: csrf, editing: true))
                <main id="text-editor" class="text-editor" data-path="\(path.url)" data-node="\(escaped(nodeID))" data-csrf="\(csrf)" data-rev="\(file.rev ?? 0)" data-name="\(escaped(name))" data-limit="\(largeTextLimit)">
                  <div class="text-editor-bar"><strong>\(escaped(name))</strong><span class="text-editor-status" role="status">Betöltés…</span>
                    <button type="button" class="button primary" data-save disabled>\(uiIcon("save"))Mentés</button>
                    <a class="button" href="/edit/\(path.url)">\(uiIcon("file"))Vissza a lapra</a></div>
                  <textarea class="text-editor-area" aria-label="Fájl tartalma" spellcheck="false" disabled></textarea>
                  <noscript><p>A szerkesztőhöz JavaScript szükséges.</p></noscript>
                </main></div>
                <script type="module" src="/text-editor.js?v=1"></script>
                """)
        }
        let loading = local ? "Szerkesztő betöltése…" : "A szerkesztőhöz futtasd a teljes ./build.sh parancsot."
        let prefs = storedPrefs ?? UserPreferences()
        let preferences = String(decoding: try JSONEncoder().encode(prefs), as: UTF8.self)
        return htmlPage(title: worksheet.title, body: """
            <div class="editor-root">
            \(siteHeader(path: path.url, project: worksheet.title, user: user, csrf: csrf, editing: true))
            <main id="editor" data-themes="\(escaped(themeJSON))" data-preferences="\(escaped(preferences))" data-path="\(path.url)" data-csrf="\(csrf)" data-motion-rate="\(motionRate)" data-role="\(user?.role.rawValue ?? "guest")" data-user="\(escaped(user?.name ?? ""))" data-manage="\(access.manageable && user?.role != .guest)" data-protected="\(access.protectedByPassword)">
              <p class="editor-loading">\(loading)</p>
              <noscript><p>A szerkesztőhöz JavaScript szükséges.</p><a href="/\(path.url)">Megtekintés</a></noscript>
            </main></div>
            """, scripts: local, updates: updates)
    }

    app.get("api", "worksheet", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        let worksheet = try await req.application.threadPool.runIfActive {
            try store.load(path, user: identity.user, unlocks: identity.unlocks)
        }
        return try worksheetResponse(worksheet)
    }

    app.get("api", "worksheet-users", "**") { req async throws -> [String] in
        let identity = try session(req, store: store)
        let user = try identity.editor()
        let path = try WorksheetPath(req.parameters.getCatchall())
        return try await req.application.threadPool.runIfActive {
            guard path.parts.count == 1 else { throw Abort(.forbidden) }
            let worksheet = try store.load(path, user: user, unlocks: identity.unlocks)
            guard try store.access(path, sheet: worksheet, user: user, unlocks: identity.unlocks).invitable else { throw Abort(.forbidden) }
            return try store.allUsers().filter { $0.role == .editor }.map(\.name)
        }
    }

    application.webSocket("api", "motion", "**", maxFrameSize: 512) { req, socket in
        guard let path = try? WorksheetPath(req.parameters.getCatchall()) else { socket.close(promise: nil); return }
        socket.onText { socket, client in live.attach(socket, path: path, client: client) }
    }

    application.post("api", "presence", "**") { req async throws -> Response in
        struct Form: Content {
            let action: String
            let node: String?
            let edge: String?
            let point: Point?
            let since: String?
            let editing: Bool?
            let revision: Int?
            let checkpointRevision: Int?
            let away: Bool?
            let mode: String?
        }
        let path = try WorksheetPath(req.parameters.getCatchall())
        let sessions = req.application.sessions
        guard let cookie = req.cookies[sessions.configuration.cookieName],
              let token = req.headers.first(name: "X-CSRF-Token") else { throw Abort(.forbidden) }
        let form = try req.content.decode(Form.self)
        guard ["poll", "select", "view-select", "leave", "checkpoint", "resign", "ping", "status", "present", "unpresent"].contains(form.action),
              let client = req.headers.first(name: "X-Worksheet-Client"),
              client.count == 32, validSlug(client) else { throw Abort(.badRequest) }
        @Sendable func state(_ action: String, since: String?) async throws -> (LiveState, EventLoopFuture<Void>?) {
            // A long poll can outlive logout. Read the current session on wake and
            // keep polling responses from refreshing or rewriting session cookies.
            guard let data = try await sessions.driver.readSession(.init(string: cookie.string), for: req).get(),
                  data["csrf"] == token else { throw Abort(.forbidden) }
            return try await req.application.threadPool.runIfActive {
                let user = try authenticatedUser(data, store: store)
                if data["user"] != nil && user == nil { throw Abort(.unauthorized) }
                return try live.presence(path, user: user, client: client, action: action,
                                  node: form.node, edge: form.edge, since: since, loop: req.eventLoop, editing: form.editing == true,
                                  revision: form.revision, checkpointRevision: form.checkpointRevision, unlocks: documentUnlocks(data), point: form.point,
                                  away: action == "snapshot" ? nil : form.away, mode: form.mode)
            }
        }
        var (snapshot, wait) = try await state(form.action, since: form.since)
        if let wait {
            try await wait.get()
            // A várakozás alatt a kliens elhagyta a lapot (leave, újratöltés) vagy a szobája lejárt: csendes 410 (goneResponse).
            do { snapshot = try await state("snapshot", since: nil).0 }
            catch let error as Abort where error.status == .gone { return goneResponse() }
        }
        let result = Response()
        try result.content.encode(snapshot)
        result.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return result
    }

    // Csevegés munkalaponként (csak bejelentkezve): GET az előzmények, POST {text} új üzenet, POST {delete} törlés.
    // A dátumok ISO 8601 alakban mennek; az új / törölt üzenet a WebSocketen is megy a szobának.
    @Sendable func chatResponse<T: Encodable>(_ value: T) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let result = Response(headers: ["Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"])
        result.body = .init(data: try encoder.encode(value))
        return result
    }
    app.get("api", "chat", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        let messages = try await req.application.threadPool.runIfActive {
            try store.chat(path, user: identity.user, unlocks: identity.unlocks)
        }
        return try chatResponse(messages)
    }
    app.post("api", "chat", "**") { req async throws -> Response in
        struct Form: Content { var text: String?; var delete: String? }
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let form = try req.content.decode(Form.self)
        struct Deleted: Encodable { let id: String; let deleted = true }
        struct Frame<T: Encodable>: Encodable { let chat: T }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let id = form.delete {
            try await req.application.threadPool.runIfActive { try store.deleteChat(path, id: id, user: identity.user, unlocks: identity.unlocks) }
            live.broadcastChat(path, message: String(decoding: try encoder.encode(Frame(chat: Deleted(id: id))), as: UTF8.self))
            return try chatResponse(Deleted(id: id))
        }
        let message = try await req.application.threadPool.runIfActive {
            try store.postChat(path, text: form.text ?? "", user: identity.user, unlocks: identity.unlocks)
        }
        live.broadcastChat(path, message: String(decoding: try encoder.encode(Frame(chat: message)), as: UTF8.self))
        return try chatResponse(message)
    }

    /// A napló „Vissza” gombjának célja: a hívó munkalap (szerkesztő vagy megtekintő) a `from` paraméterből, ha a
    /// projekten belüli, helyi cím; egyébként a projekt megtekintője.
    func logReturn(_ from: String?, project: String) -> String {
        let encoded = project.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? project
        let fallback = "/" + encoded
        guard let from, !from.contains("//"), !from.contains(":"), !from.contains("\\"), !from.contains("?"), !from.contains("#") else { return fallback }
        let owned = [project, encoded].contains { name in
            ["/", "/edit/"].contains { prefix in from == prefix + name || from.hasPrefix(prefix + name + "/") }
        }
        return owned ? from : fallback
    }
    // Projektnapló: oldal (`/_naplo/<projekt>`; az aláhúzás miatt nem ütközhet projektnévvel) és API (`/api/log/<projekt>`).
    app.get("_naplo", ":project") { req async throws -> Response in
        let identity = try session(req, store: store)
        guard let project = req.parameters.get("project") else { throw Abort(.badRequest) }
        _ = try await req.application.threadPool.runIfActive { try store.projectLog(project, user: identity.user, unlocks: identity.unlocks) }
        return htmlPage(title: "Napló · \(project)", body: """
            \(siteHeader(path: project, project: project, user: identity.user, csrf: identity.csrf))
            <main class="shell log-page" id="project-log" data-project="\(escaped(project))" data-csrf="\(identity.csrf ?? "")" data-user="\(escaped(identity.user?.name ?? ""))">
              <p class="log-back"><a class="button" href="\(escaped(logReturn(req.query[String.self, at: "from"], project: project)))">\(uiIcon("left"))Vissza</a></p>
              <h1>Napló · \(escaped(project))</h1>
              <p class="muted">A projekt közös naplója: a bejegyzések idő szerint. Írni és jelölni a projekt szerkesztői tudnak.</p>
              <noscript>A naplóhoz JavaScript szükséges.</noscript>
            </main>
            <script type="module" src="/naplo.js?v=1"></script>
            """)
    }
    app.get("api", "log", ":project") { req async throws -> Response in
        let identity = try session(req, store: store)
        guard let project = req.parameters.get("project") else { throw Abort(.badRequest) }
        let log = try await req.application.threadPool.runIfActive { try store.projectLog(project, user: identity.user, unlocks: identity.unlocks) }
        return try chatResponse(log)
    }
    app.post("api", "log", ":project") { req async throws -> Response in
        struct Form: Content { var action: String; var id: String?; var text: String?; var flag: String?; var value: Bool? }
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        guard let project = req.parameters.get("project") else { throw Abort(.badRequest) }
        let form = try req.content.decode(Form.self)
        let log = try await req.application.threadPool.runIfActive {
            try store.changeLog(project, action: form.action, id: form.id, text: form.text, flag: form.flag, value: form.value,
                                user: identity.user, unlocks: identity.unlocks)
        }
        return try chatResponse(log)
    }

    app.post("api", "subworksheet", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let user = identity.user
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let sheet = try await req.application.threadPool.runIfActive {
            try store.open(path, user: user, createOnly: true, unlocks: identity.unlocks)
        }
        live.pages.publish(.structure, at: path)
        return try worksheetResponse(sheet)
    }

    app.put("api", "worksheet", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let submitted = try req.content.decode(Worksheet.self)
        guard let match = req.headers.first(name: .ifMatch) else {
            throw Abort(.preconditionRequired, reason: "A mentéshez szükséges a munkalap revíziója.")
        }
        guard match == etag(submitted.revision) else {
            throw Abort(.badRequest, reason: "Érvénytelen mentési revízió.")
        }
        let path = try WorksheetPath(req.parameters.getCatchall())
        let client = req.headers.first(name: "X-Worksheet-Client")
        let worksheet = try await req.application.threadPool.runIfActive { try live.update(path, sheet: submitted, user: user, client: client, unlocks: identity.unlocks) }
        return try worksheetResponse(worksheet)
    }

    // Mentett állapotok: lista, új mentés, visszaállítás (admin és szerkesztő).
    app.get("api", "versions", "**") { req async throws -> WorksheetStore.VersionList in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        return try await req.application.threadPool.runIfActive {
            try store.versions(path, user: identity.user, unlocks: identity.unlocks)
        }
    }

    app.post("api", "versions", "**") { req async throws -> Response in
        struct VersionAction: Content { let action: String; let number: Int?; let revision: Int? }
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let body = try req.content.decode(VersionAction.self)
        switch body.action {
        case "save":
            let entry = try await req.application.threadPool.runIfActive {
                try store.saveVersion(path, user: user, unlocks: identity.unlocks)
            }
            let result = Response(status: .created)
            try result.content.encode(entry)
            return result
        case "restore":
            guard let number = body.number, let revision = body.revision else { throw Abort(.badRequest) }
            let worksheet = try await req.application.threadPool.runIfActive { () throws -> Worksheet in
                var sheet = try store.version(path, number: number, user: user, unlocks: identity.unlocks)
                sheet.revision = revision
                return try live.update(path, sheet: sheet, user: user, client: nil, unlocks: identity.unlocks, restoring: true)
            }
            return try worksheetResponse(worksheet)
        default: throw Abort(.badRequest)
        }
    }

    app.post("api", "text") { req -> Response in
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let form = try req.content.decode(MarkdownForm.self)
        guard form.text.utf8.count <= 100_000 else { throw Abort(.payloadTooLarge) }
        return response(markdownHTML(form.text, exactLines: form.lines == true), type: "text/html; charset=utf-8")
    }

    app.post("api", "text", "canvas") { req async throws -> CanvasMarkdownResponse in
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let sources = try req.content.decode(CanvasMarkdownRequest.self).sources
        guard sources.count <= 2_000, sources.allSatisfy({ $0.utf8.count <= 100_000 }) else {
            throw Abort(.payloadTooLarge)
        }
        return try await req.application.threadPool.runIfActive {
            CanvasMarkdownResponse(blocks: sources.map(canvasMarkdown))
        }
    }

    app.get("export", ":format", "**") { req async throws -> Response in
        let path = try WorksheetPath(req.parameters.getCatchall())
        let identity = try session(req, store: store)
        let (worksheet, texts) = try await req.application.threadPool.runIfActive {
            let sheet = try store.load(path, user: identity.user, unlocks: identity.unlocks)
            return (sheet, try store.fileTexts(path, sheet: sheet, user: identity.user, unlocks: identity.unlocks, commonDirectory: assets))
        }
        switch req.parameters.get("format") {
        case "svg":
            let host = req.headers.first(name: .host), mode = siteMode(req)
            let svg = try await req.application.threadPool.runIfActive {
                boardSVG(worksheet, siteHost: host, assetBase: "/" + path.url, mode: mode, fileText: { $0.file.flatMap { texts[$0.textKey] } })
            }
            return response("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + svg,
                            type: "image/svg+xml; charset=utf-8", filename: "\(path.name).svg")
        case "thnode", "json":
            return try worksheetResponse(worksheet, filename: "\(path.name).thnode")
        case "text", "markdown":
            return response(worksheetMarkdown(worksheet), type: "text/markdown; charset=utf-8", filename: "\(path.name).md")
        default:
            throw Abort(.notFound)
        }
    }

    app.post("api", "preferences") { req async throws -> HTTPStatus in
        let user = try session(req, store: store).editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let prefs = try req.content.decode(UserPreferences.self)
        try await req.application.threadPool.runIfActive { try store.savePreferences(prefs, for: user.name) }
        return .noContent
    }

    app.get("api", "preview-images", "**") { req async throws -> [String] in
        let identity = try session(req, store: store)
        if identity.user == nil, try store.settings().requireLogin { throw Abort(.unauthorized) }
        let path = try WorksheetPath(req.parameters.getCatchall())
        return try await req.application.threadPool.runIfActive {
            try store.contents(path, user: identity.user, unlocks: identity.unlocks)
                .filter { previewType($0) != nil }.map(\.lastPathComponent)
        }
    }

    app.get("api", "preview", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        // `format=webp`: a főoldali kártya háttere – fix méretű, elmosott kép (PreviewRaster); ha nem készíthető, SVG jön.
        if req.query[String.self, at: "format"] == "webp",
           let file = try await req.application.threadPool.runIfActive({ try store.previewWebP(path, user: identity.user, unlocks: identity.unlocks, mode: siteMode(req)) }) {
            let result = try await req.fileio.asyncStreamFile(at: file.path)
            result.headers.replaceOrAdd(name: .contentType, value: "image/webp")
            result.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return result
        }
        switch try await req.application.threadPool.runIfActive({ try store.preview(path, user: identity.user, unlocks: identity.unlocks, mode: siteMode(req)) }) {
        case .drawing(let svg):
            // `fill=1`: az előnézetes doboz teljesen kitöltése (levágva), a rajz saját arányától függetlenül.
            guard req.query[String.self, at: "fill"] == "1", let range = svg.range(of: "<svg "),
                  !svg[range.lowerBound...].prefix(while: { $0 != ">" }).contains("preserveAspectRatio") else {
                return response(svg, type: "image/svg+xml; charset=utf-8")
            }
            return response(svg.replacingCharacters(in: range, with: "<svg preserveAspectRatio=\"xMidYMid slice\" "), type: "image/svg+xml; charset=utf-8")
        case .image(let file, let mime):
            if req.query[String.self, at: "fill"] == "1", mime.hasPrefix("image/svg"),
               let text = try? await req.application.threadPool.runIfActive({ try String(contentsOf: file, encoding: .utf8) }),
               let range = text.range(of: "<svg "), !(text[range.lowerBound...].prefix(while: { $0 != ">" }).contains("preserveAspectRatio")) {
                let result = response(text.replacingCharacters(in: range, with: "<svg preserveAspectRatio=\"xMidYMid slice\" "), type: mime)
                result.headers.replaceOrAdd(name: "Content-Security-Policy", value: "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src data:")
                return result
            }
            let result = try await req.fileio.asyncStreamFile(at: file.path)
            result.headers.replaceOrAdd(name: .contentType, value: mime)
            result.headers.replaceOrAdd(name: "Content-Security-Policy", value: "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src data:")
            result.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return result
        }

    }

    app.get("api", "web-presentations", "**") { req async throws -> [WebPresentationInfo] in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        return try await req.application.threadPool.runIfActive {
            try store.webPresentations(in: path, user: identity.user, unlocks: identity.unlocks)
        }
    }

    app.patch("api", "web-presentations", "**") { req async throws -> HTTPStatus in
        let identity = try session(req, store: store)
        let user = try identity.editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let settings = try req.content.decode(WebPresentationSettings.self)
        try await req.application.threadPool.runIfActive {
            try store.setWebPresentation(settings, in: path, user: user, unlocks: identity.unlocks)
        }
        live.pages.publish(.structure, at: try WorksheetPath([path.parts[0]]))
        return .noContent
    }

    app.post("api", "web-unlock") { req async throws -> Response in
        struct Form: Content { let password: String; let csrf: String; let target: String }
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        guard (1...72).contains(form.password.utf8.count) else { throw Abort(.badRequest) }
        let candidates = try WebPresentationRequest.candidates(form.target)
        let identity = try session(req, store: store)
        let (request, hashes) = try await req.application.threadPool.runIfActive {
            try store.unlockWeb(candidates, password: form.password, user: identity.user, unlocks: identity.unlocks)
        }
        req.session.data["document-unlocks"] = identity.unlocks.union(hashes).sorted().joined(separator: "\n")
        return redirect(request.url)
    }

    app.post("api", "unlock", "**") { req async throws -> Response in
        struct Form: Content { let password: String; let csrf: String; let edit: String?; let attachment: String? }
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard (1...72).contains(form.password.utf8.count) else { throw Abort(.badRequest) }
        let hashes = try await req.application.threadPool.runIfActive { try store.unlock(path, password: form.password, user: identity.user, attachment: form.attachment) }
        req.session.data["document-unlocks"] = identity.unlocks.union(hashes).sorted().joined(separator: "\n")
        if let name = form.attachment { return redirect("/api/attachment/" + path.url + "?name=" + encodeQuery(name)) }
        return redirect((form.edit == "1" ? "/edit/" : "/") + path.url)
    }

    app.post("api", "document", "**") { req async throws -> [String: String] in
        let identity = try session(req, store: store)
        let user = try identity.editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let action = try req.content.decode(DocumentAction.self)
        let result = try await req.application.threadPool.runIfActive {
            try live.manage(path, operation: action, user: user, unlocks: identity.unlocks)
        }
        return ["path": result?.url ?? ""]
    }

    app.post("api", "media", "**") { req async throws -> [String: String] in
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let body = req.body.data, let type = req.headers.first(name: .contentType) else { throw Abort(.badRequest) }
        let bytes = Data(body.readableBytesView)
        let imageName = req.query[String.self, at: "name"]
        let filename = req.query[String.self, at: "filename"]
        let name = try await req.application.threadPool.runIfActive {
            try store.storeMedia(bytes, type: type, imageName: imageName, filename: filename, at: path, user: user, unlocks: identity.unlocks)
        }
        live.pages.publish(.attachments, at: path)
        return ["asset": name]
    }

    app.post("api", "worksheet-file", "**") { req async throws -> [String: String] in
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let name = req.query[String.self, at: "name"], let body = req.body.data else { throw Abort(.badRequest) }
        let bytes = Data(body.readableBytesView)
        let file = try await req.application.threadPool.runIfActive {
            try store.importWorksheet(bytes, named: name, at: path, user: user, unlocks: identity.unlocks)
        }
        live.pages.publish(.structure, at: file)
        return ["path": file.url]
    }

    // Projektcsomag (docs/migration.md): export, valamint import feltöltés → (jelszó) → jóváhagyás lépésekben.
    app.post("api", "package", "export", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let options = try req.content.decode(PackageExportRequest.self)
        let file = try await req.application.threadPool.runIfActive {
            try store.exportPackage(path, options: options, user: identity.user, unlocks: identity.unlocks)
        }
        // `?prepare=1`: a csomag a szerveren marad, a válasz a letöltés címe – a böngésző közvetlenül, lemezre tölti le
        // (nem a lap memóriájába), és megszakadás után folytatni tudja. Enélkül a régi működés: a válasz maga a fájl.
        if req.query[String.self, at: "prepare"] == "1" {
            let prepared = try await req.application.threadPool.runIfActive { try store.registerExport(file, user: identity.user) }
            struct Prepared: Content { let url: String; let name: String; let size: Int64 }
            return try await Prepared(url: "/api/package/download/" + prepared.token + "?name=" + encodeQuery(path.name + ".zip"),
                                      name: path.name + ".zip", size: prepared.size).encodeResponse(for: req)
        }
        let response = try await req.fileio.asyncStreamFile(at: file.path, mediaType: .zip) { _ in
            try? FileManager.default.removeItem(at: file)
        }
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        response.headers.replaceOrAdd(name: .contentDisposition, value: attachmentDisposition(path.name + ".zip"))
        return response
    }

    app.get("api", "package", "download", ":token") { req async throws -> Response in
        let identity = try session(req, store: store)
        let token = req.parameters.get("token") ?? ""
        let file = try await req.application.threadPool.runIfActive { try store.registeredExport(token, user: identity.user) }
        let name = req.query[String.self, at: "name"].flatMap { $0.hasSuffix(".zip") && !$0.contains("/") ? $0 : nil } ?? "csomag.zip"
        let response = try await req.fileio.asyncStreamFile(at: file.path, mediaType: .zip)
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        response.headers.replaceOrAdd(name: .contentDisposition, value: attachmentDisposition(name))
        return response
    }

    // Darabolt, folytatható csomagfeltöltés (ProjectPackage.swift): munkamenet → darabok → befejezés.
    app.post("api", "package", "uploads") { req async throws -> WorksheetStore.PackageUploadState in
        struct Begin: Content { let size: Int64; let target: String? }
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let body = try req.content.decode(Begin.self)
        let target = try body.target.flatMap { $0.isEmpty ? nil : $0 }.map {
            try WorksheetPath($0.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) })
        }
        return try await req.application.threadPool.runIfActive {
            try store.beginPackageUpload(size: body.size, target: target, user: identity.user, unlocks: identity.unlocks)
        }
    }
    app.get("api", "package", "uploads", ":id") { req async throws -> WorksheetStore.PackageUploadState in
        let identity = try session(req, store: store)
        let id = req.parameters.get("id") ?? ""
        return try await req.application.threadPool.runIfActive { try store.packageUploadState(id, user: identity.user) }
    }
    app.on(.PUT, "api", "package", "uploads", ":id", body: .collect(maxSize: "17mb")) { req async throws -> WorksheetStore.PackageUploadState in
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        guard let offset = req.query[Int64.self, at: "offset"], let body = req.body.data else { throw Abort(.badRequest) }
        let id = req.parameters.get("id") ?? ""
        let bytes = Data(body.readableBytesView)
        return try await req.application.threadPool.runIfActive {
            try store.appendPackageUpload(id, offset: offset, bytes: bytes, user: identity.user)
        }
    }
    app.post("api", "package", "uploads", ":id", "finish") { req async throws -> PackageReport in
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let id = req.parameters.get("id") ?? ""
        return try await req.application.threadPool.runIfActive {
            try store.finishPackageUpload(id, user: identity.user, unlocks: identity.unlocks)
        }
    }
    app.delete("api", "package", "uploads", ":id") { req async throws -> HTTPStatus in
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let id = req.parameters.get("id") ?? ""
        try await req.application.threadPool.runIfActive { try store.cancelPackageUpload(id, user: identity.user) }
        return .noContent
    }

    @Sendable func uploadPackage(_ req: Request, target: WorksheetPath?) async throws -> PackageReport {
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        guard let body = req.body.data else { throw Abort(.badRequest) }
        let bytes = Data(body.readableBytesView)
        return try await req.application.threadPool.runIfActive {
            try store.uploadPackage(bytes, target: target, user: identity.user, unlocks: identity.unlocks)
        }
    }
    app.on(.POST, "api", "package", "upload", body: .collect(maxSize: "200mb")) { req async throws -> PackageReport in
        try await uploadPackage(req, target: nil)
    }
    app.on(.POST, "api", "package", "upload", "**", body: .collect(maxSize: "200mb")) { req async throws -> PackageReport in
        try await uploadPackage(req, target: WorksheetPath(req.parameters.getCatchall()))
    }

    app.post("api", "package", "unlock") { req async throws -> PackageReport in
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let request = try req.content.decode(PackageUnlock.self)
        return try await req.application.threadPool.runIfActive {
            try store.unlockPackage(request, user: identity.user, unlocks: identity.unlocks)
        }
    }

    app.post("api", "package", "commit") { req async throws -> [String: String] in
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let request = try req.content.decode(PackageCommit.self)
        let path = try await req.application.threadPool.runIfActive {
            try store.commitPackage(request, user: identity.user, unlocks: identity.unlocks)
        }
        live.pages.publish(.structure, at: path)
        return ["path": path.url]
    }

    app.post("api", "package", "cancel") { req async throws -> HTTPStatus in
        struct Cancel: Content { let token: String }
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let request = try req.content.decode(Cancel.self)
        try await req.application.threadPool.runIfActive { try store.cancelPackage(request.token, user: identity.user) }
        return .noContent
    }

    app.on(.POST, "api", "web-archive", "**", body: .collect(maxSize: "100mb")) { req async throws -> WebPresentationInfo in
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let name = req.query[String.self, at: "name"], let body = req.body.data else { throw Abort(.badRequest) }
        let bytes = Data(body.readableBytesView)
        let info = try await req.application.threadPool.runIfActive {
            try store.importWebArchive(bytes, named: name, at: path, user: user, unlocks: identity.unlocks)
        }
        live.pages.publish(.structure, at: path)
        return info
    }

    app.post("api", "web-rename", "**") { req async throws -> [String: String] in
        struct Rename: Content { let reference: String; let name: String }
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let body = try req.content.decode(Rename.self)
        let reference = try await req.application.threadPool.runIfActive { () throws -> String in
            let others = store.webUsage(body.reference, project: path.parts[0]).filter { $0.sheet != path.url }
            let renamed = try store.renameWeb(body.reference, to: body.name, in: path, user: user, unlocks: identity.unlocks)
            // A többi lap linkjei is az új nevet kapják (a saját lapot a kliens frissíti).
            for usage in others {
                guard let sheet = try? WorksheetPath(usage.sheet.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }),
                      var board = try? store.load(sheet, user: user, unlocks: identity.unlocks) else { continue }
                for index in board.nodes.indices where usage.nodes.contains(board.nodes[index].id) {
                    board.nodes[index].link?.target = renamed
                }
                _ = try? live.update(sheet, sheet: board, user: user, client: nil, unlocks: identity.unlocks)
            }
            return renamed
        }
        live.pages.publish(.structure, at: try WorksheetPath([path.parts[0]]))
        return ["reference": reference]
    }

    app.post("api", "web-trash", "**") { req async throws -> HTTPStatus in
        struct Trash: Content { let reference: String }
        let identity = try session(req, store: store)
        let user = try identity.editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let body = try req.content.decode(Trash.self)
        try await req.application.threadPool.runIfActive {
            try store.trashWeb(body.reference, in: path, user: user, unlocks: identity.unlocks)
        }
        live.pages.publish(.structure, at: try WorksheetPath([path.parts[0]]))
        return .noContent
    }

    app.patch("api", "file-public", "**") { req async throws -> HTTPStatus in
        struct Change: Content { let name: String; let publicAccess: Bool }
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let change = try req.content.decode(Change.self)
        try await req.application.threadPool.runIfActive {
            try store.setFilePublic(change.name, publicAccess: change.publicAccess, in: path, user: identity.user, unlocks: identity.unlocks)
        }
        return .noContent
    }

    app.get("api", "usage", "**") { req async throws -> [WorksheetStore.Usage] in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let id = req.query[String.self, at: "id"], validSlug(id) else { throw Abort(.badRequest) }
        return try await req.application.threadPool.runIfActive {
            try store.usage(of: id, in: path, user: identity.user, unlocks: identity.unlocks)
        }
    }

    // Közös elem lomtárba: a többi lap rá mutató dobozai törlődnek ("delete") vagy üres dobozzá válnak ("unlink").
    // A saját lap dobozát a kliens törli utána a szokásos mentéssel.
    app.post("api", "release", "**") { req async throws -> [String: [String]] in
        struct Release: Content { let id: String; let mode: String }
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let body = try req.content.decode(Release.self)
        guard validSlug(body.id), ["delete", "unlink"].contains(body.mode) else { throw Abort(.badRequest) }
        let failed = try await req.application.threadPool.runIfActive { () throws -> [String] in
            var failed: [String] = []
            for usage in try store.usage(of: body.id, in: path, user: user, unlocks: identity.unlocks) where usage.sheet != path.url {
                do {
                    let sheet = try WorksheetPath(usage.sheet.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) })
                    var board = try store.load(sheet, user: user, unlocks: identity.unlocks)
                    let ids = Set(usage.nodes)
                    if body.mode == "delete" {
                        board.nodes.removeAll { ids.contains($0.id) }
                        board.edges.removeAll { ids.contains($0.source ?? "") || ids.contains($0.target.node ?? "") }
                    } else {
                        for index in board.nodes.indices where ids.contains(board.nodes[index].id) {
                            let name = board.nodes[index].name
                            board.nodes[index].type = "box"
                            board.nodes[index].file = nil
                            board.nodes[index].link = nil
                            board.nodes[index].text = name + " (lomtárban)"
                        }
                    }
                    _ = try live.update(sheet, sheet: board, user: user, client: nil, unlocks: identity.unlocks)
                } catch { failed.append(usage.title) }
            }
            try store.trashTarget(of: body.id, in: path, user: user, unlocks: identity.unlocks)
            return failed
        }
        live.pages.publish(.attachments, at: path)
        return ["failed": failed]
    }

    app.get("api", "trash", ":project") { req async throws -> [WorksheetStore.TrashEntry] in
        let identity = try session(req, store: store)
        let project = try WorksheetPath([req.parameters.get("project") ?? ""]).parts[0]
        return try await req.application.threadPool.runIfActive {
            try store.trashContents(project, user: identity.user, unlocks: identity.unlocks)
        }
    }

    app.post("api", "trash", ":project") { req async throws -> HTTPStatus in
        struct TrashAction: Content { let action: String; let path: String? }
        let identity = try session(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let projectPath = try WorksheetPath([req.parameters.get("project") ?? ""])
        let body = try req.content.decode(TrashAction.self)
        try await req.application.threadPool.runIfActive {
            switch body.action {
            case "restore":
                guard let path = body.path else { throw Abort(.badRequest) }
                try store.restoreTrash(projectPath.parts[0], path: path, user: identity.user, unlocks: identity.unlocks)
            case "empty":
                try store.emptyTrash(projectPath.parts[0], user: identity.user, unlocks: identity.unlocks)
            default: throw Abort(.badRequest)
            }
        }
        live.pages.publish(.structure, at: projectPath)
        return .noContent
    }

    app.post("api", "attachment", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let name = req.query[String.self, at: "name"] else { throw Abort(.badRequest) }
        let bytes = req.body.data.map { Data($0.readableBytesView) } ?? Data()
        let asset = try await req.application.threadPool.runIfActive {
            try store.storeAttachment(bytes, named: name, at: path, user: user, unlocks: identity.unlocks)
        }
        live.pages.publish(.attachments, at: path)
        return Response(status: .created, headers: ["X-ThinkNodes-Asset": asset])
    }

    app.put("api", "attachment", "**") { req async throws -> HTTPStatus in
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let name = req.query[String.self, at: "name"] else { throw Abort(.badRequest) }
        let bytes = req.body.data.map { Data($0.readableBytesView) } ?? Data()
        _ = try await req.application.threadPool.runIfActive {
            try store.storeAttachment(bytes, named: name, at: path, user: user, unlocks: identity.unlocks, replaceText: true)
        }
        live.pages.publish(.attachments, at: path)
        return .noContent
    }

    // Szövegfájl mentése a külön ablakos szerkesztőből: a fájl tartalma cserélődik, a doboz `file.rev` számlálója nő
    // (ebből töltik újra a többiek). `rev`: az a változat, amelyből a szerkesztés indult – ha közben más mentett, 409.
    app.on(.PUT, "api", "text-file", "**", body: .collect(maxSize: "13mb")) { req async throws -> [String: Int] in
        let identity = try session(req, store: store)
        let user = identity.user
        guard user != nil || req.hasSession else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let id = req.query[String.self, at: "id"], validSlug(id), let base = req.query[Int.self, at: "rev"] else { throw Abort(.badRequest) }
        let bytes = req.body.data.map { Data($0.readableBytesView) } ?? Data()
        let rev = try await req.application.threadPool.runIfActive { () throws -> Int in
            var board = try store.load(path, user: user, unlocks: identity.unlocks)
            guard let index = board.nodes.firstIndex(where: { $0.id == id }), let file = board.nodes[index].file,
                  board.nodes[index].isTextFile, board.nodes[index].type != "table", !file.isCommon,
                  let owner = file.sheet(from: path) else { throw Abort(.notFound) }
            guard (file.rev ?? 0) == base else {
                throw Abort(.conflict, reason: "A fájlt közben más is módosította. Töltsd újra, mielőtt mentesz.")
            }
            // Előbb a fájl, aztán a számláló: a többi kliens a számláló változására tölt újra, addigra az új tartalomnak
            // kell a helyén lennie. Ha a lap mentése nem sikerül (pl. más fogja a dobozt), a régi tartalom visszakerül.
            let previous = try store.attachmentData(owner, named: file.asset, user: user, unlocks: identity.unlocks)
            _ = try store.storeAttachment(bytes, named: file.asset, at: owner, user: user, unlocks: identity.unlocks, replaceText: true)
            board.nodes[index].file?.rev = base + 1
            do { _ = try live.update(path, sheet: board, user: user, client: nil, unlocks: identity.unlocks, ownSelections: true) }
            catch {
                _ = try? store.storeAttachment(previous, named: file.asset, at: owner, user: user, unlocks: identity.unlocks, replaceText: true)
                throw error
            }
            return base + 1
        }
        live.pages.publish(.attachments, at: path)
        return ["rev": rev]
    }

    // Táblázat doboz (docs/EXCEL.md): forrásfájlból táblázat, forrásfájl figyelése.
    registerTableRoutes(app, store: store, identity: { req in
        let identity = try session(req, store: store)
        guard identity.user != nil || req.hasSession else { throw Abort(.unauthorized) }
        return (identity.user, identity.unlocks)
    }, verify: { req in try verify(req, token: req.headers.first(name: "X-CSRF-Token")) },
       changed: { path in live.pages.publish(.attachments, at: path) })

    @Sendable func browseCommon(_ req: Request) async throws -> BrowseListing {
        _ = try session(req, store: store)
        let folders = req.parameters.getCatchall().map { $0.removingPercentEncoding ?? $0 }
        return try await req.application.threadPool.runIfActive {
            try CommonLibrary.list(folders, publicDirectory: assets)
        }
    }
    app.get("api", "browse-common", use: browseCommon)
    app.get("api", "browse-common", "**", use: browseCommon)

    let linkPreviews = LinkPreviews(root: store.dataRoot, eventLoopGroup: application.eventLoopGroup)
    application.lifecycle.use(LinkPreviewShutdown(previews: linkPreviews))
    // Külső webcím előnézete: az oldal megosztási képe, vagy kártya (LinkPreview.swift). `live=0`: nem frissít.
    app.get("api", "link-preview") { req async throws -> Response in
        let identity = try session(req, store: store)
        if try await req.application.threadPool.runIfActive({ try store.settings().requireLogin }) && identity.user == nil {
            throw Abort(.unauthorized)
        }
        guard let target = req.query[String.self, at: "url"] else { throw Abort(.badRequest) }
        let (file, meta) = try await linkPreviews.preview(for: target, refresh: req.query[String.self, at: "live"] != "0")
        let response: Response
        if let file, FileManager.default.fileExists(atPath: file.path) {
            response = try await req.fileio.asyncStreamFile(at: file.path)
            let types = ["png": "image/png", "jpg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"]
            response.headers.replaceOrAdd(name: .contentType, value: types[file.pathExtension] ?? "application/octet-stream")
        } else {
            response = Response(status: .ok, body: .init(string: LinkPreviews.card(meta)))
            response.headers.replaceOrAdd(name: .contentType, value: "image/svg+xml")
        }
        response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        response.headers.replaceOrAdd(name: "Content-Security-Policy", value: "sandbox; default-src 'none'; style-src 'unsafe-inline'")
        response.headers.replaceOrAdd(name: .cacheControl, value: "private, max-age=3600")
        return response
    }

    app.get("api", "browse", "**") { req async throws -> BrowseListing in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        return try await req.application.threadPool.runIfActive {
            try store.browse(path, user: identity.user, unlocks: identity.unlocks)
        }
    }

    app.get("api", "attachment", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        // A bejelentkezést a store ellenőrzi: publikus fájl bejelentkezés nélkül is letölthető.
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let name = req.query[String.self, at: "name"] else { throw Abort(.badRequest) }
        let file: URL
        do {
            guard let match = try await req.application.threadPool.runIfActive({
                try store.contents(path, user: identity.user, unlocks: identity.unlocks, named: name).first
            }) else { throw Abort(.notFound) }
            file = match
        } catch let error as Abort where error.status == .locked {
            return unlockPage(req, path: path, identity: identity, attachment: name)
        }
        // `highlight=<kiterjesztés>`: a kódfájl vásznon megjelenő eleje színezett HTML-ként (a szerkesztő doboza kéri).
        // 204: a kiterjesztéshez nincs nyelv, vagy a fájl nem szöveg – a doboz színezetlen marad.
        if let ext = req.query[String.self, at: "highlight"] {
            let html = try await req.application.threadPool.runIfActive { () -> String? in
                guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else { return nil }
                return highlightedCode(String(text.prefix(filePreviewLimit)), ext: ext)
            }
            guard let html else { return Response(status: .noContent, headers: ["Cache-Control": "no-store"]) }
            let result = response(html, type: "text/html; charset=utf-8")
            result.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
            result.headers.replaceOrAdd(name: "Content-Security-Policy", value: "sandbox; default-src 'none'")
            result.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return result
        }
        let result = try await req.fileio.asyncStreamFile(at: file.path)
        result.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename*=UTF-8''" + encodeQuery(file.lastPathComponent))
        result.headers.replaceOrAdd(name: .contentType, value: "application/octet-stream")
        if req.query[String.self, at: "inline"] == "1", let mime = canvasAssetType(name) {
            result.headers.replaceOrAdd(name: .contentType, value: mime)
            result.headers.replaceOrAdd(name: .contentDisposition, value: "inline")
            let policy = "sandbox; default-src 'none'"
            let svgSources = "; style-src 'unsafe-inline'; img-src data:; font-src data:"
            result.headers.replaceOrAdd(name: "Content-Security-Policy", value: mime == "image/svg+xml" ? policy + svgSources : policy)
        }
        result.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        result.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return result
    }

    app.get("api", "box-file", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let id = req.query[String.self, at: "id"], validSlug(id) else { throw Abort(.badRequest) }
        let source = try await req.application.threadPool.runIfActive {
            try store.boxFile(path, id: id, user: identity.user, unlocks: identity.unlocks)
        }
        switch source {
        case .disk(let url):
            let result = try await req.fileio.asyncStreamFile(at: url.path)
            result.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename*=UTF-8''" + encodeQuery(url.lastPathComponent))
            result.headers.replaceOrAdd(name: .contentType, value: "application/octet-stream")
            result.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
            result.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return result
        }
    }

    @Sendable func worksheetOrPresentation(_ req: Request) async throws -> Response {
        let identity = try session(req, store: store)
        let candidates = try WebPresentationRequest.candidates(req.url.path)
        if !candidates.isEmpty, let result = try await serveWebPresentation(req, candidates: candidates, identity: identity, store: store, webSessions: webSessions) {
            return result
        }
        let raw = req.url.path.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        guard let path = try? WorksheetPath(raw) else {
            if ["api", "export"].contains(raw.first?.lowercased() ?? "") { throw Abort(.notFound) }
            return missingPage(identity, updates: live.pages.subscribe(.index))
        }
        guard try await req.application.threadPool.runIfActive({ store.pageExists(path) }) else { return missingPage(identity, updates: live.pages.subscribe(.index)) }
        let updates = live.pages.subscribe(.viewer(path.url))
        let worksheet: Worksheet
        do {
            worksheet = try await req.application.threadPool.runIfActive {
                try store.load(path, user: identity.user, unlocks: identity.unlocks)
            }
        } catch let error as Abort where error.status == .notFound {
            return missingPage(identity, updates: live.pages.subscribe(.index))
        } catch let error as Abort where error.status == .unauthorized {
            return redirect("/login?next=/" + path.url)
        } catch let error as Abort where error.status == .forbidden {
            return accessDeniedPage(identity, updates: live.pages.subscribe(.index))
        } catch let error as Abort where error.status == .locked {
            return unlockPage(req, path: path, identity: identity, updates: live.pages.subscribe(.index))
        }
        // Minden fájlművelet a thread poolon fut, nem az event loopon.
        let (access, files, texts, pages) = try await req.application.threadPool.runIfActive {
            let children = try store.list(user: identity.user, childrenOf: path, unlocks: identity.unlocks)
            let access = try store.access(path, sheet: worksheet, user: identity.user, unlocks: identity.unlocks)
            let files = try store.contents(path, user: identity.user, unlocks: identity.unlocks)
            let texts = try store.fileTexts(path, sheet: worksheet, user: identity.user, unlocks: identity.unlocks, commonDirectory: assets)
            let pages = try children.map { child in
                (path: child.path, worksheet: child.worksheet,
                 access: try store.access(child.path, sheet: child.worksheet, user: identity.user, unlocks: identity.unlocks))
            }
            return (access, files, texts, pages)
        }
        do {
            return try passivePage(req, path: path, worksheet: worksheet, session: identity, access: access, children: pages, files: files, texts: texts, updates: updates)
        } catch let error as Abort where error.status == .notFound {
            return missingPage(identity, updates: live.pages.subscribe(.index))
        }
    }
    for depth in 1...11 {
        let prefix = (0..<depth).map { PathComponent.parameter("web-parent-\($0)") }
        let presentation = prefix + [.constant("web"), .parameter("web-name")]
        app.on(.GET, presentation, use: worksheetOrPresentation)
        app.on(.GET, presentation + [.catchall], use: worksheetOrPresentation)
    }
    app.get("**", use: worksheetOrPresentation)

}

private struct ThinkNodesPublicFiles: AsyncMiddleware {
    let files: FileMiddleware

    init(directory: String) { files = FileMiddleware(publicDirectory: directory, cachePolicy: .noCache) }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let path = request.url.path
        let decoded = path.removingPercentEncoding ?? path
        if WebPresentationRequest.matches(path) || WebPresentationRequest.matches(decoded) ||
            decoded.split(separator: "/").contains(where: { $0.hasSuffix(".web") }) {
            return try await next.respond(to: request)
        }
        return try await files.respond(to: request, chainingTo: next)
    }
}

private func serveWebPresentation(_ req: Request, candidates: [WebPresentationRequest], identity: SessionInfo, store: WorksheetStore,
                                  webSessions: WebPresentationSessions) async throws -> Response? {
    let sessions = req.application.sessions
    for candidate in candidates {
        do {
            let viewer: SessionInfo
            if let lease = candidate.lease {
                guard let session = webSessions.session(lease: lease, scope: candidate.scope,
                    cookie: req.cookies[WebPresentationSessions.cookieName]?.string),
                    let data = try await sessions.driver.readSession(session, for: req).get() else { throw Abort(.notFound) }
                let user = try authenticatedUser(data, store: store)
                if data["user"] != nil && user == nil { throw Abort(.notFound) }
                viewer = SessionInfo(user: user, unlocks: documentUnlocks(data))
            } else {
                viewer = identity
            }
            if candidate.asset == ["_tn-preview"], req.query[String.self, at: "state"] == "1" {
                guard let state = try await req.application.threadPool.runIfActive({
                    try store.webPreviewState(candidate, user: viewer.user, unlocks: viewer.unlocks)
                }) else { continue }
                let result = response("{\"pending\":\(state.pending),\"version\":\"\(state.version)\"}", type: "application/json")
                result.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
                return result
            }
            guard let (asset, directory, publicRead) = try await req.application.threadPool.runIfActive({
                try store.webAsset(candidate, user: viewer.user, unlocks: viewer.unlocks, size: WebScreenshot.boxSize(width: req.query[Double.self, at: "w"], height: req.query[Double.self, at: "h"]), live: req.query[String.self, at: "live"] != "0")
            }) else { continue }

            guard let asset else {
                let name = escaped(candidate.reference.name)
                return response("""
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 200">
                      <rect width="320" height="200" fill="#1f2b38"/>
                      <g fill="none" stroke="#8aa0b6" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">
                        <rect x="110" y="44" width="100" height="72" rx="6"/><path d="M110 60h100"/>
                        <circle cx="120" cy="52" r="1.5"/><circle cx="128" cy="52" r="1.5"/>
                        <path d="M145 76l30 26M175 76l-30 26"/>
                      </g>
                      <text x="160" y="150" fill="#c9d6e3" text-anchor="middle" font-family="sans-serif" font-size="16">Nincs elérhető előnézet</text>
                      <text x="160" y="172" fill="#8aa0b6" text-anchor="middle" font-family="sans-serif" font-size="13">\(name)</text>
                    </svg>
                    """, type: "image/svg+xml")
            }
            let query = req.url.query.map { "?" + $0 } ?? ""
            if directory && !candidate.trailingSlash { return redirect(candidate.url + "/" + query) }
            if asset.isHTML, candidate.lease != nil { return redirect(candidate.url + query) }
            guard asset.isHTML, !publicRead, let cookie = req.cookies[sessions.configuration.cookieName] else {
                return try await asset.response(to: req)
            }
            let grant = webSessions.issue(session: .init(string: cookie.string), scope: candidate.scope)
            let scope = candidate.assetScope(grant.id)
            let folders = directory ? candidate.asset : Array(candidate.asset.dropLast())
            let base = scope + (folders.isEmpty ? "" : folders.map(WebPresentationRequest.encodeAsset).joined(separator: "/") + "/")
            let result = try await asset.response(to: req, baseURL: base)
            if webSessions.requireCookie {
                result.cookies[WebPresentationSessions.cookieName] = .init(string: grant.secret, expires: grant.expires,
                    path: scope, isSecure: true, isHTTPOnly: true, sameSite: HTTPCookies.SameSitePolicy.none)
            }
            return result
        } catch let error as Abort where error.status == .unauthorized && candidate.lease == nil {
            return redirect("/login?next=" + encodeQuery(candidate.url))
        } catch let error as Abort where error.status == .locked && candidate.lease == nil {
            let page = htmlPage(title: "Prezentáció feloldása", body: """
                \(siteHeader(user: identity.user, csrf: identity.csrf))
                <main class="shell narrow"><h1>Prezentáció feloldása</h1>
                  <form class="stack panel" method="post" action="/api/web-unlock">
                    \(csrfInput(token(req)))<input type="hidden" name="target" value="\(escaped(candidate.url))">
                    <label>Prezentáció jelszava<input type="password" name="password" required></label>
                    <button class="button primary">Megnyitás</button>
                  </form>
                </main>
                """)
            page.status = .locked
            return page
        }
    }
    return nil
}

private func unlockPage(_ req: Request, path: WorksheetPath, identity: SessionInfo, editing: Bool = false, attachment: String? = nil, updates: PageUpdates.Subscription? = nil) -> Response {
    htmlPage(title: "Jelszó szükséges", body: """
        \(siteHeader(user: identity.user, csrf: identity.csrf))
        <main class="shell narrow" data-page-status="locked"><h1>Jelszó szükséges</h1>
          <form class="stack panel" method="post" action="/api/unlock/\(path.url)">
            \(csrfInput(token(req)))<input type="hidden" name="edit" value="\(editing ? "1" : "0")">
            \(attachment.map { "<input type=\"hidden\" name=\"attachment\" value=\"\(escaped($0))\">" } ?? "")
            <label>Munkalap jelszava<input type="password" name="password" required></label>
            <button class="button primary">Megnyitás</button>
          </form>
        </main>
        \(updates == nil ? "" : statusUpdatesScript)
        """, updates: updates)
}

private func etag(_ revision: Int) -> String { "\"\(revision)\"" }

private func worksheetResponse(_ worksheet: Worksheet, filename: String? = nil) throws -> Response {
    let encoder = JSONEncoder()
    // A letöltött .thnode fájl olvasható (formázott); az API-válasz tömör, mert azt csak a szerkesztő olvassa (docs/PLAN.md A1).
    encoder.outputFormatting = filename == nil ? [.withoutEscapingSlashes] : [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let json = String(decoding: try encoder.encode(worksheet), as: UTF8.self) + "\n"
    let result = response(json, type: "application/json; charset=utf-8", filename: filename)
    result.headers.replaceOrAdd(name: .eTag, value: etag(worksheet.revision))
    return result
}

private struct ProjectCard: Sendable {
    let path: WorksheetPath
    let worksheet: Worksheet
    let access: DocumentAccess
    let count: Int
}

private func menuState(_ rule: DocumentPolicy) -> String {
    "data-hidden=\"\(rule.hidden == true)\" data-frozen=\"\(rule.frozen == true)\" data-password=\"\(rule.passwordHash != nil)\" data-public=\"\(rule.guestReadable == true)\""
}

private func editorMembership(_ access: DocumentAccess) -> String {
    let editors = access.editorNames.filter { $0 != access.sheetRule.owner }
    return "data-editors=\"\(escaped(editors.joined(separator: " ")))\" data-owner=\"\(escaped(access.sheetRule.owner ?? ""))\" data-invite=\"\(access.invitable)\""
}

private func credits(_ sheet: Worksheet, _ access: DocumentAccess) -> String {
    let names = access.editorNames.filter { $0 != access.sheetRule.owner }.map(escaped).joined(separator: ", ")
    return "<div class=\"card-meta\">Létrehozó: \(escaped(sheet.creator ?? "ismeretlen"))</div><div class=\"card-meta\">Szerkesztők: \(names.isEmpty ? "—" : names)</div>"
}

private func projectBadges(_ access: DocumentAccess) -> String {
    let states = [(access.protectedByPassword, "lock", "Jelszóval védett"), (access.hidden, "eye", "Rejtett"),
                  (access.frozen, "hand", "Zárolt szerkesztés"), (access.projectRule.guestReadable == true, "butterfly", "Nyilvános")]
    return states.filter { $0.0 }.map { _, icon, label in
        "<span role=\"img\" aria-label=\"\(label)\" title=\"\(label)\">\(uiIcon(icon))</span>"
    }.joined()
}

private func indexPage(_ items: [ProjectCard], session: SessionInfo, dataFolder: String, updates: PageUpdates.Subscription, raster: Bool) -> Response {
    let cards = items.map { item in
        let count = item.count
        return """
        <a class="project-card panel layers-\(min(count, 2))" data-scope="project" \(editorMembership(item.access)) \(menuState(item.access.projectRule)) data-manage="\(item.access.manageable)" data-color-light="\(escaped(item.worksheet.resolvedBackground(mode: "light")))" data-color-dark="\(escaped(item.worksheet.resolvedBackground(mode: "dark")))" data-revision="\(item.worksheet.revision)" href="/\(item.path.url)">
          \(item.access.readable ? "<img class=\"project-background\(raster ? " is-raster" : "")\" loading=\"lazy\" alt=\"\" width=\"\(PreviewRaster.width)\" height=\"\(PreviewRaster.height)\" src=\"/api/preview/\(item.path.url)?v=\(item.worksheet.revision)\(raster ? "&amp;format=webp" : "")\">" : "")
          <div class="project-summary"><h2>\(escaped(item.worksheet.title))</h2>
          <span class="muted">/\(escaped(item.path.parts.joined(separator: "/")))</span> · \(count + 1) munkalap\(credits(item.worksheet, item.access))<div class="project-badges">\(projectBadges(item.access))</div></div>
        </a>
        """
    }.joined()
    let create = session.user == nil || session.user?.role == .guest ? "" : "<button type=\"button\" class=\"panel sub-preview new-worksheet\">\(uiIcon("plus"))Új projekt</button><button type=\"button\" class=\"panel sub-preview import-package\">\(uiIcon("download"))Projekt importálása (.zip)</button>"
    // Vendég (nincs bejelentkezve, vagy vendég szerepkör): miért nem lát minden projektet, és miért nincs létrehozás.
    let guestNotice = session.user == nil || session.user?.role == .guest
        ? "<p class=\"guest-notice\" role=\"note\">\(uiIcon("butterfly"))<span>Projektek létrehozásához és szerkesztéséhez be kell jelentkezni. Jelenleg csak a szerkesztők által publikusra állított projektek láthatók.</span></p>" : ""
    let openProject = """
        <form class="header-open" method="get" action="/open"><input aria-label="Munkalap útvonala" name="path" placeholder="Munkalap útvonala" required><button class="\(headerButtonClass)" aria-label="Megnyitás">\(uiIcon("folder"))</button></form>
        """
    return htmlPage(title: "Munkalapok", body: """
        \(siteHeader(user: session.user, csrf: session.csrf, actions: buttonLink("/utmutato.html", "Útmutató", symbol: "file", classes: headerButtonClass), centerAction: openProject))
        <main class="shell">
          <script type="module" src="/cards.js"></script>
          <div class="page-heading"><h1>Munkalapok</h1></div>
          \(guestNotice)
          <div class="project-sections" id="worksheet-cards" data-delete="\(session.user?.role == .admin)" data-csrf="\(session.csrf ?? "")">
            <div class="project-list">\(cards.isEmpty ? "<p class=\"muted\">Még nincs munkalap.</p>" : cards)</div>
            \(create.isEmpty ? "" : "<section class=\"project-actions\" aria-label=\"Új projekt\"><div class=\"project-list\">\(create)</div></section>")
          </div>
        </main>
        \(debugBadge(dataFolder: dataFolder))
        """, updates: updates)
}

/// Debug buildben a nyitóoldal jobb alsó sarkában: jelzés és az adatmappa valós útvonala (szimbolikus linkek
/// feloldva). Release buildben üres, így élesben semmi nem kerül az oldalba.
private func debugBadge(dataFolder: String) -> String {
    #if DEBUG
    let real = URL(fileURLWithPath: dataFolder, isDirectory: true).resolvingSymlinksInPath().path
    return """
        <aside class="debug-badge" aria-label="Debug build">
          <strong>Debug build</strong><span title="Adatmappa">\(escaped(real))</span>
        </aside>
        """
    #else
    return ""
    #endif
}

private func siteMode(_ req: Request) -> String? {
    let value = req.query[String.self, at: "mode"] ?? req.cookies["tn_display"]?.string
    return value == "light" || value == "dark" ? value : nil
}

private func passivePage(_ req: Request, path: WorksheetPath, worksheet: Worksheet, session: SessionInfo, access: DocumentAccess, children: [(path: WorksheetPath, worksheet: Worksheet, access: DocumentAccess)], files: [URL], texts: [String: String] = [:], updates: PageUpdates.Subscription) throws -> Response {
    let previews = children.map { child in
        """
        <a class="sub-preview preview-link" data-scope="\(child.path.parts.count == 1 ? "project" : "sheet")" \(menuState(child.access.sheetRule)) data-manage="\(child.access.manageable)" href="/\(child.path.url)">
          <strong><span aria-hidden="true">• </span>\(escaped(child.worksheet.title))</strong>
          <span class="preview-frame">\(child.access.locked ? "<span class=\"locked-preview\">Jelszó szükséges</span>" : "<img loading=\"lazy\" alt=\"\" src=\"/api/preview/\(child.path.url)?v=\(child.worksheet.revision)\">")</span>
          <small>Létrehozó: \(escaped(child.worksheet.creator ?? "ismeretlen"))</small>
        </a>
        """
    }.joined()
    let base = "/" + path.url
    let edit = access.editable
        ? "<a class=\"button small viewer-edit\" href=\"/edit/\(path.url)\" aria-label=\"Szerkesztés\" title=\"Szerkesztés\">\(uiIcon("edit"))Szerkesztés</a>"
        : "<button type=\"button\" class=\"button small viewer-edit\" disabled>\(uiIcon("edit"))Szerkesztés</button>"
    let manageEditors = path.parts.count == 1 && access.invitable
        ? "<button type=\"button\" class=\"button small\" data-manage-editors>Szerkesztők kezelése</button>" : ""
    let downloads = [
        ("svg", "SVG"), ("thnode", "ThinkNodes"), ("text", "Text"),
    ].map { format, title in
        buttonLink("/export/" + format + "/" + path.url, title, symbol: "download", classes: "button small")
    }.joined() + (access.manageable && session.user != nil && session.user?.role != .guest
        ? "<button type=\"button\" class=\"button small\" data-package-export>\(uiIcon("download"))ZIP</button>" : "")
    let note: String
    if let noteID = req.query[String.self, at: "note"] {
        guard let node = worksheet.nodes.first(where: { $0.id == noteID && !$0.isJunction }) else { throw Abort(.notFound) }
        note = """
            <article class="panel passive-note"><a class="muted" href="\(base)">Vissza a munkalaphoz</a>
              <h2>\(escaped(node.name))</h2>
              <div class="formatted-text\(node.justified == true ? " justified-text" : "")">\(node.text.isEmpty ? "<p>Még nincs leírás.</p>" : markdownHTML(node.text))</div>
            </article>
            """
    } else {
        note = ""
    }
    let host = req.headers.first(name: .host)
    let display = worksheet.painted(mode: siteMode(req))
    let theme = Themes.catalog.first { $0.id == worksheet.appearance?.theme }
    let graphicsJSON = String(decoding: try JSONEncoder().encode(theme?.graphics), as: UTF8.self)
    let selectionSample = Worksheet(appearance: worksheet.appearance, title: "", background: "@\(theme?.graphics?.selection ?? 4)")
    let selectionColor = selectionSample.painted(mode: siteMode(req)).backgroundColor
    let canvas = renderWorksheetCanvas(display, noteBase: base, siteHost: host, fileText: { $0.file.flatMap { texts[$0.textKey] } })
    let tooltips = canvas.tooltipNodes.map {
        let justification = $0.justified == true ? " data-justified" : ""
        // Text: mindenhol formázott markdown (a sima sortörés új sor).
        let body = $0.uppercase == true ? "<div class=\"is-uppercase\">\(markdownHTML($0.text))</div>" : markdownHTML($0.text)
        return "<template data-tooltip=\"\($0.id)\" data-align=\"\($0.alignment.rawValue)\"\(justification)>\(body)</template>"
    }.joined()
    let introduction = worksheet.text.map { markdownHTML($0) } ?? ""
    let notes = introduction.isEmpty ? "" :
        "<section class=\"panel worksheet-notes\"><div class=\"formatted-text\(worksheet.textJustified == true ? " justified-text" : "")\">\(introduction)</div></section>"
    let external = worksheet.nodes.compactMap { node -> String? in
        guard let link = node.link?.worksheetLink, link.isExternal(siteHost: host),
              let href = link.destination(from: path) else { return nil }
        return "<li><a href=\"\(escaped(href))\" target=\"_blank\" rel=\"noopener noreferrer\">\(uiIcon("link"))<span>\(escaped(node.name.isEmpty ? href : node.name))</span></a></li>"
    }.joined()
    let attachments = files.map { file in
        let name = file.lastPathComponent
        return "<li><a data-scope=\"attachment\" data-manage=\"\(access.manageable)\" data-document=\"\(path.url)\" data-filename=\"\(escaped(name))\" href=\"/api/attachment/\(path.url)?name=\(encodeQuery(name))\">\(uiIcon("download"))<span>\(escaped(name))</span></a></li>"
    }.joined()
    // Az „Új munkalap” ugyanolyan kártya, mint a további munkalapoké: cím, előnézet helye, alsó sor.
    let newPage = access.editable ? "<button type=\"button\" class=\"sub-preview preview-link new-worksheet new-sheet-card\"><strong><span aria-hidden=\"true\">• </span>Új munkalap</strong><span class=\"preview-frame new-sheet-preview\">\(uiIcon("plus"))</span><small>&#160;</small></button>" : ""
    let childList = "<div class=\"project-list\" data-current-sheet=\"\(path.url)\">\(previews)\(newPage)</div>"
    let childSection = previews.isEmpty ? (newPage.isEmpty ? "" : "<div class=\"viewer-new-worksheet\">\(childList)</div>")
        : "<section class=\"worksheet-section\"><h2>További munkalapok</h2>\(childList)</section>"
    let attachmentSection = attachments.isEmpty ? "" :
        "<section class=\"worksheet-section\"><h2>Mappa tartalma</h2><ul class=\"worksheet-links\">\(attachments)</ul></section>"
    let linkSection = external.isEmpty ? "" :
        "<section class=\"worksheet-section\"><h2>Külső hivatkozások</h2><ul class=\"worksheet-links\">\(external)</ul></section>"
    let parent = path.parts.count > 1
        ? "<a class=\"button small\" aria-label=\"Szülő munkalap\" title=\"Szülő munkalap\" href=\"/\(path.url.split(separator: "/").dropLast().joined(separator: "/"))\">\(uiIcon("parent-up"))</a>" : ""
    return htmlPage(title: worksheet.title, body: """
        \(siteHeader(path: path.url, project: worksheet.title, user: session.user, csrf: session.csrf, canEdit: access.editable))
        <script type="module" src="/viewer.js?v=32"></script>
        <main class="shell" id="worksheet-view" data-graphics="\(escaped(graphicsJSON))" data-selection="\(selectionColor)" data-site-mode="\(siteMode(req) ?? "light")" data-path="\(path.url)" data-csrf="\(token(req))" data-revision="\(worksheet.revision)" data-editable="\(access.editable)" data-member="\(session.user != nil)">
          <a hidden data-current-document data-scope="\(path.parts.count == 1 ? "project" : "sheet")" \(editorMembership(access)) \(menuState(access.sheetRule)) data-manage="\(access.manageable)" href="\(base)">Munkalap</a>
          <div class="viewer-heading">\(parent)<h1><span aria-hidden="true">• </span>\(escaped(worksheet.title))</h1><div class="viewer-heading-credits">\(credits(worksheet, access))</div></div>
          <div class="passive-frame panel">
            <svg class="canvas-background" aria-hidden="true"><rect width="100%" height="100%" fill="\(display.backgroundColor)"/></svg>
            \(canvas.svg)
            <div class="viewer-edit-slot">\(edit)</div>
            <button class="button fullscreen" type="button" aria-label="Teljes képernyő">\(uiIcon("fit"))</button>
            <div class="participants" aria-label="Jelenlévők"></div>
          </div>
          <div data-viewer-notes>\(tooltips)\(notes)\(note)</div>
          <div class="viewer-meta">
            <div class="viewer-credits">\(manageEditors)</div>
            <nav class="viewer-downloads" aria-label="Letöltések">\(downloads)</nav>
          </div>
          <div data-viewer-sections>
            \(childSection)\(attachmentSection)\(linkSection)
          </div>
        </main>
        """, updates: updates)
}

private func requireAdmin(_ req: Request, store: WorksheetStore) throws -> SessionInfo {
    let identity = try session(req, store: store)
    guard try identity.editor().role == .admin else { throw Abort(.forbidden) }
    return identity
}

private struct AdminUserForm: Content {
    var name: String
    var role: Role?
    var password: String?
    /// A fiókhoz rendelt Google-fiók e-mail-címe; hiányzó mező = változatlan, üres = leválasztás.
    var google: String?
    var csrf: String
}

private func localSetup(_ req: Request) -> Bool {
    guard let host = req.headers.first(name: .host)?.lowercased(),
          let ip = req.remoteAddress?.ipAddress, ip == "127.0.0.1" || ip == "::1" else { return false }
    return ["localhost", "127.0.0.1", "[::1]"].contains { host == $0 || host.hasPrefix($0 + ":") }
}

private func hashPassword(_ input: String?) throws -> String? {
    guard let input, !input.isEmpty else { return nil }
    guard (10...72).contains(input.utf8.count) else {
        throw Abort(.unprocessableEntity, reason: "A jelszó hossza 10–72 bájt lehet.")
    }
    return try Bcrypt.hash(input)
}

private func configureAdmin(_ app: any RoutesBuilder, store: WorksheetStore, live: Collaboration, google: Bool) {
    app.get("admin") { req async throws -> Response in
        let identity = try session(req, store: store)
        let updates = live.pages.subscribe(.admin)
        let users = try store.allUsers()
        if users.isEmpty && !store.testMode {
            let form = localSetup(req) ? """
                <form method="post" action="/admin/setup" class="stack panel">
                  \(csrfInput(token(req)))
                  <label>Felhasználónév<input name="name" autocomplete="username" pattern="[a-z0-9-]+" required></label>
                  <label>Jelszó<input name="password" type="password" autocomplete="new-password" minlength="10" required></label>
                  <button class="button primary" type="submit">\(uiIcon("plus"))Adminisztrátor létrehozása</button>
                </form>
                """ : "<p>Az első adminisztrátort helyi böngészőből vagy a <code>./run.sh user admin admin</code> paranccsal hozhatod létre.</p>"
            return htmlPage(title: "Első beállítás", body: """
                \(siteHeader(user: nil, csrf: nil))
                <main class="shell narrow"><h1>Első beállítás</h1>\(form)</main>
                """)
        }
        guard let user = identity.user, let csrf = identity.csrf else { return redirect("/login?next=/admin") }
        guard user.role == .admin else { throw Abort(.forbidden) }
        let settings = try store.settings()
        return adminPage(users: users, settings: settings, requests: try store.accessRequests(),
                         messages: try store.adminMessages(), deleted: store.deletedProjects(), user: user, csrf: csrf,
                         dataDirectoryPath: store.dataDirectoryPath, google: google, updates: updates)
    }

    app.post("admin", "setup") { req async throws -> Response in
        guard localSetup(req) else { throw Abort(.forbidden) }
        let form = try req.content.decode(AdminUserForm.self)
        try verify(req, token: form.csrf)
        let user = try await req.application.threadPool.runIfActive {
            guard let hash = try hashPassword(form.password) else { throw Abort(.unprocessableEntity) }
            try store.setUser(name: form.name, role: .admin, passwordHash: hash, initialOnly: true)
            return User(name: form.name, role: .admin, passwordHash: hash)
        }
        try await signIn(req, user: user)
        live.accountChanged()
        return redirect("/admin")
    }

    app.post("admin", "settings") { req -> Response in
        struct Form: Content { var requireLogin: String?; var googleRequests: String?; var googleDomains: String?; var csrf: String }
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        // A Google-mezők csak bekapcsolt Google-bejelentkezésnél vannak az űrlapon; nélkülük a szabály változatlan.
        let access = try form.googleDomains.map {
            GoogleAccess(requests: form.googleRequests == "on", domains: try GoogleAccess.domains(from: $0))
        }
        try store.setSettings(SiteSettings(requireLogin: form.requireLogin == "on", googleAccess: access))
        live.accountChanged()
        return redirect("/admin")
    }

    // Hozzáférés-kérelmek elbírálása: jóváhagyás, elutasítás, elutasítás feloldása.
    app.post("admin", "requests") { req async throws -> Response in
        struct Form: Content { var email: String; var name: String?; var role: Role?; var action: String; var csrf: String }
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        try await req.application.threadPool.runIfActive {
            switch form.action {
            case "approve":
                guard let name = form.name, let role = form.role else { throw Abort(.badRequest) }
                try store.approveAccess(email: form.email, name: name, role: role)
            case "reject": try store.rejectAccess(email: form.email)
            case "forget": try store.forgetRejectedAccess(email: form.email)
            default: throw Abort(.badRequest)
            }
        }
        live.accountChanged()
        return redirect("/admin")
    }

    app.post("admin", "avatar") { req -> Response in
        struct Form: Content { var name: String; var avatar: Int; var csrf: String }
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        try store.assignAvatar(form.avatar, to: form.name)
        live.accountChanged()
        return redirect("/admin")
    }

    /// A felhasználó színe (#rrggbb); üres érték = vissza az automatikus színre.
    app.post("admin", "color") { req -> Response in
        struct Form: Content { var name: String; var color: String; var csrf: String }
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        try store.assignColor(form.color.isEmpty ? nil : form.color, to: form.name)
        live.accountChanged()
        return redirect("/admin")
    }

    app.post("admin", "users") { req async throws -> Response in
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(AdminUserForm.self)
        try verify(req, token: form.csrf)
        guard let role = form.role else { throw Abort(.badRequest) }
        try await req.application.threadPool.runIfActive {
            try store.setUser(name: form.name, role: role, passwordHash: hashPassword(form.password),
                              google: form.google.map { Optional($0) })
        }
        live.accountChanged()
        return redirect("/admin")
    }

    app.post("admin", "users", "delete") { req -> Response in
        let identity = try requireAdmin(req, store: store)
        let form = try req.content.decode(AdminUserForm.self)
        try verify(req, token: form.csrf)
        guard form.name != identity.user?.name else { throw Abort(.forbidden, reason: "A saját fiókodat nem törölheted.") }
        try store.removeUser(named: form.name)
        live.accountChanged()
        return redirect("/admin")
    }

    // Törölt projektek (a gyökér lomtára): visszaállítás, végleges törlés, ürítés.
    app.post("admin", "trash") { req async throws -> Response in
        struct Form: Content { var id: String?; var action: String; var confirm: String?; var csrf: String }
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        // Végleges törlés csak a „Végleg” jelölőnégyzettel (a gombot a kliens addig tiltja).
        guard form.action == "restore" || form.confirm == "on" else {
            throw Abort(.badRequest, reason: "A végleges törléshez be kell jelölni a „Végleg” négyzetet.")
        }
        let restored = try await req.application.threadPool.runIfActive { () -> WorksheetPath? in
            switch form.action {
            case "restore":
                guard let id = form.id else { throw Abort(.badRequest) }
                return try store.restoreProject(id)
            case "purge":
                guard let id = form.id else { throw Abort(.badRequest) }
                try store.purgeDeletedProjects(id)
            case "empty": try store.purgeDeletedProjects()
            default: throw Abort(.badRequest)
            }
            return nil
        }
        if let restored { live.pages.publish(.structure, at: restored) }
        live.accountChanged()
        return redirect("/admin#deleted-projects")
    }

    app.delete("api", "worksheet", "**") { req async throws -> Response in
        _ = try requireAdmin(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        guard let match = req.headers.first(name: .ifMatch), match.hasPrefix("\""), match.hasSuffix("\""),
              let revision = Int(match.dropFirst().dropLast()) else { throw Abort(.preconditionRequired) }
        let path = try WorksheetPath(req.parameters.getCatchall())
        try await req.application.threadPool.runIfActive { try live.archive(path, expected: revision) }
        return Response(status: .noContent)
    }
}

private func adminPage(users: [User], settings: SiteSettings, requests: (pending: [AccessRequest], rejected: [String]),
                       messages: [AdminMessage], deleted: [WorksheetStore.DeletedProject], user: User, csrf: String,
                       dataDirectoryPath: String, google: Bool, updates: PageUpdates.Subscription) -> Response {
    // Google-fiók mező: csak akkor látszik, ha a szerveren be van állítva a Google-bejelentkezés.
    func googleField(_ email: String?) -> String {
        !google ? "" : "<label>Google-fiók<input name=\"google\" type=\"email\" autocomplete=\"off\" maxlength=\"254\" value=\"\(escaped(email ?? ""))\" placeholder=\"nincs hozzárendelve\"></label>"
    }
    let fieldsClass = google ? "account-fields with-google" : "account-fields"
    // Hozzáférés-kérés Google-fiókkal: szabály a Hozzáférés panelen, kérelmek külön panelen.
    let access = settings.googleAccess ?? GoogleAccess()
    let accessFields = !google ? "" : """
        <label class="check"><input type="checkbox" name="googleRequests"\(access.requests ? " checked" : "")>Ismeretlen Google-fiókkal lehet hozzáférést kérni (adminisztrátori jóváhagyással)</label>
        <label>Csak ezekről az e-mail-domainekről (üresen: bármelyikről)<input name="googleDomains" value="\(escaped(access.domains.joined(separator: ", ")))" placeholder="ceg.hu, masik.com" autocomplete="off"></label>
        """
    let day = DateFormatter()
    day.dateFormat = "yyyy-MM-dd"
    let pendingRows = requests.pending.map { request in
        """
        <div class="account-row">
          <form method="post" action="/admin/requests" class="account-fields with-google request-fields">
            \(csrfInput(csrf))<input type="hidden" name="email" value="\(escaped(request.email))">
            <strong>\(escaped(request.email))<br><small class="muted">\(day.string(from: Date(timeIntervalSince1970: request.date)))</small></strong>
            <label>Felhasználónév<input name="name" pattern="[a-z0-9-]+" maxlength="64" value="\(escaped(request.name))" required></label>
            <label>Szerepkör\(roles(.guest))</label>
            <button class="button primary" type="submit" name="action" value="approve">\(uiIcon("plus"))Jóváhagyás</button>
            <button class="button danger" type="submit" name="action" value="reject" formnovalidate>\(uiIcon("trash"))Elutasítás</button>
          </form>
        </div>
        """
    }.joined()
    let rejectedRows = requests.rejected.map { email in
        """
        <form method="post" action="/admin/requests" class="rejected-request">
          \(csrfInput(csrf))<input type="hidden" name="email" value="\(escaped(email))">
          <span>\(escaped(email))</span>
          <button class="button" type="submit" name="action" value="forget">Feloldás</button>
        </form>
        """
    }.joined()
    // Törölt projektek: a gyökér lomtárából visszaállíthatók vagy véglegesen törölhetők (a jelölőnégyzet a megerősítés).
    let deletedRows = deleted.map { project in
        """
        <form method="post" action="/admin/trash" class="rejected-request deleted-project">
          \(csrfInput(csrf))<input type="hidden" name="id" value="\(escaped(project.id))">
          <span><strong>\(escaped(project.name))</strong>\(project.date.map { " <small class=\"muted\">\(day.string(from: $0))</small>" } ?? "")</span>
          <span class="deleted-actions">
            <button class="button" type="submit" name="action" value="restore">\(uiIcon("restore"))Visszaállítás</button>
            <label class="check"><input type="checkbox" name="confirm" data-enables="purge">Végleg</label>
            <button class="button danger" type="submit" name="action" value="purge" data-purge disabled>\(uiIcon("trash"))Törlés</button>
          </span>
        </form>
        """
    }.joined()
    let deletedPanel = deleted.isEmpty ? "" : """
        <section class="panel admin-panel" id="deleted-projects">
          <h2>Törölt projektek (\(deleted.count))</h2>
          <p class="muted">A törölt projektek a projektmappa <code>.trash</code> mappájában vannak. A visszaállítás az eredeti néven történik; a végleges törlés nem vonható vissza.</p>
          \(deletedRows)
          <form method="post" action="/admin/trash" class="rejected-request deleted-project">
            \(csrfInput(csrf))
            <span>Minden törölt projekt</span>
            <span class="deleted-actions">
              <label class="check"><input type="checkbox" name="confirm" data-enables="purge">Végleg</label>
              <button class="button danger" type="submit" name="action" value="empty" data-purge disabled>\(uiIcon("trash"))Lomtár ürítése</button>
            </span>
          </form>
        </section>
        """
    // Adminisztrátori jelzések (AdminMessage): a fejléc jelvénye ide vezet.
    let messagePanel = messages.isEmpty ? "" : """
        <section class="panel admin-panel admin-messages" id="admin-messages">
          <h2>Teendők</h2>
          <ul>\(messages.map { "<li data-kind=\"\($0.kind.rawValue)\"><a href=\"\(escaped($0.link))\">\(escaped($0.text))</a></li>" }.joined())</ul>
        </section>
        """
    let requestPanel = requests.pending.isEmpty && requests.rejected.isEmpty && !(google && access.requests) ? "" : """
        <section class="panel admin-panel" id="access-requests">
          <h2>Hozzáférési kérelmek\(requests.pending.isEmpty ? "" : " (\(requests.pending.count))")</h2>
          \(requests.pending.isEmpty ? "<p class=\"muted\">Nincs függő kérelem.</p>" : "<p class=\"muted\">Meglévő, Google-fiók nélküli felhasználó nevét megadva a cím hozzá kapcsolódik, a szerepköre nem változik.</p>" + pendingRows)
          \(requests.rejected.isEmpty ? "" : "<details class=\"new-account\"><summary>Elutasított címek (\(requests.rejected.count))</summary>\(rejectedRows)</details>")
        </section>
        """
    func roles(_ current: Role) -> String {
        """
        <select name="role"><option value="editor"\(current == .editor ? " selected" : "")>Szerkesztő</option>
        <option value="admin"\(current == .admin ? " selected" : "")>Adminisztrátor</option>
        <option value="guest"\(current == .guest ? " selected" : "")>Vendég</option></select>
        """
    }
    let accountRows = users.map { account in
        let currentAvatar = settings.preferences?[account.name]?.avatar ?? 1
        let explicitColor = settings.preferences?[account.name]?.color
        let currentColor = settings.color(for: account.name)
        let avatarIcon = avatarSymbol(currentAvatar, color: currentColor)
        let dialogID = "avatar-" + escaped(account.name)
        let avatars = (1...avatarCount).map { number in
            "<button name='avatar' value='\(number)' aria-label='Avatar \(number)' aria-pressed='\(currentAvatar == number)'>\(avatarSymbol(number, color: currentColor))</button>"
        }.joined()
        let swatches = userPalette.map { color in
            "<button name='color' value='\(color)' aria-label='Szín \(color)' aria-pressed='\(explicitColor == color)'><svg viewBox='0 0 1 1' aria-hidden='true'><rect width='1' height='1' rx='.2' fill='\(color)'/></svg></button>"
        }.joined()
        let delete = user.name == account.name ? "" : """
            <form method="post" action="/admin/users/delete">
              \(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))">
              <button class="button danger" type="submit">\(uiIcon("trash"))Törlés</button>
            </form>
            """
        return """
            <div class="account-row">
              <button type="button" class="button current-avatar" data-avatar-dialog="\(dialogID)" aria-haspopup="dialog" aria-label="Avatar kiválasztása · \(escaped(account.name))">\(avatarIcon)</button>
              <dialog id="\(dialogID)" class="panel avatar-dialog" aria-labelledby="\(dialogID)-title">
                <h3 id="\(dialogID)-title">Avatar és szín · \(escaped(account.name))</h3>
                <form class="avatar-picker" method="post" action="/admin/avatar">\(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))">\(avatars)</form>
                <h4>Szín\(explicitColor == nil ? " (automatikus)" : "")</h4>
                <form class="color-picker" method="post" action="/admin/color">\(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))">\(swatches)</form>
                <form class="color-custom" method="post" action="/admin/color">\(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))">
                  <label>Egyedi szín<input type="color" name="color" value="\(currentColor)"></label>
                  <button class="button" type="submit">Beállítás</button>
                </form>
                <form class="color-custom" method="post" action="/admin/color">\(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))"><input type="hidden" name="color" value="">
                  <button class="button" type="submit"\(explicitColor == nil ? " disabled" : "")>Automatikus szín</button>
                </form>
                <form method="dialog"><button class="button">Bezárás</button></form>
              </dialog>
              <form method="post" action="/admin/users" class="\(fieldsClass)">
                \(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))">
                <strong>\(escaped(account.name))</strong>
                <label>Szerepkör\(roles(account.role))</label>
                <label>Új jelszó<input name="password" type="password" autocomplete="new-password" minlength="10" placeholder="Változatlan"></label>
                \(googleField(account.google))
                <button class="button" type="submit">\(uiIcon("save"))Mentés</button>
              </form>
              \(delete)
            </div>
            """
    }.joined()
    return htmlPage(title: "Beállítások", body: """
        \(siteHeader(user: user, csrf: csrf, showAdminLogout: true))
        <script type="module" src="/admin-avatars.js"></script>
        <main class="shell admin-shell">
          <h1>Beállítások</h1>
          \(messagePanel)
          <section class="panel admin-panel">
            <h2>Hozzáférés</h2>
            <form method="post" action="/admin/settings" class="stack">
              \(csrfInput(csrf))
              <label class="check"><input type="checkbox" name="requireLogin"\(settings.requireLogin ? " checked" : "")>Megtekintéshez is szükséges bejelentkezni</label>
              \(accessFields)
              <button class="button primary" type="submit">\(uiIcon("save"))Beállítások mentése</button>
            </form>
          </section>
          \(requestPanel)
          <section class="panel admin-panel">
            <h2>Projektmappa</h2>
            <p>Az aktív projektadatok teljes elérési útja:</p>
            <code class="admin-path">\(escaped(dataDirectoryPath))</code>
          </section>
          \(deletedPanel)
          <section class="panel admin-panel">
            <h2>Felhasználók</h2>
            \(accountRows)
            <details class="new-account">
              <summary>Új felhasználó</summary>
              <form method="post" action="/admin/users" class="\(fieldsClass)">
                \(csrfInput(csrf))
                <label>Név<input name="name" pattern="[a-z0-9-]+" required></label>
                <label>Szerepkör\(roles(.editor))</label>
                <label>Jelszó<input name="password" type="password" autocomplete="new-password" minlength="10"\(google ? " placeholder=\"Google-fiókkal elhagyható\"" : " required")></label>
                \(googleField(nil))
                <button class="button primary" type="submit">\(uiIcon("plus"))Létrehozás</button>
              </form>
            </details>
          </section>
        </main>
        """, updates: updates)
}

private struct LinkPreviewShutdown: LifecycleHandler {
    let previews: LinkPreviews
    func shutdownAsync(_ application: Application) async { await previews.shutdown() }
}
