// Struktúra-konténer (docs/node-types.md, „Struktúra-konténer”): a vonallal bekötött forrásfájl (ma .json, később
// Swift struct) és a konténer dobozai kétirányúan összekötve. A modul tiszta (DOM nélkül), a szerkesztő (editor.js)
// hívja; tesztje: Tests/Editor/structure-boxes.mjs.
//
// Leképezés (mindkét irányban ugyanaz):
// - doboz: név (`name`) = kulcs, szöveg (`text`) = érték;
// - konténer: `list: false` = objektum (a gyermekek neve a kulcs), `list: true` = tömb (a gyermekek neve csak felirat);
// - érték: `3` szám, `true` / `false`, `null`, idézőjelben ("3") mindig szöveg, minden más szöveg. A szöveg markdown-jelei
//   generáláskor semlegesítve (visszaper), visszafelé a visszaperek lekerülnek.
// - sorrend: a gyermekek tárolt sorrendje (a lap dobozlistájában).
// Típusszavak (Int, Float, Double, Bool, String, Date, URL, UUID; T?, [T], [K: V]) értékként: a doboz az alaptípus
// színét kapja (`typeColors`, Public/structure-types.json). A szín nem kerül a JSON-ba.
//
// Párosítás: újrageneráláskor a meglévő dobozok a szülőjük és a kulcsuk szerint (objektumban a név, tömbben az elem
// neve / egyszerű értéke, ha egyedi, egyébként a helye) kapják meg az új tartalmat; a megmaradó doboz azonosítója,
// vonalai, kézzel állított színe és betűbeállításai nem változnak. Új doboz azonosítója a konténerből és az útvonalból
// képzett hash. A helyet és a méretet mindig az elrendezés adja.

import {nameLayout, textWidth} from "./geometry.js?v=38";

export const generatedLimit = 600;
export const depthLimit = 12;
export const nameLimit = 255;
export const textLimit = 100_000;
const sizeLimits = {width: [64, 4096], height: [40, 4096]};

// Térközök: a konténer belső margója, a dobozok közti rés; betűméret és sormagasság (geometry.js labelLayout: 1,25).
const pad = 14, gap = 12, leafFontSize = 14;
// Alapszínek (a téma palettájának sorszámai, minden témában megvannak): konténer = papír (0), doboz = felület (2),
// szöveg = tinta (1).
export const containerFill = 0, leafFill = 2, ink = 1;
// Típusszínek (alapértelmezés; a szerkesztő a Public/structure-types.json-ból tölti): a 0–15 sorszámok minden témában
// megvannak, a szöveg kontrasztját a rajzolás javítja.
export const defaultTypeColors = {
  String: 5, Character: 5, Substring: 5,
  Int: 4, Int8: 4, Int16: 4, Int32: 4, Int64: 4, UInt: 4, UInt8: 4, UInt16: 4, UInt32: 4, UInt64: 4,
  Float: 12, Float16: 12, Float32: 12, Float80: 12,
  Double: 15, Float64: 15, CGFloat: 15, Decimal: 15,
  Bool: 6, Date: 14, URL: 11, UUID: 13,
};
const baseTypes = new Set(Object.keys(defaultTypeColors));

export class StructureError extends Error {}
// Szám a forrásbeli alakjával (a JSON-ban 39.10 és 39.1 ugyanaz az érték, de a doboz és a visszaírt fájl az eredetit mutatja).
class RawNumber {
  constructor(value, raw) { this.value = value; this.raw = typeof raw === "string" && numberPattern.test(raw) ? raw : String(value); }
}

// Forrásformátumok: fájlkiterjesztés → elemző (szöveg → érték) és író (érték → szöveg). Swift struct: későbbi bővítés.
export const formats = {
  json: {
    // A számok a forrásbeli alakjukkal (RawNumber: pl. 39.10, 1e3; a böngésző JSON.parse forrásszöveg-hozzáférésével,
    // ahol nincs, a számból).
    parse: source => {
      try { return JSON.parse(source, (key, value, context) => typeof value === "number" ? new RawNumber(value, context?.source) : value); }
      catch (error) { throw new StructureError("Hibás JSON: " + error.message); }
    },
    // A forrás behúzását követi (szóköz vagy tabulátor, alapból 2 szóköz); a számok a doboz szövegének alakjával.
    write: (value, previous = "") => {
      const raw = [];
      const text = JSON.stringify(value, (key, item) => item instanceof RawNumber ? "\u0000" + (raw.push(item.raw) - 1) + "\u0000" : item,
        (/\n([ \t]+)\S/.exec(previous)?.[1]) ?? 2);
      return text.replace(/"\\u0000(\d+)\\u0000"/g, (match, index) => raw[index]) + "\n";
    },
  },
  // Swift: csak olvasás (a dobozok szerkesztése nem írja át a kódot); a fa közvetlenül a forrásból (swiftTree, lent).
  swift: {tree: source => swiftTree(source)},
};
export const structureExtensions = Object.keys(formats);
export function structureFormat(filename) {
  const extension = String(filename ?? "").split(".").at(-1).toLowerCase();
  return Object.hasOwn(formats, extension) ? extension : null;
}

// 4 × 32 bites FNV-szerű hash, sávonként más szorzóval és végső keveréssel (murmur3 fmix32): 32 hexa jegy
// (Model.swift validSlug: kisbetű, szám, kötőjel).
function hash128(text) {
  let out = "";
  for (const [seed, prime] of [[0x811c9dc5, 0x01000193], [0x9e3779b9, 0x5bd1e995], [0x85ebca6b, 0xcc9e2d51], [0xc2b2ae35, 0x1b873593]]) {
    let h = seed >>> 0;
    for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), prime) >>> 0;
    h ^= h >>> 16; h = Math.imul(h, 0x85ebca6b); h ^= h >>> 13; h = Math.imul(h, 0xc2b2ae35); h ^= h >>> 16;
    out += (h >>> 0).toString(16).padStart(8, "0");
  }
  return out;
}
export const generatedId = (containerId, path) => hash128(containerId + "\u0000" + path);
// A szerkezetből adódó (kezelt) vonal azonosítója: konténer + két végpont.
export const structureEdgeId = (containerId, source, target) => hash128(containerId + "\u0000edge\u0000" + source + "\u0000" + target);
// Szöveg ujjlenyomata (a forrásé és a dobozokból írt JSON-é): ha nem változott, nincs szinkron.
export const textDigest = (text, format = "json") => hash128("structure:10\u0000" + format + "\u0000" + text).slice(0, 24);

// ---- Értékek ------------------------------------------------------------------------------------------------------

