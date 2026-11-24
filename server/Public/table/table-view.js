// Táblázat kirajzolása a szerkesztőben (Vue render-függvények). Olvasó nézetben ugyanaz a szerkezet, mint a szerver
// TableHTML-je (Sources/ThinkTable/TableHTML.swift); szerkesztési módban fejlécek, képletsor, eszközsor (docs/EXCEL.md 5–6.).

import {cellName, columnName, styleOf} from "./table-document.js";
import {display} from "./table-format.js";
import {tokenize} from "./table-formula.js";
import {parseHTMLTable, tableMime} from "./table-clipboard.js";
import {attachScrollbars, detachScrollbars} from "../scrollbar-drag.js";

export const defaultColumnWidth = 80, defaultRowHeight = 24, previewRows = 200;

const hexColor = value => typeof value === "string" && /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(value) ? value : null;

function borderCSS(line) {
  if (!line || !(line.w > 0)) return null;
  const style = ["solid", "dashed", "dotted", "double"].includes(line.style) ? line.style : "solid";
  const width = style === "double" ? 3 : Math.min(Math.max(line.w, 1), 3);
  return width + "px " + style + " " + (hexColor(line.color) ?? "#000000");
}

// Cella stílusa (a Swift TableHTML.cellCSS párja). Az `o` kulcs az áthúzás (korábban felülvonás volt).
export function cellStyle(style) {
  const css = {};
  if (style.b) css.fontWeight = 700;
  if (style.i) css.fontStyle = "italic";
  const decorations = [style.u && "underline", style.o && "line-through"].filter(Boolean);
  if (decorations.length) css.textDecoration = decorations.join(" ");
  if (hexColor(style.color)) css.color = style.color;
  if (hexColor(style.fill)) css.background = style.fill;
  if (["left", "center", "right"].includes(style.align)) css.textAlign = style.align;
  for (const side of ["top", "right", "bottom", "left"]) {
    const value = borderCSS(style.border?.[side]);
    if (value) css["border" + side[0].toUpperCase() + side.slice(1)] = value;
  }
  return css;
}

const kind = value => typeof value === "number" ? "num" : typeof value === "boolean" ? "bool" : value && typeof value === "object" ? "err" : "txt";
const columnWidth = (doc, c) => Math.max(16, Math.min(doc.cols?.[columnName(c)]?.w ?? defaultColumnWidth, 2000));
const rowHeight = (doc, r) => Math.max(12, Math.min(doc.rows?.[String(r + 1)]?.h ?? defaultRowHeight, 2000));

// A táblázat teljes szélessége: rögzített oszlopszélességekhez (table-layout: fixed) kell a kifejezett szélesség,
// különben a böngésző a tartalomhoz igazít, és pl. a félkövér betű szélesíti az oszlopot.
export const rowHeadWidth = 36;
export function tableWidth(doc, withHeader = false) {
  let width = withHeader ? rowHeadWidth : 0;
  for (let c = 0; c < doc.size.cols; c++) width += columnWidth(doc, c);
  return width;
}

// Egy cella bal felső sarka a szerkesztő rácsán belül (az oszlopfejléc sora és a sorfejléc oszlopa után).
export function gridOffset(doc, r, c) {
  let top = defaultRowHeight, left = rowHeadWidth;
  for (let row = 0; row < r; row++) top += rowHeight(doc, row);
  for (let col = 0; col < c; col++) left += columnWidth(doc, col);
  return {top, left};
}

function colgroup(h, doc, withHeader) {
  const cols = [];
  if (withHeader) cols.push(h("col", {style: {width: rowHeadWidth + "px"}}));
  for (let c = 0; c < doc.size.cols; c++) cols.push(h("col", {style: {width: columnWidth(doc, c) + "px"}}));
  return h("colgroup", cols);
}

// Más résztvevők cellakijelölése egy cellán (olvasó nézet): `marks` = [{color, range: {r0, c0, r1, c1, r, c, editing}}].
// A kijelölt tartomány a résztvevő színével árnyalt, az aktív cella keretes; szerkesztés közben a keret szaggatott.
export function peerMark(marks, r, c) {
  if (!marks?.length) return null;
  for (const {color, range} of marks) {
    if (r < range.r0 || r > range.r1 || c < range.c0 || c > range.c1) continue;
    const active = r === range.r && c === range.c;
    return {class: ["tn-peer", {"tn-peer-active": active, "tn-peer-editing": active && range.editing}], color};
  }
  return null;
}

