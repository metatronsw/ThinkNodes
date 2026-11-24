import Foundation
import Testing
import VaporTesting
@testable import ThinkCore
@testable import ThinkNodes

// Közös HTTP-segédfüggvények a tesztekhez (bejelentkezés, mentés, sütik).

func remove(_ browser: some TestingApplicationTester, path: String, session: (cookie: String, csrf: String)) async throws -> TestingHTTPResponse {
    try await browser.sendRequest(.DELETE, "/api/worksheet/\(path)", headers: [
        "Cookie": session.cookie, "If-Match": "\"2\"", "X-CSRF-Token": session.csrf
    ])
}

struct Credentials: Content {
    var name: String
    var password: String
    var csrf: String
}

func login(_ browser: some TestingApplicationTester, name: String, password: String, path: String, canEdit: Bool = true) async throws -> (cookie: String, csrf: String) {
    let loginPage = try await browser.sendRequest(.GET, "/login")
    let sessionCookie = try cookie(loginPage)
    let initialToken = try attribute("name=\"csrf\" value=\"", in: loginPage.body.string)
    let signedIn = try await browser.sendRequest(.POST, "/login", headers: ["Cookie": sessionCookie]) { request in
        try request.content.encode(Credentials(name: name, password: password, csrf: initialToken), as: .urlEncodedForm)
    }
    #expect(signedIn.status == .seeOther)
    let signedInCookie = try cookie(signedIn)
    #expect(sessionCookie != signedInCookie)
    let editor = try await browser.sendRequest(.GET, "/edit/\(path)", headers: ["Cookie": signedInCookie])
    if !canEdit {
        #expect(editor.status == .forbidden)
        let viewer = try await browser.sendRequest(.GET, "/" + path, headers: ["Cookie": signedInCookie])
        return (signedInCookie, try attribute("data-csrf=\"", in: viewer.body.string))
    }
    #expect(editor.status == .ok)
    #expect(editor.body.string.contains("worksheet-nav"))
    #expect(editor.body.string.contains(#"class="button header-button brand" href="/""#))
    #expect(editor.body.string.contains("brand-icon"))
    let token = try attribute("data-csrf=\"", in: editor.body.string)
    return (signedInCookie, token)
}

func checkPreviewAndPreferences(_ browser: some TestingApplicationTester, path: String, sheet: Worksheet,
                                        session: (cookie: String, csrf: String), png: Data) async throws {
    let headers: HTTPHeaders = ["Cookie": session.cookie, "X-CSRF-Token": session.csrf]
    let options = try await browser.sendRequest(.GET, "/api/preview-images/" + path, headers: headers)
    #expect(try options.content.decode([String].self).contains("Kép.png"))
    var selected = sheet
    selected.previewImage = "Kép.png"
    let saved = try await save(browser, path: path, worksheet: selected, session: session)
    #expect(saved.status == .ok)
    let image = try await browser.sendRequest(.GET, "/api/preview/" + path)
    #expect(image.headers.first(name: .contentType) == "image/png")
    #expect(Data(image.body.readableBytesView) == png)
    selected.revision += 1
    selected.previewImage = "hiányzó.svg"
    #expect(try await save(browser, path: path, worksheet: selected, session: session).status == .ok)
    #expect(try await browser.sendRequest(.GET, "/api/preview/" + path).body.string.contains("<svg"))
    let preferences = UserPreferences(snap: true, showGrid: false, panLocked: true, avatar: 12)
    let result = try await browser.sendRequest(.POST, "/api/preferences", headers: headers) { request in
        try request.content.encode(preferences)
    }
    #expect(result.status == .noContent)
    let page = try await browser.sendRequest(.GET, "/edit/" + path, headers: headers)
    #expect(!page.body.string.contains("&quot;avatar&quot;:12"))
}

func save(_ browser: some TestingApplicationTester, path: String, worksheet: Worksheet,
                  session: (cookie: String, csrf: String)) async throws -> TestingHTTPResponse {
    try await browser.sendRequest(.PUT, "/api/worksheet/\(path)", headers: [
        "Cookie": session.cookie, "If-Match": "\"\(worksheet.revision)\"", "X-CSRF-Token": session.csrf
    ]) { request in
        try request.content.encode(worksheet)
    }
}

func cookie(_ response: TestingHTTPResponse) throws -> String {
    let header = try #require(response.headers.first(name: .setCookie))
    return String(header.prefix { $0 != ";" })
}

func attribute(_ prefix: String, in html: String) throws -> String {
    let range = try #require(html.range(of: prefix))
    return String(html[range.upperBound...].prefix { $0 != "\"" })
}

func setupRequest(_ app: Application, _ method: HTTPMethod, _ path: String,
                          headers: HTTPHeaders = ["Host": "localhost:8080"], body: ByteBuffer? = nil) async throws -> Response {
    let eventLoop = app.eventLoopGroup.next()
    let req = Request(application: app, method: method, url: .init(path: path), headers: headers,
                      collectedBody: body, remoteAddress: try .some(.init(ipAddress: "127.0.0.1", port: 12345)),
                      logger: app.logger, on: eventLoop)
    return try await app.responder.respond(to: req).get()
}
