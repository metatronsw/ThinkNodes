// Táblázat vágólap: TSV és HTML (docs/EXCEL.md 6. fejezet). Excelbe / Numbersbe másolható, onnan beilleszthető.

import {display} from "./table-format.js";
import {cellName, styleOf} from "./table-document.js";

export const tableMime = "application/x-thinknodes-table";

// TSV-mezők: tabulátor és sorvége, idézőjeles mezőben sortörés is lehet (Excel-másolat).
export function parseTSV(text) {
  const rows = [];
  let row = [], field = "", quoted = false, started = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === "\"") {
        if (text[i + 1] === "\"") { field += "\""; i++; } else quoted = false;
      } else field += ch;
      continue;
    }
    if (ch === "\"" && !started) { quoted = true; started = true; }
    else if (ch === "\t") { row.push(field); field = ""; started = false; }
    else if (ch === "\r" || ch === "\n") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      row.push(field); rows.push(row); row = []; field = ""; started = false;
    } else { field += ch; started = true; }
  }
  if (started || row.length) { row.push(field); rows.push(row); }
  while (rows.length && rows[rows.length - 1].every(cell => !cell)) rows.pop();
  return rows;
}

// Táblázatnak tűnik-e a beillesztett szöveg (legalább 2 sor × 2 oszlop, tabulátorral).
export function looksTabular(text) {
  if (!text.includes("\t") || !/[\r\n]/.test(text.trim())) return false;
  const rows = parseTSV(text);
  return rows.length >= 2 && rows.filter(row => row.length >= 2).length >= 2;
}

const escapeHTML = text => String(text).replace(/[&<>"']/g, ch => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"})[ch]);

// Kijelölés → {tsv, html, json}. A json a saját formátum (képletekkel, stílusokkal), a többi az értékeket viszi.
export function copySelection(doc, sel) {
  const lines = [], htmlRows = [], cells = [];
  for (let r = sel.r0; r <= sel.r1; r++) {
    const fields = [], htmlCells = [], rowCells = [];
    for (let c = sel.c0; c <= sel.c1; c++) {
      const cell = doc.cells[cellName(r, c)];
      const style = styleOf(doc, cell);
      const text = display(cell?.v, style.fmt);
      fields.push(/[\t\n\r"]/.test(text) ? "\"" + text.replace(/"/g, "\"\"") + "\"" : text);
      const css = [style.b && "font-weight:bold", style.i && "font-style:italic",
        (style.u || style.o) && "text-decoration:" + [style.u && "underline", style.o && "overline"].filter(Boolean).join(" "),
        style.color && "color:" + style.color, style.fill && "background:" + style.fill].filter(Boolean).join(";");
      htmlCells.push("<td" + (css ? " style=\"" + escapeHTML(css) + "\"" : "") + ">" + escapeHTML(text) + "</td>");
      rowCells.push(cell ? {...cell, style: cell.s ? style : undefined, s: undefined} : null);
    }
    lines.push(fields.join("\t"));
    htmlRows.push("<tr>" + htmlCells.join("") + "</tr>");
    cells.push(rowCells);
  }
  return {
    tsv: lines.join("\n"),
    html: "<table>" + htmlRows.join("") + "</table>",
    json: JSON.stringify({format: "thinknodes-table-clip", origin: {row: sel.r0, col: sel.c0}, cells}),
  };
}

// HTML-táblázat (Excel, Numbers, weboldal) → cellák szövege és alapstílusa. DOMParser kell (böngésző).
export function parseHTMLTable(html) {
  if (typeof DOMParser === "undefined") return null;
  const table = new DOMParser().parseFromString(html, "text/html").querySelector("table");
  if (!table) return null;
  const rows = [];
  for (const tr of table.querySelectorAll("tr")) {
    const row = [];
    for (const td of tr.querySelectorAll("td,th")) {
      const style = {}, css = td.style;
      const weight = css.fontWeight;
      if (td.tagName === "TH" || weight === "bold" || Number(weight) >= 600 || td.querySelector("b,strong")) style.b = 1;
      if (css.fontStyle === "italic" || td.querySelector("i,em")) style.i = 1;
      const decoration = css.textDecoration || css.textDecorationLine || "";
      if (decoration.includes("underline") || td.querySelector("u")) style.u = 1;
      if (decoration.includes("overline")) style.o = 1;
      const color = cssHex(css.color), fill = cssHex(css.backgroundColor || css.background);
      if (color && color !== "#000000") style.color = color;
      if (fill && fill !== "#ffffff") style.fill = fill;
      row.push({text: td.innerText ?? td.textContent ?? "", style});
      for (let span = Number(td.colSpan) || 1; span > 1; span--) row.push({text: "", style: {}});
    }
    rows.push(row);
  }
  return rows.length ? rows : null;
}

// CSS-szín → #rrggbb (rgb(), #rgb, #rrggbb); egyébként null.
export function cssHex(value) {
  if (!value) return null;
  const hex = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(value.trim());
  if (hex) return "#" + (hex[1].length === 3 ? [...hex[1]].map(ch => ch + ch).join("") : hex[1]).toLowerCase();
  const rgb = /rgba?\(\s*(\d+)[ ,]+(\d+)[ ,]+(\d+)(?:[ ,/]+([\d.]+))?/i.exec(value);
  if (!rgb || (rgb[4] != null && Number(rgb[4]) === 0)) return null;
  return "#" + rgb.slice(1, 4).map(n => Math.min(255, Number(n)).toString(16).padStart(2, "0")).join("");
}