// Olvasó nézet: a szerver HTML-jével egyező szerkezet.
export function renderTable(h, doc, {maxRows = previewRows, marks = null} = {}) {
  const rows = Math.min(doc.size.rows, maxRows), headerRows = Math.min(doc.header?.rows ?? 0, rows);
  const row = (r, tag) => h("tr", rowHeight(doc, r) === defaultRowHeight ? {} : {style: {height: rowHeight(doc, r) + "px"}},
    Array.from({length: doc.size.cols}, (_, c) => {
      const cell = doc.cells[cellName(r, c)], style = styleOf(doc, cell), mark = peerMark(marks, r, c);
      return h(tag, {class: [kind(cell?.v), {fixed: cell?.fx != null}, mark?.class], style: mark ? {...cellStyle(style), "--tn-peer": mark.color} : cellStyle(style), title: cell?.fx ? "Rögzített érték: " + cell.fx : undefined},
        display(cell?.v, style.fmt));
    }));
  return h("div", {class: "tn-table-wrap"}, [
    h("table", {class: ["tn-table", {"no-grid": doc.grid === false}], style: {width: tableWidth(doc) + "px"}}, [
      colgroup(h, doc, false),
      headerRows ? h("thead", Array.from({length: headerRows}, (_, r) => row(r, "th"))) : null,
      h("tbody", Array.from({length: Math.max(0, rows - headerRows)}, (_, i) => row(headerRows + i, "td"))),
    ]),
    doc.size.rows > rows ? h("p", {class: "tn-table-more"}, "… további " + (doc.size.rows - rows) + " sor") : null,
  ]);
}

// A szerkesztett képlet hivatkozásai (kiemeléshez): [{r0, r1, c0, c1}].
function referencedRanges(draft, doc) {
  if (!draft?.startsWith("=")) return [];
  try {
    const result = [];
    const tokens = tokenize(draft.slice(1));
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      if (token.type !== "ref" || token.ref.table != null) continue;
      const a = token.ref;
      let b = a;
      if (tokens[i + 1]?.type === "op" && tokens[i + 1].value === ":" && tokens[i + 2]?.type === "ref") { b = tokens[i + 2].ref; i += 2; }
      result.push({r0: Math.min(a.row ?? 0, b.row ?? 0), r1: a.row == null ? doc.size.rows - 1 : Math.max(a.row, b.row),
        c0: Math.min(a.col, b.col), c1: Math.max(a.col, b.col)});
    }
    return result;
  } catch { return []; }
}

const numberFormats = [
  ["general", "Általános", null],
  ["number", "Szám", {kind: "number", dec: 2, group: true}],
  ["ft", "Pénznem (Ft)", {kind: "currency", dec: 0, symbol: "Ft"}],
  ["eur", "Pénznem (€)", {kind: "currency", dec: 2, symbol: "€", before: true}],
  ["percent", "Százalék", {kind: "percent", dec: 0}],
  ["date", "Dátum", {kind: "date", pattern: "yyyy.MM.dd."}],
  ["datetime", "Dátum és idő", {kind: "date", pattern: "yyyy.MM.dd. HH:mm"}],
  ["time", "Idő", {kind: "date", pattern: "HH:mm"}],
  ["fraction", "Tört", {kind: "fraction"}],
  ["text", "Szöveg", {kind: "text"}],
];

function formatKey(fmt) {
  if (!fmt || fmt.kind === "general") return "general";
  if (fmt.kind === "currency") return fmt.symbol === "€" ? "eur" : "ft";
  if (fmt.kind === "date") return fmt.pattern === "HH:mm" ? "time" : fmt.pattern?.includes("HH") ? "datetime" : "date";
  return fmt.kind;
}

const borderModes = [
  ["all", "Minden rács"], ["outer", "Külső keret"], ["top", "Felül"], ["bottom", "Alul"], ["left", "Balra"], ["right", "Jobbra"],
  ["innerH", "Belső vízszintes"], ["innerV", "Belső függőleges"], ["none", "Keret törlése"],
];

