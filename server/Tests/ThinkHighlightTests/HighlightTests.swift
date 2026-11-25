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
    for ext in ["js", "mjs", "cjs", "swift", "html", "htm"] { #expect(CodeHighlight.supports(ext)) }
    #expect(!CodeHighlight.supports("py") && !CodeHighlight.supports(""))
    #expect(CodeHighlight.html("a = 1", ext: "py") == nil)
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
    let broken = ["", "}", "{{{", "a { b: url(", "/* nyitott", "\"", "a:b:c;;}}{{ @ ! # - .", "((((;;;;", "é\u{1F600}{\u{0}}", "x\\",
                  "`a${`b${", "\"a\\(\"b\\(", "#\"\"\"x", "<script>`${", "<style>a{", "<a b='c", "<!--", "</", "a / b /", "'\\é", "\"\\é\"é",
                  String(repeating: "`${", count: 3000), String(repeating: "\"\\(", count: 3000), String(repeating: "/*", count: 3000)]
    for text in broken + broken.map({ $0 + "\n" + source }) {
        for ext in ["json", "css", "js", "swift", "html"] {
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

@Test func highlightJavaScript() {
    #expect(marks("// x\nconst a = new Map(); let n = 0x1F + 1e-3;", "js") == [
        "c:// x", "k:const", "o:=", "k:new", "t:Map", "o:();", "k:let", "o:=", "n:0x1F", "o:+", "n:1e-3", "o:;",
    ])
    // Osztás és reguláris kifejezés: érték után osztás, írásjel vagy kulcsszó után reguláris kifejezés.
    #expect(marks("x = a / b / c; y = /[/]\\/+/gi.test(s); return /re/", "js") == [
        "o:=", "o:/", "o:/", "o:;", "o:=", "s:/[/]\\/+/gi", "o:.", "f:test", "o:(", "o:);", "k:return", "s:/re/",
    ])
    // Sablonszöveg beágyazással; a beágyazott kapcsos zárójel nem zárja a beágyazást.
    #expect(marks("`a ${f({b: 1})} c` + 'd'", "js") == [
        "s:`a ", "o:${", "f:f", "o:({", "o::", "n:1", "o:})}", "s: c`", "o:+", "s:'d'",
    ])
    // Pont utáni név nem kulcsszó; érték jellegű kulcsszó után a `/` osztás.
    #expect(marks("Array.from(x).default; this / 2", "js") == ["t:Array", "o:.", "f:from", "o:(", "o:).", "p:default", "o:;", "k:this", "o:/", "n:2"])
}

@Test func highlightSwift() {
    #expect(marks("@MainActor final class A: B { var n = 1_000.5 /* a /* b */ c */ }", "swift") == [
        "k:@MainActor", "k:final", "k:class", "t:A", "o::", "t:B", "o:{", "k:var", "o:=", "n:1_000.5", "c:/* a /* b */ c */", "o:}",
    ])
    // Szövegbeágyazás, benne szöveggel és zárójellel; nyers szöveg; többsoros szöveg.
    #expect(marks(##"let s = "a \(f("b") + (1)) c" + #"x\(y)"\#(z)"# "##, "swift") == [
        "k:let", "o:=", "s:\"a ", "o:\\(", "f:f", "o:(", "s:\"b\"", "o:)", "o:+", "o:(", "n:1", "o:))", "s: c\"", "o:+",
        "s:#\"x\\(y)\"", "o:\\#(", "o:)", "s:\"#",
    ])
    #expect(marks("\"\"\"\nsor \"idézet\"\n\"\"\" + x", "swift") == ["s:\"\"\"\nsor \"idézet\"\n\"\"\"", "o:+"])
    // Helyzetfüggő kulcsszó névként; pont utáni tag; fordítási utasítás.
    #expect(marks("#if DEBUG\nlist.prefix(3).count; set = [.red]; get { self }", "swift") == [
        "k:#if", "t:DEBUG", "o:.", "f:prefix", "o:(", "n:3", "o:).", "p:count", "o:;", "o:=", "o:[.", "p:red", "o:];", "k:get", "o:{", "k:self", "o:}",
    ])
}

@Test func highlightHTML() {
    #expect(marks("<!DOCTYPE html><!-- j --><a href=\"x\" hidden>T &amp; U</a><br/>", "html") == [
        "k:<!DOCTYPE html>", "c:<!-- j -->", "o:<", "t:a", "p:href", "o:=", "s:\"x\"", "p:hidden", "o:>", "k:&amp;", "o:</", "t:a", "o:><", "t:br", "o:/>",
    ])
    // Beágyazott nyelvek: a script JavaScript (JSON típusnál JSON), a style CSS; a záró címke után újra HTML.
    #expect(marks("<style>a { top: 0 }</STYLE><script>let x = '</b>';</script><p>", "html") == [
        "o:<", "t:style", "o:>", "t:a", "o:{", "p:top", "o::", "n:0", "o:}</", "t:STYLE", "o:><", "t:script", "o:>",
        "k:let", "o:=", "s:'</b>'", "o:;</", "t:script", "o:><", "t:p", "o:>",
    ])
    #expect(marks("<script type=\"application/json\">{\"a\": null}</script>", "html") == [
        "o:<", "t:script", "p:type", "o:=", "s:\"application/json\"", "o:>{", "p:\"a\"", "o::", "k:null", "o:}</", "t:script", "o:>",
    ])
}

/// A szerver színezése egyezzen a közös tesztkészlettel; ugyanezt a fájlt ellenőrzi a böngészőbeli párja is
/// (Tests/Editor/highlight.mjs, Public/highlight – szerkesztés közbeni színezés). Rövid esetek a szakaszok teljes
/// listájával, mintafájlok a szakaszok számával és ellenőrző összegével (FNV-1a).
@Test func highlightMatchesSharedFixtures() throws {
    struct Fixture: Decodable {
        struct Case: Decodable { var ext: String, source: String, marks: [String] }
        struct Sample: Decodable { var file: String, count: Int, checksum: UInt32 }
        var cases: [Case], samples: [Sample]
    }
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtures.appendingPathComponent("highlight.json")))
    #expect(fixture.cases.count >= 150 && fixture.samples.count == 5)
    for item in fixture.cases {
        #expect(marks(item.source, item.ext) == item.marks, "\(item.ext): \(item.source.prefix(60))")
    }
    for sample in fixture.samples {
        let source = try String(contentsOf: fixtures.appendingPathComponent("highlight/" + sample.file), encoding: .utf8)
        let list = marks(source, (sample.file as NSString).pathExtension)
        var hash: UInt32 = 0x811c9dc5
        for item in list {
            for byte in item.utf8 { hash = (hash ^ UInt32(byte)) &* 0x01000193 }
            hash = (hash ^ 1) &* 0x01000193
        }
        #expect(list.count == sample.count, "\(sample.file): szakaszok száma")
        #expect(hash == sample.checksum, "\(sample.file): ellenőrző összeg")
    }
}
