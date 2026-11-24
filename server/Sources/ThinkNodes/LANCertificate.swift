import Crypto
import ThinkCore
import _CryptoExtras
import Foundation
import SwiftASN1
import X509
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// Saját LAN-tanúsítvány a belső hálózati HTTPS-hez (korábban a run.sh készítette openssl-lel).
/// A mappa szerkezete a régivel azonos (ca.key, ca.crt, server.key, server-<azonosító>.crt), így a
/// már telepített gyökértanúsítvány érvényes marad. A kulcsok és a CA csak hiányuk esetén készülnek;
/// a szervertanúsítvány címkészletenként külön fájl, és lejárat előtt 7 nappal megújul.
enum LANCertificate {
    struct Files {
        var certificate: String
        var key: String
        var authority: String
    }

    static func prepare(directory: String, addresses: [String]) throws -> Files {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let authorityKey = try privateKey(folder.appendingPathComponent("ca.key"))
        let serverKey = try privateKey(folder.appendingPathComponent("server.key"))
        let authorityURL = folder.appendingPathComponent("ca.crt")
        let authority = try certificateAuthority(authorityURL, key: authorityKey)

        let identifier = SHA256.hash(data: Data(addresses.joined(separator: ",").utf8))
            .prefix(6).map { String(format: "%02x", $0) }.joined()
        let serverURL = folder.appendingPathComponent("server-\(identifier).crt")
        let serverPublicKey = Certificate.PrivateKey(serverKey).publicKey
        if let text = try? String(contentsOf: serverURL, encoding: .utf8),
           let existing = try? Certificate(pemEncoded: text),
           existing.notValidAfter > Date().addingTimeInterval(7 * 86_400),
           existing.issuer == authority.subject, existing.publicKey == serverPublicKey {
            return Files(certificate: serverURL.path, key: folder.appendingPathComponent("server.key").path, authority: authorityURL.path)
        }

        let now = Date()
        let names = try addresses.map(generalName)
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: serverPublicKey,
            notValidBefore: now.addingTimeInterval(-300),
            notValidAfter: now.addingTimeInterval(90 * 86_400),
            issuer: authority.subject,
            subject: try DistinguishedName { CommonName("ThinkNodes LAN") },
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true, keyEncipherment: true))
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames(names)
            },
            issuerPrivateKey: Certificate.PrivateKey(authorityKey)
        )
        try write(try certificate.serializeAsPEM().pemString, to: serverURL, replace: true)
        return Files(certificate: serverURL.path, key: folder.appendingPathComponent("server.key").path, authority: authorityURL.path)
    }

    private static func privateKey(_ url: URL) throws -> _RSA.Signing.PrivateKey {
        if !FileManager.default.fileExists(atPath: url.path) {
            try write(try _RSA.Signing.PrivateKey(keySize: .bits2048).pemRepresentation, to: url, replace: false)
        }
        // Párhuzamos első indításnál a korábban közzétett kulcs nyer; mindenki azt olvassa vissza.
        return try _RSA.Signing.PrivateKey(pemRepresentation: String(contentsOf: url, encoding: .utf8))
    }

    private static func certificateAuthority(_ url: URL, key: _RSA.Signing.PrivateKey) throws -> Certificate {
        if !FileManager.default.fileExists(atPath: url.path) {
            let now = Date()
            let name = try DistinguishedName { CommonName("ThinkNodes LAN CA") }
            let signer = Certificate.PrivateKey(key)
            let authority = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(),
                publicKey: signer.publicKey,
                notValidBefore: now.addingTimeInterval(-300),
                notValidAfter: now.addingTimeInterval(3650 * 86_400),
                issuer: name,
                subject: name,
                signatureAlgorithm: .sha256WithRSAEncryption,
                extensions: try Certificate.Extensions {
                    Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                    Critical(KeyUsage(keyCertSign: true, cRLSign: true))
                },
                issuerPrivateKey: signer
            )
            try write(try authority.serializeAsPEM().pemString, to: url, replace: false)
        }
        return try Certificate(pemEncoded: String(contentsOf: url, encoding: .utf8))
    }

    private static func generalName(_ address: String) throws -> GeneralName {
        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            return .ipAddress(ASN1OctetString(contentBytes: ArraySlice(withUnsafeBytes(of: &v4) { Array($0) })))
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, address, &v6) == 1 {
            return .ipAddress(ASN1OctetString(contentBytes: ArraySlice(withUnsafeBytes(of: &v6) { Array($0) })))
        }
        guard address.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]*$"#, options: .regularExpression) != nil else {
            throw LaunchOptions.Problem(description: "Invalid host name or IP address for the TLS certificate: \(address)")
        }
        return .dnsName(address)
    }

    /// Írás ideiglenes fájlba, majd közzététel: a kész fájl soha nem félig írt.
    /// `replace: false` esetén a már meglévő fájl nyer (párhuzamos első indítás).
    private static func write(_ text: String, to url: URL, replace: Bool) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".issue-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: Data(text.utf8),
                                             attributes: [.posixPermissions: 0o600]) else {
            throw LaunchOptions.Problem(description: "Cannot write \(temporary.path)")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        if replace {
            guard rename(temporary.path, url.path) == 0 else {
                throw LaunchOptions.Problem(description: "Cannot write \(url.path)")
            }
        } else if link(temporary.path, url.path) != 0 && errno != EEXIST {
            throw LaunchOptions.Problem(description: "Cannot write \(url.path)")
        }
    }
}
