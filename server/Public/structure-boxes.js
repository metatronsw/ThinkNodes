// Struktúra-konténer (docs/node-types.md, „Struktúra-konténer”): a vonallal bekötött forrásfájlból (ma .json, később
// Swift struct) valódi dobozok készülnek a konténerben, a táblázat–grafikon párosítás mintájára. A modul tiszta (DOM
// nélkül), a szerkesztő (editor.js) hívja; tesztje: Tests/Editor/structure-boxes.mjs.
//
// Felépítés: forrásformátum (`formats`) → köztes fa (`boxTree`) → méretezés és elrendezés → dobozok (`generateBoxes`).
// Új formátum (pl. Swift struct: csak `struct` és tárolt `let` / `var` tulajdonság) egy elemzővel bővíthető, amely a
// forrásszövegből közönséges JS-értéket (objektum / tömb / egyszerű érték) vagy dobozleíró sémát ad.
//
// Két bemenet-alak:
// - Dobozleíró séma: {text | title, fill, textColor, shape, width, height, fontSize, bold, italic, align, layout,
//   id, children: [...]}. A gyökér maga a konténer (szövege, színe), vagy egy ilyen elemekből álló tömb.
// - Bármilyen más érték: objektum és tömb → konténer, egyszerű érték → doboz („kulcs” félkövéren, alatta az érték).
//
// Azonosítók: a konténer azonosítójából és az elem útvonalából képzett hash. Az útvonal kulcsa objektumban a kulcs,
// tömbben az elem neve (name, title, id… vagy egyszerű értéknél maga az érték), ha a testvérek közt egyedi, egyébként a
// sorszám. Így beszúrás, törlés, átrendezés után is ugyanaz az elem ugyanazt az azonosítót kapja, és a rá kötött vonal
// megmarad.
//
// Megőrzés (`previous`: az előző generálás dobozai azonosító szerint): ha az elem a forrásban nem változott (a `generated`
// ujjlenyomat azonos), a doboz kézzel állított szövege és megjelenése megmarad; ha változott, a forrásból jövő tartalom
// és stílus az új, a kézzel állított színek és betűbeállítások akkor is megmaradnak. A helyet és a méretet mindig az
// elrendezés adja.

export const generatedLimit = 400;
export const depthLimit = 8;
const textLimit = 600;
const sizeLimits = {width: [64, 4096], height: [40, 4096]};
const shapeNames = new Set(["rounded", "rectangle", "ellipse", "diamond", "triangle", "pentagon", "hexagon", "parallelogram"]);
const layouts = new Set(["auto", "row", "column"]);
const schemaKeys = new Set(["text", "title", "fill", "textColor", "shape", "width", "height", "fontSize", "bold", "italic", "align", "layout", "id", "children"]);
// A doboz kézzel állítható megjelenése, ami újragenerálás után megmarad.
const keptFields = ["fill", "textColor", "backgroundMode", "animation", "shape", "bold", "italic", "underline", "font", "fontSize",
  "uppercase", "justified", "alignment", "fitText"];
// A dobozleíró séma kulcsai a doboz mezőnevein.
const schemaFields = {fill: "fill", textColor: "textColor", shape: "shape", align: "alignment", fontSize: "fontSize", bold: "bold", italic: "italic"};

// Térközök: a konténer belső margója, a dobozok közti rés, sormagasság a betűmérethez (a szerkesztőé 1,25: bőven számol).
const pad = 16, gap = 12, lineFactor = 1.32;
// A címketerület magassága a doboz magasságához képest alakonként (geometry.js labelRatios, Rendering.swift); a szöveg
// a terület tetejétől indul, a terület pedig 6 képponttal és a kimaradó arány felével a doboz teteje alatt.
const labelHeightRatios = {diamond: .47, ellipse: .72, triangle: .42, pentagon: .58, hexagon: .76, parallelogram: .75};
const labelWidthRatios = {diamond: .50, ellipse: .72, triangle: .42, pentagon: .58, hexagon: .68, parallelogram: .60};
// A körbefuttatott szöveg és a gyermekdoboz közti térköz (geometry.js labelLayout: fent és lent 8) és egy kis tartalék.
const flowMargin = 8, slack = 6;
// Alapszínek (a téma palettájának sorszámai): konténer = papír (0), doboz = felület (2), szöveg = tinta (1).
const containerFill = 0, leafFill = 2, ink = 1, leafFontSize = 14;

