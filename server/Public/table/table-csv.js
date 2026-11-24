// CSV/TSV a böngészőben (docs/EXCEL.md): elválasztó-felismerés és mezőbontás (a CSV-szövegnézethez és a beillesztéshez).
// Swift párja: Sources/ThinkTable/TableCSV.swift. A CSV önálló szöveges dokumentum; táblázat csak importtal készül belőle.

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

// Teljes CSV → sorok (mezők szövege), a közvetlen cellaszerkesztéshez (editor.js). Az idézőjelezés a szokásos (RFC 4180).
// `newline`: a fájlban használt sorvég; `trailing`: a fájl sorvéggel zárul-e (a kiírás ezeket megőrzi).
export function parseCSVRows(text, separator = ",") {
  const rows = [];
  let row = [], field = "", quoted = false, wasQuoted = false;
  const newline = /\r\n/.test(text) ? "\r\n" : /\r(?!\n)/.test(text) && !text.includes("\n") ? "\r" : "\n";
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === "\"") { if (text[i + 1] === "\"") { field += "\""; i++; } else quoted = false; }
      else field += c;
    } else if (c === "\"" && !field && !wasQuoted) { quoted = true; wasQuoted = true; }
    else if (c === separator) { row.push(field); field = ""; wasQuoted = false; }
    else if (isNewline(c)) {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field); field = ""; wasQuoted = false; rows.push(row); row = [];
    } else field += c;
  }
  const trailing = !(field || row.length || wasQuoted);
  if (!trailing) { row.push(field); rows.push(row); }
  return {rows, newline, trailing: trailing && text.length > 0};
}

// Sorok → CSV-szöveg. Idézőjelbe kerül a mező, ha elválasztót, idézőjelet vagy sorvéget tartalmaz.
export function writeCSVRows(rows, separator = ",", {newline = "\n", trailing = true} = {}) {
  const quote = text => text.includes(separator) || /["\r\n]/.test(text) ? "\"" + text.replace(/"/g, "\"\"") + "\"" : text;
  const body = rows.map(row => row.map(quote).join(separator)).join(newline);
  return body + (trailing && rows.length ? newline : "");
}
