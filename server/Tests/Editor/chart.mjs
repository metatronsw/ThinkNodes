// Grafikon (Public/chart.js): számfelismerés, oszlopok és sorozatok kiválasztása, a négy diagramtípus SVG-je.
// Futtatás a server/ mappából: node Tests/Editor/chart.mjs
import assert from "node:assert/strict";
import {chartData, chartSVG, darkSurface, fileRows, tableRows, toNumber} from "../../Public/chart.js";

// Számok: magyar és angol írásmód, százalék; ami nem szám, az nem lesz az.
assert.deepEqual(["1 234,5", "1,234.5", "1.234,5", "12%", "-3,5", "1,234,567", ".5", "+7"].map(toNumber), [1234.5, 1234.5, 1234.5, 12, -3.5, 1234567, 0.5, 7]);
assert.deepEqual(["", "abc", "2024-01-01", "12 db", "1.2.3,4,5", null, NaN, true].map(toNumber), Array(8).fill(null));
assert.equal(toNumber(42), 42);

const csv = "Hónap;Bevétel;Kiadás;Megjegyzés\r\nJan;1 200,5;900;a\r\nFeb;1 500;1100;b\r\n;;;\r\nMár;900;1300;\r\n";
const rows = fileRows("csv", csv, "adat.csv");
assert.equal(rows.length, 5);

// Automatikus kiosztás: az első szöveges oszlop a kategória, a számoszlopok a sorozatok; az üres sor kimarad.
let data = chartData(rows, {kind: "bar"});
assert.equal(data.labelColumn, 0);
assert.deepEqual(data.labels, ["Jan", "Feb", "Már"]);
assert.deepEqual(data.series.map(item => [item.name, item.values]), [["Bevétel", [1200.5, 1500, 900]], ["Kiadás", [900, 1100, 1300]]]);
assert.deepEqual(data.columns.map(column => column.numeric), [false, true, true, false]);

// Kézi kiosztás, sorszám mint kategória, fejléc nélküli tábla.
data = chartData(rows, {kind: "line", labels: -1, values: [2]});
assert.deepEqual([data.labels, data.series.map(item => item.name)], [["1", "2", "3"], ["Kiadás"]]);
data = chartData([[2020, 5], [2021, 7]], {kind: "bar", header: false});
assert.deepEqual([data.labels, data.series[0].name, data.series[0].values], [["2020", "2021"], "B", [5, 7]]);
// Érvénytelen (nem szám, nem létező, a kategóriával azonos) értékoszlop: vissza az automatikusra.
assert.deepEqual(chartData(rows, {kind: "bar", values: [3, 9, 0]}).valueColumns, [1, 2]);

// Kör: egy sorozat. Pont: az x tengely számoszlop, akkor is, ha szöveges oszlopot kértek.
assert.equal(chartData(rows, {kind: "pie"}).series.length, 1);
data = chartData(rows, {kind: "scatter", labels: 0});
assert.deepEqual([data.labelColumn, data.x, data.valueColumns], [1, [1200.5, 1500, 900], [2]]);

// Táblázatfájl: a tárolt értékek; a hibás cella üres.
const table = JSON.stringify({format: "thinknodes-table", version: 1, id: "tbl-1", size: {rows: 3, cols: 2}, styles: [{}],
  cells: {A1: {v: "Név"}, B1: {v: "Érték"}, A2: {v: "x"}, B2: {v: 3, f: "=1+2"}, A3: {v: "y"}, B3: {v: {err: "#DIV/0!"}}}});
assert.deepEqual(fileRows("table", table), [["Név", "Érték"], ["x", 3], ["y", ""]]);
assert.equal(fileRows("table", "nem json"), null);
assert.deepEqual(tableRows({size: {rows: 1, cols: 2}, cells: {B1: {v: true}}}), [["", true]]);

