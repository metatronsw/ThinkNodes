// Táblázat szerkesztési mód: kijelölés, beírás, formázás, sor/oszlop, vágólap, visszavonás (EXCEL.md 6. fejezet).
// DOM nélküli vezérlő; a nézet (table-view.js) rajzolja, az editor.js menti. Node-ban is tesztelhető.

import {cellName, columnName, limits, parseAddress, setCell, styleIndex, styleOf} from "./table-document.js";
import {display, parseInput, precise} from "./table-format.js";
import {move, shift} from "./table-formula.js";
import {recalculate} from "./table-engine.js";
import {copySelection, parseTSV} from "./table-clipboard.js";

const clamp = (value, low, high) => Math.max(low, Math.min(high, value));

export class TableEditor {
  // doc: a táblázat munkapéldánya (a vezérlő módosítja); onChange(doc): mentéskor hívódik.
  constructor(doc, {onChange = () => {}} = {}) {
    this.doc = doc;
    this.onChange = onChange;
    this.active = {r: 0, c: 0};
    this.anchor = {r: 0, c: 0};
    this.draft = null;        // szerkesztett cella nyers szövege (null: nincs cellaszerkesztés)
    this.undoStack = [];
    this.redoStack = [];
    this.version = 0;         // a nézet ebből tudja, hogy újra kell rajzolni
  }

  get sel() {
    return {r0: Math.min(this.active.r, this.anchor.r), r1: Math.max(this.active.r, this.anchor.r),
      c0: Math.min(this.active.c, this.anchor.c), c1: Math.max(this.active.c, this.anchor.c)};
  }

  get activeName() { return cellName(this.active.r, this.active.c); }

