// Táblázat doboz fájlműveletei és párbeszédablakai (EXCEL.md 7. fejezet):
// rákérdezés feltöltéskor, új táblázat (üres / forrásfájlból), forrásfájl figyelése és újraolvasása, letöltés.

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

// Forrásfájlból (a lap melléklete) táblázat a szerveren; `replace`: meglévő táblázat újraolvasása.
export async function tableFromSource(path, csrf, from, {name = null, replace = false} = {}) {
  const query = "?from=" + encodeURIComponent(from) + (name ? "&name=" + encodeURIComponent(name) : "") + (replace ? "&replace=1" : "");
  const response = await fetch("/api/table/" + path + query, {method: "POST", headers: {"X-CSRF-Token": csrf}});
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

// Megváltozott-e a forrásfájl az import óta: {source, changed, missing, edited}.
export async function sourceStatus(path, name) {
  const response = await fetch("/api/table-source/" + path + "?name=" + encodeURIComponent(name));
  if (!response.ok) return null;
  return response.json();
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

// Feltöltéskor: táblázat legyen, vagy fájl maradjon. {choice: "table" | "file", remember} vagy null (Mégse).
export function askTableImport(filename, multiple = false) {
  return new Promise(resolve => {
    const dialog = dialogShell("Táblázat vagy fájl?");
    dialog.append(element("p", "„" + filename + "” táblázatként is beolvasható."));
    const options = element("div", "", {className: "stack table-dialog-options"});
    const choose = choice => { result = {choice, remember: remember?.checked ?? false}; dialog.close(); };
    const tableButton = element("button", "Táblázat – szerkeszthető, számol", {type: "button", className: "button primary"});
    tableButton.addEventListener("click", () => choose("table"));
    const fileButton = element("button", "Fájl – ahogy eddig (" + (["csv", "tsv"].includes(extensionOf(filename)) ? "csak olvasható nézet" : "letöltés") + ")",
      {type: "button", className: "button"});
    fileButton.addEventListener("click", () => choose("file"));
    options.append(tableButton, fileButton);
    dialog.append(options);
    let remember = null;
    if (multiple) {
      const label = element("label", "", {className: "table-dialog-remember"});
      remember = element("input", "", {type: "checkbox"});
      label.append(remember, document.createTextNode(" A többi fájlra is ugyanezt"));
      dialog.append(label);
    }
    const cancel = element("button", "Mégse", {type: "button", className: "button"});
    cancel.addEventListener("click", () => dialog.close());
    dialog.append(cancel);
    let result = null;
    dialog.addEventListener("close", () => { dialog.remove(); resolve(result); });
    dialog.showModal();
    tableButton.focus();
  });
}

// Új táblázat: {mode: "empty"} | {mode: "upload", file} | {mode: "browse"} vagy null (Mégse).
export function askNewTable() {
  return new Promise(resolve => {
    const dialog = dialogShell("Új táblázat");
    let result = null;
    const options = element("div", "", {className: "stack table-dialog-options"});
    const empty = element("button", "Üres táblázat (5 × 10)", {type: "button", className: "button primary"});
    empty.addEventListener("click", () => { result = {mode: "empty"}; dialog.close(); });
    const browse = element("button", "Forrásfájl a projektből…", {type: "button", className: "button"});
    browse.addEventListener("click", () => { result = {mode: "browse"}; dialog.close(); });
    const input = element("input", "", {type: "file", accept: [...importableExtensions].map(ext => "." + ext).join(","), hidden: true});
    const upload = element("button", "Forrásfájl feltöltése a gépről (CSV, TSV)…", {type: "button", className: "button"});
    upload.addEventListener("click", () => input.click());
    input.addEventListener("change", () => { if (input.files?.[0]) { result = {mode: "upload", file: input.files[0]}; dialog.close(); } });
    options.append(empty, browse, upload, input);
    const cancel = element("button", "Mégse", {type: "button", className: "button"});
    cancel.addEventListener("click", () => dialog.close());
    dialog.append(options, cancel);
    dialog.addEventListener("close", () => { dialog.remove(); resolve(result); });
    dialog.showModal();
    empty.focus();
  });
}
