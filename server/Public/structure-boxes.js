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

import {nameLayout, textWidth} from "./geometry.js?v=37";

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
export const defaultTypeColors = {String: 5, Int: 4, Float: 12, Double: 15, Bool: 6, Date: 14, URL: 11, UUID: 13};
const baseTypes = new Set(Object.keys(defaultTypeColors));

export class StructureError extends Error {}

// Forrásformátumok: fájlkiterjesztés → elemző (szöveg → érték) és író (érték → szöveg). Swift struct: későbbi bővítés.
export const formats = {
  json: {
    parse: source => {
      try { return JSON.parse(source); } catch (error) { throw new StructureError("Hibás JSON: " + error.message); }
    },
    // A forrás behúzását követi (szóköz vagy tabulátor, alapból 2 szóköz).
    write: (value, previous = "") => JSON.stringify(value, null, (/\n([ \t]+)\S/.exec(previous)?.[1]) ?? 2) + "\n",
  },
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
// Szöveg ujjlenyomata (a forrásé és a dobozokból írt JSON-é): ha nem változott, nincs szinkron.
export const textDigest = (text, format = "json") => hash128("structure:2\u0000" + format + "\u0000" + text).slice(0, 24);

// ---- Értékek ------------------------------------------------------------------------------------------------------

// Markdown-jelek semlegesítése (CommonMark visszaper): ami a doboz szövegében formázásként hatna.
export function escapeMarkdown(text) {
  const link = /\]\s*[([:]/.test(text);
  return String(text).split("\n").map(line => {
    let out = line.replace(link ? /[\\`*_<&[\]]/g : /[\\`*_<&]/g, "\\$&");
    out = out.replace(/^(\s*)([#>+-])/, "$1\\$2").replace(/^(\s*\d+)([.)])/, "$1\\$2");
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
export function typeInfo(text) {
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
    return baseTypes.has(s) ? {base: s, collection: null, optional} : null;
  }
  return parse(value);
}

// A doboz automatikus kitöltése: típusszónál a típus színe, egyébként doboz / konténer alapszín.
export function automaticFill(text, leaf, typeColors = defaultTypeColors) {
  if (!leaf) return containerFill;
  const type = typeInfo(text);
  return type && typeColors[type.base] != null ? typeColors[type.base] : leafFill;
}

// ---- Fa a forrásból -----------------------------------------------------------------------------------------------
// Elem: {key, name, text, list, children?}. A `key` a párosítás kulcsa (testvérek közt egyedi).

const isPlainObject = value => value != null && typeof value === "object" && !Array.isArray(value);
const titleKeys = ["name", "title", "label", "id", "key", "név", "nev", "cím", "cim"];
function itemTitle(value) {
  if (!isPlainObject(value)) return null;
  for (const key of titleKeys) if (typeof value[key] === "string" || typeof value[key] === "number") return String(value[key]);
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
      ? siblingKeys(value.map(item => item !== null && typeof item === "object" ? (itemTitle(item) == null ? null : "=" + itemTitle(item)) : "=" + JSON.stringify(item)))
      : entries.map(([name]) => "." + name);
    const children = [];
    for (let i = 0; i < entries.length; i++) {
      if (budget.count >= generatedLimit) { budget.truncated = true; break; }
      const [name, item] = entries[i];
      const child = valueTree(item, budget, depth + 1);
      child.key = keys[i];
      child.name = list ? (item !== null && typeof item === "object" ? itemTitle(item) ?? undefined : undefined) : checkName(name);
      if (child.name != null && child.name.length > nameLimit) child.name = child.name.slice(0, nameLimit);
      if (child.name != null && /[\r\n]/.test(child.name)) child.name = child.name.replace(/[\r\n]+/g, " ");
      children.push(child);
    }
    return {text: "", list, children};
  }
  const text = formatValue(value);
  if (text.length > textLimit) throw new StructureError("Túl hosszú érték (legfeljebb " + textLimit + " karakter).");
  return {text};
}

// A forrásszövegből a fa; a gyökér a konténer maga. Egyszerű érték gyökérnél a konténerben egy doboz áll.
export function boxTree(source, format = "json") {
  const handler = formats[format];
  if (!handler) throw new StructureError("Ismeretlen forrásformátum: " + format);
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
const nameSpace = (item, width) => nameLayout({type: "box", name: item.name, list: item.list, width})?.height ?? 0;

function measure(item) {
  const fontSize = item.fields.fontSize ?? leafFontSize;
  if (!item.children?.length) {
    const {natural, widths} = textSize(item.text, fontSize);
    const nameWidth = item.name ? Math.min(300, textWidth(item.name, 13, {bold: true}) + 12) : 0;
    item.width = Math.min(300, Math.max(80, Math.ceil(Math.max(natural + 30, nameWidth))));
    // Címketerület: szélesség × 0,94 − 16, magasság × 0,94 − 12 (geometry.js labelLayout); tördelésre 15% tartalék.
    const room = item.width * .94 - 16;
    const rows = item.text ? widths.reduce((sum, w) => sum + Math.max(1, Math.ceil(w * 1.15 / room)), 0) : 0;
    item.height = Math.max(40, Math.ceil((rows * lineHeight(fontSize) + 12) / .94 + 6));
    item.nameHeight = nameSpace(item, item.width);
    return item;
  }
  for (const child of item.children) measure(child);
  item.rows = arrange(item.children, item.layout);
  const innerWidth = Math.max(60, ...item.rows.map(row => row.width));
  item.width = Math.min(sizeLimits.width[1], Math.ceil(innerWidth + 2 * pad));
  // A konténer saját szövege (ha van) fölül, a körbefuttatás miatt a címketerület arányával (0,94) számolva.
  const title = item.text ? textSize(item.text, fontSize).widths.reduce((sum, w) => sum + Math.max(1, Math.ceil(w * 1.15 / (item.width * .94 - 16))), 0) * lineHeight(fontSize) : 0;
  const body = item.rows.reduce((sum, row) => sum + row.height, 0) + gap * Math.max(0, item.rows.length - 1);
  const k = .03, fixed = title ? 6 + title + 8 + 6 : pad - 4;
  item.header = title ? Math.ceil((k * (body + pad) + fixed) / (1 - k)) : fixed;
  item.height = Math.min(sizeLimits.height[1], Math.max(40, Math.ceil(item.header + body + pad)));
  item.nameHeight = nameSpace(item, item.width);
  return item;
}

// Sorokba rendezés: csak egyszerű értékek → egymás alatt, egyforma szélességgel; egyébként polcos tördelés nagyjából
// kiegyensúlyozott, legfeljebb 1400 képpont széles sorokkal. A sor magassága a nevekkel együtt (a doboz fölött).
function arrange(children, layout) {
  const slot = child => child.nameHeight + child.height;
  if (layout === "column") {
    const width = Math.max(...children.map(child => child.width));
    for (const child of children) if (child.width < width) { child.width = width; child.nameHeight = nameSpace(child, width); }
    return children.map(child => ({items: [child], width, height: slot(child), names: child.nameHeight}));
  }
  const widest = Math.max(...children.map(child => child.width));
  const area = children.reduce((sum, child) => sum + (child.width + gap) * (slot(child) + gap), 0);
  const target = Math.max(widest, Math.min(1400, Math.sqrt(area) * 1.5));
  const rows = [];
  let row = null;
  for (const child of children) {
    if (!row || (row.items.length && row.width + gap + child.width > target)) rows.push(row = {items: [], width: 0, names: 0, boxes: 0});
    row.width += (row.items.length ? gap : 0) + child.width;
    row.names = Math.max(row.names, child.nameHeight);
    row.boxes = Math.max(row.boxes, child.height);
    row.items.push(child);
  }
  for (const each of rows) each.height = each.names + each.boxes;
  return rows;
}

// Helyek kiosztása: a dobozok `position`-je a középpontjuk munkalap-koordinátában; egy sorban a dobozok teteje egy
// vonalban, fölöttük a sor leghosszabb nevének helye.
function place(item, left, top, out) {
  let y = top + item.header;
  for (const row of item.rows ?? []) {
    let x = left + pad;
    for (const child of row.items) {
      const boxTop = y + row.names;
      out.push({item: child, position: {x: x + child.width / 2, y: boxTop + child.height / 2}});
      if (child.children?.length) place(child, x, boxTop, out);
      x += child.width + gap;
    }
    y += row.height + gap;
  }
}

// A doboz mezői: a forrásból (név, szöveg, list) és az automatikus kitöltés; meglévő doboznál a kézi beállítások maradnak.
const leafLayout = item => !item.children?.length && item.list == null;
function fieldsFor(item, typeColors) {
  const leaf = leafLayout(item), before = item.previous;
  const fill = automaticFill(item.text, leaf, typeColors);
  if (!before) return {fill, textColor: ink, fontSize: leafFontSize, alignment: leaf ? "center" : "left", shape: "rounded"};
  // A régi automatikus szín (a régi szövegből) helyett az új; a kézzel állított szín marad.
  const beforeLeaf = !(before.list != null) && !item.hadChildren;
  const fields = {fontSize: before.fontSize ?? leafFontSize};
  if (before.fill === automaticFill(before.text, beforeLeaf, typeColors) || before.fill == null) fields.fill = fill;
  return fields;
}

// A konténer új tartalma. `container`: a konténer doboz (id, position, width, height, text, fontSize).
// `previous`: a konténer jelenlegi leszármazottai a lap sorrendjében (tömb). Eredmény:
// - `nodes`: [{id, parent, previous?, fields}] a szülő előbb, mint a gyermeke, a forrás sorrendjében; `fields` a doboz
//   beállítandó mezői (meglévő doboznál csak ami a generálásból adódik: név, szöveg, list, hely, méret, automatikus szín);
// - `removed`: a megszűnő dobozok azonosítói; `patch`: a konténer módosítása (méret, hely, list).
export function generateBoxes(source, container, {format = "json", previous = [], typeColors = defaultTypeColors} = {}) {
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
      // A konténer saját szövege nem adat: a meglévő konténeré marad.
      if (!leafLayout(child)) child.text = child.previous?.text ?? "";
      child.fields = fieldsFor(child, typeColors);
      all.push(child);
      walk(child);
    }
  })(root);
  for (const item of [root, ...all]) item.layout = item.children?.length && item.children.every(leafLayout) ? "column" : "auto";
  root.fields = {fontSize: container.fontSize ?? 16};
  root.text = container.text ?? "";
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
      fields: {...item.fields, type: "box", name: item.name, text: item.text ?? "", list: leaf ? undefined : item.list,
        position, width: item.width, height: item.height, ...(leaf ? {} : {verticalAlignment: "top"})}};
  });
  const kept = new Set(nodes.map(node => node.id));
  const removed = previous.filter(node => !kept.has(node.id)).map(node => node.id);
  const patch = {width, height, position: {x: left + width / 2, y: top + height / 2}, list: root.list};
  return {nodes, removed, patch, count, truncated};
}

// ---- Visszafelé: dobozokból JSON ----------------------------------------------------------------------------------

// A konténer fajtája: a tárolt jelző, vagy (jelző nélkül) objektum, ha minden gyermeknek egyedi neve van.
export function inferList(children) {
  if (!children.length) return false;
  const names = children.map(child => child.name?.trim() ?? "");
  return names.some(name => !name) || new Set(names).size !== names.length;
}

// A konténer értéke a lap dobozaiból. `nodes`: a lap dobozai (sorrendben); `rootId`: a konténer.
export function boxesValue(nodes, rootId) {
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
    if (list == null) return parseValue(node.text);
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
  return formats[format].write(boxesValue(nodes, rootId), previous);
}
