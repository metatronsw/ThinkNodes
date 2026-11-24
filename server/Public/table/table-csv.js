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
