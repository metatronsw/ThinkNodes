// Struktúra-konténer (Public/structure-boxes.js): fa, elrendezés, stabil azonosítók, kézi beállítások megőrzése.
// Futtatás a server/ mappából: node Tests/Editor/structure-boxes.mjs
import assert from "node:assert/strict";
import {generateBoxes, boxTree, isSchema, structureFormat, escapeMarkdown, StructureError, generatedLimit} from "../../Public/structure-boxes.js";

const container = {id: "c0ffee", position: {x: 100, y: 100}, width: 240, height: 120, text: "**adat.json**", fontSize: 16};
const byText = result => new Map(result.nodes.map(node => [node.text, node]));
const previousOf = result => new Map(result.nodes.map(node => [node.id, structuredClone(node)]));

// Formátum a fájlnévből.
assert.equal(structureFormat("adat.JSON"), "json");
assert.equal(structureFormat("adat.swift"), null);
assert.equal(structureFormat("json"), "json");
assert.equal(structureFormat(undefined), null);

// Általános JSON: objektum → konténer, egyszerű érték → doboz; a gyökér maga a konténer.
const sample = {name: "teszt", count: 3, ok: true, list: [1.5, null, "hosszú szöveg"], meta: {}};
let result = generateBoxes(JSON.stringify(sample), container);
assert.equal(result.schema, false);
assert.equal(result.nodes.length, 8);
let nodes = byText(result);
assert.ok(nodes.has("**name**\nteszt") && nodes.has("**ok**\ntrue") && nodes.has("**meta**\n{ }"));
const list = nodes.get("**list** [3]");
assert.equal(list.parent, container.id);
assert.equal(list.verticalAlignment, "top");
assert.deepEqual(result.nodes.filter(node => node.parent === list.id).map(node => node.text), ["1.5", "null", "hosszú szöveg"]);
assert.equal(nodes.get("null").italic, true);
// Minden azonosító érvényes (Model.swift validSlug), egyedi, és minden doboz generált, szülővel.
assert.ok(result.nodes.every(node => /^[0-9a-f]{32}$/.test(node.id) && /^[0-9a-f]{24}$/.test(node.generated) && node.parent));
assert.equal(new Set(result.nodes.map(node => node.id)).size, result.nodes.length);
// A szülő előbb áll, mint a gyermeke; a gyermek a szülője területén belül van.
const boxes = new Map([[container.id, {...container, ...result.patch}]]);
for (const node of result.nodes) {
  const parent = boxes.get(node.parent);
  assert.ok(parent, "a szülő előbb jön");
  assert.ok(node.position.x - node.width / 2 >= parent.position.x - parent.width / 2 - .001);
  assert.ok(node.position.x + node.width / 2 <= parent.position.x + parent.width / 2 + .001);
  assert.ok(node.position.y - node.height / 2 >= parent.position.y - parent.height / 2 - .001);
  assert.ok(node.position.y + node.height / 2 <= parent.position.y + parent.height / 2 + .001);
  assert.ok(node.width >= 64 && node.height >= 40);
  boxes.set(node.id, node);
}
// A konténer címe a gyermekek fölött elfér: a címketerület a doboz tetejétől 3% + 6 képpontra kezdődik (0,94-es arány),
// a sor 1,25 betűméret magas, a körbefuttatás térköze 8 (geometry.js labelLayout) – különben a cím a gyermekek alá csúszik.
for (const owner of [{...container, ...result.patch, fontSize: 16}, ...result.nodes]) {
  const children = result.nodes.filter(node => node.parent === owner.id);
  if (!children.length || !owner.text) continue;
  const top = owner.position.y - owner.height / 2;
  const firstChild = Math.min(...children.map(node => node.position.y - node.height / 2));
  assert.ok(firstChild - top >= owner.height * .03 + 6 + owner.fontSize * 1.25 + 8, owner.text);
}
// A konténer bal felső sarka a helyén marad.
assert.equal(result.patch.position.x - result.patch.width / 2, container.position.x - container.width / 2);
assert.equal(result.patch.position.y - result.patch.height / 2, container.position.y - container.height / 2);

// Stabil azonosítók: beszúrás és átrendezés után ugyanaz az elem ugyanazt az azonosítót kapja (a vonal megmarad).
const people = [{name: "Anna", age: 30}, {name: "Béla", age: 41}];
const first = generateBoxes(JSON.stringify({people}), container);
const second = generateBoxes(JSON.stringify({people: [{name: "Cecil", age: 22}, people[1], people[0]], extra: 1}), container);
const idOf = (res, text) => res.nodes.find(node => node.text === text)?.id;
for (const text of ["**Anna**", "**Béla**", "**age**\n30", "**people** [2]"]) assert.ok(idOf(first, text), text);
assert.equal(idOf(first, "**Anna**"), idOf(second, "**Anna**"));
assert.equal(idOf(first, "**Béla**"), idOf(second, "**Béla**"));
assert.equal(first.nodes.find(node => node.text === "**age**\n30").id, second.nodes.find(node => node.text === "**age**\n30").id);
// Azonos nevű testvérek: a sorszám a kulcs.
const twins = generateBoxes(JSON.stringify([{name: "x"}, {name: "x"}]), container);
assert.equal(new Set(twins.nodes.map(node => node.id)).size, twins.nodes.length);
// Egyszerű értékek tömbje: az érték a kulcs.
const tags = generateBoxes(JSON.stringify(["a", "b"]), container), tags2 = generateBoxes(JSON.stringify(["c", "a", "b"]), container);
assert.equal(idOf(tags, "a"), idOf(tags2, "a"));
// Más konténer: más azonosítók.
assert.notEqual(idOf(generateBoxes(JSON.stringify(["a"]), {...container, id: "other"}), "a"), idOf(tags, "a"));