export class StructureError extends Error {}

// Forrásformátumok: fájlkiterjesztés → elemző (szöveg → érték). Swift struct: későbbi bővítés (TODO.md).
export const formats = {
  json: source => {
    try { return JSON.parse(source); } catch (error) { throw new StructureError("Hibás JSON: " + error.message); }
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
// A forrás ujjlenyomata: ha nem változott, nincs újragenerálás.
export const textDigest = (text, format = "json") => hash128("structure:1\u0000" + format + "\u0000" + text).slice(0, 24);
// Egy elem ujjlenyomata: a forrásból jövő szöveg és stílus (a hely és a méret nem).
const itemSignature = item => hash128("item:1\u0000" + JSON.stringify([item.text ?? "", item.style, !item.children?.length])).slice(0, 24);

// Markdown-jelek semlegesítése a forrásból jövő szövegben (CommonMark visszaper-escape).
export function escapeMarkdown(text) {
  return String(text).split("\n").map(line => line.replace(/[\\`*_[\]<>#~|&]/g, "\\$&").replace(/^(\s*)([-+])(?=\s|$)/, "$1\\$2")
    .replace(/^(\s*\d+)([.)])(?=\s|$)/, "$1\\$2")).join("\n");
}
const clip = text => text.length > textLimit ? text.slice(0, textLimit) + "…" : text;
const isPlainObject = value => value != null && typeof value === "object" && !Array.isArray(value);

function formatValue(value) {
  if (value === null) return "null";
  if (typeof value === "string") return escapeMarkdown(clip(value));
  return String(value);
}

// ---- Séma felismerése ---------------------------------------------------------------------------------------------

function isSchemaNode(value, depth = 0) {
  if (!isPlainObject(value) || depth > depthLimit + 2) return false;
  const keys = Object.keys(value);
  if (!keys.length || !keys.every(key => schemaKeys.has(key))) return false;
  if (!("text" in value) && !("title" in value) && !Array.isArray(value.children)) return false;
  if ("children" in value && !(Array.isArray(value.children) && value.children.every(child => isSchemaNode(child, depth + 1)))) return false;
  return ["text", "title"].every(key => !(key in value) || typeof value[key] === "string");
}
export function isSchema(value) {
  if (Array.isArray(value)) return value.length > 0 && value.every(item => isSchemaNode(item));
  return isSchemaNode(value);
}

const paintValue = value => Number.isInteger(value) && value >= 0 && value < 64 ? value
  : typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value) ? value.toLowerCase() : undefined;
const sizeValue = (value, [low, high]) => typeof value === "number" && Number.isFinite(value) ? Math.min(high, Math.max(low, Math.round(value))) : undefined;

function schemaStyle(node) {
  const style = {};
  const fill = paintValue(node.fill), textColor = paintValue(node.textColor);
  if (fill !== undefined) style.fill = fill;
  if (textColor !== undefined) style.textColor = textColor;
  if (shapeNames.has(node.shape)) style.shape = node.shape;
  if (["left", "center", "right"].includes(node.align)) style.alignment = node.align;
  if (Number.isInteger(node.fontSize) && node.fontSize >= 8 && node.fontSize <= 96) style.fontSize = node.fontSize;
  if (node.bold === true) style.bold = true;
  if (node.italic === true) style.italic = true;
  return style;
}

// ---- Fa építése ---------------------------------------------------------------------------------------------------
// Elem: {key, text, style, layout, width?, height?, children?}. A `key` az útvonal szegmense (azonosítóhoz); a `style`
// a forrásból jövő megjelenés (doboz mezőnevekkel).

// Testvérkulcsok: a jelölt kulcs, ha egyedi, egyébként a sorszám.
function siblingKeys(candidates) {
  const seen = new Map();
  for (const key of candidates) if (key != null) seen.set(key, (seen.get(key) ?? 0) + 1);
  return candidates.map((key, i) => key != null && seen.get(key) === 1 ? "=" + key : String(i));
}

// Gyermekek a korlátokon belül: mélységen vagy darabszámon túl egy „… további” doboz zár.
function childList(makers, keys, budget, depth) {
  if (depth >= depthLimit) return [{key: "…", text: "… (" + makers.length + " elem, túl mély)", style: {italic: true}}];
  const children = [];
  for (let i = 0; i < makers.length; i++) {
    if (budget.count >= generatedLimit) {
      budget.truncated = true;
      children.push({key: "…", text: "… további " + (makers.length - i) + " elem", style: {italic: true}});
      budget.count++;
      break;
    }
    children.push(makers[i](keys[i]));
  }
  return children;
}

function schemaTree(node, key, budget, depth) {
  budget.count++;
  const text = escapeMarkdown(clip(node.text ?? node.title ?? ""));
  const item = {key, text, style: schemaStyle(node), layout: layouts.has(node.layout) ? node.layout : "auto",
    width: sizeValue(node.width, sizeLimits.width), height: sizeValue(node.height, sizeLimits.height)};
  if ("title" in node && !("text" in node)) item.style.bold ??= true;
  if (Array.isArray(node.children) && node.children.length) item.children = schemaChildren(node.children, budget, depth);
  return item;
}
function schemaChildren(list, budget, depth) {
  const keys = siblingKeys(list.map(child => typeof child.id === "string" && child.id ? "#" + child.id : (child.text ?? child.title ?? null)));
  return childList(list.map(child => key => schemaTree(child, key, budget, depth + 1)), keys, budget, depth);
}

const titleKeys = ["name", "title", "label", "id", "key", "név", "nev", "cím", "cim"];
function itemTitle(value) {
  if (!isPlainObject(value)) return null;
  for (const key of titleKeys) if (typeof value[key] === "string" || typeof value[key] === "number") return String(value[key]);
  return null;
}

function genericTree(value, label, key, budget, depth) {
  budget.count++;
  const title = label == null ? "" : "**" + escapeMarkdown(clip(label)) + "**";
  if (Array.isArray(value) || isPlainObject(value)) {
    const array = Array.isArray(value);
    const entries = array ? value.map((item, i) => [i, item]) : Object.entries(value);
    const heading = array && label != null ? title + " [" + value.length + "]" : title;
    if (!entries.length) return {key, text: (heading ? heading + "\n" : "") + (array ? "[ ]" : "{ }"), style: {}, layout: "auto"};
    const simple = entries.every(([, item]) => item === null || typeof item !== "object");
    const keys = array
      ? siblingKeys(value.map(item => item !== null && typeof item === "object" ? itemTitle(item) : JSON.stringify(item)))
      : entries.map(([name]) => "." + name);
    const item = {key, text: heading, style: {}, layout: simple ? "column" : "auto"};
    item.children = childList(entries.map(([name, child]) => childKey => {
      const childLabel = array ? itemTitle(child) ?? (child !== null && typeof child === "object" ? (name + 1) + "." : null) : name;
      return genericTree(child, childLabel, childKey, budget, depth + 1);
    }), keys, budget, depth);
    return item;
  }
  const text = title ? title + "\n" + formatValue(value) : formatValue(value);
  return {key, text, style: {alignment: title ? "left" : "center", ...(value === null ? {italic: true} : {})}, layout: "auto"};
}

// A forrásszövegből a fa; a gyökér a konténer maga (szövege a séma gyökerének szövege, általános értéknél null).
export function boxTree(source, format = "json") {
  const parse = formats[format];
  if (!parse) throw new StructureError("Ismeretlen forrásformátum: " + format);
  const value = parse(source);
  const budget = {count: 0, truncated: false};
  let root;
  const schema = isSchema(value);
  if (schema && Array.isArray(value)) root = {key: "", text: null, style: {}, layout: "auto", children: schemaChildren(value, budget, 0)};
  else if (schema) { root = schemaTree(value, "", budget, 0); budget.count--; }
  else {
    root = genericTree(value, null, "", budget, 0);
    budget.count--;
    if (!root.children) root = {key: "", text: null, style: {}, layout: "auto", children: [{...root, key: "value"}]};
    root.text = null;
  }
  return {root, schema, count: budget.count, truncated: budget.truncated};
}

// ---- Azonosítók és megőrzés ---------------------------------------------------------------------------------------

// Az elem doboz-mezői a forrásból és az alapértékekből (hely és méret nélkül).
function baseFields(item) {
  const leaf = !item.children?.length;
  return {fill: leaf ? leafFill : containerFill, textColor: ink, shape: "rounded", fontSize: leafFontSize,
    alignment: leaf ? "center" : "left", ...item.style};
}

// Azonosító és ujjlenyomat minden elemre; ha az előző generálásban már volt ilyen doboz, a kézi beállítások átkerülnek.
function resolve(item, containerId, path, previous) {
  for (const child of item.children ?? []) {
    const childPath = path + "/" + child.key;
    child.id = generatedId(containerId, childPath);
    child.signature = itemSignature(child);
    const fields = baseFields(child), before = previous?.get(child.id);
    if (before) {
      const unchanged = before.generated === child.signature;
      for (const field of keptFields) {
        // A forrásban megadott stílus változáskor a forrásé; minden más kézi beállítás marad.
        if (!unchanged && field in child.style) continue;
        if (field in before) fields[field] = before[field];
        else if (unchanged || !(field in child.style)) delete fields[field];
      }
      if (unchanged && typeof before.text === "string") child.text = before.text;
    }
    child.fields = fields;
    resolve(child, containerId, childPath, previous);
  }
}

// ---- Méretezés és elrendezés --------------------------------------------------------------------------------------

// Becsült szövegszélesség (a szerkesztő pontos mérése helyett; a doboz így bőven elfér).
function lineWidth(line, fontSize, bold) {
  const plain = line.replace(/\\(.)/g, "$1").replace(/\*\*/g, "");
  let width = 0;
  for (const letter of plain) width += /[iljtf.,:;'|!]/.test(letter) ? .3 : /[mwMW@]/.test(letter) ? .85 : /[A-ZÁÉÍÓÖŐÚÜŰ0-9]/.test(letter) ? .64 : .54;
  return width * fontSize * (bold ? 1.08 : 1);
}
function textBlock(text, fontSize, bold, width) {
  const lines = String(text ?? "").split("\n");
  const widths = lines.map(line => lineWidth(line, fontSize, bold || /^\*\*/.test(line)));
  const natural = Math.max(0, ...widths);
  const room = Math.max(20, width ?? natural);
  const rows = widths.reduce((sum, w) => sum + Math.max(1, Math.ceil(w / room)), 0);
  return {natural, height: (text ? rows : 0) * fontSize * lineFactor};
}

function measure(item) {
  const fontSize = item.fields.fontSize ?? leafFontSize, bold = !!item.fields.bold;
  if (!item.children?.length) {
    const natural = textBlock(item.text, fontSize, bold).natural;
    item.width ??= Math.min(300, Math.max(80, Math.ceil(natural + 32)));
    item.height ??= Math.max(40, Math.ceil(textBlock(item.text, fontSize, bold, item.width - 28).height + 22));
    return item;
  }
  for (const child of item.children) measure(child);
  const shape = item.fields.shape ?? "rounded";
  const widthRatio = labelWidthRatios[shape] ?? .94, heightRatio = labelHeightRatios[shape] ?? .94;
  const titleWidth = Math.ceil(Math.min(600, textBlock(item.text, fontSize, true).natural / widthRatio + 2 * pad + 8));
  item.rows = arrange(item.children, item.layout, titleWidth - 2 * pad);
  const innerWidth = Math.max(titleWidth - 2 * pad, ...item.rows.map(row => row.width));
  item.width ??= Math.min(sizeLimits.width[1], Math.ceil(innerWidth + 2 * pad));
  const body = item.rows.reduce((sum, row) => sum + row.height, 0) + gap * Math.max(0, item.rows.length - 1);
  // Fejléc: a címketerület eltolása (a magasság kimaradó arányának fele + 6), a cím, térköz. A magasság maga is a
  // fejléctől függ: h = fejléc + törzs + margó, ebből a fejléc zárt alakban.
  const k = (1 - heightRatio) / 2;
  const title = item.text ? textBlock(item.text, fontSize, true, item.width * widthRatio - 16).height : 0;
  const fixed = 6 + title + flowMargin + slack;
  item.header = !item.text ? pad : item.height != null ? Math.ceil(k * item.height + fixed) : Math.ceil((k * (body + pad) + fixed) / (1 - k));
  item.height ??= Math.min(sizeLimits.height[1], Math.max(40, Math.ceil(item.header + body + pad)));
  return item;
}

// Sorokba rendezés: oszlop (egymás alatt, egyforma szélesség), sor (egymás mellett), automatikus (polcos tördelés
// nagyjából kiegyensúlyozott, legfeljebb 1400 képpont széles sorokkal).
function arrange(children, layout, minimum) {
  if (layout === "column") {
    const width = Math.max(minimum, ...children.map(child => child.width));
    for (const child of children) if (!child.children?.length && child.width < width) child.width = width;
    return children.map(child => ({items: [child], width, height: child.height}));
  }
  const widest = Math.max(...children.map(child => child.width));
  const area = children.reduce((sum, child) => sum + (child.width + gap) * (child.height + gap), 0);
  const target = layout === "row" ? Infinity : Math.max(widest, minimum, Math.min(1400, Math.sqrt(area) * 1.5));
  const rows = [];
  let row = null;
  for (const child of children) {
    if (!row || (row.items.length && row.width + gap + child.width > target)) rows.push(row = {items: [], width: 0, height: 0});
    row.width += (row.items.length ? gap : 0) + child.width;
    row.height = Math.max(row.height, child.height);
    row.items.push(child);
  }
  return rows;
}

// Helyek kiosztása: a dobozok `position`-je a középpontjuk munkalap-koordinátában.
function place(item, left, top, parentId, out) {
  let y = top + (item.header ?? pad);
  for (const row of item.rows ?? []) {
    let x = left + pad;
    for (const child of row.items) {
      const leaf = !child.children?.length;
      out.push({id: child.id, type: "box", text: child.text ?? "", generated: child.signature, parent: parentId,
        position: {x: x + child.width / 2, y: y + child.height / 2}, width: child.width, height: child.height,
        ...child.fields, ...(leaf ? {} : {verticalAlignment: "top"})});
      if (!leaf) place(child, x, y, child.id, out);
      x += child.width + gap;
    }
    y += row.height + gap;
  }
}

// A konténer új tartalma: a generált dobozok (szülő előbb, mint a gyermeke), a konténer módosítása (méret, hely, séma
// gyökerénél szöveg és stílus). `container`: a konténer doboz (id, position, width, height, text, fontSize); a bal
// felső sarka a helyén marad. `previous`: Map azonosító → az előző generálás doboza (megőrzéshez).
export function generateBoxes(source, container, {format = "json", previous = new Map()} = {}) {
  const {root, schema, count, truncated} = boxTree(source, format);
  const rootText = root.text;
  resolve(root, container.id, "", previous);
  root.text = rootText ?? container.text ?? "";
  root.fields = {fontSize: root.style.fontSize ?? container.fontSize ?? 16, bold: root.style.bold, shape: root.style.shape ?? container.shape};
  measure(root);
  const width = Math.max(sizeLimits.width[0], root.width), height = Math.max(sizeLimits.height[0], root.height);
  const left = container.position.x - container.width / 2, top = container.position.y - container.height / 2;
  const nodes = [];
  place(root, left, top, container.id, nodes);
  const patch = {width, height, position: {x: left + width / 2, y: top + height / 2}, verticalAlignment: "top"};
  if (schema && rootText != null) Object.assign(patch, {text: rootText}, root.style);
  return {nodes, patch, schema, count, truncated};
}
