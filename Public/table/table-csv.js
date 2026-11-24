// CSV/TSV a böngészőben (EXCEL.md): elválasztó-felismerés és mezőbontás (a CSV-szövegnézethez és a beillesztéshez).
// Swift párja: Sources/ThinkTable/TableCSV.swift. A CSV önálló szöveges dokumentum; táblázat csak importtal készül belőle.

import {cellName, emptyTable, setCell, styleIndex, styleOf} from "./table-document.js";
import {display, general, parseInput} from "./table-format.js";
import {recalculate} from "./table-engine.js";

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