// Megőrzés: változatlan elemen a kézzel állított szín és szöveg (megjegyzés) marad; változott elemen a szín marad,
// a tartalom az új.
let previous = previousOf(result);
const nameBox = [...previous.values()].find(node => node.text === "**name**\nteszt");
const countBox = [...previous.values()].find(node => node.text === "**count**\n3");
Object.assign(nameBox, {fill: "#ff0000", textColor: 5, text: "**name**\nteszt\n\n*megjegyzés*", backgroundMode: "translucent"});
Object.assign(countBox, {fill: 7, text: "**count**\n3 – kézi"});
result = generateBoxes(JSON.stringify({...sample, count: 4}), container, {previous});
nodes = new Map(result.nodes.map(node => [node.id, node]));
const name = nodes.get(nameBox.id), count = nodes.get(countBox.id);
assert.deepEqual([name.fill, name.textColor, name.backgroundMode, name.text], ["#ff0000", 5, "translucent", "**name**\nteszt\n\n*megjegyzés*"]);
assert.equal(name.generated, nameBox.generated);
assert.deepEqual([count.fill, count.text], [7, "**count**\n4"]);
assert.notEqual(count.generated, countBox.generated);
// A megőrzött, hosszabb szöveghez a doboz is nagyobb.
assert.ok(name.height > countBox.height);

// Dobozleíró séma: a gyökér a konténer (szöveg, szín), a gyermekek stílusa a forrásból.
const schema = {text: "Csapat", fill: 4, children: [
  {title: "Fejlesztés", layout: "column", children: [{text: "Anna"}, {text: "Béla", fill: "#FFCC00", shape: "ellipse"}]},
  {text: "Design", width: 200, height: 90, align: "right", fontSize: 18},
]};
assert.ok(isSchema(schema) && isSchema(schema.children) && !isSchema({text: "x", other: 1}) && !isSchema({text: 5}));
result = generateBoxes(JSON.stringify(schema), container);
assert.equal(result.schema, true);
assert.deepEqual([result.patch.text, result.patch.fill], ["Csapat", 4]);
nodes = byText(result);
assert.deepEqual([nodes.get("Béla").fill, nodes.get("Béla").shape], ["#ffcc00", "ellipse"]);
assert.equal(nodes.get("Fejlesztés").bold, true);
assert.equal(nodes.get("Anna").width, nodes.get("Béla").width, "oszlopban egyforma szélesség");
assert.deepEqual([nodes.get("Design").width, nodes.get("Design").height, nodes.get("Design").alignment, nodes.get("Design").fontSize], [200, 90, "right", 18]);
// Sémában a forrásban megadott szín változáskor a forrásé, a kézi szín csak ott marad, ahol a forrás nem ad színt.
previous = previousOf(result);
for (const node of previous.values()) node.fill = 9;
const changed = structuredClone(schema);
changed.children[0].children[1].fill = "#00aa00";
result = generateBoxes(JSON.stringify(changed), container, {previous});
nodes = byText(result);
assert.deepEqual([nodes.get("Béla").fill, nodes.get("Anna").fill, nodes.get("Design").fill], ["#00aa00", 9, 9]);

// Hibás forrás: StructureError, hogy a szerkesztő a meglévő dobozokat megtartsa.
assert.throws(() => generateBoxes("{\"a\": ", container), StructureError);
assert.throws(() => boxTree("[]", "yaml"), StructureError);
// Egyszerű érték és üres tömb gyökérként.
assert.deepEqual(generateBoxes("42", container).nodes.map(node => node.text), ["42"]);
assert.deepEqual(generateBoxes("[]", container).nodes.map(node => node.text), ["[ ]"]);

// Korlátok: legfeljebb generatedLimit + 1 doboz (a „… további” jelzéssel), és a méretek a modell határain belül.
const big = generateBoxes(JSON.stringify(Array.from({length: 1000}, (_, i) => ({name: "n" + i, value: i}))), container);
assert.equal(big.truncated, true);
assert.ok(big.nodes.length <= generatedLimit + 1);
assert.ok(big.nodes.at(-1).text.startsWith("… további"));
assert.ok([big.patch, ...big.nodes].every(node => node.width <= 4096 && node.height <= 4096));
let deep = 1;
for (let i = 0; i < 20; i++) deep = {level: deep};
assert.ok(generateBoxes(JSON.stringify(deep), container).nodes.some(node => node.text.includes("túl mély")));

// A forrás szövegében a markdown-jelek semlegesek.
assert.equal(escapeMarkdown("*a* _b_ [c](d) # e"), "\\*a\\* \\_b\\_ \\[c\\](d) \\# e");
assert.equal(escapeMarkdown("- lista\n1. elem"), "\\- lista\n1\\. elem");
assert.equal(byText(generateBoxes(JSON.stringify({"a*b": "x_y"}), container)).has("**a\\*b**\nx\\_y"), true);

console.log("structure-boxes: rendben");
