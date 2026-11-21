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
    if store.testMode, let name = data["tester"], isTesterName(name) { return User(name: name, role: .admin, passwordHash: "") }
    guard let name = data["user"], let user = try store.user(named: name),
          data["credential"] == user.passwordHash else { return nil }
    return user
}

private func documentUnlocks(_ data: SessionData) -> Set<String> {
    Set((data["document-unlocks"] ?? "").split(separator: "\n").map(String.init))
}

private func session(_ req: Request, store: WorksheetStore) throws -> SessionInfo {
    guard req.hasSession, let user = try authenticatedUser(req.session.data, store: store) else {
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
            <button class="button primary" type="submit">\(uiIcon("login"))Belépés</button>
          </form>
        </main>
        """)
}

func configure(_ application: Application, store: WorksheetStore) {
    let live = Collaboration(store: store)
    let assets = application.directory.publicDirectory
    let defaultMotionRate = 33
    let rate = Int(Environment.get("THINKNODES_MOTION_RATE") ?? "") ?? defaultMotionRate
    let motionRate = (1...999_999_999).contains(rate) ? rate : defaultMotionRate
    let secure = application.http.server.configuration.tlsConfiguration != nil || Environment.get("THINKNODES_SECURE_COOKIES") == "1"
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
    application.middleware.use(FileMiddleware(publicDirectory: assets, cachePolicy: .noCache))
    let app = application.grouped(application.sessions.middleware)
    application.routes.defaultMaxBodySize = "16mb"

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
        let projects = try await req.application.threadPool.runIfActive {
            try store.list(user: identity.user, rootsOnly: true, unlocks: identity.unlocks).map { item -> ProjectCard in
                let access = try store.access(item.path, sheet: item.worksheet, user: identity.user, unlocks: identity.unlocks)
                return ProjectCard(path: item.path, worksheet: item.worksheet, access: access,
                                   count: access.readable ? try store.list(user: identity.user, childrenOf: item.path, recursive: true, unlocks: identity.unlocks).count : 0)
            }
        }
        return indexPage(projects, session: identity)
    }

    app.get("open") { req -> Response in
        guard let input = req.query[String.self, at: "path"] else { throw Abort(.badRequest) }
        let path = try worksheetPath(input.trimmingCharacters(in: .whitespacesAndNewlines))
        return redirect("/" + path.url)
    }

    configureAdmin(app, store: store, live: live)

    app.get("edit", "**") { req async throws -> Response in
        let path = try WorksheetPath(req.parameters.getCatchall())
        let identity = try session(req, store: store)
        guard let user = identity.user, let csrf = identity.csrf else {
            return redirect("/login?next=/edit/" + path.url)
        }
        let worksheet: Worksheet
        do {
            worksheet = try await req.application.threadPool.runIfActive { try store.open(path, user: user, unlocks: identity.unlocks) }
        } catch let error as Abort where error.status == .locked {
            return unlockPage(req, path: path, identity: identity, editing: true)
        }
        let access = try store.access(path, sheet: worksheet, user: user, unlocks: identity.unlocks)
        guard access.editable else { throw Abort(.forbidden) }
        let local = [assets + "vendor/vue.js", assets + "vendor/d3.js"].allSatisfy { FileManager.default.fileExists(atPath: $0) }
        let loading = local ? "Szerkesztő betöltése…" : "A szerkesztőhöz futtasd a teljes ./build.sh parancsot."
        let actions = "<div id='editor-tools'></div>" + headerLink("/" + path.url, "Bezárás", symbol: "left")
        return htmlPage(title: worksheet.title, body: """
            <div class="editor-root">
            \(siteHeader(path: path.url, project: worksheet.title, user: user, csrf: csrf, actions: actions, editing: true))
            <main id="editor" data-folder="\(access.folderPath)" data-path="\(path.url)" data-csrf="\(csrf)" data-motion-rate="\(motionRate)" data-role="\(user.role.rawValue)" data-user="\(escaped(user.name))">
              <p class="editor-loading">\(loading)</p>
              <noscript><p>A szerkesztőhöz JavaScript szükséges.</p><a href="/\(path.url)">Megtekintés</a></noscript>
            </main></div>
            """, scripts: local)
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
            let worksheet = try store.load(path, user: user, unlocks: identity.unlocks)
            guard try store.access(path, sheet: worksheet, user: user, unlocks: identity.unlocks).manageable else { throw Abort(.forbidden) }
            return try store.allUsers().map(\.name)
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
        guard let user = identity.user else { throw Abort(.unauthorized) }
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        let sheet = try await req.application.threadPool.runIfActive {
            try store.open(path, user: user, createOnly: true, unlocks: identity.unlocks, directory: req.query[String.self, at: "folder"] == "1")
        }
        return try worksheetResponse(sheet)
    }

    app.put("api", "worksheet", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let user = try identity.editor()
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
        _ = try session(req, store: store).editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let source = try req.content.decode(MarkdownForm.self).text
        guard source.utf8.count <= 100_000 else { throw Abort(.payloadTooLarge) }
        return response(markdownHTML(source), type: "text/html; charset=utf-8")
    }

    app.post("api", "text", "canvas") { req async throws -> CanvasMarkdownResponse in
        _ = try session(req, store: store).editor()
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
        let worksheet = try await req.application.threadPool.runIfActive {
            try store.load(path, user: identity.user, unlocks: identity.unlocks)
        }
        switch req.parameters.get("format") {
        case "svg":
            return response("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + boardSVG(worksheet, siteHost: req.headers.first(name: .host), assetBase: "/" + path.url),
                            type: "image/svg+xml; charset=utf-8", filename: "\(path.name).svg")
        case "thnode", "json":
            return try worksheetResponse(worksheet, filename: "\(path.name).thnode")
        case "text", "markdown":
            return response(worksheetMarkdown(worksheet), type: "text/markdown; charset=utf-8", filename: "\(path.name).md")
        default:
            throw Abort(.notFound)
        }
    }

    app.get("api", "preview", "**") { req async throws -> Response in
        let identity = try session(req, store: store)
        let path = try WorksheetPath(req.parameters.getCatchall())
        let svg = try await req.application.threadPool.runIfActive { try store.previewSVG(path, user: identity.user, unlocks: identity.unlocks) }
        return response(svg, type: "image/svg+xml; charset=utf-8")
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
        let user = try identity.editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let body = req.body.data, let type = req.headers.first(name: .contentType) else { throw Abort(.badRequest) }
        let bytes = Data(body.readableBytesView)
        let imageName = req.query[String.self, at: "name"]
        let filename = req.query[String.self, at: "filename"]
        let name = try await req.application.threadPool.runIfActive {
            try store.storeMedia(bytes, type: type, imageName: imageName, filename: filename, at: path, user: user, unlocks: identity.unlocks)
        }
        return ["asset": name]
    }

    app.post("api", "attachment", "**") { req async throws -> HTTPStatus in
        let identity = try session(req, store: store)
        let user = try identity.editor()
        try verify(req, token: req.headers.first(name: "X-CSRF-Token"))
        let path = try WorksheetPath(req.parameters.getCatchall())
        guard let name = req.query[String.self, at: "name"] else { throw Abort(.badRequest) }
        let bytes = req.body.data.map { Data($0.readableBytesView) } ?? Data()
        try await req.application.threadPool.runIfActive {
            try store.storeAttachment(bytes, named: name, at: path, user: user, unlocks: identity.unlocks)
        }
        return .created
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

    app.get("**") { req async throws -> Response in
        let path = try WorksheetPath(req.parameters.getCatchall())
        let identity = try session(req, store: store)
        let worksheet: Worksheet
        do {
            let opened = try await req.application.threadPool.runIfActive {
                try store.openWithStatus(path, user: identity.user, unlocks: identity.unlocks)
            }
            if opened.created { return redirect("/edit/" + path.url) }
            worksheet = opened.worksheet
        } catch let error as Abort where error.status == .unauthorized {
            return redirect("/login?next=/" + path.url)
        }
        catch let error as Abort where error.status == .locked { return unlockPage(req, path: path, identity: identity) }
        let children = try await req.application.threadPool.runIfActive {
            try store.list(user: identity.user, childrenOf: path, unlocks: identity.unlocks)
        }
        let access = try store.access(path, sheet: worksheet, user: identity.user, unlocks: identity.unlocks)
        let files = try store.contents(path, user: identity.user, unlocks: identity.unlocks)
        let pages = try children.map { child in
            (child.path, child.worksheet, try store.access(child.path, sheet: child.worksheet, user: identity.user, unlocks: identity.unlocks))
        }
        return try passivePage(req, path: path, worksheet: worksheet, session: identity, access: access, children: pages, files: files)
    }
}

func encodeQuery(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
}

private func unlockPage(_ req: Request, path: WorksheetPath, identity: SessionInfo, editing: Bool = false, attachment: String? = nil) -> Response {
    htmlPage(title: "Jelszó szükséges", body: """
        \(siteHeader(user: identity.user, csrf: identity.csrf))
        <main class="shell narrow"><h1>Jelszó szükséges</h1>
          <form class="stack panel" method="post" action="/api/unlock/\(path.url)">
            \(csrfInput(token(req)))<input type="hidden" name="edit" value="\(editing ? "1" : "0")">
            \(attachment.map { "<input type=\"hidden\" name=\"attachment\" value=\"\(escaped($0))\">" } ?? "")
            <label>Munkalap jelszava<input type="password" name="password" required></label>
            <button class="button primary">Megnyitás</button>
          </form>
        </main>
        """)
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

private func indexPage(_ items: [ProjectCard], session: SessionInfo) -> Response {
    let cards = items.map { item in
        let count = item.count
        return """
        <a class="project-card panel layers-\(min(count, 2))" data-scope="project" \(menuState(item.access.projectRule)) data-manage="\(item.access.manageable)" data-color="\(escaped(item.worksheet.backgroundColor))" data-revision="\(item.worksheet.revision)" href="/\(item.path.url)">
          \(item.access.readable ? "<img class=\"project-background\" loading=\"lazy\" alt=\"\" src=\"/api/preview/\(item.path.url)?v=\(item.worksheet.revision)\">" : "")
          <div class="project-summary"><h2>\(escaped(item.worksheet.title))</h2>
          <span class="muted">/\(escaped(item.path.parts.joined(separator: "/")))</span> · \(count + 1) munkalap\(credits(item.worksheet, item.access))<div class="project-badges">\(projectBadges(item.access))</div></div>
        </a>
        """
    }.joined()
    let create = session.user == nil ? "" : "<button type=\"button\" class=\"panel sub-preview new-worksheet\">\(uiIcon("plus"))Új projekt</button>"
    return htmlPage(title: "Munkalapok", body: """
        \(siteHeader(user: session.user, csrf: session.csrf))
        <main class="shell">
          <script type="module" src="/cards.js"></script>
          <div class="page-heading"><h1>Munkalapok</h1></div>
          <div class="home-tools">
            <form class="open-path panel" method="get" action="/open">
              <label>Munkalap útvonala<input name="path" placeholder="gondolatok/otletek1" required></label>
              <button class="button primary" type="submit">\(uiIcon("folder"))Megnyitás</button>
            </form>
            <a class="guide-link panel" href="/utmutato.html">\(uiIcon("file"))Útmutató</a>
          </div>
          <div class="project-list" id="worksheet-cards" data-delete="\(session.user?.role == .admin)" data-csrf="\(session.csrf ?? "")">\(cards.isEmpty && create.isEmpty ? "<p class=\"muted\">Még nincs munkalap.</p>" : cards)\(create)</div>
        </main>
        """)
}

private func passivePage(_ req: Request, path: WorksheetPath, worksheet: Worksheet, session: SessionInfo, access: DocumentAccess, children: [(path: WorksheetPath, worksheet: Worksheet, access: DocumentAccess)], files: [URL]) throws -> Response {
    let previews = children.map { child in
        """
        <a class="sub-preview preview-link" data-scope="\(child.path.url == child.access.folderPath ? "project" : "sheet")" \(menuState(child.access.sheetRule)) data-manage="\(child.access.manageable)" href="/\(child.path.url)">
          \(child.access.locked ? "<div class=\"locked-preview\">Jelszó szükséges</div>" : "<img loading=\"lazy\" alt=\"\" src=\"/api/preview/\(child.path.url)?v=\(child.worksheet.revision)\">")
          <strong>\(escaped(child.worksheet.title))</strong>
          <small>Létrehozó: \(escaped(child.worksheet.creator ?? "ismeretlen"))</small>
        </a>
        """
    }.joined()
    let base = "/" + path.url
    let edit = access.editable
        ? "<a class=\"button small viewer-edit\" href=\"/edit/\(path.url)\" aria-label=\"Szerkesztés\" title=\"Szerkesztés\">\(uiIcon("edit"))</a>" : ""
    let downloads = [
        ("svg", "SVG"), ("thnode", "ThinkNodes"), ("text", "Text"),
    ].map { format, title in
        headerLink("/export/" + format + "/" + path.url, title, symbol: "download")
    }.joined()
    let note: String
    if let noteID = req.query[String.self, at: "note"] {
        guard let node = worksheet.nodes.first(where: { $0.id == noteID && $0.file?.type != .image }) else { throw Abort(.notFound) }
        note = """
            <article class="panel passive-note"><a class="muted" href="\(base)">Vissza a munkalaphoz</a>
              <h2>\(escaped(node.title))</h2>
              <div class="formatted-text\(node.textStyle?.justified == true ? " justified-text" : "")">\(node.text.isEmpty ? "<p>Még nincs leírás.</p>" : markdownHTML(node.text))</div>
            </article>
            """
    } else {
        note = ""
    }
    let host = req.headers.first(name: .host)
    let canvas = renderWorksheetCanvas(worksheet, noteBase: base, siteHost: host)
    let tooltips = canvas.tooltipNodes.map {
        let justification = $0.textStyle?.justified == true ? " data-justified" : ""
        return "<template data-tooltip=\"\($0.id)\"\(justification)>\(markdownHTML($0.text))</template>"
    }.joined()
    let introduction = worksheet.text.map(markdownHTML) ?? ""
    let notes = introduction.isEmpty ? "" :
        "<section class=\"panel worksheet-notes\"><div class=\"formatted-text\(worksheet.textJustified == true ? " justified-text" : "")\">\(introduction)</div></section>"
    let external = worksheet.nodes.compactMap { node -> String? in
        guard let raw = node.link, let link = WorksheetLink(raw), link.isExternal(siteHost: host),
              let href = link.destination(from: path) else { return nil }
        return "<li><a href=\"\(escaped(href))\" target=\"_blank\" rel=\"noopener noreferrer\">\(escaped(node.title))</a></li>"
    }.joined()
    let attachments = files.map { file in
        let name = file.lastPathComponent
        return "<li><a data-scope=\"attachment\" data-manage=\"\(access.manageable)\" data-document=\"\(path.url)\" data-filename=\"\(escaped(name))\" href=\"/api/attachment/\(path.url)?name=\(encodeQuery(name))\">\(escaped(file.lastPathComponent))</a></li>"
    }.joined()
    let newPage = access.editable ? "<button type=\"button\" class=\"button new-worksheet\">\(uiIcon("plus"))Új munkalap</button><button type=\"button\" class=\"button new-worksheet\" data-folder=\"1\">Új almappa</button>" : ""
    return htmlPage(title: worksheet.title, body: """
        \(siteHeader(path: path.url, project: worksheet.title, user: session.user, csrf: session.csrf, canEdit: access.editable))
        <script type="module" src="/viewer.js?v=5"></script>
        <main class="shell" id="worksheet-view" data-path="\(path.url)" data-csrf="\(token(req))" data-revision="\(worksheet.revision)" data-editable="\(access.editable)" data-member="\(session.user != nil)">
          <a hidden data-current-document data-scope="\(access.folderPath == path.url ? "project" : "sheet")" \(menuState(access.sheetRule)) data-manage="\(access.manageable)" href="\(base)">Munkalap</a>
          <div class="passive-frame panel">
            <svg class="passive-backdrop" aria-hidden="true"><rect width="100%" height="100%" fill="\(worksheet.backgroundColor)"/></svg>
            \(canvas.svg)
            \(edit)
            <button class="button fullscreen" type="button" aria-label="Teljes képernyő">\(uiIcon("fit"))</button>
          </div>
          <div data-viewer-notes>\(tooltips)\(notes)\(note)</div>
          <nav class="viewer-downloads" aria-label="Letöltések és szerzők">\(downloads)\(credits(worksheet, access))</nav>
          <div data-viewer-sections>
          <section class="worksheet-section"><h2>További oldalak:</h2><div class="project-list" data-current-sheet="\(access.folderPath)">\(previews)\(newPage)</div></section>
          <section class="worksheet-section"><h2>Külső hivatkozások</h2>\(external.isEmpty ? "<p>Nincs külső hivatkozás.</p>" : "<ul>\(external)</ul>")</section>
          <section class="worksheet-section"><h2>Mappa tartalma</h2>\(attachments.isEmpty ? "<p>Nincs csatolt fájl.</p>" : "<ul>\(attachments)</ul>")</section>
          </div>
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

private func configureAdmin(_ app: any RoutesBuilder, store: WorksheetStore, live: Collaboration) {
    app.get("admin") { req async throws -> Response in
        let identity = try session(req, store: store)
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
                         dataDirectoryPath: store.dataDirectoryPath)
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
        struct Form: Content { var requireLogin: String?; var csrf: String }
        _ = try requireAdmin(req, store: store)
        let form = try req.content.decode(Form.self)
        try verify(req, token: form.csrf)
        try store.setSettings(SiteSettings(requireLogin: form.requireLogin == "on"))
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
        try await req.application.threadPool.runIfActive { try live.archive(path, expected: revision) }
        return Response(status: .noContent)
    }
}

private func adminPage(users: [User], settings: SiteSettings, user: User, csrf: String,
                       dataDirectoryPath: String) -> Response {
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
              <button class="button danger" type="submit">\(uiIcon("trash"))Törlés</button>
            </form>
            """
        return """
            <div class="account-row">
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
        """)
}