// Eszközsor (a doboz fölött és a panelen is): formázás, számformátum, keret, Σ, sorok/oszlopok.
// `icon(név)`: a szerkesztő ikonrajzolója (icons.svg); az igazítás a szövegeknél megszokott ikonokat kapja.
export function tableToolbar(h, edit, {compact = false, icon = null} = {}) {
  const style = edit.activeStyle();
  const toggle = (key, label, title) => h("button", {type: "button", class: ["button", "tn-tool", "tn-tool-" + key], "aria-pressed": String(!!edit.isOn(key)),
    title, "aria-label": title, onClick: () => edit.toggle(key)}, label);
  const tool = (label, title, action) => h("button", {type: "button", class: "button tn-tool", title, "aria-label": title, onClick: action}, label);
  edit.borderLine ??= {w: 1, color: "#000000", style: "solid"};
  return h("div", {class: ["tn-toolbar", {compact}], role: "toolbar", "aria-label": "Táblázat formázása"}, [
    toggle("b", "B", "Félkövér (Ctrl+B)"), toggle("i", "I", "Dőlt (Ctrl+I)"), toggle("u", "U", "Aláhúzott (Ctrl+U)"), toggle("o", "S", "Áthúzott"),
    h("label", {class: "tn-color", title: "Betűszín"}, ["A", h("input", {type: "color", "aria-label": "Betűszín", value: hexColor(style.color) ?? "#000000",
      onChange: e => edit.setStyle("color", e.target.value)})]),
    h("label", {class: "tn-color tn-fill", title: "Cellaszín"}, ["▧", h("input", {type: "color", "aria-label": "Cellaszín", value: hexColor(style.fill) ?? "#ffffff",
      onChange: e => edit.setStyle("fill", e.target.value)})]),
    tool("⌫", "Színek törlése", () => edit.styleSelection(s => ({...s, color: undefined, fill: undefined}))),
    ...[["left", "⇤", "Balra"], ["center", "↔", "Középre"], ["right", "⇥", "Jobbra"]].map(([align, label, title]) =>
      h("button", {type: "button", class: "button tn-tool tn-tool-align", "aria-pressed": String(style.align === align), title, "aria-label": title,
        onClick: () => edit.setStyle("align", style.align === align ? undefined : align)}, icon ? [icon("text-" + align)] : label)),
    h("select", {class: "tn-select", "aria-label": "Számformátum", title: "Számformátum", value: formatKey(style.fmt),
      onChange: e => edit.setStyle("fmt", numberFormats.find(([key]) => key === e.target.value)?.[2] ?? undefined)},
      numberFormats.map(([key, label]) => h("option", {value: key}, label))),
    tool(",0−", "Kevesebb tizedesjegy", () => edit.stepDecimals(-1)),
    tool(",0+", "Több tizedesjegy", () => edit.stepDecimals(1)),
    h("select", {class: "tn-select", "aria-label": "Keret", title: "Keret", value: "",
      onChange: e => { if (e.target.value) edit.border(e.target.value, {...edit.borderLine}); e.target.value = ""; }},
      [h("option", {value: ""}, "Keret…"), ...borderModes.map(([key, label]) => h("option", {value: key}, label))]),
    h("select", {class: "tn-select", "aria-label": "Keret vastagsága", title: "Keret vastagsága", value: String(edit.borderLine.w),
      onChange: e => { edit.borderLine.w = Number(e.target.value); edit.touch(); }},
      [["1", "Vékony"], ["2", "Közepes"], ["3", "Vastag"]].map(([v, label]) => h("option", {value: v}, label))),
    h("select", {class: "tn-select", "aria-label": "Keret stílusa", title: "Keret stílusa", value: edit.borderLine.style,
      onChange: e => { edit.borderLine.style = e.target.value; edit.touch(); }},
      [["solid", "Folytonos"], ["dashed", "Szaggatott"], ["dotted", "Pontozott"], ["double", "Dupla"]].map(([v, label]) => h("option", {value: v}, label))),
    h("label", {class: "tn-color", title: "Keret színe"}, ["▢", h("input", {type: "color", "aria-label": "Keret színe", value: edit.borderLine.color,
      onChange: e => { edit.borderLine.color = e.target.value; edit.touch(); }})]),
    tool("Σ", "Összegzés", () => edit.autoSum()),
    tool("+sor", "Sor beszúrása fölé", () => edit.insertRows(true)),
    tool("−sor", "Sor törlése", () => edit.deleteRows()),
    tool("+osz", "Oszlop beszúrása elé", () => edit.insertCols(true)),
    tool("−osz", "Oszlop törlése", () => edit.deleteCols()),
    tool("↶", "Visszavonás (Ctrl+Z)", () => edit.undo()),
    tool("↷", "Újra (Ctrl+Y)", () => edit.redo()),
  ]);
}

