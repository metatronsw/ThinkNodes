import Crypto
import Foundation
import Vapor

/// Google-bejelentkezés: OpenID Connect, „authorization code” folyamat PKCE-vel.
///
/// A szerver csak azonosításra használja a Google-t: a visszakapott, ellenőrzött e-mail-címhez az admin által
/// előre hozzárendelt ThinkNodes-fiók tartozik (`User.google`); a Google-től új fiók nem jön létre.
/// Az ID tokent a szerver közvetlenül a Google token-végpontjától kapja TLS-en, ezért az aláírását nem
/// ellenőrzi külön (OpenID Connect Core 3.1.3.7), a tartalmát (kibocsátó, címzett, lejárat, nonce) igen.
struct GoogleSignIn: Sendable {
    static let callbackPath = "/login/google/callback"

    var clientID: String
    var clientSecret: String
    /// A Google-nál regisztrált visszatérési cím, ha nem a kérés gazdanevéből kell képezni (pl. proxy mögött).
    var redirectURI: String?
    /// A hitelesítő kód beváltása ID tokenre (a tesztek lecserélik).
    var exchange: @Sendable (Request, [String: String]) async throws -> String = GoogleSignIn.exchangeAtGoogle

    /// `THINKNODES_GOOGLE_CLIENT_ID` és `THINKNODES_GOOGLE_CLIENT_SECRET`; ha bármelyik hiányzik, nincs Google-belépés.
    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> GoogleSignIn? {
        func value(_ name: String) -> String? {
            let text = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
        guard let id = value("THINKNODES_GOOGLE_CLIENT_ID"), let secret = value("THINKNODES_GOOGLE_CLIENT_SECRET") else { return nil }
        return GoogleSignIn(clientID: id, clientSecret: secret, redirectURI: value("THINKNODES_GOOGLE_REDIRECT"))
    }

    /// Véletlen, URL-be írható titok (state, nonce, PKCE-ellenőrző).
    static func secret() -> String { base64URL(Data([UInt8].random(count: 32))) }

    func redirect(for req: Request, secure: Bool) -> String {
        if let redirectURI { return redirectURI }
        let host = req.headers.first(name: .host) ?? "localhost"
        return (secure ? "https://" : "http://") + host + Self.callbackPath
    }

    func authorizationURL(redirect: String, state: String, nonce: String, verifier: String) -> String {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email"),
            .init(name: "state", value: state),
            .init(name: "nonce", value: nonce),
            .init(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account")
        ]
        // A „+” a lekérdezésben szóközt jelentene; az URLComponents nem kódolja.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.string!
    }

    func tokenRequest(code: String, redirect: String, verifier: String) -> [String: String] {
        ["grant_type": "authorization_code", "code": code, "client_id": clientID, "client_secret": clientSecret,
         "redirect_uri": redirect, "code_verifier": verifier]
    }

    /// Az ID token ellenőrzése; az eredmény a Google által igazolt e-mail-cím.
    func verifiedEmail(idToken: String, nonce: String, now: Date = Date()) throws -> String {
        struct Claims: Decodable {
            var iss: String, aud: String, exp: Double, nonce: String?, email: String?, verified: Bool
            enum CodingKeys: String, CodingKey { case iss, aud, exp, nonce, email, verified = "email_verified" }
            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                iss = try values.decode(String.self, forKey: .iss)
                aud = try values.decode(String.self, forKey: .aud)
                exp = try values.decode(Double.self, forKey: .exp)
                nonce = try values.decodeIfPresent(String.self, forKey: .nonce)
                email = try values.decodeIfPresent(String.self, forKey: .email)
                verified = (try? values.decode(Bool.self, forKey: .verified))
                    ?? ((try? values.decode(String.self, forKey: .verified)) == "true")
            }
        }
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let payload = Self.decodeBase64URL(String(parts[1])),
              let claims = try? JSONDecoder().decode(Claims.self, from: payload) else {
            throw Abort(.badGateway, reason: "Google ID token: unreadable")
        }
        guard ["https://accounts.google.com", "accounts.google.com"].contains(claims.iss) else {
            throw Abort(.badGateway, reason: "Google ID token: unexpected issuer")
        }
        guard claims.aud == clientID else { throw Abort(.badGateway, reason: "Google ID token: issued for another client") }
        guard claims.exp > now.timeIntervalSince1970 else { throw Abort(.badGateway, reason: "Google ID token: expired") }
        guard claims.nonce == nonce else { throw Abort(.badGateway, reason: "Google ID token: nonce mismatch") }
        guard claims.verified, let email = claims.email, !email.isEmpty else {
            throw Abort(.badGateway, reason: "Google ID token: no verified e-mail")
        }
        return email.lowercased()
    }

    private static func exchangeAtGoogle(_ req: Request, _ form: [String: String]) async throws -> String {
        struct Tokens: Content { var id_token: String }
        let response = try await req.client.post("https://oauth2.googleapis.com/token") { request in
            try request.content.encode(form, as: .urlEncodedForm)
            request.timeout = .seconds(15)
        }
        guard response.status == .ok, let tokens = try? response.content.decode(Tokens.self) else {
            throw Abort(.badGateway, reason: "Google token endpoint: HTTP \(response.status.code)")
        }
        return tokens.id_token
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decodeBase64URL(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        return Data(base64Encoded: value)
    }
}
