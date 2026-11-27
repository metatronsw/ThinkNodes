// Struktúra-konténer (Public/structure-boxes.js): értékek, típusszavak, generálás, párosítás, visszafelé alakítás.
// Futtatás a server/ mappából: node Tests/Editor/structure-boxes.mjs
import assert from "node:assert/strict";
import {generateBoxes, boxesValue, boxesSource, parseValue, formatValue, typeInfo, automaticFill, structureFormat, escapeMarkdown,
  unescapeMarkdown, StructureError, generatedLimit, defaultTypeColors, textDigest, inferList, boxTree, structureEdgeId, writable} from "../../Public/structure-boxes.js";
import {nameLayout} from "../../Public/geometry.js?v=38";

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
assert.equal(structureFormat("Modell.swift"), "swift");
assert.equal(structureFormat("adat.txt"), null);
assert.deepEqual([writable("json"), writable("swift")], [true, false]);

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

// JSON-tömb: rács közel 1:1 arányban, balról jobbra, majd soronként lefelé (mint az írott szöveg).
{
  const grid = generateBoxes(JSON.stringify(Array.from({length: 100}, (_, i) => i)), container);
  assert.ok(grid.patch.width / grid.patch.height > .7 && grid.patch.width / grid.patch.height < 1.4, "közel négyzetes: " + grid.patch.width + " × " + grid.patch.height);
  const items = apply(grid, container).slice(1), top = node => node.position.y - node.height / 2;
  for (let i = 1; i < items.length; i++) {
    const a = items[i - 1], b = items[i];
    assert.ok((top(b) === top(a) && b.position.x > a.position.x) || (top(b) > top(a) && b.position.x < a.position.x), "soronként balról jobbra " + i);
  }
  const tags = apply(generateBoxes(JSON.stringify([{name: "Anna", kor: 1}, {name: "Béla", kor: 2}, {name: "Cecil", kor: 3}, {name: "Dóra", kor: 4}]), container), container);
  const order = tags.filter(node => node.parent === container.id).map(node => [node.name, top(node), node.position.x]);
  assert.ok(order[0][1] === order[1][1] && order[0][2] < order[1][2], "az első két elem egy sorban, balról jobbra");
}
// Átméretezés (`layoutWidth`): a konténer a megadott szélességhez igazítja az oszlopok számát; a doboz szélessége marad.
{
  const value = Object.fromEntries(Array.from({length: 12}, (_, i) => ["mezo" + i, "érték " + i]));
  const columnsOf = nodes => new Set(nodes.map(node => node.position.x - node.width / 2)).size;
  const auto = apply(generateBoxes(JSON.stringify(value), container), container);
  assert.equal(columnsOf(auto.slice(1)), 1, "alapból egy oszlop");
  const wide = {...container, layoutWidth: 700};
  const r = generateBoxes(JSON.stringify(value), wide), fitted = apply(r, wide);
  assert.ok(columnsOf(fitted.slice(1)) > 1, "szélesebb konténerben több oszlop");
  assert.equal(r.patch.width, 700, "a megadott szélesség marad");
  assert.ok(fitted.slice(1).every(node => node.position.x + node.width / 2 <= r.patch.position.x + 350 + .001), "a tartalom elfér");
  // A sorrend oszloponként fentről lefelé, majd a következő oszlop.
  const lefts = fitted.slice(1).map(node => node.position.x - node.width / 2);
  assert.ok(lefts.every((left, i) => i === 0 || left >= lefts[i - 1]), "oszlopfolytonos sorrend");
  // Túl keskeny: egy oszlop, a konténer a tartalomhoz nő.
  const narrow = generateBoxes(JSON.stringify(value), {...container, layoutWidth: 70});
  assert.ok(narrow.patch.width > 70);
  // Tömb: annyi oszlop, amennyi elfér.
  const arr = generateBoxes(JSON.stringify(Array.from({length: 20}, (_, i) => i)), {...container, layoutWidth: 400});
  assert.ok(arr.nodes.every(node => node.fields.position.x + node.fields.width / 2 <= arr.patch.position.x + arr.patch.width / 2 + .001));
  assert.ok(arr.patch.width <= 400 + .001);
  // Nagyobbra húzva: a magasság sem vágódik vissza.
  const tall = generateBoxes(JSON.stringify(value), {...container, layoutWidth: 700, layoutHeight: 900});
  assert.deepEqual([tall.patch.width, tall.patch.height], [700, 900]);
  // Egyetlen belső tömb ({"tagok": [...]}): a külső átméretezése a belsőt is újrarendezi (kitölti a külsőt).
  const wrapped = JSON.stringify({tagok: Array.from({length: 24}, (_, i) => "elem " + i)});
  const narrowWrap = apply(generateBoxes(wrapped, {...container, layoutWidth: 300}), container);
  const wideWrap = apply(generateBoxes(wrapped, {...container, layoutWidth: 1200, layoutHeight: 800}), container);
  const columnCount = all => new Set(all.filter(node => node.parent === byName(all, "tagok").id).map(node => node.position.x)).size;
  assert.ok(columnCount(wideWrap) > columnCount(narrowWrap), "szélesebb külső: több oszlop a belső tömbben");
  assert.ok(byName(wideWrap, "tagok").width >= 1200 - 2 * 14 - .001 && byName(wideWrap, "tagok").height > 600, "a belső kitölti a külsőt");
  // Kézzel átméretezett doboz: a szélessége marad.
  const previous = auto.slice(1).map(node => ({...node}));
  previous.find(node => node.name === "mezo3").layoutWidth = 280;
  const again = apply(generateBoxes(JSON.stringify(value), auto[0], {previous}), auto[0], previous);
  assert.equal(byName(again, "mezo3").width, 280);
}
// JSON-számok és logikai értékek: típusjel (Int / Double / Bool) és típusszín; a forrásbeli számalak marad (39.10, nagy egész).
{
  const typed = '{"key": 32, "decimal": 39.12, "tizedes": 39.10, "nagy": 12345678901234567890, "exp": 1e3, "flag": true, "szoveg": "32", "lista": [1, 2.5, false]}';
  const r = generateBoxes(typed, container), all = apply(r, container);
  const note = name => byName(all, name);
  assert.deepEqual(["key", "decimal", "tizedes", "nagy", "exp", "flag"].map(name => [note(name).nameNote, note(name).text]),
    [["Int", "32"], ["Double", "39.12"], ["Double", "39.10"], ["Int", "12345678901234567890"], ["Double", "1e3"], ["Bool", "true"]]);
  assert.deepEqual([note("key").fill, note("decimal").fill, note("flag").fill], [defaultTypeColors.Int, defaultTypeColors.Double, defaultTypeColors.Bool]);
  assert.deepEqual([note("szoveg").nameNote, note("szoveg").text, note("szoveg").fill], [undefined, "\"32\"", 2], "idézőjeles szám: szöveg, jel nélkül");
  assert.deepEqual(all.filter(node => node.parent === note("lista").id).map(node => node.nameNote), ["Int", "Double", "Bool"]);
  // Visszaírás: a számok az eredeti alakjukkal (39.10, a nagy egész pontosan).
  const written = boxesSource(all, container.id);
  assert.ok(written.includes('"tizedes": 39.10') && written.includes('"nagy": 12345678901234567890') && written.includes('"exp": 1e3'));
  // Értékváltozás: a típusjel és az automatikus szín követi (szám → szöveg), a kézi szín marad.
  note("decimal").fill = "#123456";
  const again = apply(generateBoxes(typed.replace('"key": 32', '"key": "harminckettő"').replace("39.12", "40"), all[0], {previous: all.slice(1)}), all[0], all.slice(1));
  assert.deepEqual([byName(again, "key").nameNote, byName(again, "key").fill], [undefined, 2]);
  assert.deepEqual([byName(again, "decimal").nameNote, byName(again, "decimal").fill], ["Int", "#123456"]);
}
// Swift-változatok is típusszavak.
for (const word of ["Int8", "UInt64", "Float16", "Float80", "CGFloat", "Decimal", "Character", "[UInt8]", "Int32?"]) assert.ok(typeInfo(word), word);
assert.equal(automaticFill("UInt8", true), defaultTypeColors.Int);
assert.equal(automaticFill("Float64", true), defaultTypeColors.Double);

