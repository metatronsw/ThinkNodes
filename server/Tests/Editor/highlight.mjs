// A böngészőbeli kódszínezés (Public/highlight, szerkesztés közben) pontosan egyezzen a szerverével
// (Sources/ThinkHighlight). Az elvárt eredmény: Tests/Fixtures/highlight.json – a Swift-teszt
// (highlightMatchesSharedFixtures) ugyanezt ellenőrzi. Két rész: rövid esetek a szakaszok teljes listájával, és
// mintafájlok (Tests/Fixtures/highlight/) a szakaszok számával és ellenőrző összegével.
// Futtatás a server/ mappából, Node 22+. A fixture újraírása (új nyelv, új eset): --write, utána a Swift-teszt dönt.
import assert from "node:assert/strict";
import {readFileSync, writeFileSync} from "node:fs";

const {highlightTokens, highlightHTML, supportsHighlight} = await import("../../Public/highlight/index.js");

const fixtureURL = new URL("../Fixtures/highlight.json", import.meta.url);
const marks = (source, ext) => highlightTokens(source, ext).map(token => token.kind + ":" + source.slice(token.start, token.end));
// FNV-1a (32 bit) a szakaszok UTF-8 bájtjain, szakaszonként egy elválasztó bájttal.
function checksum(list) {
  let hash = 0x811c9dc5;
  const encoder = new TextEncoder();
  for (const item of list) {
    for (const byte of encoder.encode(item)) hash = Math.imul(hash ^ byte, 0x01000193) >>> 0;
    hash = Math.imul(hash ^ 1, 0x01000193) >>> 0;
  }
  return hash;
}

// Rövid esetek: nyelvenként a nehéz helyek, és hibás / lezáratlan bemenetek minden nyelven.
const sources = {
  json: ['{"a": 1, "b" : [true, null, -2.5e+3, "x\\"y"]}', '// jegyzet\n{"név": "árvíztűrő"} /* vége */', '["nyitott\n, 3]', "[igen, a1, falsey]", '"a""b":1'],
  css: ["a.b:hover > #id, * { color: red; margin: -1.5px 10% 0 !important }", "@media (min-width: 700px) { .a { b:hover { top: 0 } } }",
    '/* x */ p { --gap: 4px; background: url(data:a;b) var(--gap) #fff "é;" }', "@import \"a.css\";\n@charset 'utf-8';",
    "a\\:b { content: '\\'' ; width: calc(100% - .5em + +2px) }", "@font-face { font-family: X; src: URL( a b ) }", "a{b:c", "é { ő: ű }"],
  js: ["// x\nconst a = new Map(); let n = 0x1F + 1e-3;", "x = a / b / c; y = /[/]\\/+/gi.test(s); return /re/", "`a ${f({b: 1})} c` + 'd'",
    "Array.from(x).default; this / 2", "#!/usr/bin/env node\nlet a = 10n ** 2n, b = 1_000.5e+10, c = .5, d = 0b101, e = 1..toString();",
    "`a\\`b${`c${d}e`}f` / 2", "a = b\n/ c /\nd; f = (x) / 2 /i; g = [1] /2/ 3", "class Á extends B { #p = $x?.y ?? z; static async *g() { yield* this } }",
    "x = '\\\ny'; s = \"a\\\"b\" + 'c\nd", "label: for (const [k, v] of Object.entries(o)) { if (k in o) continue label }", "...rest, a.b.c(), a?.[0], a.for"],
  swift: ["@MainActor final class A: B { var n = 1_000.5 /* a /* b */ c */ }", 'let s = "a \\(f("b") + (1)) c" + #"x\\(y)"\\#(z)"# ',
    '"""\nsor "idézet"\n""" + x', "#if DEBUG\nlist.prefix(3).count; set = [.red]; get { self }",
    "func f<T: Hashable>(_ x: inout T?, `class`: Int = 0xFF, y: Double = 1e-5) async throws -> [String: Any] { try await g($0) }",
    '##"a "# b \\#(c) \\##(d + "e")"## + "\\u{1F600}\\"\\\\" + "nyitott', "let r = 1...5, h = 1..<n, t = a.0.1; open class C {}; open(file)",
    "#selector(a) #available(iOS 17, *) @objc(x) @_spi(y) prefix operator +++", '"""\n\\(a\n + "b")\\\nc"""x'],
  html: ['<!DOCTYPE html><!-- j --><a href="x" hidden>T &amp; U</a><br/>', "<style>a { top: 0 }</STYLE><script>let x = '</b>';</script><p>",
    '<script type="application/json">{"a": null}</script>', '<script type="text/plain">a < b</script><script type=module>import a from "b"</script>',
    "<p class=a data-x='1\n2' é=ő>&#123; &x; & &nbsp</p><?xml version=\"1.0\"?>", "<a <b> c=\"d", "a < b && c > d </ x", "<SCRIPT>if (a</b/) `</scr`</SCRIPT x>"],
};
const broken = ["", "}", "{{{", "a { b: url(", "/* nyitott", '"', "a:b:c;;}}{{ @ ! # - .", "((((;;;;", "é😀{\u0000}", "x\\", "`a${`b${", '"a\\("b\\(', '#"""x',
  "<script>`${", "<style>a{", "<a b='c", "<!--", "</", "a / b /", "'\\é", '"\\é"é', "\\", "#", "@", "$", "\"\\", "é\\", "`${".repeat(200), '"\\('.repeat(200), "/*".repeat(200)];
