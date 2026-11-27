// Struktúra-konténer (Public/structure-boxes.js): értékek, típusszavak, generálás, párosítás, visszafelé alakítás.
// Futtatás a server/ mappából: node Tests/Editor/structure-boxes.mjs
import assert from "node:assert/strict";
import {generateBoxes, boxesValue, boxesSource, parseValue, formatValue, typeInfo, automaticFill, structureFormat, escapeMarkdown,
  unescapeMarkdown, StructureError, generatedLimit, defaultTypeColors, textDigest, inferList} from "../../Public/structure-boxes.js";
import {nameLayout} from "../../Public/geometry.js?v=37";

const container = {id: "c0ffee", type: "box", position: {x: 100, y: 100}, width: 240, height: 120, text: "", name: "adat.json", fontSize: 16};

// A szerkesztő alkalmazási lépése (editor.js applyStructure): a meglévő doboz mezői frissülnek, az új létrejön, a
// megszűnő törlődik; a sorrend a forrásé. Eredmény: a konténer és a leszármazottai (a lap sorrendjében).
function apply(result, root, previous = []) {
  const byId = new Map(previous.map(node => [node.id, node]));
  const nodes = result.nodes.map(({id, parent, fields}) => {
    const node = {...(byId.get(id) ?? {id}), parent};
    for (const [key, value] of Object.entries(fields)) if (value === undefined) delete node[key]; else node[key] = value;
    return node;
  });
  return [{...root, ...result.patch}, ...nodes];
}
const generate = (value, previous = [], root = container) => {
  const result = generateBoxes(typeof value === "string" ? value : JSON.stringify(value), root, {previous: previous.slice(1)});
  return {result, nodes: apply(result, previous[0] ?? root, previous.slice(1))};
};
const find = (nodes, predicate) => nodes.find(predicate);
const byName = (nodes, name) => find(nodes, node => node.name === name);

// Formátum a fájlnévből.
assert.equal(structureFormat("adat.JSON"), "json");
assert.equal(structureFormat("adat.swift"), null);

// Értékek: oda-vissza veszteség nélkül; a literálnak látszó szöveg idézőjelben, a markdown-jelek semlegesek.
for (const value of [3, -2.5, 1e21, true, false, null, "szöveg", "3", "true", "null", " szóköz", "\"idézett\"", "*csillag* _al_ `kód`", "# cím",
  "- lista", "1. elem", "a\nb", "a\\*b", "[x](y)", "Int", "[String: Int]", "", "&amp;", "<b>"]) {
  assert.deepEqual(parseValue(formatValue(value)), value, JSON.stringify(value));
}
assert.equal(formatValue("3"), "\"3\"");
assert.equal(formatValue("*a*"), "\\*a\\*");
assert.equal(formatValue("[Int]"), "[Int]", "link nélkül a szögletes zárójel marad");
assert.equal(parseValue("  42 "), 42);
assert.equal(parseValue("kézzel írt *szöveg*"), "kézzel írt *szöveg*");
assert.equal(unescapeMarkdown(escapeMarkdown("a\\b*c")), "a\\b*c");

// Típusszavak.
assert.deepEqual(typeInfo("Int"), {base: "Int", collection: null, optional: false});
assert.deepEqual(typeInfo("Double?"), {base: "Double", collection: null, optional: true});
assert.deepEqual(typeInfo("[String]"), {base: "String", collection: "array", optional: false});
assert.deepEqual(typeInfo("[String: [Int]]?"), {base: "Int", collection: "dictionary", optional: true});
assert.deepEqual(typeInfo(formatValue("[UUID]")), {base: "UUID", collection: "array", optional: false});
for (const text of ["int", "Integer", "[Int", "Int??x", "[: Int]", "valami", ""]) assert.equal(typeInfo(text), null, text);
assert.equal(automaticFill("Bool", true), defaultTypeColors.Bool);
assert.equal(automaticFill("Bool", false), 0);
assert.equal(automaticFill("szöveg", true), 2);

