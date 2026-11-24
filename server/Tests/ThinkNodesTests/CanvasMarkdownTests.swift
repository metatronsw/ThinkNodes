import Foundation
import Testing
@testable import ThinkCore
@testable import ThinkNodes

/// A doboz-markdown szerveroldali feldolgozása egyezzen a közös tesztkészlettel; ugyanezt a fájlt ellenőrzi a
/// kliensoldali párja is (Tests/Editor/canvas-markdown.mjs, Public/canvas-markdown.js).
@Test func canvasMarkdownMatchesSharedFixtures() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/canvas-markdown.json")
    let cases = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [[String: Any]])
    #expect(cases.count >= 50)
    for item in cases {
        let source = try #require(item["source"] as? String)
        let expected = try #require(item["blocks"] as? NSArray)
        let actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(canvasMarkdown(source))) as? NSArray
        #expect(actual == expected, "Eltérés: \(source.prefix(60))")
    }
}