// ---- Swift-forrás (csak olvasás) ----
const swift = `import Foundation
/// Felhasználó (a dokumentációs komment nem számít)
struct User: Codable, Equatable {
    let id: UUID
    var nev: String = "Anna \\(1 + 2) { // nem komment"
    var vezeteknev = "Kiss"
    @Published private(set) var kor: Int = 30 // életkor
    var lakcim: Cim?
    static let alap = User()
    lazy var gyorsitotar: [String: Int] = [:]
    var teljesNev: String { "\\(nev) \\(vezeteknev)" }
    var nagykoru: Bool {
        get { return kor >= 18 }
        set { kor = newValue ? 18 : 0 }
    }
    var cimke: String {
        let x = nev.uppercased()
        return x + "!" + other.nev
    }
    var szamlalo = 0 { didSet { print(oldValue) } }
    func koszon() -> String { let belso = 5; return "Szia \\(nev)" }
    struct Cim { var varos: String; var irsz: Int? ; let arany = 1.5 }
    init() { id = UUID() }
}
/* struct Rejtett { let a: Int } */
struct Doboz<T>: Hashable where T: Hashable {
    var ertek: T
    var cimek: [User.Cim] = []
    var tomb: [String: [Int]]
    let raw = #"nyers "idézőjel" \\(nem interpoláció)"#
    let tobbsoros = """
        első sor { 
        második sor
        """
}
extension User { struct Bovitett { let x: Double } }
`;
const tree = boxTree(swift, "swift").root;
// Két felső szintű struct (User, Doboz): a konténerben egymás mellett; a beágyazott (Cim) és a bővítményben megadott
// (Bovitett) struct a User konténerében.
assert.deepEqual(tree.children.map(item => item.name), ["User", "Doboz<T>"]);
const user = tree.children[0];
assert.equal(user.text, "*Codable, Equatable*");
const prop = name => user.children.find(item => item.name === name);
assert.deepEqual(user.children.map(item => item.name), ["id", "nev", "vezeteknev", "kor", "lakcim", "gyorsitotar", "teljesNev", "nagykoru", "cimke",
  "szamlalo", "koszon", "Cim", "Bovitett"]);
