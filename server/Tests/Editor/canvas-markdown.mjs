// A doboz-markdown kliensoldali feldolgozása (Public/canvas-markdown.js) pontosan egyezzen a szerverével
// (CanvasMarkdown.swift). Az elvárt eredmény: Tests/Fixtures/canvas-markdown.json (a Swift-teszt is ezt ellenőrzi).
// Futtatás a repó gyökeréből, Node 22+; a commonmark.js-t a ./build.sh tölti le a Public/vendor/ alá.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {runInThisContext} from "node:vm";

globalThis.self = globalThis;
runInThisContext(readFileSync("Public/vendor/commonmark.js", "utf8"));
const {canvasMarkdown} = await import("../../Public/canvas-markdown.js");
const cases = JSON.parse(readFileSync("Tests/Fixtures/canvas-markdown.json", "utf8"));
let failed = 0;
for (const {source, blocks} of cases) {
  try { assert.deepStrictEqual(canvasMarkdown(source), blocks); }
  catch (error) { failed++; console.error("Eltérés:", JSON.stringify(source).slice(0, 80)); console.error(error.message.slice(0, 1500)); }
}
assert.equal(failed, 0, failed + " eset eltér a szerver kimenetétől");
console.log("Passed canvas markdown parity (" + cases.length + " cases).");
