import Foundation
import Testing
@testable import ThinkCore
@testable import ThinkNodes

/// Külső link-előnézet: belső hálózati címet nem kér le, az og:image-et mindkét attribútum-sorrendben megtalálja.
@Test func linkPreviewBlocksPrivateTargetsAndReadsOpenGraph() throws {
    for blocked in ["http://localhost/", "http://127.0.0.1/admin", "http://10.0.0.5/", "http://192.168.1.1/", "http://169.254.169.254/latest",
                    "http://[::1]/", "ftp://example.com/", "http://example.com:8080/", "http://172.16.0.1/"] {
        #expect(throws: (any Error).self, "\(blocked)") { try LinkPreviews.checkPublic(URL(string: blocked)!) }
    }
    #expect(LinkPreviews.publicIPv4(0x0808_0808))
    #expect(!LinkPreviews.publicIPv6([0xFE, 0x80] + Array(repeating: 0, count: 14)))
    #expect(!LinkPreviews.publicIPv6(Array(repeating: 0, count: 10) + [0xFF, 0xFF, 127, 0, 0, 1]))
    let html = #"<head><title>Cím &amp; más</title><meta content="/kep.png" property="og:image"><meta name="twitter:image" content="b.png"></head>"#
    #expect(LinkPreviews.metaContent(html, ["og:image"]) == "/kep.png")
    #expect(LinkPreviews.metaContent(#"<meta property='og:image' content='https://x/y.jpg'>"#, ["og:image"]) == "https://x/y.jpg")
    #expect(LinkPreviews.decodeEntities(LinkPreviews.titleTag(html) ?? "") == "Cím & más")
    #expect(LinkPreviews.imageExtension(Data("<svg".utf8)) == nil)
}