// Szerkesztési mód: képletsor és rács (az eszközsor a panelen van, hogy kis dobozban is látsszon a rács). `onExit`: kilépés (Esc). A vezérlő (TableEditor) állapotát rajzolja; a `version` mező
// változása váltja ki az újrarajzolást (a hívó olvassa).
// A virtuális ablak ráhagyása (képpont) a látható rész fölött és alatt, és az újrarajzolás küszöbe: a küszöbnél kevesebb
// görgetés nem rajzol újra. A ráhagyásnak a küszöbnél nagyobbnak kell lennie, különben üres sáv látszana.
const windowAbove = 480, windowBelow = 640, windowStep = 320;

export function renderTableEditor(h, edit, {onExit = () => {}, focusGrid = false} = {}) {
  const doc = edit.doc, sel = edit.sel, draft = edit.draft;
  const highlighted = referencedRanges(draft, doc);
  const inRange = (range, r, c) => r >= range.r0 && r <= range.r1 && c >= range.c0 && c <= range.c1;
  edit.scrollTop ??= 0; edit.viewport ??= 400;

  // Virtualizálás: csak a látható sorok (és egy kis ráhagyás) rajzolódnak ki; a többit térköz helyettesíti.
  let first = 0, top = 0;
  // Ráhagyás fölül és alul: a görgetés csak akkor rajzol újra, ha a ráhagyás fogytán van (lásd az onScroll küszöbét);
  // így gyors görgetésnél nem minden második képkocka újrarajzolás.
  while (first < doc.size.rows && top + rowHeight(doc, first) < edit.scrollTop - windowAbove) { top += rowHeight(doc, first); first++; }
  let last = first, bottom = top;
  while (last < doc.size.rows && bottom < edit.scrollTop + edit.viewport + windowBelow) { bottom += rowHeight(doc, last); last++; }
  let rest = 0;
  for (let r = last; r < doc.size.rows; r++) rest += rowHeight(doc, r);

  let dragging = false;
  const pressCell = (event, r, c) => {
    event.stopPropagation();
    if (event.button !== 0) return;
    // A billentyűzet a táblázathoz menjen (a panel gombjáról vagy a vászonról idekattintva is).
    if (edit.draft == null) focusSink(event.currentTarget);
    if (edit.pointing) { event.preventDefault(); edit.insertReference(r, c); edit.pointStart = {r, c}; return; }
    edit.select(r, c, event.shiftKey);
    dragging = true;
    edit.dragging = true;
  };
  const enterCell = (event, r, c) => {
    if (!(event.buttons & 1)) { edit.dragging = false; return; }
    if (edit.pointStart && edit.pointing) { edit.insertReference(edit.pointStart.r, edit.pointStart.c, r, c); return; }
    if (edit.dragging) edit.select(r, c, true);
  };

  const resizeColumn = (event, c) => {
    event.stopPropagation(); event.preventDefault();
    const startX = event.clientX, startWidth = columnWidth(doc, c);
    const scale = event.currentTarget.getBoundingClientRect().width / (event.currentTarget.offsetWidth || 1) || 1;
    edit.record();
    const moveHandler = e => edit.setColumnWidth(c, startWidth + (e.clientX - startX) / scale, {record: false});
    const up = () => { removeEventListener("pointermove", moveHandler); removeEventListener("pointerup", up); edit.changed([]); };
    addEventListener("pointermove", moveHandler);
    addEventListener("pointerup", up);
  };

  const cellInput = () => h("input", {class: "tn-cell-input", value: draft, spellcheck: false, "aria-label": "Cella " + edit.activeName,
    onVnodeMounted: ({el}) => { el.focus(); el.setSelectionRange?.(el.value.length, el.value.length); },
    onInput: e => edit.setDraft(e.target.value), onPointerdown: e => e.stopPropagation()});

  const headerRow = h("tr", {class: "tn-colhead"}, [
    h("th", {class: "tn-corner", onPointerdown: e => { e.stopPropagation(); edit.anchor = {r: 0, c: 0}; edit.active = {r: doc.size.rows - 1, c: doc.size.cols - 1}; edit.touch(); }}),
    ...Array.from({length: doc.size.cols}, (_, c) => h("th", {class: {selected: c >= sel.c0 && c <= sel.c1},
      onPointerdown: e => { e.stopPropagation(); edit.selectColumn(c, e.shiftKey); }}, [
      columnName(c), h("span", {class: "tn-resize", title: "Oszlopszélesség", onPointerdown: e => resizeColumn(e, c)}),
    ])),
  ]);

  const bodyRows = [];
  // A sorok kulcsa a sorszám: görgetéskor a megmaradó sorok DOM-ja érintetlen marad, csak a belépő és kilépő sorok
  // jönnek létre, illetve tűnnek el. Kulcs nélkül minden látható cella tartalma kicserélődött (teljes újraelrendezés).
  bodyRows.push(h("tr", {key: "top", class: "tn-spacer", style: {height: top + "px"}}));
  for (let r = first; r < last; r++) {
    const cells = [h("th", {class: ["tn-rowhead", {selected: r >= sel.r0 && r <= sel.r1}],
      onPointerdown: e => { e.stopPropagation(); edit.selectRow(r, e.shiftKey); }}, String(r + 1))];
    for (let c = 0; c < doc.size.cols; c++) {
      const name = cellName(r, c), cell = doc.cells[name], style = styleOf(doc, cell);
      const isActive = r === edit.active.r && c === edit.active.c;
      const refIndex = highlighted.findIndex(range => inRange(range, r, c));
      cells.push(h("td", {
        class: [kind(cell?.v), {
          selected: r >= sel.r0 && r <= sel.r1 && c >= sel.c0 && c <= sel.c1, active: isActive, header: r < (doc.header?.rows ?? 0),
          fixed: cell?.fx != null, ["tn-ref tn-ref-" + (refIndex % 4)]: refIndex >= 0,
        }],
        style: cellStyle(style), title: cell?.fx ? "Rögzített érték (az eredeti képlet: " + cell.fx + ")" : undefined,
        onPointerdown: e => pressCell(e, r, c), onPointerenter: e => enterCell(e, r, c),
        onDblclick: e => { e.stopPropagation(); edit.select(r, c); edit.startDraft(); },
      }, isActive && draft != null ? [cellInput()] : display(cell?.v, style.fmt)));
    }
    bodyRows.push(h("tr", rowHeight(doc, r) === defaultRowHeight ? {key: r} : {key: r, style: {height: rowHeight(doc, r) + "px"}}, cells));
  }
  bodyRows.push(h("tr", {key: "bottom", class: "tn-spacer", style: {height: rest + "px"}}));

  const stop = e => e.stopPropagation();
  return h("div", {class: "tn-table-editor", tabindex: -1, "data-table-editor": "",
    onVnodeMounted: ({el}) => { if (focusGrid && edit.draft == null) focusSink(el); },
    onPointerdown: stop, onDblclick: stop, onClick: stop, onContextmenu: stop,
    onKeydown: event => {
      event.stopPropagation();
      if (event.key === "Escape" && edit.draft == null) { event.preventDefault(); onExit(); return; }
      // Gyors gépelés: amíg a cella beviteli mezője meg nem jelenik, a betűk a vázlathoz fűződnek.
      if (edit.draft != null && event.target.matches?.(".tn-sink, .tn-table-editor") && event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
        event.preventDefault();
        edit.setDraft(edit.draft + event.key);
        return;
      }
      if (edit.keydown(event)) {
        event.preventDefault();
        if (edit.draft == null) focusSink(event.currentTarget);
      }
    },
    onCopy: event => { if (edit.draft != null) return; event.stopPropagation(); event.preventDefault(); writeClip(event, edit.copy()); },
    onCut: event => { if (edit.draft != null) return; event.stopPropagation(); event.preventDefault(); writeClip(event, edit.cut()); },
    onPaste: event => {
      if (edit.draft != null) { event.stopPropagation(); return; }
      event.stopPropagation(); event.preventDefault();
      const data = event.clipboardData;
      const json = data?.getData(tableMime);
      const html = data?.getData("text/html");
      const rows = !json && html ? parseHTMLTable(html) : null;
      try { edit.paste({json: json || null, rows, tsv: data?.getData("text/plain") ?? ""}); }
      catch (error) { edit.problem = error.message; edit.touch(); }
    },
    onWheel: stop,
  }, [
    // Billentyűzet-nyelő: a fókusz itt van, amíg nincs cellaszerkesztés. A gépelést (IME, érintőbillentyűzet,
    // szövegbeszúrás is) elkapja, és cellaszerkesztést indít vele.
    h("input", {class: "tn-sink", "aria-label": "Táblázat, aktív cella: " + edit.activeName, autocomplete: "off", spellcheck: false,
      onInput: e => { const text = e.target.value; e.target.value = ""; if (text && edit.draft == null) edit.startDraft(text); },
      onPointerdown: stop}),
    h("div", {class: "tn-formula-bar"}, [
      h("span", {class: "tn-name"}, edit.activeName),
      edit.plain ? null : h("span", {class: "tn-fx"}, "fx"),
      h("input", {class: "tn-formula", spellcheck: false, "aria-label": edit.plain ? "Cella tartalma" : "Képletsor", value: draft ?? edit.rawText(edit.activeName),
        onFocus: () => { if (edit.draft == null) edit.startDraft(); },
        onInput: e => edit.setDraft(e.target.value), onPointerdown: stop}),
    ]),
    edit.problem ? h("p", {class: "tn-problem", role: "alert"}, edit.problem) : null,
    // A görgethető rács külön tartóban áll: Safariban ide kerülnek mellé a saját görgetősávok (scrollbar-drag.js).
    h("div", {class: "tn-table-scroll-host"}, [h("div", {class: "tn-table-scroll",
      onVnodeMounted: ({el}) => { edit.viewport = el.clientHeight || 400; el.scrollTop = edit.scrollTop; el.scrollLeft = edit.scrollLeft ?? 0; attachScrollbars(el); },
      onVnodeUpdated: ({el}) => attachScrollbars(el), onVnodeBeforeUnmount: ({el}) => detachScrollbars(el),
      onScroll: e => {
        const el = e.currentTarget;
        edit.viewport = el.clientHeight || 400;
        if (Math.abs(el.scrollTop - edit.scrollTop) > windowStep) { edit.scrollTop = el.scrollTop; edit.touch(); }
      }}, [
      h("table", {class: ["tn-table", "tn-editing", {"no-grid": doc.grid === false}], style: {width: tableWidth(doc, true) + "px"}}, [
        colgroup(h, doc, true),
        h("thead", [headerRow]),
        h("tbody", bodyRows),
      ]),
    ])]),
  ]);
}

