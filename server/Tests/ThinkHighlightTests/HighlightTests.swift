import Foundation
import Testing
@testable import ThinkHighlight

/// Kódszínezés (Sources/ThinkHighlight): a szakaszok fajtája és szövege, olvasható formában: `k:true`.
private func marks(_ source: String, _ ext: String) -> [String] {
    let bytes = Array(source.utf8)
    return (CodeHighlight.tokens(source, ext: ext) ?? []).map {
        $0.kind.rawValue + ":" + String(decoding: bytes[$0.range], as: UTF8.self)
    }
}

@Test func highlightKnowsItsLanguages() {
    #expect(CodeHighlight.supports("json") && CodeHighlight.supports("CSS"))
    #expect(!CodeHighlight.supports("swift") && !CodeHighlight.supports(""))
    #expect(CodeHighlight.html("let a = 1", ext: "swift") == nil)
}

@Test func highlightJSON() {
    #expect(marks(#"{"a": 1, "b" : [true, null, -2.5e+3, "x\"y"]}"#, "json") == [
        "o:{", "p:\"a\"", "o::", "n:1", "o:,", "p:\"b\"", "o::", "o:[", "k:true", "o:,", "k:null", "o:,", "n:-2.5e+3", "o:,",
        "s:\"x\\\"y\"", "o:]}",
    ])
    // Megjegyzés (JSONC), ékezetes szöveg, lezáratlan szöveg a sor végéig.
    #expect(marks("// jegyzet\n{\"név\": \"árvíztűrő\"} /* vége */", "json") == [
        "c:// jegyzet", "o:{", "p:\"név\"", "o::", "s:\"árvíztűrő\"", "o:}", "c:/* vége */",
    ])
    #expect(marks("[\"nyitott\n, 3]", "json") == ["o:[", "s:\"nyitott", "o:,", "n:3", "o:]"])
    // Ismeretlen szó színezetlen marad; a szóba ágyazott szám nem szám.
    #expect(marks("[igen, a1, falsey]", "json") == ["o:[", "o:,", "o:,", "o:]"])
}

@Test func highlightCSS() {
    #expect(marks("a.b:hover > #id, * { color: red; margin: -1.5px 10% 0 !important }", "css") == [
        "t:a.b:hover", "o:>", "t:#id", "o:,", "t:*", "o:{", "p:color", "o::", "o:;", "p:margin", "o::", "n:-1.5px", "n:10%", "n:0",
        "k:!important", "o:}",
    ])
    // @-szabály, egymásba ágyazás: a blokkon belüli szelektor nem tulajdonság.
    #expect(marks("@media (min-width: 700px) { .a { b:hover { top: 0 } } }", "css") == [
        "k:@media", "o:(", "o::", "n:700px", "o:)", "o:{", "t:.a", "o:{", "t:b:hover", "o:{", "p:top", "o::", "n:0", "o:}", "o:}", "o:}",
    ])
    // Függvény, saját tulajdonság, szín, szöveg, megjegyzés; az url(…) pontosvesszője nem zárja a deklarációt.
    #expect(marks("/* x */ p { --gap: 4px; background: url(data:a;b) var(--gap) #fff \"é;\" }", "css") == [
        "c:/* x */", "t:p", "o:{", "p:--gap", "o::", "n:4px", "o:;", "p:background", "o::", "f:url", "o:(", "s:data:a;b", "o:)",
        "f:var", "o:(", "p:--gap", "o:)", "n:#fff", "s:\"é;\"", "o:}",
    ])
    #expect(marks("@import \"a.css\";\n@charset 'utf-8';", "css") == ["k:@import", "s:\"a.css\"", "o:;", "k:@charset", "s:'utf-8'", "o:;"])
}

@Test func highlightHTMLIsEscapedAndComplete() {
    let source = "{\"<b>&\": \"é>\"}"
    #expect(CodeHighlight.html(source, ext: "json")
            == "<span class=\"hl-o\">{</span><span class=\"hl-p\">\"&lt;b&gt;&amp;\"</span><span class=\"hl-o\">:</span> <span class=\"hl-s\">\"é&gt;\"</span><span class=\"hl-o\">}</span>")
    // Hibás, lezáratlan vagy értelmetlen bemenet: a kimenet a címkék nélkül mindig a teljes forrás.
    let broken = ["", "}", "{{{", "a { b: url(", "/* nyitott", "\"", "a:b:c;;}}{{ @ ! # - .", "((((;;;;", "é\u{1F600}{\u{0}}", "x\\"]
    for text in broken + broken.map({ $0 + "\n" + source }) {
        for ext in ["json", "css"] {
            let html = try? #require(CodeHighlight.html(text, ext: ext))
            let plain = (html ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
            #expect(plain == text, "\(ext): \(text)")
        }
    }
}

@Test func highlightStopsColouringLargeFiles() throws {
    let row = "{\"a\": 1}\n"
    let text = String(repeating: row, count: CodeHighlight.colouredLimit / row.utf8.count + 50)
    let html = try #require(CodeHighlight.html(text, ext: "json"))
    #expect(html.hasSuffix(String(repeating: row, count: 40)))
    #expect(html.hasPrefix("<span class=\"hl-o\">{</span>"))
}

/// Az önálló SVG-be ágyazott színszabályok ugyanazok, mint amiket a szerkesztő és a megtekintő használ (app.css).
@Test func highlightColourRulesMatchTheStylesheet() throws {
    let css = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Public/app.css")
    let lines = Set(try String(contentsOf: css, encoding: .utf8).split(separator: "\n").map(String.init))
    #expect(CodeHighlight.colourRules.count == lines.filter { $0.hasPrefix(".hl-") }.count)
    for rule in CodeHighlight.colourRules { #expect(lines.contains(rule), "Hiányzik az app.css-ből: \(rule)") }
}