const cases = [];
for (const [ext, list] of Object.entries(sources)) for (const source of [...list, ...broken]) cases.push({ext, source});
const samples = ["sample.json", "sample.css", "sample.js", "sample.swift", "sample.html"];

function measure() {
  return {
    cases: cases.map(({ext, source}) => ({ext, source, marks: marks(source, ext)})),
    samples: samples.map(file => {
      const list = marks(readFileSync(new URL("../Fixtures/highlight/" + file, import.meta.url), "utf8"), file.split(".").pop());
      return {file, count: list.length, checksum: checksum(list)};
    }),
  };
}

// A HTML a jelölők nélkül mindig a teljes forrás, és minden nyitó jelölőnek van záró párja.
for (const {ext, source} of cases) {
  const html = highlightHTML(source, ext);
  const plain = html.replace(/<\/?span[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  assert.equal(plain, source, ext + ": a HTML szövege eltér a forrástól");
  assert.equal(html.match(/<span /g)?.length ?? 0, html.match(/<\/span>/g)?.length ?? 0);
}
assert.ok(supportsHighlight("JSON") && supportsHighlight("mjs") && !supportsHighlight("py") && !supportsHighlight(undefined));
assert.equal(highlightHTML("a = 1", "py"), null);
assert.equal(highlightHTML('{"<b>&": "é>"}', "json"),
  '<span class="hl-o">{</span><span class="hl-p">"&lt;b&gt;&amp;"</span><span class="hl-o">:</span> <span class="hl-s">"é&gt;"</span><span class="hl-o">}</span>');

const measured = measure();
if (process.argv.includes("--write")) {
  writeFileSync(fixtureURL, JSON.stringify(measured, null, 1) + "\n");
  console.log("Fixture written: " + measured.cases.length + " cases, " + measured.samples.length + " samples.");
} else {
  const expected = JSON.parse(readFileSync(fixtureURL, "utf8"));
  assert.equal(measured.cases.length, expected.cases.length, "Az esetek száma eltér: --write, majd a Swift-teszt");
  measured.cases.forEach((item, index) => assert.deepEqual(item, expected.cases[index], item.ext + ": " + JSON.stringify(item.source.slice(0, 60))));
  assert.deepEqual(measured.samples, expected.samples);
  console.log("Passed highlight parity (" + measured.cases.length + " cases, " + measured.samples.length + " sample files).");
}
