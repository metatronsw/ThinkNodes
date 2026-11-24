// Táblázat doboz fájlműveletei és párbeszédablaka (EXCEL.md 7. fejezet): új táblázat (üres / fájlból), letöltés.
// A feltöltött .csv önálló szöveges dokumentum; táblázat csak kifejezett kérésre készül belőle, és utána
// nincs kapcsolat a fájl és a táblázat között (független másolat).

import {storeAttachment} from "../canvas-files.js";
import {cellName, emptyTable, encodeTable, setCell, styleIndex} from "./table-document.js";
import {parseTSV} from "./table-clipboard.js";
import {parseInput} from "./table-format.js";
import {recalculate} from "./table-engine.js";

// Táblázattá alakítható kiterjesztések (első kör; a második körben xlsx, xls, ods).
export const importableExtensions = new Set(["csv", "tsv"]);
export const extensionOf = name => name.includes(".") ? name.split(".").pop().toLowerCase() : "";

async function failure(response, fallback) {
  const detail = await response.json().catch(() => ({}));
  return Error(detail.reason || fallback + " (" + response.status + ")");
}

// A táblázat doboz tulajdonságai a sor- és oszlopszám alapján.
export function tableBoxProperties({asset, filename, rows, cols}) {
  return {type: "table", file: {asset, filename, showFilename: true}, fontSize: 13,
    width: Math.round(Math.min(760, Math.max(240, 24 + cols * 80))), height: Math.round(Math.min(520, Math.max(140, 64 + Math.min(rows, 20) * 24)))};
}

// A lap egy mellékletéből (pl. .csv) új, független táblázat a szerveren.
export async function tableFromSource(path, csrf, from) {
  const response = await fetch("/api/table/" + path + "?from=" + encodeURIComponent(from), {method: "POST", headers: {"X-CSRF-Token": csrf}});
  if (!response.ok) throw await failure(response, "A táblázat létrehozása sikertelen");
  return response.json();
}

// Feltöltött (vagy máshonnan letöltött) fájlból új táblázat; maga a fájl nem tárolódik.
export async function tableFromUpload(path, csrf, blob, name) {
  if (blob.size > 12 * 1024 * 1024) throw Error("A fájl legfeljebb 12 MiB lehet.");
  const response = await fetch("/api/table/" + path + "?name=" + encodeURIComponent(name), {method: "POST",
    headers: {"X-CSRF-Token": csrf, "Content-Type": "application/octet-stream"}, body: blob});
  if (!response.ok) throw await failure(response, "A táblázat létrehozása sikertelen");
  return response.json();
}

// Új táblázatfájl feltöltése szabad néven ("Táblázat", "Táblázat 2", …).
export async function storeNewTable(path, csrf, doc, stem = "Táblázat") {
  for (let attempt = 1; attempt <= 50; attempt++) {
    const filename = (attempt === 1 ? stem : stem + " " + attempt) + ".tntable";
    try {
      const asset = await storeAttachment(new Blob([encodeTable(doc)], {type: "application/json"}), path, csrf, filename);
      return {asset, filename, rows: doc.size.rows, cols: doc.size.cols};
    } catch (error) {
      if (!/létezik|409/.test(error.message)) throw error;
    }
  }
  throw Error("Nem található szabad fájlnév a táblázatnak.");
}

export async function createEmptyTable(path, csrf) {
  return storeNewTable(path, csrf, emptyTable("Táblázat", 10, 5));
}

// Beillesztett TSV (Excelből másolt tartomány) → új táblázat. Képlet nem jön át, az "=" kezdetű szöveg szöveg marad.
export async function createTableFromTSV(path, csrf, text) {
  const rows = parseTSV(text).slice(0, 1000);
  const cols = Math.min(100, Math.max(...rows.map(row => row.length)));
  const doc = emptyTable("Beillesztett táblázat", Math.max(1, rows.length), Math.max(1, cols));
  rows.forEach((row, r) => row.slice(0, 100).forEach((field, c) => {
    const parsed = parseInput(field);
    if (parsed.kind === "empty") return;
    const cell = {};
    if (parsed.kind === "formula") cell.v = field.trim();
    else {
      cell.v = parsed.value;
      if (parsed.format) cell.s = styleIndex(doc, {fmt: parsed.format});
    }
    setCell(doc, cellName(r, c), cell);
  }));
  recalculate(doc);
  return storeNewTable(path, csrf, doc, "Beillesztett táblázat");
}

export const exportURL = (path, name, format = "csv") =>
  "/api/table-export/" + path + "?name=" + encodeURIComponent(name) + "&format=" + format;

// MARK: Párbeszédablakok (natív <dialog>, a file-browser.js mintájára)

function element(tag, text, attrs = {}) {
  const item = document.createElement(tag);
  Object.assign(item, attrs);
  if (text) item.textContent = text;
  return item;
}

function dialogShell(title) {
  const dialog = element("dialog", "", {className: "panel table-dialog"});
  dialog.setAttribute("aria-label", title);
  dialog.append(element("h3", title));
  document.body.append(dialog);
  return dialog;
}

// Új táblázat: {mode: "empty"} | {mode: "upload", file} | {mode: "browse"} | {mode: "link"} vagy null (Mégse).
export function askNewTable() {
  return new Promise(resolve => {
    const dialog = dialogShell("Új táblázat");
    let result = null;
    const options = element("div", "", {className: "stack table-dialog-options"});
    const empty = element("button", "Üres táblázat (5 × 10)", {type: "button", className: "button primary"});
    empty.addEventListener("click", () => { result = {mode: "empty"}; dialog.close(); });
    const browse = element("button", "Önálló másolat egy projektfájlból (CSV, TSV)…", {type: "button", className: "button"});
    browse.addEventListener("click", () => { result = {mode: "browse"}; dialog.close(); });
    const input = element("input", "", {type: "file", accept: [...importableExtensions].map(ext => "." + ext).join(","), hidden: true});
    const upload = element("button", "Önálló másolat a gépről (CSV, TSV)…", {type: "button", className: "button"});
    upload.addEventListener("click", () => input.click());
    input.addEventListener("change", () => { if (input.files?.[0]) { result = {mode: "upload", file: input.files[0]}; dialog.close(); } });
    const link = element("button", "Linkelt táblázat egy dokumentumhoz (CSV, TSV)…", {type: "button", className: "button"});
    link.addEventListener("click", () => { result = {mode: "link"}; dialog.close(); });
    options.append(empty, browse, upload, link, input);
    const cancel = element("button", "Mégse", {type: "button", className: "button"});
    cancel.addEventListener("click", () => dialog.close());
    dialog.append(options, cancel);
    dialog.addEventListener("close", () => { dialog.remove(); resolve(result); });
    dialog.showModal();
    empty.focus();
  });
}