// A rajz: érvényes, önálló SVG a kért méretben, style attribútum nélkül (a megtekintő szabálya nem engedné).
const big = [["x", "y", "z", "w"], ...Array.from({length: 300}, (_, i) => [i, Math.sin(i / 6) * 40000, i * 9, -i])];
for (const kind of ["bar", "line", "pie", "scatter"]) {
  for (const source of [rows, big]) {
    for (const size of [{width: 380, height: 260}, {width: 120, height: 70}, {width: 64, height: 40}]) {
      const svg = chartSVG(source, {kind}, {...size, dark: source === big});
      assert.match(svg, new RegExp(`^<svg [^>]*width="${size.width}" height="${size.height}"`), kind);
      assert.ok(svg.endsWith("</svg>") && !/\sstyle=|NaN|undefined|Infinity/.test(svg), kind + " " + size.width);
      assert.equal((svg.match(/<svg/g) ?? []).length, 1);
    }
  }
}
// Oszlop: soronként és sorozatonként egy jel, buboréksúgóval; két sorozatnál jelmagyarázat, egynél nincs.
let svg = chartSVG(rows, {kind: "bar"}, {width: 380, height: 260});
assert.equal((svg.match(/<path /g) ?? []).length, 6);
assert.match(svg, /<title>Bevétel · Jan: 1.?200,5<\/title>/);
assert.equal((svg.match(/<rect /g) ?? []).length, 2);
assert.equal((chartSVG(rows, {kind: "bar", values: [1]}, {width: 380, height: 260}).match(/<rect /g) ?? []).length, 0);
// Kör: nyolcnál több szelet „Egyéb”-be vonódik; negatív és nulla érték kimarad.
svg = chartSVG(big, {kind: "pie", values: [2]}, {width: 380, height: 260});
assert.equal((svg.match(/<path /g) ?? []).length, 8);
assert.ok(svg.includes("Egyéb"));
assert.ok(chartSVG(big, {kind: "pie", values: [3]}, {width: 380, height: 260}).includes("pozitív számok"));
// Idegen szöveg nem kerül jelölőnyelvként a rajzba.
assert.ok(!chartSVG([["a<b>", "<script>"], ["\"x\"&", 1]], {kind: "bar"}, {width: 300, height: 200}).includes("<script>"));
// Nincs mit rajzolni: üzenet, nem hiba.
assert.ok(chartSVG([["a", "b"], ["x", "y"]], {kind: "bar"}, {width: 300, height: 200}).includes("Nincs ábrázolható"));
assert.ok(chartSVG(null, {kind: "bar"}, {width: 300, height: 200}).includes("nem olvasható"));
assert.ok(chartSVG([], {kind: "nincs ilyen"}, {width: 300, height: 200}).includes("Nincs ábrázolható"));

// Felület: a háttérszínből, annak híján a szövegszínből.
assert.deepEqual([darkSurface("#101010", "#000"), darkSurface("#ffffff", "#fff"), darkSurface(undefined, "#f0f0f0"), darkSurface(undefined, "#182335"), darkSurface("", 3)],
  [true, false, true, false, false]);
// Adatvonal: csak táblázat (vagy CSV) és grafikon között; a félkorong a doboz oldalához igazodik.
const {isDataLink, plugTransform} = await import("../../Public/geometry.js");
const boxes = new Map([["t", {type: "table"}], ["c", {type: "csv"}], ["g", {type: "chart"}], ["b", {type: "box"}]]);
const link = (source, target) => isDataLink({source, target: {node: target}}, id => boxes.get(id));
assert.deepEqual([link("t", "g"), link("g", "c"), link("b", "g"), link("t", "c"), link("g", "g"), link("t", undefined)], [true, true, false, false, false, false]);
const box = {position: {x: 100, y: 50}, width: 200, height: 100};
// Jobb oldal: a domború rész jobbra (kifelé) néz; alsó oldal: lefelé. Legalább 16 egység átmérő.
assert.equal(plugTransform(box, {x: 200, y: 70}, 2), "translate(200 70) rotate(180) scale(16)");
assert.equal(plugTransform(box, {x: 0, y: 40}, 2), "translate(0 40) rotate(0) scale(16)");
assert.equal(plugTransform(box, {x: 120, y: 100}, 4), "translate(120 100) rotate(-90) scale(24)");
assert.equal(plugTransform(box, {x: 120, y: 0}, 2), "translate(120 0) rotate(90) scale(16)");
// Az adatvonal a két doboz egymás felé eső oldalának közepéhez csatlakozik, akármilyen szögben áll a két doboz.
const {edgeGeometry, sideMidpoint} = await import("../../Public/geometry.js");
const placed = new Map([["t", {type: "table", shape: "rounded", position: {x: 0, y: 0}, width: 200, height: 100}],
  ["g", {type: "chart", shape: "rounded", position: {x: 400, y: 60}, width: 300, height: 200}],
  ["b", {type: "box", shape: "rectangle", position: {x: 400, y: 60}, width: 300, height: 200}]]);
let wire = edgeGeometry({source: "t", target: {node: "g"}, type: "straight"}, id => placed.get(id));
assert.deepEqual([wire.from, wire.to], [{x: 100, y: 0}, {x: 250, y: 60}]);
placed.get("g").position = {x: 60, y: 500};
wire = edgeGeometry({source: "g", target: {node: "t"}, type: "straight"}, id => placed.get(id));
assert.deepEqual([wire.from, wire.to], [{x: 60, y: 400}, {x: 0, y: 50}]);
// Közönséges vonal (doboz → táblázat) nem oldalközépre megy.
wire = edgeGeometry({source: "t", target: {node: "b"}, type: "straight"}, id => placed.get(id));
assert.notDeepEqual(wire.to, sideMidpoint(placed.get("b"), {x: 0, y: 0}));
console.log("chart: rendben");
