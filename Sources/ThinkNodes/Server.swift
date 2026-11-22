import Foundation
import NIOSSL
import Vapor

@main
enum ThinkNodes {
    static func main() async {
        do {
            try await run()
        } catch {
            let description = (error as? any AbortError)?.reason ?? String(describing: error)
            FileHandle.standardError.write(Data(("ThinkNodes: " + description + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let directory = Environment.get("THINKNODES_DATA") ?? "Projects"
        let store = try WorksheetStore(root: URL(fileURLWithPath: directory, isDirectory: true),
                                       testMode: Environment.get("THINKNODES_TEST_MODE") == "1")
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "user" {
            try addUser(arguments, store: store)
            return
        }

        let https = arguments.first == "serve-https"
        let command = https ? [CommandLine.arguments[0], "serve"] + Array(arguments.dropFirst()) : [CommandLine.arguments[0]] + arguments
        var environment = try Environment.detect(arguments: command)
        try LoggingSystem.bootstrap(from: &environment)
        let app = try await Application.make(environment)
        do {
            if https {
                guard let cert = Environment.get("THINKNODES_TLS_CERT"), let key = Environment.get("THINKNODES_TLS_KEY") else {
                    throw Abort(.internalServerError, reason: "HTTPS-indításhoz használd a ./run.sh parancsot.")
                }
                let chain = try NIOSSLCertificate.fromPEMFile(cert)
                guard !chain.isEmpty else { throw Abort(.internalServerError, reason: "Üres TLS-tanúsítványlánc.") }
                let tls = TLSConfiguration.makeServerConfiguration(
                    certificateChain: chain.map { .certificate($0) },
                    privateKey: .privateKey(try NIOSSLPrivateKey(file: key, format: .pem))
                )
                _ = try NIOSSLContext(configuration: tls)
                app.http.server.configuration.tlsConfiguration = tls
            }
            store.reconcileAtStartup()
            configure(app, store: store)
            try await app.execute()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private static func addUser(_ arguments: [String], store: WorksheetStore) throws {
        guard arguments.count == 3, validSlug(arguments[1]), let role = Role(rawValue: arguments[2]),
              let password = readLine(), (8...72).contains(password.utf8.count) else {
            throw Abort(.badRequest, reason: "Használat: ./run.sh user név admin|editor|guest. A jelszó 8–72 bájt legyen.")
        }
        let hash = try Bcrypt.hash(password)
        try store.setUser(name: arguments[1], role: role, passwordHash: hash)
        print("Fiók mentve: \(arguments[1]) (\(role.rawValue))")
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
    if store.testMode, let name = data["tester"], isTesterName(name) { return User(name: name, role: .admin, passwordHash: "", avatar: try store.settings().preferences?[name]?.avatar) }
    guard let name = data["user"], let user = try store.user(named: name),
          data["credential"] == user.passwordHash else { return nil }
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

private func signIn(_ req: Request, user: User) async throws {
    if let oldID = req.session.id {
        try await req.application.sessions.driver.deleteSession(oldID, for: req).get()
        req.session.id = nil
    }
    req.session.data = .init()
    req.session.data["user"] = user.name
    req.session.data["credential"] = user.passwordHash
    _ = token(req)
}

private let statusUpdatesScript = #"<script type="module" src="/status-updates.js"></script>"#

private func loginPage(_ req: Request, next: String, message: String? = nil, updates: PageUpdates.Subscription? = nil) -> Response {
    let problem = message.map { "<p class=\"error\" role=\"alert\">\(escaped($0))</p>" } ?? ""
    return htmlPage(title: "Bejelentkezés", body: """
        \(siteHeader(user: nil, csrf: nil))
        <main class="shell narrow" data-page-status="login" data-watch-next="\(escaped(next))">
          <h1>Bejelentkezés</h1>
          \(problem)
          <form method="post" action="/login" class="stack panel">
            \(csrfInput(token(req)))
            <input type="hidden" name="next" value="\(escaped(next))">
            <label>Felhasználónév<input name="name" autocomplete="username" required autofocus></label>
            <label>Jelszó<input name="password" type="password" autocomplete="current-password" required></label>
            <button class="button primary" type="submit">\(uiIcon("login"))Belépés</button>
          </form>
        </main>
        \(updates == nil ? "" : statusUpdatesScript)
        """, updates: updates)
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

func configure(_ application: Application, store: WorksheetStore, secureCookies: Bool? = nil) {
    let live = Collaboration(store: store)
    let assets = application.directory.publicDirectory
    let themeJSON = String(decoding: (try? JSONEncoder().encode(Themes.catalog)) ?? Data(), as: UTF8.self)
    let defaultMotionRate = 33
    let rate = Int(Environment.get("THINKNODES_MOTION_RATE") ?? "") ?? defaultMotionRate
    let motionRate = (1...999_999_999).contains(rate) ? rate : defaultMotionRate
    let secure = secureCookies ?? (application.http.server.configuration.tlsConfiguration != nil || Environment.get("THINKNODES_SECURE_COOKIES") == "1")
    // Without HTTPS the browser drops the SameSite=None asset cookie, so the lease URL alone grants access.
    let webSessions = WebPresentationSessions(requireCookie: secure)
    application.sessions.use(.memory)
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

    application.get("api", "page-changes", ":id") { req async throws -> Response in
        guard let id = req.parameters.get("id").flatMap(UUID.init(uuidString:)),
              let since = req.query[String.self, at: "since"].flatMap(UUID.init(uuidString:)) else { throw Abort(.badRequest) }
        let version = try await live.pages.wait(id, since: since, on: req.eventLoop)
        return response(version.uuidString, type: "text/plain; charset=utf-8")
    }

    app.get("login") { req -> Response in
        let next = safeNext(req.query[String.self, at: "next"])
        let updates = next == "/" || next == "/admin" ? nil : live.pages.subscribe(.index)
        return loginPage(req, next: next, updates: updates)
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
            let response = loginPage(req, next: next, message: "Hibás felhasználónév vagy jelszó.")
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
        if try store.settings().requireLogin && identity.user == nil { return redirect("/login") }
        let updates = live.pages.subscribe(.index)
        let projects = try await req.application.threadPool.runIfActive {
            try store.list(user: identity.user, rootsOnly: true, unlocks: identity.unlocks).map { item -> ProjectCard in
                let access = try store.access(item.path, sheet: item.worksheet, user: identity.user, unlocks: identity.unlocks)
                return ProjectCard(path: item.path, worksheet: item.worksheet, access: access,
                                   count: access.readable ? try store.list(user: identity.user, childrenOf: item.path, recursive: true, unlocks: identity.unlocks).count : 0)
            }
        }
        return indexPage(projects, session: identity, updates: updates)
    }

    app.get("open") { req -> Response in
        guard let input = req.query[String.self, at: "path"],
              let path = try? worksheetPath(input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return missingPage(try session(req, store: store))
        }
        return redirect("/" + path.url)
    }

    configureAdmin(app, store: store, live: live)

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
        let access = try store.access(path, sheet: worksheet, user: user, unlocks: identity.unlocks)
        guard access.editable else { return accessDeniedPage(identity, updates: live.pages.subscribe(.index)) }
        let local = [assets + "vendor/vue.js", assets + "vendor/d3.js"].allSatisfy { FileManager.default.fileExists(atPath: $0) }
        let loading = local ? "Szerkesztő betöltése…" : "A szerkesztőhöz futtasd a teljes ./build.sh parancsot."
        let csrf = token(req)
        let prefs = try user.flatMap { try store.settings().preferences?[$0.name] } ?? UserPreferences()
        let preferences = String(decoding: try JSONEncoder().encode(prefs), as: UTF8.self)
        return htmlPage(title: worksheet.title, body: """
            <div class="editor-root">
            \(siteHeader(path: path.url, project: worksheet.title, user: user, csrf: csrf, editing: true))
            <main id="editor" data-themes="\(escaped(themeJSON))" data-preferences="\(escaped(preferences))" data-path="\(path.url)" data-csrf="\(csrf)" data-motion-rate="\(motionRate)" data-role="\(user?.role.rawValue ?? "guest")" data-user="\(escaped(user?.name ?? ""))">
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
            guard try store.access(path, sheet: worksheet, user: user, unlocks: identity.unlocks).manageable else { throw Abort(.forbidden) }
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
        }
        let path = try WorksheetPath(req.parameters.getCatchall())
        let sessions = req.application.sessions
        guard let cookie = req.cookies[sessions.configuration.cookieName],
              let token = req.headers.first(name: "X-CSRF-Token") else { throw Abort(.forbidden) }
        let form = try req.content.decode(Form.self)
        guard ["poll", "select", "view-select", "leave", "checkpoint", "resign", "ping"].contains(form.action),
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
                                  revision: form.revision, checkpointRevision: form.checkpointRevision, unlocks: documentUnlocks(data), point: form.point)
            }
        }
        var (snapshot, wait) = try await state(form.action, since: form.since)
        if let wait {
            try await wait.get()
            snapshot = try await state("snapshot", since: nil).0
        }
        let result = Response()
        try result.content.encode(snapshot)
        result.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return result
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

    app.post("api", "text") { req -> Response in
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let source = try req.content.decode(MarkdownForm.self).text
        guard source.utf8.count <= 100_000 else { throw Abort(.payloadTooLarge) }
        return response(markdownHTML(source), type: "text/html; charset=utf-8")
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
            return (sheet, try store.fileTexts(path, sheet: sheet, user: identity.user, unlocks: identity.unlocks))
        }
        switch req.parameters.get("format") {
        case "svg":
            return response("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + boardSVG(worksheet, siteHost: req.headers.first(name: .host), assetBase: "/" + path.url, mode: siteMode(req),
                                                                            fileText: { $0.file.flatMap { texts[$0.asset] } }),
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
        switch try await req.application.threadPool.runIfActive({ try store.preview(path, user: identity.user, unlocks: identity.unlocks, mode: siteMode(req)) }) {
        case .drawing(let svg): return response(svg, type: "image/svg+xml; charset=utf-8")
        case .image(let file, let mime):
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

    app.get("api", "attachment", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        if try store.settings().requireLogin && identity.user == nil { throw Abort(.unauthorized) }
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
        let children = try await req.application.threadPool.runIfActive {
            try store.list(user: identity.user, childrenOf: path, unlocks: identity.unlocks)
        }
        let access = try store.access(path, sheet: worksheet, user: identity.user, unlocks: identity.unlocks)
        let files = try store.contents(path, user: identity.user, unlocks: identity.unlocks)
        let texts = try store.fileTexts(path, sheet: worksheet, user: identity.user, unlocks: identity.unlocks)
        let pages = try children.map { child in
            (child.path, child.worksheet, try store.access(child.path, sheet: child.worksheet, user: identity.user, unlocks: identity.unlocks))
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
            guard let (asset, directory, publicRead) = try await req.application.threadPool.runIfActive({
                try store.webAsset(candidate, user: viewer.user, unlocks: viewer.unlocks)
            }) else { continue }

            guard let asset else {
                let name = escaped(candidate.reference.name)
                return response("""
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 100">
                      <rect width="320" height="100" rx="8" fill="#233b53"/>
                      <path d="M143 16h34v22h-34z M160 38v6 M150 45h20" stroke="#fff" fill="none" stroke-width="3"/>
                      <text x="160" y="77" fill="white" text-anchor="middle" font-family="sans-serif" font-size="17">\(name)</text>
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

func encodeQuery(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
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
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
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
    return "data-editors=\"\(escaped(editors.joined(separator: " ")))\" data-owner=\"\(escaped(access.sheetRule.owner ?? ""))\""
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

private func indexPage(_ items: [ProjectCard], session: SessionInfo, updates: PageUpdates.Subscription) -> Response {
    let cards = items.map { item in
        let count = item.count
        return """
        <a class="project-card panel layers-\(min(count, 2))" data-scope="project" \(editorMembership(item.access)) \(menuState(item.access.projectRule)) data-manage="\(item.access.manageable)" data-color-light="\(escaped(item.worksheet.resolvedBackground(mode: "light")))" data-color-dark="\(escaped(item.worksheet.resolvedBackground(mode: "dark")))" data-revision="\(item.worksheet.revision)" href="/\(item.path.url)">
          \(item.access.readable ? "<img class=\"project-background\" loading=\"lazy\" alt=\"\" src=\"/api/preview/\(item.path.url)?v=\(item.worksheet.revision)\">" : "")
          <div class="project-summary"><h2>\(escaped(item.worksheet.title))</h2>
          <span class="muted">/\(escaped(item.path.parts.joined(separator: "/")))</span> · \(count + 1) munkalap\(credits(item.worksheet, item.access))<div class="project-badges">\(projectBadges(item.access))</div></div>
        </a>
        """
    }.joined()
    let create = session.user == nil || session.user?.role == .guest ? "" : "<button type=\"button\" class=\"panel sub-preview new-worksheet\">\(uiIcon("plus"))Új projekt</button>"
    let openProject = """
        <form class="header-open" method="get" action="/open"><input aria-label="Munkalap útvonala" name="path" placeholder="Munkalap útvonala" required><button class="\(headerButtonClass)" aria-label="Megnyitás">\(uiIcon("folder"))</button></form>
        """
    return htmlPage(title: "Munkalapok", body: """
        \(siteHeader(user: session.user, csrf: session.csrf, actions: buttonLink("/utmutato.html", "Útmutató", symbol: "file", classes: headerButtonClass), centerAction: openProject))
        <main class="shell">
          <script type="module" src="/cards.js"></script>
          <div class="page-heading"><h1>Munkalapok</h1></div>
          <div class="project-list" id="worksheet-cards" data-delete="\(session.user?.role == .admin)" data-csrf="\(session.csrf ?? "")">\(cards.isEmpty && create.isEmpty ? "<p class=\"muted\">Még nincs munkalap.</p>" : cards)\(create)</div>
        </main>
        """, updates: updates)
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
    let manageEditors = path.parts.count == 1 && access.manageable
        ? "<button type=\"button\" class=\"button small\" data-manage-editors>Szerkesztők kezelése</button>" : ""
    let managePresentations = access.manageable
        ? "<button type=\"button\" class=\"button small\" data-web-presentations>\(uiIcon("website"))Prezentációk</button>" : ""
    let downloads = [
        ("svg", "SVG"), ("thnode", "ThinkNodes"), ("text", "Text"),
    ].map { format, title in
        buttonLink("/export/" + format + "/" + path.url, title, symbol: "download", classes: "button small")
    }.joined()
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
    let canvas = renderWorksheetCanvas(display, noteBase: base, siteHost: host, fileText: { $0.file.flatMap { texts[$0.asset] } })
    let tooltips = canvas.tooltipNodes.map {
        let justification = $0.justified == true ? " data-justified" : ""
        return "<template data-tooltip=\"\($0.id)\"\(justification)>\(markdownHTML($0.text))</template>"
    }.joined()
    let introduction = worksheet.text.map(markdownHTML) ?? ""
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
        <script type="module" src="/viewer.js?v=18"></script>
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
            <div class="viewer-credits">\(manageEditors)\(managePresentations)</div>
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

private func configureAdmin(_ app: any RoutesBuilder, store: WorksheetStore, live: Collaboration) {
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
        return adminPage(users: users, settings: settings, user: user, csrf: csrf,
                         dataDirectoryPath: store.dataDirectoryPath, updates: updates)
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
        struct Form: Content { var requireLogin: String?; var csrf: String }
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        try store.setSettings(SiteSettings(requireLogin: form.requireLogin == "on"))
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

    app.post("admin", "users") { req async throws -> Response in
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(AdminUserForm.self)
        try verify(req, token: form.csrf)
        guard let role = form.role else { throw Abort(.badRequest) }
        try await req.application.threadPool.runIfActive {
            try store.setUser(name: form.name, role: role, passwordHash: hashPassword(form.password))
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

private func adminPage(users: [User], settings: SiteSettings, user: User, csrf: String,
                       dataDirectoryPath: String, updates: PageUpdates.Subscription) -> Response {
    func roles(_ current: Role) -> String {
        """
        <select name="role"><option value="editor"\(current == .editor ? " selected" : "")>Szerkesztő</option>
        <option value="admin"\(current == .admin ? " selected" : "")>Adminisztrátor</option>
        <option value="guest"\(current == .guest ? " selected" : "")>Vendég</option></select>
        """
    }
    let accountRows = users.map { account in
        let currentAvatar = settings.preferences?[account.name]?.avatar ?? 1
        let avatarIcon = "<img src='/icons/avatar-\(currentAvatar).svg' alt=''>"
        let dialogID = "avatar-" + escaped(account.name)
        let avatars = (1...12).map { number in
            "<button name='avatar' value='\(number)' aria-label='Avatar \(number)' aria-pressed='\(currentAvatar == number)'><img src='/icons/avatar-\(number).svg' alt=''></button>"
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
                <h3 id="\(dialogID)-title">Avatar · \(escaped(account.name))</h3>
                <form class="avatar-picker" method="post" action="/admin/avatar">\(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))">\(avatars)</form>
                <form method="dialog"><button class="button">Mégse</button></form>
              </dialog>
              <form method="post" action="/admin/users" class="account-fields">
                \(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))">
                <strong>\(escaped(account.name))</strong>
                <label>Szerepkör\(roles(account.role))</label>
                <label>Új jelszó<input name="password" type="password" autocomplete="new-password" minlength="10" placeholder="Változatlan"></label>
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
          <section class="panel admin-panel">
            <h2>Hozzáférés</h2>
            <form method="post" action="/admin/settings" class="stack">
              \(csrfInput(csrf))
              <label class="check"><input type="checkbox" name="requireLogin"\(settings.requireLogin ? " checked" : "")>Megtekintéshez is szükséges bejelentkezni</label>
              <button class="button primary" type="submit">\(uiIcon("save"))Beállítások mentése</button>
            </form>
          </section>
          <section class="panel admin-panel">
            <h2>Projektmappa</h2>
            <p>Az aktív projektadatok teljes elérési útja:</p>
            <code class="admin-path">\(escaped(dataDirectoryPath))</code>
          </section>
          <section class="panel admin-panel">
            <h2>Felhasználók</h2>
            \(accountRows)
            <details class="new-account">
              <summary>Új felhasználó</summary>
              <form method="post" action="/admin/users" class="account-fields">
                \(csrfInput(csrf))
                <label>Név<input name="name" pattern="[a-z0-9-]+" required></label>
                <label>Szerepkör\(roles(.editor))</label>
                <label>Jelszó<input name="password" type="password" autocomplete="new-password" minlength="10" required></label>
                <button class="button primary" type="submit">\(uiIcon("plus"))Létrehozás</button>
              </form>
            </details>
          </section>
        </main>
        """, updates: updates)
}