// A fókusz a rejtett billentyűzet-nyelőre kerül (ha éppen nincs cellaszerkesztés).
function focusSink(from) {
  const root = from?.closest?.(".tn-table-editor") ?? from;
  // Ha már a nyelőn van a fókusz, nem hívjuk újra: a focus() azonnali elrendezést kényszerít ki (kattintásonként ~9 ms).
  const sink = root?.querySelector?.(".tn-sink");
  if (sink && sink.ownerDocument.activeElement !== sink) sink.focus({preventScroll: true});
}

function writeClip(event, data) {
  event.clipboardData?.setData("text/plain", data.tsv);
  event.clipboardData?.setData("text/html", data.html);
  try { event.clipboardData?.setData(tableMime, data.json); } catch { /* egyes böngészők nem engedik a saját típust */ }
}

// Az aktív cella látható maradjon (a görgetőn belül).
export function revealActive(root, edit) {
  const scroller = root?.querySelector?.(".tn-table-scroll");
  const cell = scroller?.querySelector?.("td.active");
  if (!scroller || !cell) return;
  const head = scroller.querySelector("thead")?.offsetHeight ?? 0;
  if (cell.offsetTop - head < scroller.scrollTop) scroller.scrollTop = cell.offsetTop - head;
  else if (cell.offsetTop + cell.offsetHeight > scroller.scrollTop + scroller.clientHeight) scroller.scrollTop = cell.offsetTop + cell.offsetHeight - scroller.clientHeight;
  const rowHead = scroller.querySelector(".tn-rowhead")?.offsetWidth ?? 0;
  if (cell.offsetLeft - rowHead < scroller.scrollLeft) scroller.scrollLeft = cell.offsetLeft - rowHead;
  else if (cell.offsetLeft + cell.offsetWidth > scroller.scrollLeft + scroller.clientWidth) scroller.scrollLeft = cell.offsetLeft + cell.offsetWidth - scroller.clientWidth;
}
