// A konténer szövegének körbefuttatása (a szöveg kikerüli a benne lévő dobozokat) a szerkesztőben (Public/geometry.js
// labelLayout, textSlot) pontosan egyezzen a szerverével (Rendering.swift ideaDrawing, textSlot). Az elvárt eredmény:
// Tests/Fixtures/text-flow.json – a Swift-teszt (textFlowMatchesSharedFixtures) ugyanezt ellenőrzi a kirajzolt SVG-n.
// Futtatás a server/ mappából, Node 22+. A fixture újraírása (ha a tördelés szándékosan változott): --write.
import assert from "node:assert/strict";
import {readFileSync, writeFileSync} from "node:fs";
import {runInThisContext} from "node:vm";

globalThis.self = globalThis;
runInThisContext(readFileSync("Public/vendor/commonmark.js", "utf8"));
const {canvasMarkdown} = await import("../../Public/canvas-markdown.js");
const {labelLayout} = await import("../../Public/geometry.js");
const {decodeWorksheet} = await import("../../Public/worksheet-json.js");

const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.";
const text = "# Címsor a konténerben\n\n" + lorem + "\n\n" + lorem + "\n\n- első felsorolási elem\n- második, valamivel hosszabb felsorolási elem, amely átfordul\n\nZáró bekezdés rövid szöveggel.";
const box = (id, x, y, w, h, extra = {}) => ({id, type: "box", text: "", shape: "rectangle", fill: 2, textCol: 1, fontSz: 16,
  align: "center", pos: {x, y}, w, h, ...extra});
const container = extra => box("kontener", 40, -20, 760, 620, {text, container: true, align: "left", vAlign: "top", ...extra});
const child = (id, x, y, w, h) => box(id, x, y, w, h, {parent: "kontener"});
// Minden eset: a konténer beállításai és a benne lévő dobozok (vászon-koordinátákkal, a fájl kulcsaival).
const setups = {
  "nincs doboz, felül": [container({})],
  "egy doboz jobbra fent": [container({}), child("a", 280, -200, 200, 140)],
  "egy doboz balra középen": [container({}), child("a", -220, 0, 180, 160)],
  "két doboz, sorkizárt": [container({justified: true}), child("a", 260, -180, 220, 120), child("b", -200, 120, 200, 140)],
  "doboz a közepén (két oldalt kevés hely)": [container({}), child("a", 40, -60, 420, 120)],
  "középre igazítva": [container({align: "center", vAlign: "middle"}), child("a", 280, -220, 180, 120)],
  "jobbra és alulra igazítva, sorkizárt": [container({align: "right", vAlign: "bottom", justified: true}), child("a", 40, -200, 240, 140)],
  "keskeny konténer": [box("kontener", 0, 0, 360, 900, {text, container: true, align: "left", vAlign: "top"}), box("a", 60, -280, 180, 140, {parent: "kontener"})],
  "körbefuttatás kikapcsolva": [container({textFlow: false, vAlign: "middle"}), child("a", 280, -200, 200, 140)],
  "szöveg nem fér ki": [box("kontener", 0, 0, 520, 300, {text, container: true, align: "left", vAlign: "top"}), box("a", 120, -60, 200, 120, {parent: "kontener"})],
};

function lines(nodes) {
  const [owner, ...inner] = decodeWorksheet({nodes}).nodes;
  const obstacles = owner.textFlow === false ? [] : inner.map(node => ({x: node.position.x - owner.position.x,
    y: node.position.y - owner.position.y, width: node.width, height: node.height}));
  const round = value => Math.round(value * 1000) / 1000;
  return labelLayout(owner, canvasMarkdown(owner.text), obstacles).lines.map(line => ({text: line.text, x: round(line.x), y: round(line.y), anchor: line.anchor}));
}

const fixture = "Tests/Fixtures/text-flow.json";
if (process.argv.includes("--write")) {
  writeFileSync(fixture, JSON.stringify(Object.entries(setups).map(([name, nodes]) => ({name, nodes, lines: lines(nodes)})), null, 1) + "\n");
  console.log("Fixture újraírva: " + fixture);
} else {
  const cases = JSON.parse(readFileSync(fixture, "utf8"));
  assert.equal(cases.length, Object.keys(setups).length, "a fixture és az esetek száma eltér (--write)");
  for (const {name, nodes, lines: expected} of cases) assert.deepStrictEqual(lines(nodes), expected, "Eltérés: " + name);
  console.log("Passed text flow parity (" + cases.length + " cases).");
}
