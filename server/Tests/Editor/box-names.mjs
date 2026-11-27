// A doboz nevének tördelése (Public/geometry.js nameLayout) pontosan egyezzen a szerverével (Rendering.swift nameLayout).
// Az elvárt eredmény: Tests/Fixtures/box-names.json – a Swift-teszt (boxNamesMatchSharedFixtures) ugyanezt ellenőrzi.
// Futtatás a server/ mappából: node Tests/Editor/box-names.mjs; a fixture újraírása (szándékos változásnál): --write.
import assert from "node:assert/strict";
import {readFileSync, writeFileSync} from "node:fs";
import {nameLayout, nameStyle} from "../../Public/geometry.js";

const fixture = "Tests/Fixtures/box-names.json";
const cases = [
  {name: "kor", width: 176},
  {name: "Rövid név", width: 64},
  {name: "Hosszabb név, amely több sorba tördelődik a doboz szélességén", width: 176},
  {name: "Árvíztűrő tükörfúrógép és ŐŰ nagybetűk", width: 120},
  {name: "nagyonhosszúszóamelynemfértelegysorbanéstovábbisvanbelőle", width: 140},
  {name: "csapat", list: true, width: 240},
  {name: "beallitasok", list: false, width: 90},
  {name: "", list: true, width: 120},
  {name: "  szóközök   között  ", width: 200},
  {name: "x".repeat(40) + " " + "Lorem ipsum dolor sit amet, ".repeat(8).trim(), width: 300},
  {name: "W".repeat(255), width: 4096},
];
const actual = cases.map(item => {
  const layout = nameLayout({type: "box", name: item.name, list: item.list, width: item.width});
  return {...item, lines: layout?.lines ?? [], height: layout?.height ?? 0};
});
// Nem doboz (pl. előnézet) és üres név: nincs felirat.
assert.equal(nameLayout({type: "preview", name: "x", width: 100}), null);
assert.equal(nameLayout({type: "box", name: "  ", width: 100}), null);
// A sorok magassága és a jel helye.
for (const item of actual) {
  if (!item.lines.length) continue;
  assert.equal(item.height, item.lines.length * nameStyle.line + nameStyle.gap);
  if (item.list != null) assert.ok(item.lines.at(-1).endsWith(item.list ? "[]" : "{}"));
}
if (process.argv.includes("--write")) {
  writeFileSync(fixture, JSON.stringify(actual, null, 1) + "\n");
  console.log("box-names: fixture újraírva (" + actual.length + " eset)");
} else {
  assert.deepEqual(actual, JSON.parse(readFileSync(fixture, "utf8")));
  console.log("box-names: " + actual.length + " eset egyezik");
}
