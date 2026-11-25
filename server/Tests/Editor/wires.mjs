// A vonalak rajzolt útvonala a szerkesztőben (Public/geometry.js: edgeGeometry, wireHeads, pairShift) pontosan egyezzen
// a szerverével (Rendering.swift): oda-vissza kötések eltolása a vonalvastagság szerint, és a vonal vége a nyílhegy
// talpánál. Az elvárt eredmény: Tests/Fixtures/wires.json – a Swift-teszt (wirePathsMatchSharedFixtures) ugyanezt
// ellenőrzi a kirajzolt SVG-n. Futtatás a server/ mappából, Node 22+. A fixture újraírása: --write.
import assert from "node:assert/strict";
import {readFileSync, writeFileSync} from "node:fs";

const {edgeGeometry, edgePaint, reverseWidth, wireHeads, wireRoutes, taperedArc} = await import("../../Public/geometry.js");
const {decodeWorksheet} = await import("../../Public/worksheet-json.js");

const box = (id, x, y, extra = {}) => ({id, type: "box", text: id, shape: "rectangle", fill: 2, textCol: 1, fontSz: 16, align: "center",
  pos: {x, y}, w: 140, h: 80, ...extra});
const wire = (id, source, target, extra = {}) => ({id, source, target: {node: target}, type: "straight", appearance: "plain", endArrow: true, ...extra});
const row = [box("a", -300, 0), box("b", 300, 0)], slanted = [box("a", -300, -120), box("b", 280, 160)];
const setups = {
  "egy vonal, nyíllal": {nodes: row, edges: [wire("e1", "a", "b")]},
  "egy vonal, nyíl nélkül": {nodes: row, edges: [wire("e1", "a", "b", {endArrow: false})]},
  "vastag vonal, nyíllal": {nodes: slanted, edges: [wire("e1", "a", "b", {w: 24})]},
  "két nyílhegy rövid vonalon": {nodes: [box("a", -150, 0), box("b", 150, 0)], edges: [wire("e1", "a", "b", {w: 32, startArrow: true})]},
  "oda-vissza pár, vékony": {nodes: row, edges: [wire("e1", "a", "b"), wire("e2", "b", "a")]},
  "oda-vissza pár, ferde": {nodes: slanted, edges: [wire("e1", "a", "b"), wire("e2", "b", "a")]},
  "oda-vissza pár, 12-es": {nodes: row, edges: [wire("e1", "a", "b", {w: 12}), wire("e2", "b", "a", {w: 12})]},
  "oda-vissza pár, 2-es és 24-es": {nodes: slanted, edges: [wire("e1", "a", "b"), wire("e2", "b", "a", {w: 24})]},
  "oda-vissza pár, ellipszis és doboz": {nodes: [box("a", -300, 0, {shape: "ellipse", w: 120, h: 120}), box("b", 300, 60)], edges: [wire("e1", "a", "b"), wire("e2", "b", "a")]},
  "S-görbe, vastag": {nodes: slanted, edges: [wire("e1", "a", "b", {type: "sCurve", w: 12})]},
  "kötél, vastag": {nodes: slanted, edges: [wire("e1", "a", "b", {type: "rope", w: 12})]},
  "konténer és belső doboza (nincs eltolás)": {nodes: [box("a", 0, 0, {w: 600, h: 400, container: true}), box("b", 120, 60, {parent: "a"})],
    edges: [wire("e1", "a", "b"), wire("e2", "b", "a")]},
};

function paths({nodes: stored, edges: storedEdges}) {
  const {nodes, edges} = decodeWorksheet({nodes: stored, edges: storedEdges});
  const index = new Map(nodes.map(node => [node.id, node])), routes = wireRoutes(edges);
  const inside = (node, outer) => { for (let at = node; at?.parent; at = index.get(at.parent)) if (at.parent === outer.id) return true; return false; };
  return edges.map(edge => {
    const source = index.get(edge.source), target = index.get(edge.target.node);
    const nested = inside(target, source) ? 1 : inside(source, target) ? -1 : 0;
    const geometry = edgeGeometry(edge, id => index.get(id), nested, reverseWidth(edge, routes));
    const paint = edgePaint(edge);
    assert.equal(taperedArc(geometry, paint), null, "ívelt (kúpos) vonal nincs az esetek között");
    const heads = wireHeads(geometry, paint);
    return {id: edge.id, d: geometry.path(heads.source.base, heads.target.base)};
  });
}
// Az útvonal betűi és számai (3 tizedesre), hogy a két oldal számformátuma ne számítson.
const tokens = d => d.match(/[A-Za-z]|-?\d+(?:\.\d+)?(?:e-?\d+)?/g).map(token => /[A-Za-z]/.test(token) ? token : Math.round(Number(token) * 1000) / 1000);

const fixture = "Tests/Fixtures/wires.json";
if (process.argv.includes("--write")) {
  writeFileSync(fixture, JSON.stringify(Object.entries(setups).map(([name, sheet]) => ({name, ...sheet,
    paths: paths(sheet).map(({id, d}) => ({id, path: tokens(d)}))})), null, 1) + "\n");
  console.log("Fixture újraírva: " + fixture);
} else {
  const cases = JSON.parse(readFileSync(fixture, "utf8"));
  assert.equal(cases.length, Object.keys(setups).length, "a fixture és az esetek száma eltér (--write)");
  for (const item of cases) {
    assert.deepStrictEqual(paths(item).map(({id, d}) => ({id, path: tokens(d)})), item.paths, "Eltérés: " + item.name);
  }
  console.log("Passed wire path parity (" + cases.length + " cases).");
}