// Generálás: objektum → {} konténer (list: false), tömb → [] (list: true), egyszerű érték → doboz (név = kulcs).
const sample = {name: "teszt", kor: 3, aktiv: true, csapat: [{name: "Anna", kor: 30}, {name: "Béla", kor: 41}], cimkek: ["a", "b"], ures: {}, tipus: "Int"};
let {result, nodes} = generate(sample);
assert.equal(nodes[0].list, false);
assert.deepEqual([byName(nodes, "name").text, byName(nodes, "kor").text, byName(nodes, "aktiv").text], ["teszt", "3", "true"]);
const csapat = byName(nodes, "csapat");
assert.equal(csapat.list, true);
assert.deepEqual(nodes.filter(node => node.parent === csapat.id).map(node => [node.name, node.list]), [["Anna", false], ["Béla", false]]);
assert.deepEqual(nodes.filter(node => node.parent === byName(nodes, "cimkek").id).map(node => [node.name, node.text]), [[undefined, "a"], [undefined, "b"]]);
assert.equal(byName(nodes, "ures").list, false);
assert.equal(byName(nodes, "tipus").fill, defaultTypeColors.Int);
assert.equal(byName(nodes, "name").fill, 2);
assert.equal(csapat.fill, 0);
assert.ok(nodes.slice(1).every(node => /^[0-9a-f]{32}$/.test(node.id) && node.parent && node.type === "box"));
assert.equal(new Set(nodes.map(node => node.id)).size, nodes.length);
// Oda-vissza: a dobozokból ugyanaz a JSON.
assert.deepEqual(boxesValue(nodes, container.id), sample);
assert.equal(boxesSource(nodes, container.id), JSON.stringify(sample, null, 2) + "\n");
assert.equal(boxesSource(nodes, container.id, {previous: "{\n\t\"a\": 1\n}"}), JSON.stringify(sample, null, "\t") + "\n", "a forrás behúzása marad");

// Elrendezés: a szülő előbb áll, mint a gyermeke; a gyermek a neve fölötte együtt a szülő területén belül van.
const boxes = new Map([[container.id, nodes[0]]]);
for (const node of nodes.slice(1)) {
  const parent = boxes.get(node.parent);
  assert.ok(parent, "a szülő előbb jön");
  const name = nameLayout(node)?.height ?? 0;
  const top = node.position.y - node.height / 2 - name, parentTop = parent.position.y - parent.height / 2;
  assert.ok(top >= parentTop - .001, "a név a szülőn belül: " + node.name);
  assert.ok(node.position.x - node.width / 2 >= parent.position.x - parent.width / 2 - .001);
  assert.ok(node.position.x + node.width / 2 <= parent.position.x + parent.width / 2 + .001);
  assert.ok(node.position.y + node.height / 2 <= parent.position.y + parent.height / 2 + .001);
  boxes.set(node.id, node);
}
// Egy sorban a testvérek (név + doboz) nem fedik egymást.
for (const parent of nodes) {
  const children = nodes.filter(node => node.parent === parent.id);
  for (const a of children) for (const b of children) {
    if (a === b) continue;
    const ra = [a.position.x - a.width / 2, a.position.y - a.height / 2 - (nameLayout(a)?.height ?? 0), a.position.x + a.width / 2, a.position.y + a.height / 2];
    const rb = [b.position.x - b.width / 2, b.position.y - b.height / 2 - (nameLayout(b)?.height ?? 0), b.position.x + b.width / 2, b.position.y + b.height / 2];
    assert.ok(ra[2] <= rb[0] + .001 || rb[2] <= ra[0] + .001 || ra[3] <= rb[1] + .001 || rb[3] <= ra[1] + .001, a.name + " / " + b.name);
  }
}
// A konténer bal felső sarka a helyén marad.
assert.equal(result.patch.position.x - result.patch.width / 2, container.position.x - container.width / 2);
assert.equal(result.patch.position.y - result.patch.height / 2, container.position.y - container.height / 2);