// Markdown-jelek semlegesítése (CommonMark visszaper): ami a doboz szövegében formázásként hatna.
export function escapeMarkdown(text) {
  const link = /\]\s*[([:]/.test(text);
  return String(text).split("\n").map(line => {
    let out = line.replace(link ? /[\\`*_<&[\]]/g : /[\\`*_<&]/g, "\\$&");
    out = out.replace(/^(\s*)([#+-])(?=\s|$)/, "$1\\$2").replace(/^(\s*)>/, "$1\\>").replace(/^(\s*\d+)([.)])(?=\s|$)/, "$1\\$2");
    if (/^\s*=+\s*$/.test(out)) out = out.replace("=", "\\=");
    return out;
  }).join("\n");
}
export const unescapeMarkdown = text => String(text).replace(/\\([!-/:-@[-`{-~])/g, "$1");

const numberPattern = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$/;
// A szöveg JSON-literálnak olvasódna-e (szám, true, false, null, idézőjeles szöveg).
const literal = text => numberPattern.test(text) || text === "true" || text === "false" || text === "null" || /^".*"$/s.test(text);

// Érték → a doboz szövege.
export function formatValue(value) {
  if (value === null) return "null";
  if (typeof value === "string") return literal(value.trim()) || value !== value.trim() ? JSON.stringify(value) : escapeMarkdown(value);
  return String(value);
}
// A doboz szövege → érték (a formatValue fordítottja).
export function parseValue(text) {
  const trimmed = String(text ?? "").trim();
  if (numberPattern.test(trimmed)) { const number = Number(trimmed); if (Number.isFinite(number)) return number; }
  if (trimmed === "true") return true;
  if (trimmed === "false") return false;
  if (trimmed === "null") return null;
  if (/^".*"$/s.test(trimmed)) { try { return JSON.parse(trimmed); } catch {} }
  return unescapeMarkdown(trimmed);
}

// Típusszó: alaptípus, ?-es opcionális, [T] tömb, [K: V] szótár. Eredmény: {base, collection, optional} vagy null.
// `known`: az alaptípusok (alapból a beépítettek; a szerkesztő a structure-types.json típusait is átadja).
export function typeInfo(text, known = baseTypes) {
  const value = unescapeMarkdown(String(text ?? "")).trim();
  if (!value || value.length > 80) return null;
  function parse(source) {
    let s = source.trim(), optional = false;
    while (s.endsWith("?")) { optional = true; s = s.slice(0, -1).trim(); }
    if (s.startsWith("[") && s.endsWith("]")) {
      const inner = s.slice(1, -1);
      let depth = 0, colon = -1;
      for (let i = 0; i < inner.length && colon < 0; i++) {
        if (inner[i] === "[") depth++;
        else if (inner[i] === "]") depth--;
        else if (inner[i] === ":" && depth === 0) colon = i;
      }
      if (colon >= 0) {
        const key = parse(inner.slice(0, colon)), item = parse(inner.slice(colon + 1));
        return key && item ? {base: item.base, collection: "dictionary", optional} : null;
      }
      const item = parse(inner);
      return item ? {base: item.base, collection: "array", optional} : null;
    }
    return known.has(s) ? {base: s, collection: null, optional} : null;
  }
  return parse(value);
}

// A doboz automatikus kitöltése: típusszónál a típus színe, egyébként doboz / konténer alapszín.
const knownTypes = new WeakMap();
export function automaticFill(text, leaf, typeColors = defaultTypeColors, note = null) {
  if (!leaf) return containerFill;
  if (!knownTypes.has(typeColors)) knownTypes.set(typeColors, new Set(Object.keys(typeColors)));
  const known = knownTypes.get(typeColors);
  // A típusjel (JSON-szám, -logikai érték: „Int”, „Double”, „Bool”) elsőbbséget kap.
  const marked = note ? typeInfo(note, known) : null;
  if (marked && typeColors[marked.base] != null) return typeColors[marked.base];
  // „Típus = érték / képlet” alakban (Swift-forrás) a típus az első sor „ = ” előtti része.
  const type = typeInfo(String(text ?? "").split("\n")[0].split(" = ")[0], known);
  return type && typeColors[type.base] != null ? typeColors[type.base] : leafFill;
}

// ---- Fa a forrásból -----------------------------------------------------------------------------------------------
// Elem: {key, name, text, list, children?}. A `key` a párosítás kulcsa (testvérek közt egyedi).

const isPlainObject = value => value != null && typeof value === "object" && !Array.isArray(value) && !(value instanceof RawNumber);
const isComposite = value => Array.isArray(value) || isPlainObject(value);
const plainValue = value => value instanceof RawNumber ? value.value : value;
const titleKeys = ["name", "title", "label", "id", "key", "név", "nev", "cím", "cim"];
function itemTitle(value) {
  if (!isPlainObject(value)) return null;
  for (const key of titleKeys) {
    const field = value[key];
    if (typeof field === "string") return field;
    if (field instanceof RawNumber) return field.raw;
  }
  return null;
}
// Testvérkulcsok: a jelölt kulcs, ha egyedi, egyébként a sorszám.
function siblingKeys(candidates) {
  const seen = new Map();
  for (const key of candidates) if (key != null) seen.set(key, (seen.get(key) ?? 0) + 1);
  return candidates.map((key, i) => key != null && seen.get(key) === 1 ? key : "#" + i);
}
function checkName(name) {
  if (name.length > nameLimit) throw new StructureError("Túl hosszú kulcs (legfeljebb " + nameLimit + " karakter): " + name.slice(0, 40) + "…");
  if (/[\r\n]/.test(name)) throw new StructureError("Sortörés a kulcsban: " + JSON.stringify(name.slice(0, 40)));
  return name;
}

function valueTree(value, budget, depth) {
  budget.count++;
  if (depth > depthLimit) throw new StructureError("Túl mély szerkezet (legfeljebb " + depthLimit + " szint).");
  if (Array.isArray(value) || isPlainObject(value)) {
    const list = Array.isArray(value);
    const entries = list ? value.map((item, i) => [i, item]) : Object.entries(value);
    const keys = list
      ? siblingKeys(value.map(item => isComposite(item) ? (itemTitle(item) == null ? null : "=" + itemTitle(item)) : "=" + JSON.stringify(plainValue(item))))
      : entries.map(([name]) => "." + name);
    const children = [];
    for (let i = 0; i < entries.length; i++) {
      if (budget.count >= generatedLimit) { budget.truncated = true; break; }
      const [name, item] = entries[i];
      const child = valueTree(item, budget, depth + 1);
      child.key = keys[i];
      child.name = list ? (isComposite(item) ? itemTitle(item) ?? undefined : undefined) : checkName(name);
      if (child.name != null && child.name.length > nameLimit) child.name = child.name.slice(0, nameLimit);
      if (child.name != null && /[\r\n]/.test(child.name)) child.name = child.name.replace(/[\r\n]+/g, " ");
      children.push(child);
    }
    return {text: "", list, children};
  }
  // Nem szöveg érték: a típusa halvány jelként a név előtt és típusszínként (szám: Int vagy Double az alakja szerint).
  if (value instanceof RawNumber) return {text: value.raw, note: /[.eE]/.test(value.raw) ? "Double" : "Int"};
  if (typeof value === "boolean") return {text: String(value), note: "Bool"};
  const text = formatValue(value);
  if (text.length > textLimit) throw new StructureError("Túl hosszú érték (legfeljebb " + textLimit + " karakter).");
  return {text};
}

// A forrásszövegből a fa; a gyökér a konténer maga. Egyszerű érték gyökérnél a konténerben egy doboz áll.
export function boxTree(source, format = "json") {
  const handler = formats[format];
  if (!handler) throw new StructureError("Ismeretlen forrásformátum: " + format);
  if (handler.tree) {
    const root = handler.tree(source);
    let count = 0;
    (function walk(item) { for (const child of item.children ?? []) { count++; walk(child); } })(root);
    if (count > generatedLimit) throw new StructureError("Túl sok elem (legfeljebb " + generatedLimit + ").");
    return {root, count, truncated: false};
  }
  const budget = {count: 0, truncated: false};
  let root = valueTree(handler.parse(source), budget, 0);
  budget.count--;
  if (!root.children) root = {text: "", list: true, children: [{...root, key: "#0"}]};
  return {root, count: budget.count, truncated: budget.truncated};
}

// ---- Párosítás a meglévő dobozokkal -------------------------------------------------------------------------------

// A meglévő gyermek kulcsa, a forrás elemeivel azonos módon képezve.
function existingKeys(children, list, byParent) {
  if (!list) return children.map(child => "." + (child.name ?? "").trim());
  return siblingKeys(children.map(child => {
    if (child.name?.trim()) return "=" + child.name.trim();
    const leaf = child.list == null && !(byParent.get(child.id)?.length);
    return leaf ? "=" + JSON.stringify(parseValue(child.text)) : null;
  }));
}

// Az elem és a meglévő doboz összepárosítása, rekurzívan. `byParent`: szülő azonosító → meglévő gyermekek (sorrendben).
function match(item, existingId, byParent, containerId, path, used) {
  const old = byParent.get(existingId) ?? [];
  const oldKeys = existingKeys(old, item.list, byParent);
  const oldByKey = new Map(), taken = new Set();
  oldKeys.forEach((key, i) => { if (!oldByKey.has(key)) oldByKey.set(key, old[i]); });
  const pending = [];
  for (const child of item.children ?? []) {
    const found = oldByKey.get(child.key);
    if (found && !taken.has(found.id)) { child.previous = found; taken.add(found.id); }
    else pending.push(child);
  }
  // A kulcs nélkül maradtak a maradék régi dobozokkal sorrendben párosodnak (átnevezett kulcs, megváltozott érték).
  const leftovers = old.filter(node => !taken.has(node.id));
  for (const child of pending) {
    const found = leftovers.shift();
    if (found) { child.previous = found; taken.add(found.id); }
  }
  for (const child of item.children ?? []) {
    const childPath = path + "/" + child.key;
    if (child.previous) child.id = child.previous.id;
    else {
      let id = generatedId(containerId, childPath), n = 0;
      while (used.has(id)) id = generatedId(containerId, childPath + "#" + ++n);
      child.id = id;
    }
    used.add(child.id);
    match(child, child.previous?.id, byParent, containerId, childPath, used);
  }
}

// ---- Méretezés és elrendezés --------------------------------------------------------------------------------------

const lineHeight = size => size * 1.25;
function textSize(text, fontSize) {
  const lines = String(text ?? "").split("\n").map(line => unescapeMarkdown(line));
  const widths = lines.map(line => textWidth(line, fontSize));
  return {natural: Math.max(0, ...widths), widths};
}
// A név magassága a doboz fölött (geometry.js nameLayout).
// Gyorsítótár generálásonként (a rács-próbák sokszor kérdezik ugyanazt).
const nameSpaces = new Map();
function nameSpace(item, width) {
  const key = (item.name ?? "") + "\u0000" + (item.note ?? "") + "\u0000" + item.list + "\u0000" + width;
  if (!nameSpaces.has(key)) nameSpaces.set(key, nameLayout({type: "box", name: item.name, nameNote: item.note, list: item.list, width})?.height ?? 0);
  return nameSpaces.get(key);
}

function measure(item) {
  const fontSize = item.fields.fontSize ?? leafFontSize;
  if (!item.children?.length) {
    const {natural, widths} = textSize(item.text, fontSize);
    const nameWidth = item.name ? Math.min(300, textWidth((item.note ? item.note + " " : "") + item.name, 13, {bold: true}) + 12) : 0;
    // Címketerület: szélesség × arány − 16, magasság × arány − 12 (geometry.js labelLayout, labelRatios); rombusznál
    // 0,50 / 0,47, egyébként 0,94. Tördelésre 15% tartalék.
    const diamond = (item.fields.shape ?? item.previous?.shape) === "diamond";
    const [rw, rh] = diamond ? [.5, .47] : [.94, .94];
    // Kézzel átméretezett doboz (`layoutWidth`): a szélessége marad, a szöveg ahhoz tördel.
    const fixed = item.previous?.layoutWidth;
    item.width = fixed ? Math.min(sizeLimits.width[1], Math.max(sizeLimits.width[0], Math.round(fixed)))
      : diamond ? Math.min(420, Math.max(120, Math.ceil(Math.max((natural + 16) / rw, nameWidth))))
      : Math.min(300, Math.max(80, Math.ceil(Math.max(natural + 30, nameWidth))));
    const room = item.width * rw - 16;
    const rows = item.text ? widths.reduce((sum, w) => sum + Math.max(1, Math.ceil(w * 1.15 / room)), 0) : 0;
    // Kézzel nagyobbra húzott doboz (`layoutHeight`): a magassága is marad (a felesleges hely nem vész el).
    item.height = Math.min(sizeLimits.height[1], Math.max(diamond ? 64 : 40, Math.ceil((rows * lineHeight(fontSize) + 12) / rh + 6), Math.round(item.previous?.layoutHeight ?? 0)));
    item.naturalWidth = item.width;
    item.nameHeight = nameSpace(item, item.width);
    return item;
  }
  // Egyetlen belső konténer (pl. {"tagok": [...]}): a kézzel méretezett külső konténert kitölti (a saját kézi mérete
  // nélkül), így a külső átméretezése a belsőt is újrarendezi.
  const only = item.children.length === 1 && item.children[0].children?.length ? item.children[0] : null;
  if (only && !only.previous?.layoutWidth && item.target) {
    only.target = item.target - 2 * pad;
    if (item.targetHeight) only.targetHeight = item.targetHeight - (pad - 4) - pad - nameSpace(only, only.target);
  }
  for (const child of item.children) measure(child);
  // Összecsukott konténer (`collapsed`): csak a neve és egy rövid összegzés látszik; a tartalma rejtett (a rajzolás
  // kihagyja, a rá mutató vonalak a konténerhez futnak).
  if (item.collapsed) {
    item.layout = {slots: [], width: 0, height: 0};
    const {natural} = textSize(item.text, fontSize);
    item.width = Math.min(sizeLimits.width[1], Math.max(Math.ceil(natural + 30), 100, Math.round(item.target ?? 0)));
    item.header = 0;
    item.height = Math.max(40, Math.round(item.targetHeight ?? 0));
    item.nameHeight = nameSpace(item, item.width);
    return item;
  }
  item.layout = arrange(item);
  const innerWidth = Math.max(60, item.layout.width);
  // Kézzel átméretezett konténer (`target`): a szélessége marad, ha a tartalom elfér benne; ha nem, a tartalomé.
  item.width = Math.min(sizeLimits.width[1], Math.max(Math.ceil(innerWidth + 2 * pad), item.target ? Math.round(item.target) : 0));
  // A konténer saját szövege (ha van) fölül, a körbefuttatás miatt a címketerület arányával (0,94) számolva.
  const title = item.text ? textSize(item.text, fontSize).widths.reduce((sum, w) => sum + Math.max(1, Math.ceil(w * 1.15 / (item.width * .94 - 16))), 0) * lineHeight(fontSize) : 0;
  const body = item.layout.height;
  const k = .03, fixed = title ? 6 + title + 8 + 6 : pad - 4;
  item.header = title ? Math.ceil((k * (body + pad) + fixed) / (1 - k)) : fixed;
  // Kézzel nagyobbra húzott konténer: a magassága is marad (a felesleges hely nem vész el).
  item.height = Math.min(sizeLimits.height[1], Math.max(40, Math.ceil(item.header + body + pad), Math.round(item.targetHeight ?? 0)));
  item.nameHeight = nameSpace(item, item.width);
  return item;
}

// Elrendezés: a konténer elemeinek helye a konténer tartalomterületén belül ({slots: [{child, x, y}], width, height};
// y a doboz teteje, a neve fölötte). Három mód:
// - objektum / struct: egymás alatt, a forrás (kód) sorrendjében, akkor is, ha több hely van (a kézzel szélesebbre
//   húzott konténerben a fölösleg üres marad); új oszlop csak akkor, ha az oszlop túl magas lenne (a doboz legfeljebb
//   4096 képpont);
// - JSON-tömb (`list: true`): rács, balról jobbra, majd soronként lefelé (mint az írott szöveg); az oszlopok száma a
//   közel 1:1 arányhoz igazodik, kézzel méretezett konténerben a szélességhez (egyenletesen kitöltve);
// - Swift-struct számított tulajdonsággal / függvénnyel (`side`): a többi tag bal oldalt egymás alatt, ezek jobb oldalt,
//   ahol lehet, a használt tag magasságában.
// Oszloponként az egyszerű dobozok egyforma szélesek.
const columnLimit = 3600;
const slotHeight = child => child.nameHeight + child.height;
function columnsOf(groups) {
  return groups.map(items => {
    const width = Math.max(...items.map(child => child.width));
    for (const child of items) if (!child.children?.length && child.width < width) { child.width = width; child.nameHeight = nameSpace(child, width); }
    return {items, width, height: items.reduce((sum, child) => sum + slotHeight(child), 0) + gap * (items.length - 1)};
  });
}
// Oszlopok egymás mellett, oszloponként fentről lefelé.
function stack(columns) {
  const slots = [];
  let x = 0;
  for (const column of columns) {
    let y = 0;
    for (const child of column.items) { slots.push({child, x, y: y + child.nameHeight}); y += slotHeight(child) + gap; }
    x += column.width + gap;
  }
  return {slots, width: Math.max(0, x - gap), height: Math.max(0, ...columns.map(column => column.height))};
}
// Sorrendtartó oszlopokra bontás `count` oszlopra (oszloponként nagyjából egyenlő elemszám), illetve magasság szerint.
const splitEven = (children, count) => {
  const per = Math.ceil(children.length / count), groups = [];
  for (let i = 0; i < children.length; i += per) groups.push(children.slice(i, i + per));
  return groups;
};
function splitByHeight(children) {
  const groups = [];
  let group = null, height = 0;
  for (const child of children) {
    if (!group || (group.length && height + gap + slotHeight(child) > columnLimit)) { groups.push(group = []); height = -gap; }
    group.push(child);
    height += gap + slotHeight(child);
  }
  return groups;
}
// Rács `count` oszloppal, soronként balról jobbra: az oszlop szélessége a legszélesebb eleméé, egy sorban a dobozok
// teteje egy vonalban (fölöttük a sor leghosszabb nevének helye).
function grid(children, count) {
  const widths = Array.from({length: count}, (_, column) => Math.max(0, ...children.filter((_, i) => i % count === column).map(child => child.width)));
  children.forEach((child, i) => { const width = widths[i % count]; if (!child.children?.length && child.width < width) { child.width = width; child.nameHeight = nameSpace(child, width); } });
  const offsets = widths.map((_, column) => widths.slice(0, column).reduce((sum, width) => sum + width + gap, 0));
  const slots = [];
  let y = 0;
  for (let start = 0; start < children.length; start += count) {
    const row = children.slice(start, start + count);
    const names = Math.max(...row.map(child => child.nameHeight)), boxes = Math.max(...row.map(child => child.height));
    row.forEach((child, i) => slots.push({child, x: offsets[i], y: y + names}));
    y += names + boxes + gap;
  }
  return {slots, width: widths.reduce((sum, width) => sum + width, 0) + gap * (count - 1), height: Math.max(0, y - gap)};
}
function arrange(item) {
  const children = item.children;
  const reset = () => { for (const child of children) if (child.naturalWidth != null) { child.width = child.naturalWidth; child.nameHeight = nameSpace(child, child.width); } };
  // Kézzel átméretezett konténer: a tartalom a szélességéhez igazodik (az oszlopok száma).
  const target = item.target ? Math.max(40, item.target - 2 * pad) : null;
  if (item.list === true && children.length > 1 && target) {
    let chosen = 1;
    for (let count = 2; count <= children.length; count++) {
      reset();
      if (grid(children, count).width > target) break;
      chosen = count;
    }
    reset();
    return grid(children, chosen);
  }
  if (item.list === true && children.length > 1) {
    // Rács: az oszlopszám, amelynél a tartalom aránya a legközelebb esik az 1:1-hez (és egy oszlop sem túl magas).
    let best = null;
    for (let count = 1; count <= children.length; count++) {
      reset();
      const layout = grid(children, count);
      const tooTall = layout.height > columnLimit;
      const score = Math.abs(Math.log(Math.max(1, layout.width) / Math.max(1, layout.height)));
      if (!best || (best.tooTall && !tooTall) || (tooTall === best.tooTall && score < best.score)) best = {layout, tooTall, score, count};
      if (layout.width > layout.height * 1.5 && !tooTall) break;
      if (Math.ceil(children.length / count) === Math.ceil(children.length / (count + 1)) && count + 1 <= children.length) continue;
    }
    // A kiválasztott oszlopszámmal újra (a szélesítés a próbák alatt elcsúszhatott).
    reset();
    return grid(children, best.count);
  }
  const side = children.filter(child => child.side), main = children.filter(child => !child.side);
  if (side.length && main.length) {
    // Bal oszlop: a többi tag a forrás sorrendjében; jobb oszlop: a számított tagok, a használt tag magasságában.
    const [right] = columnsOf([side]);
    const left = stack(columnsOf(splitByHeight(main)));
    const top = new Map(left.slots.map(slot => [slot.child.name, slot.y - slot.child.nameHeight]));
    const x = left.width + gap * 3, slots = [...left.slots];
    let bottom = 0;
    for (const child of right.items) {
      const wanted = Math.min(...(child.deps ?? []).map(name => top.get(name)).filter(value => value != null));
      const y = Math.max(Number.isFinite(wanted) ? wanted : bottom, bottom);
      slots.push({child, x, y: y + child.nameHeight});
      bottom = y + slotHeight(child) + gap;
    }
    return {slots, width: x + right.width, height: Math.max(left.height, bottom - gap)};
  }
  // Objektum / struct: mindig egymás alatt, a kód sorrendjében (a több hely nem ad több oszlopot, a fölösleg üres marad);
  // új oszlop csak a doboz legnagyobb magassága miatt.
  return stack(columnsOf(splitByHeight(children)));
}

// Helyek kiosztása: a dobozok `position`-je a középpontjuk munkalap-koordinátában.
function place(item, left, top, out) {
  if (item.collapsed) { placeHidden(item, left + item.width / 2, top + item.height / 2, out); return; }
  for (const {child, x, y} of item.layout?.slots ?? []) {
    const boxLeft = left + pad + x, boxTop = top + item.header + y;
    out.push({item: child, position: {x: boxLeft + child.width / 2, y: boxTop + child.height / 2}});
    if (child.children?.length) place(child, boxLeft, boxTop, out);
  }
}
// Az összecsukott konténer rejtett tartalma: a konténer közepén (nem rajzolódik; így a határoló doboz sem nő tőle).
function placeHidden(item, x, y, out) {
  for (const child of item.children ?? []) {
    out.push({item: child, position: {x, y}});
    placeHidden(child, x, y, out);
  }
}

// Összecsukott konténer szövege: „▸ N elem” (Swift-structnál a protokollok előtte); felismerhető, kibontáskor törlődik.
const summaryMark = "▸ ";
const summaryText = text => String(text ?? "").startsWith(summaryMark);
function collapsedSummary(item) {
  const count = item.children.length;
  const protocols = item.sourceText && item.text && !summaryText(item.text) ? " · " + item.text : "";
  return summaryMark + count + (item.list ? " elem" : item.ref ? " tag" : " mező") + protocols;
}

// A doboz mezői: a forrásból (név, szöveg, list) és az automatikus kitöltés; meglévő doboznál a kézi beállítások maradnak.
const leafLayout = item => !item.children?.length && item.list == null;
// Üres érték: JSON `null`, Swift `= nil`, illetve alapérték nélküli opcionális `var` (kezdetben nil).
export function isNil(text, note, leaf = true) {
  const value = String(text ?? "").trim();
  return leaf && (value === "null" || / = nil$/.test(value) || value === "= nil" || (note === "var" && /\?$/.test(value) && !value.includes(" = ")));
}
// Az automatikus megjelenés: kitöltés (típusszín), alak (mindig lekerekített doboz), üres érték: csak keret (`empty`)
// és dőlt szöveg.
function automaticLook(text, note, leaf, typeColors, shape) {
  const empty = isNil(text, note, leaf);
  return {fill: automaticFill(text, leaf, typeColors, note), shape: shape ?? "rounded", backgroundMode: empty ? "empty" : undefined, italic: empty || undefined};
}
// A korábbi automatikus alak: a 2026-11-27-i köztes változat a számított tulajdonságot és a függvényt rombuszként
// generálta; az ilyen rombusz automatikusnak számít (visszaáll dobozra), a kézzel állított alak marad.
const beforeShape = node => (node.nameNote === "ƒ" || node.nameNote === "func") && node.shape === "diamond" ? "diamond" : "rounded";
function fieldsFor(item, typeColors) {
  const leaf = leafLayout(item), before = item.previous;
  const look = automaticLook(item.text, item.note, leaf, typeColors, item.shape);
  if (!before) return {...look, textColor: ink, fontSize: leafFontSize, alignment: item.align ?? (leaf ? "center" : "left")};
  // A régi automatikus megjelenés (a régi szövegből) helyett az új; ami kézzel állított (eltér a régi automatikustól), marad.
  const beforeLeaf = !(before.list != null) && !item.hadChildren;
  const old = automaticLook(before.text, before.nameNote, beforeLeaf, typeColors, beforeShape(before));
  const fields = {fontSize: before.fontSize ?? leafFontSize};
  if (before.fill === old.fill || before.fill == null) fields.fill = look.fill;
  if ((before.shape ?? "rounded") === old.shape) fields.shape = look.shape;
  if (before.backgroundMode === old.backgroundMode) fields.backgroundMode = look.backgroundMode;
  if (before.italic === old.italic) fields.italic = look.italic;
  return fields;
}

// A konténer új tartalma. `container`: a konténer doboz (id, position, width, height, text, fontSize).
// `previous`: a konténer jelenlegi leszármazottai a lap sorrendjében (tömb). Eredmény:
// - `nodes`: [{id, parent, previous?, fields}] a szülő előbb, mint a gyermeke, a forrás sorrendjében; `fields` a doboz
//   beállítandó mezői (meglévő doboznál csak ami a generálásból adódik: név, szöveg, list, hely, méret, automatikus szín);
// - `removed`: a megszűnő dobozok azonosítói; `patch`: a konténer módosítása (méret, hely, list).
export function generateBoxes(source, container, {format = "json", previous = [], typeColors = defaultTypeColors} = {}) {
  nameSpaces.clear();
  const {root, count, truncated} = boxTree(source, format);
  // Csak a sima dobozok a struktúra részei; a konténerbe tett más objektum (kép, fájl …) érintetlen marad.
  previous = previous.filter(node => node.type === "box");
  const byParent = new Map();
  for (const node of previous) {
    if (!byParent.has(node.parent)) byParent.set(node.parent, []);
    byParent.get(node.parent).push(node);
  }
  const used = new Set([container.id]);
  match(root, container.id, byParent, container.id, "", used);
  // Mezők és méretek (a megtartott betűmérettel és szöveggel számolva).
  const all = [];
  (function walk(item) {
    for (const child of item.children ?? []) {
      child.hadChildren = (byParent.get(child.previous?.id) ?? []).length > 0;
      child.target = child.previous?.layoutWidth;
      child.targetHeight = child.previous?.layoutHeight;
      // A konténer saját szövege nem adat: a meglévő konténeré marad (az összecsukáskori összegzés nem).
      child.collapsed = !leafLayout(child) && child.previous?.collapsed === true && child.children?.length > 0;
      if (!leafLayout(child) && !child.sourceText) child.text = summaryText(child.previous?.text) ? "" : child.previous?.text ?? "";
      if (child.collapsed) child.text = collapsedSummary(child);
      child.fields = fieldsFor(child, typeColors);
      all.push(child);
      walk(child);
    }
  })(root);
  root.fields = {fontSize: container.fontSize ?? 16};
  root.target = container.layoutWidth;
  root.targetHeight = container.layoutHeight;
  // Egyetlen Swift-struct: maga a konténer a struct (név, protokollok); egyébként a konténer saját szövege marad.
  if (!root.sourceText) root.text = summaryText(container.text) ? "" : container.text ?? "";
  root.collapsed = container.collapsed === true && root.children?.length > 0;
  if (root.collapsed) root.text = collapsedSummary(root);
  measure(root);
  const width = Math.max(sizeLimits.width[0], root.width), height = Math.max(sizeLimits.height[0], root.height);
  const left = container.position.x - container.width / 2, top = container.position.y - container.height / 2;
  const placed = [];
  place(root, left, top, placed);
  const parentOf = new Map();
  (function link(item, parent) { for (const child of item.children ?? []) { parentOf.set(child, parent); link(child, child.id); } })(root, container.id);
  const nodes = placed.map(({item, position}) => {
    const leaf = leafLayout(item);
    return {id: item.id, parent: parentOf.get(item), previous: item.previous,
      fields: {...item.fields, type: "box", name: item.name, nameNote: item.note, computed: item.computed, text: item.text ?? "", list: leaf ? undefined : item.list,
        position, width: item.width, height: item.height, ...(leaf ? {} : {verticalAlignment: "top"})}};
  });
  const kept = new Set(nodes.map(node => node.id));
  const removed = previous.filter(node => !kept.has(node.id)).map(node => node.id);
  const patch = {width, height, position: {x: left + width / 2, y: top + height / 2}, list: root.list};
  if (root.root || root.collapsed || summaryText(container.text)) Object.assign(patch, root.root ? {name: root.name} : {}, {text: root.text});
  // Kezelt vonalak (Swift): a képletben / függvénytörzsben használt testvér-tagtól a számított tulajdonsághoz, illetve
  // függvényhez; a struct típusú tulajdonságtól a struct konténeréhez. Az azonosító a végpontokból képzett hash
  // (structureEdgeId), így a szerkesztő felismeri őket.
  const edges = [];
  const containers = new Map();
  (function collect(item, id) { if (item.ref) containers.set(item.ref, id); for (const child of item.children ?? []) collect(child, child.id); })(root, container.id);
  const add = (source, target) => { if (source && target && source !== target) edges.push({id: structureEdgeId(container.id, source, target), source, target}); };
  (function walk(item) {
    const byName = new Map((item.children ?? []).map(child => [child.name, child.id]));
    for (const child of item.children ?? []) {
      for (const name of child.deps ?? []) add(byName.get(name), child.id);
      for (const ref of child.refs ?? []) add(child.id, containers.get(ref));
      walk(child);
    }
  })(root);
  return {nodes, removed, patch, count, truncated, edges};
}

// ---- Visszafelé: dobozokból JSON ----------------------------------------------------------------------------------

// A konténer fajtája: a tárolt jelző, vagy (jelző nélkül) objektum, ha minden gyermeknek egyedi neve van.
export function inferList(children) {
  if (!children.length) return false;
  const names = children.map(child => child.name?.trim() ?? "");
  return names.some(name => !name) || new Set(names).size !== names.length;
}

// A konténer értéke a lap dobozaiból. `nodes`: a lap dobozai (sorrendben); `rootId`: a konténer.
// `raw`: a számok a doboz szövegének alakjával (RawNumber; a visszaíráshoz).
export function boxesValue(nodes, rootId, {raw = false} = {}) {
  const byParent = new Map();
  for (const node of nodes) {
    if (!node.parent) continue;
    if (!byParent.has(node.parent)) byParent.set(node.parent, []);
    byParent.get(node.parent).push(node);
  }
  const root = nodes.find(node => node.id === rootId);
  const seen = new Set();
  function value(node, isRoot) {
    if (seen.has(node.id)) throw new StructureError("Körkörös szülő–gyermek kapcsolat.");
    seen.add(node.id);
    const children = (byParent.get(node.id) ?? []).filter(child => child.type === "box");
    const list = node.list ?? (children.length || isRoot ? inferList(children) : null);
    if (list == null) {
      const value = parseValue(node.text);
      return raw && typeof value === "number" ? new RawNumber(value, String(node.text ?? "").trim()) : value;
    }
    if (list) return children.map(child => value(child, false));
    const object = {};
    for (const child of children) {
      let key = (child.name ?? "").trim(), n = 1;
      while (Object.hasOwn(object, key)) key = (child.name ?? "").trim() + " (" + ++n + ")";
      object[key] = value(child, false);
    }
    return object;
  }
  return value(root, true);
}

// A dobozokból írt forrásszöveg (a korábbi forrás behúzásával).
export function boxesSource(nodes, rootId, {format = "json", previous = ""} = {}) {
  if (!formats[format]?.write) throw new StructureError("A ." + format + " forrás csak olvasható: a dobozok változása nem íródik vissza.");
  return formats[format].write(boxesValue(nodes, rootId, {raw: true}), previous);
}
// Visszaírható-e a forrásformátum (a dobozok felől).
export const writable = format => Boolean(formats[format]?.write);

// ---- Swift-forrás (csak olvasás) ----------------------------------------------------------------------------------
// A forrás structjai (beágyazottak is, „A.B” néven) a gyökérkonténerben egymás mellett álló konténerek; a tulajdonságok
// dobozok: név = a tulajdonság neve, előtte halványan `let` / `var` / `ƒ` (`nameNote`), szöveg = „Típus = alapérték”,
// számított változónál „Típus = képlet” (`computed`: szaggatott keret). A képlet által használt tulajdonságokra és a
// struct típusú tulajdonság structjára halvány nyíl mutat (`edges`). Statikus tulajdonság, metódus, init nem jelenik meg.
// Nem teljes Swift-elemző: kommenteket, szövegliterálokat (interpolációval, többsoros, nyers), zárójelezést kezel.

// A kód „maszkolva”: a kommentek (mindkét változatban) és a szövegliterálok tartalma (a kódban) szóközre cserélve, a
// pozíciók maradnak. `code`: szöveg és komment nélkül (zárójelek, azonosítók keresése; az interpoláció kód marad);
// `clean`: csak komment nélkül (a megjelenített képlethez).
function maskSwift(text) {
  const code = text.split(""), clean = text.split("");
  const blank = (array, from, to) => { for (let i = from; i < to; i++) if (array[i] !== "\n") array[i] = " "; };
  let i = 0;
  // Szövegliterál a `start` helytől: a tartalma a `code` változatban szóköz, az interpolációk (`\(…)`) kódja marad.
  // Nyers szöveg: #…"…"#, többsoros: """…""". Eredmény: a literál utáni hely.
  function readString(start) {
    let hashes = 0;
    while (text[start + hashes] === "#") hashes++;
    const multi = text.startsWith('"""', start + hashes), quote = multi ? '"""' : '"';
    const close = quote + "#".repeat(hashes), escape = "\\" + "#".repeat(hashes);
    let j = start + hashes + quote.length, segment = j;
    while (j < text.length) {
      if (text.startsWith(close, j)) { blank(code, segment, j); return j + close.length; }
      if (!multi && text[j] === "\n") { blank(code, segment, j); return j; }
      if (text.startsWith(escape + "(", j)) {
        blank(code, segment, j);
        let depth = 1, k = j + escape.length + 1;
        while (k < text.length) {
          if (text[k] === '"' || (text[k] === "#" && /^#+"/.test(text.slice(k, k + 8)))) { k = readString(k); continue; }
          if (text[k] === "(") depth++;
          else if (text[k] === ")" && --depth === 0) break;
          k++;
        }
        j = k + 1; segment = j;
        continue;
      }
      if (text.startsWith(escape, j)) { j += escape.length + 1; continue; }
      j++;
    }
    blank(code, segment, text.length);
    return text.length;
  }
  while (i < text.length) {
    if (text.startsWith("//", i)) {
      const end = text.indexOf("\n", i);
      const stop = end < 0 ? text.length : end;
      blank(code, i, stop); blank(clean, i, stop); i = stop;
    } else if (text.startsWith("/*", i)) {
      let depth = 1, j = i + 2;
      while (j < text.length && depth > 0) {
        if (text.startsWith("/*", j)) { depth++; j += 2; }
        else if (text.startsWith("*/", j)) { depth--; j += 2; }
        else j++;
      }
      blank(code, i, j); blank(clean, i, j); i = j;
    } else if (text[i] === '"' || (text[i] === "#" && /^#+"/.test(text.slice(i, i + 8)))) {
      i = readString(i);
    } else i++;
  }
  return {code: code.join(""), clean: clean.join("")};
}

// A `from` helyen nyíló zárójel párja (a maszkolt kódban); -1, ha nincs.
function closing(code, from) {
  const open = code[from], close = {"{": "}", "(": ")", "[": "]", "<": ">"}[open];
  let depth = 0;
  for (let i = from; i < code.length; i++) {
    if (code[i] === open) depth++;
    else if (code[i] === close && --depth === 0) return i;
  }
  return -1;
}

// Kifejezés vége: sortörés, `;` vagy `}` 0-s mélységben (zárójelek, szögletes és kapcsos zárójelek számítanak).
function expressionEnd(code, from, limit) {
  let depth = 0;
  for (let i = from; i < limit; i++) {
    const c = code[i];
    // Alapérték után álló figyelők (`{ didSet … }`): a kifejezés előttük véget ér.
    if (c === "{" && depth === 0 && /^\{\s*(didSet|willSet)\b/.test(code.slice(i, i + 40))) return i;
    if ("([{".includes(c)) depth++;
    else if (")]}".includes(c)) { if (depth === 0) return i; depth--; }
    else if (depth === 0 && (c === "\n" || c === ";")) {
      // A következő sor operátorral vagy ponttal folytatódik: a kifejezés tart.
      const rest = code.slice(i + 1, limit).match(/^\s*(\S)/);
      if (c === "\n" && rest && /[.+\-*/%&|?:=<>^]/.test(rest[1]) && !/^\s*(\/\/)/.test(code.slice(i + 1, i + 6))) continue;
      return i;
    }
  }
  return limit;
}

// Megjelenítéshez: soronként levágott szóközök; `join`: a sorok egy sorba (típus, alapérték), egyébként sortöréssel (képlet).
const compact = (text, join = true) => {
  const lines = text.split("\n").map(line => line.trim()).filter(Boolean);
  const joined = lines.join(join ? " " : "\n");
  return joined.length > 600 ? joined.slice(0, 600) + "…" : joined;
};
// A típus nélküli alapérték típusa a literálból (ha egyértelmű).
function literalType(value) {
  const v = value.trim();
  if (/^-?(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*)$/.test(v)) return "Int";
  if (/^-?\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d+)?$/.test(v)) return "Double";
  if (/^#*"/.test(v)) return "String";
  if (v === "true" || v === "false") return "Bool";
  const call = /^([A-Z][A-Za-z0-9_.]*)(<[^>]*>)?\s*\(/.exec(v);
  if (call) return call[1] + (call[2] ?? "");
  return null;
}

const keywordNames = new Set(["let", "var", "func", "init", "deinit", "subscript", "case", "typealias", "associatedtype", "struct", "class",
  "enum", "extension", "actor", "protocol", "static", "private", "fileprivate", "public", "internal", "open", "lazy", "weak", "unowned",
  "final", "override", "mutating", "nonmutating", "nonisolated", "dynamic", "required", "convenience", "indirect", "some", "any", "self",
  "Self", "return", "if", "else", "switch", "guard", "true", "false", "nil", "try", "await", "in", "is", "as"]);

// A struct törzsének 0-s mélységén álló szakaszai (a beágyazott típusok, metódusok, init-ek törzse kimarad).
function topLevel(code, start, end) {
  const top = [];
  let depth = 0;
  for (let i = start; i < end; i++) {
    if (code[i] === "{") depth++;
    else if (code[i] === "}") depth--;
    top.push(depth === 0 && code[i] !== "}");
  }
  return top;
}
// A deklaráció előtti rész a sor (vagy a `;`) elejétől: módosítók, attribútumok.
function declarationPrefix(code, index, start) {
  const lineStart = Math.max(code.lastIndexOf("\n", index), code.lastIndexOf(";", index), code.lastIndexOf("{", index), code.lastIndexOf("}", index)) + 1;
  return code.slice(Math.max(lineStart, start), index);
}
// A törzs (képlet, függvény) kiírása: egyetlen `return` kifejezésnél csak a kifejezés, egyébként soronként.
function bodyText(clean, from, to) {
  const text = clean.slice(from, to).trim();
  return /^return\s/.test(text) && !text.includes("\n") ? compact(text.replace(/^return\s+/, "")) : compact(text, false);
}

// A struct tagjai a forrás sorrendjében: tulajdonságok (let / var, számított is) és függvények (func).
function swiftMembers(code, clean, start, end) {
  const members = [];
  const top = topLevel(code, start, end);
  const words = /\b(let|var|func)\b/g;
  words.lastIndex = start;
  let match;
  while ((match = words.exec(code)) && match.index < end) {
    if (!top[match.index - start]) continue;
    const before = declarationPrefix(code, match.index, start);
    if (!/^[\s\w@().,]*$/.test(before) || /\b(static|class)\b/.test(before) || /\b(func|init|case|if|guard|while|for|let|var)\b/.test(before)) continue;
    let i = match.index + match[0].length;
    if (match[1] === "func") {
      // Függvény: név (operátor is), generikus paraméterek, paraméterlista, a `{` előtti rész (async, throws, -> típus), törzs.
      const name = /^\s*(`?[A-Za-z_][A-Za-z0-9_]*`?|[^\s(<]+)/.exec(code.slice(i, i + 200));
      if (!name) continue;
      i += name[0].length;
      const generic = /^\s*</.exec(code.slice(i, i + 4));
      if (generic) { const close = closing(code, i + generic[0].length - 1); if (close < 0) continue; i = close + 1; }
      const open = code.indexOf("(", i);
      if (open < 0 || open >= end || code.slice(i, open).trim()) continue;
      const close = closing(code, open);
      if (close < 0) continue;
      let j = close + 1;
      while (j < end && code[j] !== "{" && code[j] !== "\n") j++;
      const tail = compact(clean.slice(close + 1, j));
      const signature = compact("(" + clean.slice(open + 1, close) + ")") + (tail ? " " + tail : "");
      let body = null;
      if (code[j] === "{") { const bodyClose = closing(code, j); if (bodyClose > 0) body = {start: j + 1, end: bodyClose}; }
      members.push({kind: "function", pos: match.index, name: name[1].replace(/`/g, ""), signature,
        code: body ? code.slice(body.start, body.end) : ""});
      words.lastIndex = body ? body.end : j;
      continue;
    }
    const name = /^\s*`?([A-Za-z_][A-Za-z0-9_]*)`?/.exec(code.slice(i, i + 200));
    if (!name || keywordNames.has(name[1])) continue;
    i += name[0].length;
    let type = null, value = null, body = null;
    const colon = /^\s*:/.exec(code.slice(i, end));
    if (colon) {
      // Típus: a `=` vagy `{` előttig, illetve a sor végéig (zárójelezést követve).
      let j = i + colon[0].length, d = 0;
      for (; j < end; j++) {
        const c = code[j];
        if ("([<".includes(c)) d++;
        else if (")]>".includes(c) && !(c === ">" && code[j - 1] === "-")) d--;
        else if (d <= 0 && (c === "=" || c === "{" || c === "\n" || c === ";" || c === ",")) break;
      }
      type = compact(clean.slice(i + colon[0].length, j));
      i = j;
    }
    const rest = /^[ \t]*(=|\{)/.exec(code.slice(i, end));
    if (rest?.[1] === "=") {
      const from = i + rest[0].length, stop = expressionEnd(code, from, end);
      value = compact(clean.slice(from, stop));
    } else if (rest?.[1] === "{") {
      const open = i + rest[0].length - 1, close = closing(code, open);
      if (close < 0) continue;
      body = {start: open + 1, end: close};
    }
    let computed = false, formula = null, formulaCode = "";
    if (body && !/^\s*(willSet|didSet)\b/.test(code.slice(body.start, body.end))) {
      computed = true;
      const inner = code.slice(body.start, body.end), getter = /\bget\s*\{/.exec(inner);
      let from = body.start, to = body.end;
      if (getter && /^\s*(get|set|_read|_modify)\b/.test(inner)) { from = body.start + getter.index + getter[0].length; to = closing(code, from - 1); }
      formula = bodyText(clean, from, to);
      formulaCode = code.slice(body.start, body.end);
    }
    members.push({kind: "property", pos: match.index, name: name[1], keyword: match[1], type: type || (value != null ? literalType(value) : null),
      value, computed, formula, code: formulaCode});
  }
  return members;
}

// A forrás structjai: {qualified (minősített név), name (egyszerű név + generikus paraméterek), owner (a befoglaló típus
// minősített neve), pos, conformances, members}.
function swiftStructs(text) {
  const {code, clean} = maskSwift(text);
  const structs = [];
  (function scan(start, end, scope) {
    const declaration = /\b(struct|class|enum|extension|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_.]*)/g;
    declaration.lastIndex = start;
    let match, depth = 0, last = start;
    while ((match = declaration.exec(code)) && match.index < end) {
      // Csak a 0-s mélységű deklarációk (a törzsekben a rekurzió keres).
      for (let i = last; i < match.index; i++) { if (code[i] === "{") depth++; else if (code[i] === "}") depth--; }
      last = match.index;
      if (depth !== 0) continue;
      const open = code.indexOf("{", match.index + match[0].length);
      if (open < 0 || open >= end) break;
      const close = closing(code, open);
      if (close < 0) break;
      const kind = match[1], name = match[2];
      const qualified = kind === "extension" ? name : [...scope, name].join(".");
      if (kind === "struct") {
        const header = clean.slice(match.index + match[0].length, open);
        const generic = /^\s*<[^>]*>/.exec(header)?.[0].trim() ?? "";
        const conformances = /:\s*([^{]*?)(\bwhere\b[^{]*)?$/s.exec(header.replace(/^\s*<[^>]*>/, ""))?.[1]?.replace(/\s+/g, " ").trim() ?? "";
        structs.push({qualified, name: name + generic, owner: scope.join("."), pos: match.index, conformances,
          members: swiftMembers(code, clean, open + 1, close)});
      }
      scan(open + 1, close, qualified.split("."));
      declaration.lastIndex = close + 1;
      last = close + 1;
      depth = 0;
    }
  })(0, code.length, []);
  return structs;
}

// A típus szövegében hivatkozott structok (a hatókör szerint feloldva: A.B-ben a „C” előbb A.B.C, majd A.C, majd C).
function typeReferences(type, owner, known) {
  const found = [];
  for (const [name] of String(type ?? "").matchAll(/[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*/g)) {
    const scope = owner.split(".");
    for (let n = scope.length; n >= 0; n--) {
      const candidate = [...scope.slice(0, n), name].join(".");
      if (known.has(candidate)) { if (!found.includes(candidate)) found.push(candidate); break; }
    }
  }
  return found;
}

// A törzsben használt testvér-tagok (azonosító, előtte nem pont, kivéve `self.`).
function usedNames(code, names) {
  const used = [];
  for (const m of String(code).matchAll(/(self\.)?\b([A-Za-z_][A-Za-z0-9_]*)\b/g)) {
    if ((code[m.index - 1] === "." && !m[1]) || !names.has(m[2]) || used.includes(m[2])) continue;
    used.push(m[2]);
  }
  return used;
}

// A Swift-forrás fája. Egyetlen felső szintű struct: maga a konténer az a struct (név, protokollok); több: mindegyik
// külön konténer a gyökérben. A beágyazott struct a szülője konténerében, a tagok között (a forrás sorrendjében).
// Számított tulajdonság (ƒ) és függvény (func), mindkettő szaggatott kerettel: a használt tagoktól nyíl mutat feléjük (`deps`);
// struct típusú tulajdonságtól a struct konténeréhez (`refs`).
function swiftTree(source) {
  const structs = swiftStructs(String(source));
  const known = new Set(structs.map(item => item.qualified));
  const byName = new Map(structs.map(item => [item.qualified, item]));
  for (const item of structs) item.nested = [];
  const roots = [];
  for (const item of structs) {
    const owner = byName.get(item.owner);
    if (owner && owner !== item) owner.nested.push(item); else roots.push(item);
  }
  function structItem(item, root) {
    const names = new Set(item.members.map(member => member.name));
    const members = item.members.map(member => {
      const others = new Set([...names].filter(name => name !== member.name));
      if (member.kind === "function") {
        return {pos: member.pos, key: "." + member.name, name: member.name, note: "func", text: escapeMarkdown(member.signature), sourceText: true,
          computed: true, align: "left", side: true, deps: usedNames(member.code, others), refs: []};
      }
      const typeText = member.type ? escapeMarkdown(member.type) : "";
      const rest = member.computed ? member.formula : member.value;
      const text = rest != null && rest !== "" ? (typeText ? typeText + " = " : "= ") + escapeMarkdown(rest) : typeText;
      return {pos: member.pos, key: "." + member.name, name: member.name, text, sourceText: true,
        note: member.computed ? "ƒ" : member.keyword, computed: member.computed || undefined, align: "left", side: member.computed || undefined,
        deps: member.computed ? usedNames(member.code, others) : [], refs: typeReferences(member.type, item.qualified, known)};
    });
    const nested = item.nested.map(child => ({pos: child.pos, ...structItem(child, false)}));
    return {key: "." + item.qualified, ref: item.qualified, name: root || !byName.has(item.owner) ? item.qualified.replace(/[^.]+$/, "") + item.name : item.name,
      sourceText: true, text: item.conformances ? "*" + escapeMarkdown(item.conformances) + "*" : "",
      children: [...members, ...nested].sort((a, b) => a.pos - b.pos)};
  }
  if (roots.length === 1) return {...structItem(roots[0], true), key: "", root: true};
  return {text: "", children: roots.map(item => structItem(item, true))};
}
