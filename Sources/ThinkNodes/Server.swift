import Foundation
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
        let directory = Environment.get("THINKNODES_DATA") ?? "Data"
        let store = try WorksheetStore(root: URL(fileURLWithPath: directory, isDirectory: true))
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "user" {
            try addUser(arguments, store: store)
            return
        }

        var environment = try Environment.detect()
        try LoggingSystem.bootstrap(from: &environment)
        let app = try await Application.make(environment)
        do {
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
              let password = readLine(), (10...72).contains(password.utf8.count) else {
            throw Abort(.badRequest, reason: "Használat: ./run.sh user név admin|editor. A jelszó 10–72 bájt legyen.")
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
    var markdown: String
}

private struct CanvasMarkdownRequest: Content {
    var sources: [String]
}

private struct CanvasMarkdownResponse: Content {
    var text: [String]
}

private struct SessionInfo: Sendable {
    var user: User?
    var csrf: String?

    func editor() throws -> User {
        guard let user else { throw Abort(.unauthorized, reason: "A szerkesztéshez jelentkezz be.") }
        return user
    }
}

private func session(_ req: Request, store: WorksheetStore) throws -> SessionInfo {
    guard req.hasSession else { return SessionInfo(user: nil, csrf: nil) }
    guard let name = req.session.data["user"], let user = try store.user(named: name),
          req.session.data["credential"] == user.passwordHash else {
        return SessionInfo(user: nil, csrf: nil)
    }
    return SessionInfo(user: user, csrf: token(req))
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

private func loginPage(_ req: Request, next: String, message: String? = nil) -> Response {
    let problem = message.map { "<p class=\"error\" role=\"alert\">\(escaped($0))</p>" } ?? ""
    return htmlPage(title: "Bejelentkezés", body: """
        \(siteHeader(user: nil, csrf: nil))
        <main class="shell narrow">
          <h1>Bejelentkezés</h1>
          \(problem)
          <form method="post" action="/login" class="stack panel">
            \(csrfInput(token(req)))
            <input type="hidden" name="next" value="\(escaped(next))">
            <label>Felhasználónév<input name="name" autocomplete="username" required autofocus></label>
            <label>Jelszó<input name="password" type="password" autocomplete="current-password" required></label>
            <button class="button primary" type="submit">Belépés</button>
          </form>
        </main>
        """)
}

func configure(_ app: Application, store: WorksheetStore) {
    let assets = app.directory.publicDirectory
    let secure = Environment.get("THINKNODES_SECURE_COOKIES") == "1"
    app.sessions.use(.memory)
    app.sessions.configuration = .init(cookieName: "thinknodes_session") { sessionID in
        .init(string: sessionID.string, path: "/", isSecure: secure, isHTTPOnly: true, sameSite: .lax)
    }
    app.middleware.use(FileMiddleware(publicDirectory: assets))
    app.middleware.use(app.sessions.middleware)
    app.routes.defaultMaxBodySize = "16mb"

    app.get("health") { _ in "ok" }

    app.get("login") { req -> Response in
        loginPage(req, next: safeNext(req.query[String.self, at: "next"]))
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
        let worksheets = try await req.application.threadPool.runIfActive { try store.list() }
        return indexPage(worksheets, session: identity)
    }

    app.get("open") { req -> Response in
        guard let input = req.query[String.self, at: "path"] else { throw Abort(.badRequest) }
        let path = try worksheetPath(input.trimmingCharacters(in: .whitespacesAndNewlines))
        return redirect("/" + path.url)
    }

    configureAdmin(app, store: store)

    app.get("edit", "**") { req async throws -> Response in
        let path = try WorksheetPath(req.parameters.getCatchall())
        let identity = try session(req, store: store)
        guard let user = identity.user, let csrf = identity.csrf else {
            return redirect("/login?next=/edit/" + path.url)
        }
        let worksheet = try await req.application.threadPool.runIfActive { try store.open(path, authenticated: true) }
        let local = [assets + "vendor/vue.js", assets + "vendor/d3.js"].allSatisfy { FileManager.default.fileExists(atPath: $0) }
        let loading = local ? "Szerkesztő betöltése…" : "A szerkesztőhöz futtasd a teljes ./build.sh parancsot."
        return htmlPage(title: worksheet.title, body: """
            <main id="editor" class="editor-root" data-path="\(path.url)" data-csrf="\(csrf)" data-role="\(user.role.rawValue)">
              <p class="editor-loading">\(loading)</p>
              <noscript><p>A szerkesztőhöz JavaScript szükséges.</p><a href="/\(path.url)">Megtekintés</a></noscript>
            </main>
            """, scripts: local)
    }

    app.get("api", "worksheet", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        let worksheet = try await req.application.threadPool.runIfActive {
            try store.load(path, authenticated: identity.user != nil)
        }
        return try worksheetResponse(worksheet)
    }

    app.put("api", "worksheet", "**") { req async throws -> Response in
        _ = try session(req, store: store).editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let submitted = try req.content.decode(Worksheet.self)
        guard let match = req.headers.first(name: .ifMatch) else {
            throw Abort(.preconditionRequired, reason: "A mentéshez szükséges a munkalap revíziója.")
        }
        guard match == etag(submitted.revision) else {
            throw Abort(.badRequest, reason: "Érvénytelen mentési revízió.")
        }
        let path = try WorksheetPath(req.parameters.getCatchall())
        let worksheet = try await req.application.threadPool.runIfActive { try store.update(path, worksheet: submitted) }
        return try worksheetResponse(worksheet)
    }

    app.post("api", "markdown") { req -> Response in
        _ = try session(req, store: store).editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let source = try req.content.decode(MarkdownForm.self).markdown
        guard source.utf8.count <= 100_000 else { throw Abort(.payloadTooLarge) }
        return response(markdownHTML(source), type: "text/html; charset=utf-8")
    }

    app.post("api", "markdown", "canvas") { req async throws -> CanvasMarkdownResponse in
        _ = try session(req, store: store).editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let sources = try req.content.decode(CanvasMarkdownRequest.self).sources
        guard sources.count <= 2_000, sources.allSatisfy({ $0.utf8.count <= 100_000 }) else {
            throw Abort(.payloadTooLarge)
        }
        return try await req.application.threadPool.runIfActive {
            CanvasMarkdownResponse(text: sources.map(canvasMarkdown))
        }
    }

    app.get("export", ":format", "**") { req async throws -> Response in
        let path = try WorksheetPath(req.parameters.getCatchall())
        let identity = try session(req, store: store)
        let worksheet = try await req.application.threadPool.runIfActive {
            try store.load(path, authenticated: identity.user != nil)
        }
        switch req.parameters.get("format") {
        case "svg":
            return response("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + boardSVG(worksheet),
                            type: "image/svg+xml; charset=utf-8", filename: "\(path.name).svg")
        case "json":
            return try worksheetResponse(worksheet, filename: "\(path.name).json")
        case "markdown":
            return response(worksheetMarkdown(worksheet), type: "text/markdown; charset=utf-8", filename: "\(path.name).md")
        default:
            throw Abort(.notFound)
        }
    }

    app.get("**") { req async throws -> Response in
        let path = try WorksheetPath(req.parameters.getCatchall())
        let identity = try session(req, store: store)
        let worksheet: Worksheet
        do {
            worksheet = try await req.application.threadPool.runIfActive {
                try store.open(path, authenticated: identity.user != nil)
            }
        } catch let error as Abort where error.status == .unauthorized {
            return redirect("/login?next=/" + path.url)
        }
        return try passivePage(req, path: path, worksheet: worksheet, session: identity)
    }
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

private func indexPage(_ items: [(path: WorksheetPath, worksheet: Worksheet)], session: SessionInfo) -> Response {
    let cards = items.map { item in
        """
        <a class="project-card panel" href="/\(item.path.url)">
          <span class="project-glyph" aria-hidden="true">◇</span>
          <div><h2>\(escaped(item.worksheet.title))</h2>
          <span class="muted">/\(escaped(item.path.parts.joined(separator: "/")))</span></div>
        </a>
        """
    }.joined()
    return htmlPage(title: "Munkalapok", body: """
        \(siteHeader(user: session.user, csrf: session.csrf))
        <main class="shell">
          <div class="page-heading"><h1>Munkalapok</h1></div>
          <form class="open-path panel" method="get" action="/open">
            <label>Munkalap útvonala<input name="path" placeholder="gondolatok/otletek1" required></label>
            <button class="button primary" type="submit">Megnyitás</button>
          </form>
          <div class="project-list">\(cards.isEmpty ? "<p class=\"muted\">Még nincs munkalap.</p>" : cards)</div>
        </main>
        """)
}

private func passivePage(_ req: Request, path: WorksheetPath, worksheet: Worksheet, session: SessionInfo) throws -> Response {
    let base = "/" + path.url
    let edit = session.user == nil ? "" : "<a class=\"button primary\" href=\"/edit/\(path.url)\">Szerkesztés</a>"
    let note: String
    if let noteID = req.query[String.self, at: "note"] {
        guard let node = worksheet.nodes.first(where: { $0.id == noteID }) else { throw Abort(.notFound) }
        note = """
            <article class="panel passive-note"><a class="muted" href="\(base)">Vissza a munkalaphoz</a>
              <h2>\(escaped(node.title))</h2>
              \(renderedComment(node.comment))
              <div class="markdown">\(node.markdown.isEmpty ? "<p>Még nincs leírás.</p>" : markdownHTML(node.markdown))</div>
            </article>
            """
    } else {
        note = ""
    }
    let description = renderedComment(worksheet.comment)
    let introduction = worksheet.markdown.map(markdownHTML) ?? ""
    let notes = description.isEmpty && introduction.isEmpty ? "" :
        "<section class=\"panel worksheet-notes\">\(description)<div class=\"markdown\">\(introduction)</div></section>"
    return htmlPage(title: worksheet.title, body: """
        \(siteHeader(path: path.url, project: worksheet.title, user: session.user, csrf: session.csrf))
        <main class="shell">
          <div class="page-heading"><h1>\(escaped(worksheet.title))</h1>\(edit)</div>
          <div class="browse-bar"><span class="muted">/\(escaped(path.parts.joined(separator: "/")))</span>
            <nav class="exports" aria-label="Letöltések"><a href="/export/svg/\(path.url)">SVG</a><a href="/export/json/\(path.url)">JSON</a><a href="/export/markdown/\(path.url)">Markdown</a></nav>
          </div>
          <div class="passive-frame panel">\(worksheet.nodes.isEmpty ? "<p class=\"muted empty\">A munkalap üres.</p>" : boardSVG(worksheet, noteBase: base))</div>
          \(notes)
          \(note)
        </main>
        """)
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

private func configureAdmin(_ app: Application, store: WorksheetStore) {
    app.get("admin") { req async throws -> Response in
        let identity = try session(req, store: store)
        let users = try store.allUsers()
        if users.isEmpty {
            let form = localSetup(req) ? """
                <form method="post" action="/admin/setup" class="stack panel">
                  \(csrfInput(token(req)))
                  <label>Felhasználónév<input name="name" autocomplete="username" pattern="[a-z0-9-]+" required></label>
                  <label>Jelszó<input name="password" type="password" autocomplete="new-password" minlength="10" required></label>
                  <button class="button primary" type="submit">Adminisztrátor létrehozása</button>
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
        return adminPage(users: users, settings: settings, user: user, csrf: csrf)
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
        return redirect("/admin")
    }

    app.post("admin", "settings") { req -> Response in
        struct Form: Content { var requireLogin: String?; var guestCreation: String?; var csrf: String }
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        try store.setSettings(SiteSettings(requireLogin: form.requireLogin == "on", guestCreation: form.guestCreation == "on"))
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
        return redirect("/admin")
    }

    app.post("admin", "users", "delete") { req -> Response in
        let identity = try requireAdmin(req, store: store)
        let form = try req.content.decode(AdminUserForm.self)
        try verify(req, token: form.csrf)
        guard form.name != identity.user?.name else { throw Abort(.forbidden, reason: "A saját fiókodat nem törölheted.") }
        try store.removeUser(named: form.name)
        return redirect("/admin")
    }

    app.delete("api", "worksheet", "**") { req async throws -> Response in
        _ = try requireAdmin(req, store: store)
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        guard let match = req.headers.first(name: .ifMatch), match.hasPrefix("\""), match.hasSuffix("\""),
              let revision = Int(match.dropFirst().dropLast()) else { throw Abort(.preconditionRequired) }
        let path = try WorksheetPath(req.parameters.getCatchall())
        try await req.application.threadPool.runIfActive { try store.archive(path, expected: revision) }
        return Response(status: .noContent)
    }
}

private func adminPage(users: [User], settings: SiteSettings, user: User, csrf: String) -> Response {
    func roles(_ current: Role) -> String {
        """
        <select name="role"><option value="editor"\(current == .editor ? " selected" : "")>Szerkesztő</option>
        <option value="admin"\(current == .admin ? " selected" : "")>Adminisztrátor</option></select>
        """
    }
    let accountRows = users.map { account in
        let delete = user.name == account.name ? "" : """
            <form method="post" action="/admin/users/delete">
              \(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))">
              <button class="button danger" type="submit">Törlés</button>
            </form>
            """
        return """
            <div class="account-row">
              <form method="post" action="/admin/users" class="account-fields">
                \(csrfInput(csrf))<input type="hidden" name="name" value="\(escaped(account.name))">
                <strong>\(escaped(account.name))</strong>
                <label>Szerepkör\(roles(account.role))</label>
                <label>Új jelszó<input name="password" type="password" autocomplete="new-password" minlength="10" placeholder="Változatlan"></label>
                <button class="button" type="submit">Mentés</button>
              </form>
              \(delete)
            </div>
            """
    }.joined()
    return htmlPage(title: "Beállítások", body: """
        \(siteHeader(user: user, csrf: csrf))
        <main class="shell admin-shell">
          <h1>Beállítások</h1>
          <section class="panel admin-panel">
            <h2>Hozzáférés</h2>
            <form method="post" action="/admin/settings" class="stack">
              \(csrfInput(csrf))
              <label class="check"><input type="checkbox" name="requireLogin"\(settings.requireLogin ? " checked" : "")>Megtekintéshez is szükséges bejelentkezni</label>
              <label class="check"><input type="checkbox" name="guestCreation"\(settings.guestCreation ? " checked" : "")>Vendég is létrehozhat hiányzó munkalapot nyilvános módban</label>
              <button class="button primary" type="submit">Beállítások mentése</button>
            </form>
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
                <button class="button primary" type="submit">Létrehozás</button>
              </form>
            </details>
          </section>
        </main>
        """)
}
