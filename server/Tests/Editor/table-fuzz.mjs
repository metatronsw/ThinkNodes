// Differenciális fuzz-teszt (audit, 2026-11-24): rögzített kezdőértékű véletlen esetek a számkezelésre
// (kiírás, kerekítés, beolvasás, tört, képlet). A JS eredménye a Tests/TableFixtures/numbers-fuzz.json;
// a Swift (Tests/ThinkTableTests/FixtureTests.swift sharedFuzzFixtures) ugyanezt kell adja.
// Futtatás: node Tests/Editor/table-fuzz.mjs        – ellenőrzi, hogy a fixture naprakész
//           node Tests/Editor/table-fuzz.mjs --write – újragenerálja
import assert from "node:assert/strict";
import {readFileSync, writeFileSync} from "node:fs";
import {display, general, parseInput, roundHalfAway} from "../../Public/table/table-format.js";
import {emptyTable, setCell} from "../../Public/table/table-document.js";
import {recalculate} from "../../Public/table/table-engine.js";

function mulberry32(seed) {
  return () => {
    seed |= 0; seed = seed + 0x6D2B79F5 | 0;
    let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

// A számok szövegként tárolódnak (a JS legrövidebb pontos alakja): egyes JSON-dekóderek (pl. a macOS 13 Foundation
// JSONDecoder-e) a lebegőpontos literált 1 ulp pontatlansággal olvassák be, a teszt viszont a motorok egyezését méri.
const n = value => typeof value === "number" ? "n:" + String(value) : value;

export function generate() {
  const random = mulberry32(20261124);
  const int = (a, b) => a + Math.floor(random() * (b - a + 1));
  const pick = list => list[int(0, list.length - 1)];
  const value = () => {
    switch (int(0, 5)) {
      case 0: return (random() < .5 ? -1 : 1) * random() * Math.pow(10, int(-12, 22));             // tetszőleges nagyságrend
      case 1: { const d = int(0, 6); return (random() < .3 ? -1 : 1) * (int(0, 99999) + 0.5) / Math.pow(10, d); }  // pontosan fél
      case 2: { const d = int(1, 6); return (random() < .3 ? -1 : 1) * (int(0, 99999) * 10 + 5) / Math.pow(10, d + 1); } // x,xx5
      case 3: return int(-1000000, 1000000);                                                         // egész
      case 4: return Number((random() * 1000).toFixed(int(0, 4)));                                   // „emberi” tizedes
      default: return int(0, 50) + int(1, 31) / int(2, 64);                                          // tört
    }
  };
  const formats = [null, {kind: "number", dec: 2, group: true}, {kind: "number", dec: 0}, {kind: "number", dec: 4},
    {kind: "currency", dec: 0, symbol: "Ft"}, {kind: "currency", dec: 2, symbol: "€", before: true},
    {kind: "percent", dec: 1}, {kind: "fraction"}, {kind: "fraction", dec: 999}, {kind: "date", pattern: "yyyy.MM.dd. HH:mm"}];
  const cases = {format: [], round: [], parse: [], formula: []};
  for (let i = 0; i < 1200; i++) {
    const v = value(), fmt = pick(formats);
    if (fmt?.kind === "date" && (v < 0 || v > 2900000)) continue;
    cases.format.push({v: n(v), fmt, text: display(v, fmt)});
    const d = int(-3, 8);
    cases.round.push({v: n(v), d, r: n(roundHalfAway(v, d))});
  }
  for (let i = 0; i < 600; i++) {
    const v = value(), fmt = pick(formats.slice(0, 8));
    const text = display(v, fmt).replace(/\u00a0/g, pick([" ", "\u00a0", ""]));
    const parsed = parseInput(text);
    cases.parse.push({input: text, kind: parsed.kind, v: n(parsed.value ?? null), fmt: parsed.format ?? null});
  }
  const literal = v => { const text = general(v); return /E/.test(text) ? String(v) : text; };
  for (let i = 0; i < 600; i++) {
    const a = literal(Number(value().toPrecision(8))), b = literal(Number(value().toPrecision(6))) || "1";
    const op = pick(["+", "-", "*", "/", "^", "=", "<"]);
    const forms = [
      "=" + a.replace(",", ".") + op + b.replace(",", "."),
      "=ROUND(" + a.replace(",", ".") + ";" + int(-2, 6) + ")",
      "=SZUM(" + a + ";" + b + ")",
      "=(" + a + ")" + op + "(" + b + ")",
      "=AVERAGE(" + a.replace(",", ".") + "," + b.replace(",", ".") + ")",
    ];
    const formula = pick(forms);
    const doc = emptyTable(null, 1, 1);
    setCell(doc, "A1", {f: formula.slice(1)});
    recalculate(doc);
    cases.formula.push({f: formula.slice(1), v: n(doc.cells.A1.v)});
  }
  return cases;
}

const file = new URL("../TableFixtures/numbers-fuzz.json", import.meta.url);
const cases = generate();
const text = JSON.stringify(cases) + "\n";
if (process.argv.includes("--write")) {
  writeFileSync(file, text);
  console.log("numbers-fuzz.json: " + Object.entries(cases).map(([k, v]) => k + " " + v.length).join(", "));
} else {
  assert.equal(readFileSync(file, "utf8"), text, "a numbers-fuzz.json elavult: node Tests/Editor/table-fuzz.mjs --write");
  console.log("table-fuzz: a fixture naprakész (" + Object.values(cases).reduce((n, v) => n + v.length, 0) + " eset)");
}