// Párosítás: beszúrás a tömb elejére, kulcs átnevezése, érték változása – a meglévő dobozok azonosítója, kézi színe marad.
const previous = nodes;
const anna = find(previous, node => node.name === "Anna"), annaKor = previous.find(node => node.parent === anna.id && node.name === "kor");
const aktiv = byName(previous, "aktiv"), tipus = byName(previous, "tipus"), cimkeB = previous.find(node => node.text === "b");
aktiv.fill = "#ff0000"; aktiv.alignment = "left"; aktiv.fontSize = 18;
const changed = {...sample, aktiv: false, tipus: "String", csapat: [{name: "Cecil", kor: 22}, ...sample.csapat], cimkek: ["c", "a", "b"]};
delete changed.name; changed.nev = "teszt";
({result, nodes} = generate(changed, previous));
assert.equal(find(nodes, node => node.name === "Anna").id, anna.id);
assert.equal(nodes.find(node => node.parent === anna.id && node.name === "kor").id, annaKor.id);
assert.equal(find(nodes, node => node.text === "b").id, cimkeB.id);
const aktivNow = byName(nodes, "aktiv");
assert.deepEqual([aktivNow.id, aktivNow.text, aktivNow.fill, aktivNow.alignment, aktivNow.fontSize], [aktiv.id, "false", "#ff0000", "left", 18]);
assert.equal(byName(nodes, "tipus").id, tipus.id);
assert.equal(byName(nodes, "tipus").fill, defaultTypeColors.String, "az automatikus típusszín követi az értéket");
assert.equal(byName(nodes, "nev").id, byName(previous, "name").id, "átnevezett kulcs: a maradék dobozzal párosodik");
assert.ok(find(nodes, node => node.name === "Cecil") && !previous.some(node => node.id === find(nodes, n => n.name === "Cecil").id));
assert.deepEqual(result.removed, []);
assert.deepEqual(boxesValue(nodes, container.id), changed);
// Törlés: a megszűnő elem azonosítója a `removed` listában.
({result, nodes} = generate({...changed, csapat: [changed.csapat[0]]}, nodes));
assert.ok(result.removed.includes(anna.id) && result.removed.includes(annaKor.id));

// Visszafelé: a dobozok szerkesztése a JSON-ban.
({nodes} = generate(sample));
byName(nodes, "kor").text = "4";
byName(nodes, "name").text = "\"5\"";
nodes.push({id: "uj", type: "box", parent: container.id, name: "uj", text: "kézzel *írt*"});
nodes.push({id: "kep", type: "image", parent: container.id, text: ""});
nodes.push({id: "lista-uj", type: "box", parent: byName(nodes, "cimkek").id, text: "null"});
assert.deepEqual(boxesValue(nodes, container.id), {...sample, kor: 4, name: "5", uj: "kézzel *írt*", cimkek: ["a", "b", null]});
// Azonos nevek objektumban: a második egyedi kulcsot kap (nem vész el).
nodes.push({id: "dupla", type: "box", parent: container.id, name: "kor", text: "9"});
assert.equal(boxesValue(nodes, container.id)["kor (2)"], 9);
// Jelző nélküli (kézzel épített) konténer: egyedi nevek → objektum, egyébként tömb.
assert.equal(inferList([{name: "a"}, {name: "b"}]), false);
assert.equal(inferList([{name: "a"}, {}]), true);
assert.equal(inferList([{name: "a"}, {name: "a"}]), true);
const hand = [{id: "k", type: "box"}, {id: "x", type: "box", parent: "k", name: "x", text: "1"}, {id: "y", type: "box", parent: "k", name: "y", text: "igen"}];
assert.deepEqual(boxesValue(hand, "k"), {x: 1, y: "igen"});
assert.deepEqual(boxesValue([{id: "k", type: "box"}], "k"), {});

// Egyszerű érték és üres tömb gyökérként.
({nodes} = generate("42"));
assert.deepEqual([nodes[0].list, nodes.slice(1).map(node => node.text)], [true, ["42"]]);
assert.deepEqual(boxesValue(nodes, container.id), [42]);
({nodes} = generate("[]"));
assert.deepEqual([nodes.length, nodes[0].list, boxesValue(nodes, container.id)], [1, true, []]);

// Hibák és korlátok: hibás JSON, túl hosszú vagy sortöréses kulcs, túl mély szerkezet; sok elemnél csonkolás jelzéssel.
assert.throws(() => generateBoxes("{\"a\": ", container), StructureError);
assert.throws(() => generateBoxes(JSON.stringify({["k".repeat(256)]: 1}), container), StructureError);
assert.throws(() => generateBoxes(JSON.stringify({"a\nb": 1}), container), StructureError);
let deep = 1;
for (let i = 0; i < 20; i++) deep = {level: deep};
assert.throws(() => generateBoxes(JSON.stringify(deep), container), StructureError);
const big = generateBoxes(JSON.stringify(Array.from({length: 1000}, (_, i) => ({name: "n" + i, value: i}))), container);
assert.equal(big.truncated, true);
assert.ok(big.nodes.length <= generatedLimit);
assert.ok([big.patch, ...big.nodes.map(node => node.fields)].every(node => node.width <= 4096 && node.height <= 4096));

// Ujjlenyomat: formátumtól és szövegtől függ.
assert.notEqual(textDigest("{}"), textDigest("{ }"));
assert.match(textDigest("{}"), /^[0-9a-f]{24}$/);

console.log("structure-boxes: rendben");
