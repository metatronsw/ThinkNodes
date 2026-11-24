// CSV/TSV ↔ táblázat a böngészőben (EXCEL.md). Swift párja: Sources/ThinkTable/TableCSV.swift.
// Dokumentumhoz linkelt táblázat: a CSV maga a táblázat. Beolvasáskor a `=` kezdetű mező képlet; mentéskor a cellák
// a beírt alakjukban (képlet "=…", formázott szám pl. "1 200 Ft", "12%") íródnak vissza, a formázás (szín, keret) nem.

import {cellName, emptyTable, setCell, styleIndex, styleOf} from "./table-document.js";
import {display, general, parseInput} from "./table-format.js";
import {recalculate} from "./table-engine.js";

export const linkableExtensions = new Set(["csv", "tsv"]);
const isNewline = ch => ch === "\n" || ch === "\r";

// Elválasztó: tsv-nél tabulátor, egyébként az első sor (idézőjelen kívül) leggyakoribb jele; döntetlennél , ; tab sorrend.
export function detectSeparator(text, ext) {
  if (ext.toLowerCase() === "tsv") return "\t";
  const candidates = [",", ";", "\t"], counts = [0, 0, 0];
  let quoted = false;
  for (const ch of text) {
    if (ch === "\"") quoted = !quoted;
    else if (!quoted && isNewline(ch)) break;
    else if (!quoted && candidates.includes(ch)) counts[candidates.indexOf(ch)]++;
  }
  let best = 0;
  for (let i = 1; i < 3; i++) if (counts[i] > counts[best]) best = i;
  return counts[best] > 0 ? candidates[best] : ",";
}

// Mezők soronként (idézőjeles mezők, "" escape, CRLF egy sorvége – mint a Swift grafémaként).
export function csvRows(text, separator, limit = 1001) {
  const rows = [];
  let row = [], field = "", quoted = false, started = false;
  const chars = [...text];
  for (let i = 0; i < chars.length && rows.length < limit; i++) {
    const ch = chars[i];
    if (quoted) {
      if (ch === "\"") {
        if (chars[i + 1] === "\"") { field += "\""; i++; } else quoted = false;
      } else field += ch;
      continue;
    }
    if (ch === "\"" && !started) { quoted = true; started = true; }
    else if (ch === separator) { row.push(field); field = ""; started = false; }
    else if (isNewline(ch)) {
      if (ch === "\r" && chars[i + 1] === "\n") i++;
      row.push(field); rows.push(row); row = []; field = ""; started = false;
    } else { field += ch; started = true; }
  }
  if (started || row.length) { row.push(field); rows.push(row); }
  while (rows.length && rows[rows.length - 1].every(cell => !cell)) rows.pop();
  return rows;
}

// CSV → táblázat (a Swift TableCSV.importCSV párja). `formulas`: a "=" kezdetű mező képlet (linkelt táblázat).
export function importCSV(text, name, ext = "csv", {formulas = false} = {}) {
  if (text.startsWith("﻿")) text = text.slice(1);
  const separator = detectSeparator(text, ext);
  const parsed = csvRows(text, separator);
  const doc = emptyTable(name, 1, 1);
  const usedRows = Math.min(parsed.length, 1000);
  const usedCols = Math.min(Math.max(1, ...parsed.map(row => row.length)), 100);
  parsed.slice(0, 1000).forEach((fields, r) => fields.slice(0, 100).forEach((field, c) => {
    const input = parseInput(field);
    if (input.kind === "empty") return;
    const cell = {};
    if (input.kind === "formula") { if (formulas) cell.f = input.formula; else cell.v = field.trim(); }
    else {
      cell.v = input.value;
      if (input.format) cell.s = styleIndex(doc, {fmt: input.format});
    }
    setCell(doc, cellName(r, c), cell);
  }));
  doc.size = {rows: Math.max(usedRows, 1), cols: Math.max(usedCols, 1)};
  if (usedRows > 1) {
    const first = [], second = [];
    for (let c = 0; c < usedCols; c++) {
      const a = doc.cells[cellName(0, c)], b = doc.cells[cellName(1, c)];
      if (a?.v != null) first.push(a.v);
      if (b?.v != null) second.push(b.v);
    }
    const allText = first.length && first.every(v => typeof v === "string")
      && Array.from({length: usedCols}, (_, c) => doc.cells[cellName(0, c)]?.f == null).every(Boolean);
    if (allText && second.some(v => typeof v === "number")) {
      doc.header = {rows: 1, cols: 0};
      for (let c = 0; c < usedCols; c++) {
        const name = cellName(0, c), cell = doc.cells[name];
        if (cell) setCell(doc, name, {...cell, s: styleIndex(doc, {...styleOf(doc, cell), b: 1})});
      }
    }
  }
  return {doc, separator, eol: /\r\n/.test(text) ? "\r\n" : "\n"};
}

// Linkelt táblázat: CSV → kiszámolt táblázat, a visszaíráshoz szükséges jellemzőkkel (elválasztó, sorvége, BOM).
export function linkedTable(text, name, ext) {
  const bom = text.startsWith("﻿");
  const {doc, separator, eol} = importCSV(text, name, ext, {formulas: true});
  recalculate(doc);
  doc.linked = {separator, eol, bom};
  return doc;
}

// Táblázat → CSV a beírt alakban. Vesszős CSV-ben a sima számok tizedesponttal, egyébként tizedesvesszővel íródnak.
export function linkedCSV(doc) {
  const {separator = ",", eol = "\n", bom = false} = doc.linked ?? {};
  let rows = 0, cols = 0;
  for (const name of Object.keys(doc.cells)) {
    const match = /^([A-Z]+)(\d+)$/.exec(name);
    if (!match) continue;
    const col = [...match[1]].reduce((n, ch) => n * 26 + ch.charCodeAt(0) - 64, 0);
    rows = Math.max(rows, Number(match[2])); cols = Math.max(cols, col);
  }
  const quote = text => text.includes(separator) || /["\r\n]/.test(text) || /^\s|\s$/.test(text) ? "\"" + text.replace(/"/g, "\"\"") + "\"" : text;
  const lines = [];
  for (let r = 0; r < rows; r++) {
    const fields = [];
    for (let c = 0; c < cols; c++) {
      const cell = doc.cells[cellName(r, c)];
      let text = "";
      if (cell?.f != null) text = "=" + cell.f;
      else if (typeof cell?.v === "number") {
        const fmt = styleOf(doc, cell).fmt;
        text = fmt ? display(cell.v, fmt).replace(/ /g, " ") : separator === "," ? String(cell.v) : general(cell.v);
      } else if (typeof cell?.v === "string") {
        // Ha a szöveg számnak vagy képletnek látszana, ' elé kerül (beolvasáskor szöveg marad).
        const input = parseInput(cell.v);
        text = input.kind === "value" && typeof input.value === "string" ? cell.v : "'" + cell.v;
      } else if (cell?.v != null) text = display(cell.v, null);
      fields.push(quote(text));
    }
    lines.push(fields.join(separator));
  }
  return (bom ? "﻿" : "") + lines.join(eol) + (lines.length ? eol : "");
}