  *selectedNames() {
    const {r0, r1, c0, c1} = this.sel;
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) yield cellName(r, c);
  }

  touch() { this.version++; }

  // A cella szerkeszthető nyers szövege: képletnél "=…", számnál teljes pontosságú alak (15 értékes jegy) a formátum
  // jelével (%, pénznem), dátumnál a dátum. A kerekített kiírás nem kerülhet ide: F2+Enter után elveszne a pontosság.
  rawText(name) {
    const cell = this.doc.cells[name];
    if (!cell) return "";
    if (cell.f != null) return "=" + cell.f;
    const v = cell.v, fmt = styleOf(this.doc, cell).fmt;
    if (typeof v === "number") {
      if (fmt?.kind === "date") return display(v, fmt).replace(/\u00a0/g, " ");
      if (fmt?.kind === "percent") return precise(v * 100) + "%";
      if (fmt?.kind === "currency") return fmt.before ? (fmt.symbol ?? "Ft") + " " + precise(v) : precise(v) + " " + (fmt.symbol ?? "Ft");
      return precise(v);
    }
    if (typeof v === "string") return parseInput(v).kind === "value" && typeof parseInput(v).value === "string" ? v : "'" + v;
    return display(v, null);
  }

  // MARK: Kijelölés

  select(r, c, extend = false) {
    this.commitDraft();
    // A széle fölé lépve a táblázat bővül (Enter / nyíl az utolsó soron, oszlopon), a korlátokon belül.
    r = clamp(r, 0, limits.maxRows - 1); c = clamp(c, 0, limits.maxCols - 1);
    if (r >= this.doc.size.rows) this.doc.size.rows = r + 1;
    if (c >= this.doc.size.cols) this.doc.size.cols = c + 1;
    this.active = {r, c};
    if (!extend) this.anchor = {...this.active};
    this.touch();
  }

  selectRow(r, extend = false) {
    this.commitDraft();
    this.anchor = extend ? {r: this.anchor.r, c: 0} : {r, c: 0};
    this.active = {r, c: this.doc.size.cols - 1};
    this.touch();
  }

  selectColumn(c, extend = false) {
    this.commitDraft();
    this.anchor = extend ? {r: 0, c: this.anchor.c} : {r: 0, c};
    this.active = {r: this.doc.size.rows - 1, c};
    this.touch();
  }

  moveBy(dr, dc, extend = false) {
    this.select(this.active.r + dr, this.active.c + dc, extend);
  }

  // Ctrl+nyíl: a következő kitöltött/üres határig (Excel).
  jump(dr, dc, extend = false) {
    const filled = (r, c) => this.doc.cells[cellName(r, c)]?.v != null || this.doc.cells[cellName(r, c)]?.f != null;
    let {r, c} = this.active;
    const inside = (r, c) => r >= 0 && c >= 0 && r < this.doc.size.rows && c < this.doc.size.cols;
    const startFilled = filled(r, c) && inside(r + dr, c + dc) && filled(r + dr, c + dc);
    while (inside(r + dr, c + dc)) {
      r += dr; c += dc;
      if (startFilled ? !inside(r + dr, c + dc) || !filled(r + dr, c + dc) : filled(r, c)) break;
    }
    this.select(r, c, extend);
  }

  // MARK: Beírás

  startDraft(text = null) {
    this.draft = text ?? this.rawText(this.activeName);
    // Változatlan vázlat (F2 / dupla kattintás, majd Enter) nem írja felül a cellát: így a 15 jegyen túli pontosság
    // és a beírt alak sem vész el (audit, 2026-11-24).
    this.draftOriginal = text == null ? this.draft : null;
    this.touch();
  }

  setDraft(text) { this.draft = text; this.touch(); }

  cancelDraft() { this.draft = null; this.touch(); }

  // Képletírás közben kattintott cella hivatkozásként a képletbe kerül.
  insertReference(r, c, r1 = r, c1 = c) {
    if (this.draft == null || !this.draft.startsWith("=")) return false;
    const ref = cellName(Math.min(r, r1), Math.min(c, c1)) + (r1 !== r || c1 !== c ? ":" + cellName(Math.max(r, r1), Math.max(c, c1)) : "");
    this.draft = this.draft.replace(/\$?[A-Z]{1,3}\$?\d+(:\$?[A-Z]{1,3}\$?\d+)?$/i, "") + ref;
    this.touch();
    return true;
  }

  // Képletírás közben a vezérlő eldönti, hogy egy kattintás hivatkozás-beszúrás legyen-e: igen, ha a képlet
  // operátorra, nyitó zárójelre, elválasztóra vagy már egy hivatkozásra végződik.
  get pointing() {
    return this.draft != null && this.draft.startsWith("=") && /([=+\-*/^&(;,<>:]|\$?[A-Z]{1,3}\$?\d+)$/i.test(this.draft.trimEnd());
  }

  commitDraft() {
    if (this.draft == null) return false;
    const text = this.draft;
    this.draft = null;
    if (text === this.draftOriginal) { this.touch(); return true; }
    this.setInput(this.activeName, text);
    return true;
  }

  // Egy cella beírt szövege → érték vagy képlet; a felismert formátum a cella stílusába kerül, ha még nincs.
  setInput(name, text, {record = true} = {}) {
    if (record) this.record();
    const cell = {...(this.doc.cells[name] ?? {})};
    delete cell.f; delete cell.v; delete cell.fx;
    const parsed = parseInput(text);
    if (parsed.kind === "formula") cell.f = parsed.formula;
    else if (parsed.kind === "value") {
      cell.v = parsed.value;
      const style = styleOf(this.doc, cell);
      if (parsed.format && !style.fmt) cell.s = styleIndex(this.doc, {...style, fmt: parsed.format});
    }
    setCell(this.doc, name, cell);
    if (record) this.changed([name]);
  }

  clearSelection() {
    this.record();
    const names = [...this.selectedNames()];
    for (const name of names) {
      const cell = this.doc.cells[name];
      if (cell) setCell(this.doc, name, {s: cell.s});
    }
    this.changed(names);
  }

  // MARK: Formázás

  styleSelection(update) {
    this.commitDraft();
    this.record();
    for (const name of this.selectedNames()) {
      const cell = {...(this.doc.cells[name] ?? {})};
      cell.s = styleIndex(this.doc, update({...styleOf(this.doc, cell)}));
      setCell(this.doc, name, cell);
    }
    this.changed([]);
  }

  // B / I / U / O: ha a kijelölés minden cellája be van kapcsolva, kikapcsol; különben bekapcsol.
  toggle(key) {
    const on = [...this.selectedNames()].every(name => styleOf(this.doc, this.doc.cells[name])[key]);
    this.styleSelection(style => ({...style, [key]: on ? undefined : 1}));
  }

  isOn(key) { return [...this.selectedNames()].every(name => styleOf(this.doc, this.doc.cells[name])[key]); }

  activeStyle() { return styleOf(this.doc, this.doc.cells[this.activeName]); }

  setStyle(key, value) { this.styleSelection(style => ({...style, [key]: value ?? undefined})); }

  // Tizedesjegy −/+ : a számformátum `dec` mezője (általános formátumból 2 tizedes számformátum lesz).
  stepDecimals(delta) {
    this.styleSelection(style => {
      const fmt = style.fmt && !["general", "date", "text", "fraction"].includes(style.fmt.kind)
        ? {...style.fmt} : {kind: "number", dec: 2, group: true};
      fmt.dec = clamp((fmt.dec ?? 2) + delta, 0, 10);
      return {...style, fmt};
    });
  }

  // Keret: mode = all | outer | none | top | bottom | left | right | innerH | innerV; line = {w, color, style}.
  border(mode, line = {w: 1, color: "#000000", style: "solid"}) {
    const {r0, r1, c0, c1} = this.sel;
    this.commitDraft();
    this.record();
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) {
      const name = cellName(r, c);
      const cell = {...(this.doc.cells[name] ?? {})};
      const style = {...styleOf(this.doc, cell)};
      const border = {...(style.border ?? {})};
      const sides = {
        all: ["top", "right", "bottom", "left"],
        outer: [r === r0 && "top", r === r1 && "bottom", c === c0 && "left", c === c1 && "right"],
        top: [r === r0 && "top"], bottom: [r === r1 && "bottom"], left: [c === c0 && "left"], right: [c === c1 && "right"],
        innerH: [r > r0 && "top", r < r1 && "bottom"], innerV: [c > c0 && "left", c < c1 && "right"],
        none: [],
      }[mode].filter(Boolean);
      if (mode === "none") { delete style.border; }
      else { for (const side of sides) border[side] = {...line}; style.border = border; }
      cell.s = styleIndex(this.doc, style);
      setCell(this.doc, name, cell);
    }
    this.changed([]);
  }

  // Σ: több cellánál oszloponként SUM a kijelölés alá; egy cellánál a fölötte lévő összefüggő számok összege.
  autoSum() {
    this.commitDraft();
    const {r0, r1, c0, c1} = this.sel;
    const isNumber = (r, c) => typeof this.doc.cells[cellName(r, c)]?.v === "number";
    this.record();
    const changed = [];
    if (r0 === r1 && c0 === c1) {
      let top = r0;
      while (top > 0 && isNumber(top - 1, c0)) top--;
      if (top === r0) { this.undoStack.pop(); return; }
      const name = cellName(r0, c0);
      setCell(this.doc, name, {...(this.doc.cells[name] ?? {}), f: "SUM(" + cellName(top, c0) + ":" + cellName(r0 - 1, c0) + ")", v: undefined});
      changed.push(name);
    } else {
      const target = r1 + 1;
      if (target >= limits.maxRows) { this.undoStack.pop(); return; }
      this.doc.size.rows = Math.max(this.doc.size.rows, target + 1);
      for (let c = c0; c <= c1; c++) {
        const name = cellName(target, c);
        setCell(this.doc, name, {...(this.doc.cells[name] ?? {}), f: "SUM(" + cellName(r0, c) + ":" + cellName(r1, c) + ")"});
        changed.push(name);
      }
    }
    this.changed(changed);
  }

  // MARK: Sorok és oszlopok

  // Beszúrás (count > 0) vagy törlés (count < 0) az `at` helytől; a cellák, a méretek és a képletek eltolódnak.
  shiftAxis(axis, at, count) {
    this.commitDraft();
    const doc = this.doc, size = axis === "row" ? "rows" : "cols";
    const maximum = axis === "row" ? limits.maxRows : limits.maxCols;
    if (count > 0 && doc.size[size] + count > maximum) return false;
    if (count < 0 && doc.size[size] + count < 1) return false;
    this.record();
    const cells = {};
    for (const [name, cell] of Object.entries(doc.cells)) {
      const address = parseAddress(name);
      let index = axis === "row" ? address.row : address.col;
      if (count < 0 && index >= at && index < at - count) continue;
      if (index >= at) index += count;
      const moved = {...cell};
      if (moved.f != null) moved.f = shift(moved.f, axis, at, count);
      cells[axis === "row" ? cellName(index, address.col) : cellName(address.row, index)] = moved;
    }
    doc.cells = cells;
    const info = axis === "row" ? doc.rows : doc.cols;
    if (info) {
      const next = {};
      for (const [key, value] of Object.entries(info)) {
        let index = axis === "row" ? Number(key) - 1 : parseAddress(key + "1").col;
        if (count < 0 && index >= at && index < at - count) continue;
        if (index >= at) index += count;
        next[axis === "row" ? String(index + 1) : columnName(index)] = value;
      }
      if (axis === "row") doc.rows = next; else doc.cols = next;
    }
    doc.size[size] += count;
    this.active = {r: clamp(this.active.r, 0, doc.size.rows - 1), c: clamp(this.active.c, 0, doc.size.cols - 1)};
    this.anchor = {...this.active};
    this.changed(null);
    return true;
  }

  insertRows(before = true) { const {r0, r1} = this.sel; return this.shiftAxis("row", before ? r0 : r1 + 1, r1 - r0 + 1); }
  insertCols(before = true) { const {c0, c1} = this.sel; return this.shiftAxis("col", before ? c0 : c1 + 1, c1 - c0 + 1); }
  deleteRows() { const {r0, r1} = this.sel; return this.shiftAxis("row", r0, -(r1 - r0 + 1)); }
  deleteCols() { const {c0, c1} = this.sel; return this.shiftAxis("col", c0, -(c1 - c0 + 1)); }

  setColumnWidth(c, width, {record = true} = {}) {
    if (record) this.record();
    this.doc.cols ??= {};
    this.doc.cols[columnName(c)] = {w: clamp(Math.round(width), 16, 2000)};
    if (record) this.changed([]); else this.touch();
  }

  // MARK: Vágólap

  copy() { this.commitDraft(); return copySelection(this.doc, this.sel); }

  cut() {
    const data = this.copy();
    this.clearSelection();
    return data;
  }

  // Beillesztés az aktív cellától: saját formátum (képletekkel, eltolva), HTML-táblázat (stílussal) vagy TSV.
  paste({json, rows: htmlRows, tsv}) {
    this.commitDraft();
    const {r: r0, c: c0} = this.active;
    let grid;
    if (json) {
      const clip = JSON.parse(json);
      grid = clip.cells.map(row => row.map(cell => cell && {cell, origin: clip.origin}));
    } else if (htmlRows) grid = htmlRows.map(row => row.map(item => ({text: item.text, style: item.style})));
    else grid = parseTSV(tsv ?? "").map(row => row.map(text => ({text})));
    if (!grid.length) return;
    const rows = grid.length, cols = Math.max(...grid.map(row => row.length));
    if (r0 + rows > limits.maxRows || c0 + cols > limits.maxCols) throw Error("A beillesztett tartomány túl nagy.");
    this.record();
    this.doc.size.rows = Math.max(this.doc.size.rows, r0 + rows);
    this.doc.size.cols = Math.max(this.doc.size.cols, c0 + cols);
    const changed = [];
    grid.forEach((row, i) => row.forEach((item, j) => {
      const name = cellName(r0 + i, c0 + j);
      changed.push(name);
      if (!item) { setCell(this.doc, name, null); return; }
      if (item.cell) {
        const {style, ...cell} = item.cell;
        if (cell.f != null) cell.f = move(cell.f, r0 - item.origin.row, c0 - item.origin.col);
        cell.s = style ? styleIndex(this.doc, style) : 0;
        setCell(this.doc, name, cell);
        return;
      }
      const current = this.doc.cells[name];
      setCell(this.doc, name, item.style ? {s: styleIndex(this.doc, {...styleOf(this.doc, current), ...item.style})} : {s: current?.s});
      // Külső forrásból képlet nem jön (CSV-hez hasonlóan): az "=" kezdetű szöveg szöveg marad.
      const parsed = parseInput(item.text);
      this.setInput(name, parsed.kind === "formula" ? "'" + item.text.trim() : item.text, {record: false});
    }));
    this.anchor = {r: r0, c: c0};
    this.active = {r: r0 + rows - 1, c: c0 + cols - 1};
    this.changed(changed);
  }

  // MARK: Visszavonás, mentés

  record() {
    this.undoStack.push(JSON.stringify(this.doc));
    if (this.undoStack.length > 100) this.undoStack.shift();
    this.redoStack = [];
  }

  restore(from, to) {
    if (!from.length) return false;
    this.commitDraft();
    to.push(JSON.stringify(this.doc));
    const previous = JSON.parse(from.pop());
    for (const key of Object.keys(this.doc)) delete this.doc[key];
    Object.assign(this.doc, previous);
    this.active = {r: clamp(this.active.r, 0, this.doc.size.rows - 1), c: clamp(this.active.c, 0, this.doc.size.cols - 1)};
    this.anchor = {...this.active};
    this.touch();
    this.onChange(this.doc);
    return true;
  }

  undo() { return this.restore(this.undoStack, this.redoStack); }
  redo() { return this.restore(this.redoStack, this.undoStack); }

  // Változás után: újraszámolás (null: minden; [] csak stílus, nincs számolás) és mentés.
  changed(names) {
    if (names === null) recalculate(this.doc);
    else if (names.length) recalculate(this.doc, names);
    this.touch();
    this.onChange(this.doc);
  }

  // MARK: Billentyűzet

  // Billentyű kezelése; true, ha a vezérlő kezelte (ilyenkor a hívó megállítja az eseményt).
  keydown(event) {
    const key = event.key, ctrl = event.ctrlKey || event.metaKey, shiftKey = event.shiftKey;
    if (this.draft != null) {
      if (key === "Escape") { this.cancelDraft(); return true; }
      if (key === "Enter" && !event.altKey) { this.commitDraft(); this.moveBy(shiftKey ? -1 : 1, 0); return true; }
      if (key === "Tab") { this.commitDraft(); this.moveBy(0, shiftKey ? -1 : 1); return true; }
      return false;  // a szövegmező kezeli
    }
    if (ctrl) {
      const lower = key.toLowerCase();
      if (lower === "z") { shiftKey ? this.redo() : this.undo(); return true; }
      if (lower === "y") { this.redo(); return true; }
      if (lower === "b") { this.toggle("b"); return true; }
      if (lower === "i") { this.toggle("i"); return true; }
      if (lower === "u") { this.toggle("u"); return true; }
      if (lower === "a") { this.anchor = {r: 0, c: 0}; this.active = {r: this.doc.size.rows - 1, c: this.doc.size.cols - 1}; this.touch(); return true; }
      const arrows = {ArrowUp: [-1, 0], ArrowDown: [1, 0], ArrowLeft: [0, -1], ArrowRight: [0, 1]}[key];
      if (arrows) { this.jump(...arrows, shiftKey); return true; }
      if (key === "Home") { this.select(0, 0, shiftKey); return true; }
      return false;
    }
    const arrows = {ArrowUp: [-1, 0], ArrowDown: [1, 0], ArrowLeft: [0, -1], ArrowRight: [0, 1]}[key];
    if (arrows) { this.moveBy(...arrows, shiftKey); return true; }
    if (key === "Tab") { this.moveBy(0, shiftKey ? -1 : 1); return true; }
    if (key === "Enter") { this.moveBy(shiftKey ? -1 : 1, 0); return true; }
    if (key === "Home") { this.select(this.active.r, 0, shiftKey); return true; }
    if (key === "End") { this.select(this.active.r, this.doc.size.cols - 1, shiftKey); return true; }
    if (key === "F2") { this.startDraft(); return true; }
    if (key === "Delete" || key === "Backspace") { this.clearSelection(); return true; }
    if (key.length === 1 && !event.altKey && !event.isComposing) { this.startDraft(key); return true; }
    return false;
  }
}
