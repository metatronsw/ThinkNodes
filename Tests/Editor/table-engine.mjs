// Közös tesztesetek (Tests/TableFixtures) a JavaScript-oldalra; a Swift párja: Tests/ThinkTableTests/FixtureTests.swift.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {recalculate} from "../../Public/table/table-engine.js";
import {display, parseInput} from "../../Public/table/table-format.js";
import {move, shift} from "../../Public/table/table-formula.js";
import {decodeTable, encodeTable, emptyTable, parseAddress, setCell, styleIndex} from "../../Public/table/table-document.js";
import {TableEditor} from "../../Public/table/table-edit.js";
import {detectSeparator} from "../../Public/table/table-csv.js";

const fixture = name => JSON.parse(readFileSync(new URL("../TableFixtures/" + name, import.meta.url), "utf8"));
let failures = 0;
const check = (label, run) => { try { run(); } catch (error) { failures++; console.error("✘ " + label + "\n  " + error.message.split("\n").slice(0, 6).join("\n  ")); } };

function apply(inputs, doc) {
  for (const [name, input] of Object.entries(inputs)) {
    const address = parseAddress(name);
    const parsed = parseInput(input), cell = {};
    if (parsed.kind === "formula") cell.f = parsed.formula;
    else if (parsed.kind === "value") {
      cell.v = parsed.value;
      if (parsed.format) cell.s = styleIndex(doc, {fmt: parsed.format});
    }
    setCell(doc, name, cell);
    doc.size.rows = Math.max(doc.size.rows, address.row + 1);
    doc.size.cols = Math.max(doc.size.cols, address.col + 1);
  }
}

for (const test of fixture("formulas.json")) {
  const doc = emptyTable(null, 1, 1);
  apply(test.cells, doc);
  recalculate(doc);
  for (const [name, expected] of Object.entries(test.expect))
    check(test.name + ": " + name, () => assert.deepEqual(doc.cells[name]?.v, expected));
  if (test.change) {
    apply(test.change, doc);
    recalculate(doc, Object.keys(test.change));
    for (const [name, expected] of Object.entries(test.after))
      check(test.name + " (változás után): " + name, () => assert.deepEqual(doc.cells[name]?.v, expected));
    const full = structuredClone(doc);
    recalculate(full);
    check(test.name + ": részleges = teljes", () => assert.deepEqual(full, doc));
  }
}

for (const test of fixture("formats.json"))
  check("formátum " + JSON.stringify(test.value) + " " + JSON.stringify(test.fmt), () => assert.equal(display(test.value, test.fmt), test.text));

for (const test of fixture("inputs.json")) check("bemenet " + JSON.stringify(test.input), () => {
  const parsed = parseInput(test.input);
  assert.equal(parsed.kind, test.kind);
  if (test.kind === "formula") assert.equal(parsed.formula, test.formula);
  if (test.kind === "value") { assert.deepEqual(parsed.value, test.v); assert.deepEqual(parsed.format ?? undefined, test.fmt); }
});

for (const test of fixture("rewrite.json")) check("átírás " + test.formula + " " + test.op, () => assert.equal(
  test.op === "shift" ? shift(test.formula, test.axis, test.at, test.count) : move(test.formula, test.rows, test.cols), test.expect));

check("dokumentum oda-vissza", () => {
  const doc = emptyTable("Próba", 3, 2);
  setCell(doc, "B2", {f: "1+1", v: 2, s: styleIndex(doc, {b: true, border: {bottom: {w: 2, color: "#333333"}}})});
  const text = encodeTable(doc);
  assert.deepEqual(decodeTable(text), doc);
  assert.ok(text.includes('"b":1'));
  assert.throws(() => decodeTable('{"format":"thinknodes-table","version":1,"size":{"rows":1,"cols":1},"cells":{"ZZZZ1":{"v":1}}}'));
});

check("CSV-elválasztó (a Swift-tel egyezően)", () => {
  assert.equal(detectSeparator("a;b,c\n", "csv"), ",");
  assert.equal(detectSeparator("a;b;c,d\n", "csv"), ";");
  assert.equal(detectSeparator("a,b\n", "tsv"), "\t");
});

// Szerkesztésvezérlő (DOM nélkül).
check("szerkesztés: beírás, Σ, beszúrás, beillesztés, visszavonás, keret", () => {
  const doc = emptyTable("T", 4, 3);
  let saves = 0;
  const edit = new TableEditor(doc, {onChange: () => saves++});
  edit.select(0, 0); edit.startDraft("10"); edit.commitDraft();
  edit.select(1, 0); edit.startDraft("1 200 Ft"); edit.commitDraft();
  assert.equal(doc.cells.A2.v, 1200);
  assert.equal(doc.styles[doc.cells.A2.s].fmt.kind, "currency");
  edit.select(2, 0); edit.autoSum();
  assert.equal(doc.cells.A3.f, "SUM(A1:A2)");
  assert.equal(doc.cells.A3.v, 1210);
  edit.select(0, 0); edit.insertRows(true);
  assert.equal(doc.cells.A4.f, "SUM(A2:A3)");
  assert.equal(doc.cells.A4.v, 1210);
  assert.equal(doc.size.rows, 5);
  edit.undo();
  assert.equal(doc.cells.A3.f, "SUM(A1:A2)");
  edit.redo();
  edit.select(1, 0); edit.select(3, 0, true);
  const clip = edit.copy();
  assert.equal(clip.tsv.split("\n").length, 3);
  edit.select(1, 2); edit.paste({json: clip.json});
  assert.equal(doc.cells.C4.f, "SUM(C2:C3)");
  assert.equal(doc.cells.C4.v, 1210);
  edit.select(0, 1); edit.paste({tsv: "a\t=1+1\n2\t3"});
  assert.equal(doc.cells.C1.v, "=1+1");
  assert.equal(doc.cells.C1.f, undefined);
  assert.equal(doc.cells.B2.v, 2);
  edit.select(0, 0); edit.select(1, 1, true); edit.border("outer", {w: 3, color: "#ff0000", style: "solid"});
  assert.deepEqual(doc.styles[doc.cells.A1.s].border, {top: {w: 3, color: "#ff0000", style: "solid"}, left: {w: 3, color: "#ff0000", style: "solid"}});
  edit.toggle("b");
  assert.equal(doc.styles[doc.cells.B2.s].b, 1);
  edit.select(0, 0); edit.deleteRows();
  assert.equal(doc.cells.A3.f, "SUM(A1:A2)");
  assert.ok(saves > 5);
  assert.ok(edit.keydown({key: "ArrowDown"}) && edit.active.r === 1);
  assert.ok(edit.keydown({key: "x"}) && edit.draft === "x");
});

if (failures) { console.error(failures + " hiba"); process.exit(1); }
console.log("table-engine: minden közös teszteset rendben");