assert.deepEqual([prop("id").note, prop("id").text], ["let", "UUID"]);
assert.equal(prop("vezeteknev").text, "String = \"Kiss\"", "a típus a literálból");
assert.equal(prop("kor").text, "Int = 30");
assert.equal(prop("szamlalo").text, "Int = 0", "a didSet nem része az alapértéknek");
assert.deepEqual([prop("teljesNev").note, prop("teljesNev").computed, prop("teljesNev").shape, prop("teljesNev").deps], ["ƒ", true, undefined, ["nev", "vezeteknev"]]);
assert.deepEqual([prop("nagykoru").text, prop("nagykoru").deps], ["Bool = kor >= 18", ["kor"]]);
assert.deepEqual(prop("cimke").deps, ["nev"], "más objektum azonos nevű tagja (other.nev) nem függőség, a saját nev igen");
assert.ok(prop("cimke").text.includes("\n"), "több utasítás: soronként");
assert.deepEqual(prop("lakcim").refs, ["User.Cim"]);
// Függvény: „func” jel, az aláírás a szövege; a törzsben használt tagok a függőségei.
assert.deepEqual([prop("koszon").note, prop("koszon").shape, prop("koszon").computed, prop("koszon").text, prop("koszon").deps], ["func", undefined, true, "() -> String", ["nev"]]);
const cim = prop("Cim");
assert.deepEqual(cim.children.map(item => [item.name, item.text]), [["varos", "String"], ["irsz", "Int?"], ["arany", "Double = 1.5"]]);
assert.equal(prop("Bovitett").children[0].text, "Double");
const doboz = tree.children[1];
assert.equal(doboz.text, "*Hashable*");
assert.deepEqual(doboz.children.find(item => item.name === "cimek").refs, ["User.Cim"]);
assert.ok(doboz.children.find(item => item.name === "tobbsoros").text.startsWith("String = "));
// Egyetlen felső szintű struct: maga a konténer az (név, protokollok).
{
  const single = generateBoxes("struct Pont: Equatable {\n  var x: Double = 0\n  var y: Double = 0\n  var hossz: Double { (x * x + y * y).squareRoot() }\n}", container, {format: "swift"});
  assert.deepEqual([single.patch.name, single.patch.text], ["Pont", "*Equatable*"]);
  const all = apply(single, container);
  assert.deepEqual(all.filter(node => node.parent === container.id).map(node => node.name), ["x", "y", "hossz"]);
  assert.equal(byName(all, "hossz").shape, "rounded");
  // A nyíl a használt tagtól a számított tulajdonság felé mutat.
  assert.ok(single.edges.some(edge => edge.source === byName(all, "x").id && edge.target === byName(all, "hossz").id));
}
// Generálás: a jelek, a rombusz, a szaggatott keret és a kezelt vonalak.
({result, nodes} = (() => { const r = generateBoxes(swift, container, {format: "swift"}); return {result: r, nodes: apply(r, container)}; })());
const inUser = name => nodes.find(node => node.name === name && node.parent === byName(nodes, "User").id);
const teljes = inUser("teljesNev"), nev = inUser("nev");
assert.deepEqual([teljes.nameNote, teljes.computed, teljes.shape, inUser("kor").nameNote, inUser("kor").shape], ["ƒ", true, "rounded", "var", "rounded"]);
// Elrendezés: a tárolt tagok (és a beágyazott struct) bal oldalt egymás alatt, a forrás sorrendjében; a számított
// tagok és a függvények jobb oldalt, a használt tag magasságában (a nevük teteje egy vonalban), egymást nem fedve.
const nameTop = node => node.position.y - node.height / 2 - (nameLayout(node)?.height ?? 0);
for (const parent of nodes) {
  const children = nodes.filter(node => node.parent === parent.id);
  const side = children.filter(node => node.nameNote === "ƒ" || node.nameNote === "func"), main = children.filter(node => !side.includes(node));
  for (let i = 1; i < main.length; i++) {
    assert.ok(main[i - 1].position.y + main[i - 1].height / 2 <= nameTop(main[i]) + .001, main[i - 1].name + " fölött " + main[i].name);
    assert.equal(main[i - 1].position.x - main[i - 1].width / 2, main[i].position.x - main[i].width / 2, "egy oszlopban: " + main[i].name);
  }
  const right = Math.max(...main.map(node => node.position.x + node.width / 2));
  for (let i = 0; i < side.length; i++) {
    assert.ok(side[i].position.x - side[i].width / 2 > right, "jobb oldalt: " + side[i].name);
    if (i) assert.ok(side[i - 1].position.y + side[i - 1].height / 2 <= nameTop(side[i]) + .001, "nem fedik egymást: " + side[i].name);
  }
}
assert.equal(nameTop(teljes), nameTop(inUser("nev")), "a teljesNev a nev magasságában");
// A köztes változat rombusza (automatikus) dobozzá válik; a kézzel állított más alak marad.
{
  const old = nodes.map(node => ({...node}));
  old.find(node => node.id === teljes.id).shape = "diamond";
  old.find(node => node.id === inUser("nev").id).shape = "hexagon";
  const fixed = apply(generateBoxes(swift, old[0], {format: "swift", previous: old.slice(1)}), old[0], old.slice(1));
  assert.deepEqual([fixed.find(node => node.id === teljes.id).shape, fixed.find(node => node.id === inUser("nev").id).shape], ["rounded", "hexagon"]);
}
assert.equal(inUser("kor").fill, defaultTypeColors.Int, "típusszín a „Típus = érték” szövegből");
assert.equal(byName(nodes, "User").list, undefined, "Swift-konténeren nincs {} jel");
assert.equal(byName(nodes, "Cim").parent, byName(nodes, "User").id, "a beágyazott struct a szülőjében");
assert.ok(result.edges.some(edge => edge.source === nev.id && edge.target === teljes.id), "használt tag → számított");
assert.ok(result.edges.some(edge => edge.source === nev.id && edge.target === inUser("koszon").id), "használt tag → függvény");
assert.ok(result.edges.some(edge => edge.source === inUser("lakcim").id && edge.target === byName(nodes, "Cim").id), "tulajdonság → struct");
assert.ok(result.edges.every(edge => edge.id === structureEdgeId(container.id, edge.source, edge.target)));
assert.throws(() => boxesSource(nodes, container.id, {format: "swift"}), StructureError);
// Üres érték (nil): alapérték nélküli opcionális var és `= nil`: csak keret, dőlt.
assert.deepEqual([inUser("lakcim").backgroundMode, inUser("lakcim").italic], ["empty", true]);
assert.deepEqual([inUser("kor").backgroundMode, inUser("kor").italic], [undefined, undefined]);
// Újragenerálás változott forrásból: a megmaradó tulajdonság azonosítója marad, a megszűnt függőség vonala eltűnik;
// a kézzel állított alak marad.
inUser("kor").shape = "ellipse";
const swift2 = swift.replace('var teljesNev: String { "\\(nev) \\(vezeteknev)" }', "var teljesNev: String { nev }").replace("var kor: Int = 30", "var kor: Int? = nil");
const second = generateBoxes(swift2, nodes[0], {format: "swift", previous: nodes.slice(1)});
const after = apply(second, nodes[0], nodes.slice(1));
assert.equal(second.nodes.find(node => node.fields.name === "teljesNev").id, teljes.id);
assert.ok(!second.edges.some(edge => edge.source === inUser("vezeteknev").id && edge.target === teljes.id));
const korAfter = after.find(node => node.id === inUser("kor").id);
assert.deepEqual([korAfter.shape, korAfter.backgroundMode, korAfter.italic, korAfter.text], ["ellipse", "empty", true, "Int? = nil"]);
assert.deepEqual(second.removed, []);
// JSON null: csak keret, dőlt; a null-ból szöveg lesz: vissza.
{
  const first = apply(generateBoxes('{"a": null, "b": 1}', container), container);
  assert.deepEqual([byName(first, "a").backgroundMode, byName(first, "a").italic, byName(first, "b").backgroundMode], ["empty", true, undefined]);
  const next = apply(generateBoxes('{"a": "szöveg", "b": null}', first[0], {previous: first.slice(1)}), first[0], first.slice(1));
  assert.deepEqual([byName(next, "a").backgroundMode, byName(next, "a").italic, byName(next, "b").backgroundMode], [undefined, undefined, "empty"]);
}

console.log("structure-boxes: rendben");
