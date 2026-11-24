// Táblázat doboz adatmodellje (docs/EXCEL.md 3. fejezet). Swift párja: Sources/ThinkTable/TableDocument.swift.
// A fájl (`.tntable`) JSON; a cellák ritkán, "A1" kulccsal, a stílusok indexelve.

export const limits = {maxRows: 1000, maxCols: 100, maxCells: 50000, maxBytes: 5 * 1024 * 1024};

export function columnName(col) {
  let n = col + 1, result = "";
  while (n > 0) { const r = (n - 1) % 26; result = String.fromCharCode(65 + r) + result; n = Math.floor((n - 1) / 26); }
  return result;
}

export function columnIndex(letters) {
  let value = 0;
  for (const ch of letters.toUpperCase()) {
    const code = ch.charCodeAt(0);
    if (code < 65 || code > 90) return null;
    value = value * 26 + (code - 64);
    if (value > 16384) return null;
  }
  return value > 0 ? value - 1 : null;
}

export const cellName = (row, col) => columnName(col) + (row + 1);

export function parseAddress(name) {
  const match = /^([A-Za-z]{1,3})([1-9][0-9]*)$/.exec(name);
  if (!match) return null;
  const col = columnIndex(match[1]);
  return col == null ? null : {row: Number(match[2]) - 1, col};
}

export function newTableID() {
  return "tbl-" + (crypto.randomUUID?.() ?? Math.random().toString(16).slice(2) + "00000000").slice(0, 8).toLowerCase();
}

export function emptyTable(name = null, rows = 10, cols = 5) {
  const doc = {format: "thinknodes-table", version: 1, id: newTableID(), size: {rows, cols}, grid: true, styles: [{}], cells: {}};
  if (name) doc.name = name;
  return doc;
}

// Beolvasás és ellenőrzés (a Swift TableDocument.decode párja). Hibás fájlra kivételt dob.
export function decodeTable(text) {
  if (text.length > limits.maxBytes) throw Error("A táblázat túl nagy.");
  const doc = JSON.parse(text);
  if (doc?.format !== "thinknodes-table" || !(doc.version >= 1)) throw Error("Ismeretlen táblázatformátum.");
  doc.cells ??= {};
  doc.styles = Array.isArray(doc.styles) && doc.styles.length ? doc.styles : [{}];
  doc.size ??= {rows: 1, cols: 1};
  doc.size.rows = Math.min(Math.max(doc.size.rows | 0, 1), limits.maxRows);
  doc.size.cols = Math.min(Math.max(doc.size.cols | 0, 1), limits.maxCols);
  for (const key of Object.keys(doc.cells)) {
    const address = parseAddress(key);
    if (!address || address.row >= limits.maxRows || address.col >= limits.maxCols) throw Error("Érvénytelen cellacím: " + key);
    doc.size.rows = Math.max(doc.size.rows, address.row + 1);
    doc.size.cols = Math.max(doc.size.cols, address.col + 1);
  }
  return doc;
}

// Kulcsok rendezve, mint a Swift JSONEncoder .sortedKeys: a fájl tartalma így mindkét oldalon azonos alakú.
export function encodeTable(doc) {
  const sorted = value => Array.isArray(value) ? value.map(sorted)
    : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
  return JSON.stringify(sorted(doc));
}

export const styleOf = (doc, cell) => doc.styles[cell?.s ?? 0] ?? {};

// Stílus indexe; ha még nincs ilyen, hozzáadja. Az üres mezők nem számítanak.
export function styleIndex(doc, style) {
  const clean = cleanStyle(style);
  const key = encodeTable(clean);
  if (key === "{}") return 0;
  const index = doc.styles.findIndex(existing => encodeTable(cleanStyle(existing)) === key);
  if (index >= 0) return index;
  doc.styles.push(clean);
  return doc.styles.length - 1;
}

export function cleanStyle(style) {
  const result = {};
  for (const [key, value] of Object.entries(style ?? {})) {
    if (value == null || value === false || value === 0 && ["b", "i", "u", "o"].includes(key)) continue;
    if (key === "border") {
      const border = Object.fromEntries(Object.entries(value).filter(([, line]) => line && line.w > 0));
      if (Object.keys(border).length) result.border = border;
      continue;
    }
    result[key] = ["b", "i", "u", "o"].includes(key) ? 1 : value;
  }
  return result;
}

export function setCell(doc, name, cell) {
  const empty = !cell || (cell.v == null && cell.f == null && !(cell.s > 0) && cell.fx == null);
  if (empty) delete doc.cells[name];
  else {
    const clean = {};
    for (const key of ["f", "fx", "s", "v"]) if (cell[key] != null && !(key === "s" && cell[key] === 0)) clean[key] = cell[key];
    doc.cells[name] = clean;
  }
}
