// Szabadkézi rajz (Public/sketch.js) – a szerkesztő és a szerver (Sources/ThinkCore/Sketch.swift) ugyanazt a remegő
// rajzot adja. Az elvárt eredmény: Tests/Fixtures/sketch.json; a Swift-teszt (sketchMatchesSharedFixtures) ugyanezt
// olvassa. Új eset vagy szándékos algoritmusváltozás után: node Tests/Editor/sketch.mjs --write
import assert from "node:assert/strict";
import {readFileSync, writeFileSync} from "node:fs";
import {sketchSeed, sketchOutline, sketchPaths, sketchShift, stickyColor} from "../../Public/sketch.js";

const cases = [
  {id: "box-a", shape: "rounded", width: 220, height: 120, roughness: 1.3, passes: 2},
  {id: "n00042", shape: "rectangle", width: 640, height: 400, roughness: 1.3, passes: 2},
  {id: "kerek", shape: "ellipse", width: 180, height: 110, roughness: 1.3, passes: 2},
  {id: "rombusz", shape: "diamond", width: 160, height: 150, roughness: 2, passes: 3,
    vertices: [[0, -75], [80, 0], [0, 75], [-80, 0]]},
  {id: "vonal-1", shape: "rounded", width: 64, height: 40, roughness: .5, passes: 1},
];
const tokens = d => d.match(/[A-Za-z]|-?\d+(?:\.\d+)?/g).map(token => /[A-Za-z]/.test(token) ? token : Number(token));
const draw = item => {
  const paths = sketchPaths(sketchSeed(item.id), sketchOutline(item.shape, item.width, item.height, item.vertices), item.roughness, item.passes);
  return {fill: tokens(paths.fill), strokes: paths.strokes.map(tokens), shift: sketchShift(sketchSeed(item.id), item.roughness)};
};
const fixture = "Tests/Fixtures/sketch.json";
if (process.argv.includes("--write")) {
  writeFileSync(fixture, JSON.stringify({seed: sketchSeed("box-a"), sticky: stickyColor("#f0bd23"),
    cases: cases.map(item => ({...item, ...draw(item)}))}) + "\n");
  console.log("Fixture újraírva: " + fixture);
} else {
  const saved = JSON.parse(readFileSync(fixture, "utf8"));
  assert.equal(sketchSeed("box-a"), saved.seed);
  assert.equal(stickyColor("#f0bd23"), saved.sticky);
  assert.equal(saved.cases.length, cases.length, "a fixture és az esetek száma eltér (--write)");
  for (const item of saved.cases) {
    const drawn = draw(item);
    assert.deepStrictEqual({fill: drawn.fill, strokes: drawn.strokes, shift: drawn.shift},
      {fill: item.fill, strokes: item.strokes, shift: item.shift}, "Eltérés: " + item.id);
  }
  // Ugyanaz az azonosító mindig ugyanazt rajzolja, más azonosító mást.
  assert.deepStrictEqual(draw(cases[0]), draw(cases[0]));
  assert.notDeepStrictEqual(draw(cases[0]).fill, draw({...cases[0], id: "box-b"}).fill);
  console.log("Passed sketch parity (" + saved.cases.length + " cases).");
}
