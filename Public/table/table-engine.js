// Kiértékelés, függőségi gráf, újraszámolás (EXCEL.md 4. fejezet). Swift párja: Sources/ThinkTable/TableEngine.swift.
// Belső érték: {t: "empty"} | {t: "number", v} | {t: "text", v} | {t: "bool", v} | {t: "error", v}.

import {parse, references} from "./table-formula.js";
import {cellName, parseAddress} from "./table-document.js";
import {general, parseInput, roundHalfAway} from "./table-format.js";

const EMPTY = {t: "empty"};
const num = v => ({t: "number", v});
const err = v => ({t: "error", v});
const checked = n => Number.isFinite(n) ? num(n) : err("#NUM!");
const same = (a, b) => a.t === b.t && a.v === b.v;

// Cellaérték (fájl) → belső érték.
function fromCell(value) {
  if (value == null) return EMPTY;
  if (typeof value === "number") return num(value);
  if (typeof value === "string") return {t: "text", v: value};
  if (typeof value === "boolean") return {t: "bool", v: value};
  return err(value.err);
}

// Belső érték → cellaérték (fájl). Üres → 0, nem véges szám → #NUM!.
function toCell(value) {
  switch (value.t) {
    case "empty": return 0;
    case "number": return Number.isFinite(value.v) ? value.v : {err: "#NUM!"};
    case "error": return {err: value.v};
    default: return value.v;
  }
}

const parseCache = new Map();
function parsed(formula) {
  if (parseCache.has(formula)) return parseCache.get(formula);
  let result;
  try { result = parse(formula); } catch { result = null; }
  if (parseCache.size > 5000) parseCache.clear();
  parseCache.set(formula, result);
  return result;
}

class Context {
  constructor(doc, resolver, dirty) {
    this.doc = doc; this.resolver = resolver; this.dirty = dirty;
    this.computed = new Map(); this.visiting = new Set();
  }

  cellValue(name) {
    const cell = this.doc.cells[name];
    if (!cell) return EMPTY;
    if (cell.f == null || (this.dirty && !this.dirty.has(name))) return fromCell(cell.v);
    if (this.computed.has(name)) return this.computed.get(name);
    if (this.visiting.has(name)) return err("#CIRC!");
    this.visiting.add(name);
    const expr = parsed(cell.f);
    let result;
    if (expr) {
      const value = evaluate(expr, this);
      result = value.range ? err("#VALUE!") : value.t === "empty" ? num(0) : value;
    } else result = err("#NAME?");
    this.visiting.delete(name);
    this.computed.set(name, result);
    return result;
  }

  lookup(ref, row) {
    if (ref.table != null) {
      const value = this.resolver?.value(ref.table, {row, col: ref.col});
      return value === undefined ? err("#REF!") : fromCell(value);
    }
    return this.cellValue(cellName(row, ref.col));
  }

  rangeValues(a, b) {
    let size;
    if (a.table != null) {
      size = this.resolver?.bounds(a.table);
      if (!size) return null;
    } else size = this.doc.size;
    const c0 = Math.min(a.col, b.col), c1 = Math.min(Math.max(a.col, b.col), size.cols - 1);
    const r0 = Math.min(a.row ?? 0, b.row ?? 0);
    const r1 = a.row == null ? size.rows - 1 : Math.min(Math.max(a.row, b.row), size.rows - 1);
    const values = [];
    if (c0 > c1 || r0 > r1) return values;
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) values.push(this.lookup({table: a.table, col: c}, r));
    return values;
  }
}

// Minden képletes cella újraszámolása (changed == null), vagy csak a megváltozottak és a tőlük függők.
// A dokumentumot helyben módosítja; a visszatérési érték a megváltozott értékű cellák neve.
export function recalculate(doc, changed = null, resolver = null) {
  const dirty = changed ? dependents(changed, doc) : null;
  const context = new Context(doc, resolver, dirty);
  const targets = (dirty ? [...dirty] : Object.keys(doc.cells).filter(name => doc.cells[name].f != null))
    .sort(compareNames);
  const updated = [];
  for (const name of targets) {
    const cell = doc.cells[name];
    if (cell?.f == null) continue;
    const value = toCell(context.cellValue(name));
    if (JSON.stringify(cell.v) !== JSON.stringify(value)) updated.push(name);
    cell.v = value;
  }
  return updated;
}

// A Swift String-rendezés párja (a sorrend csak a determinizmushoz kell; az eredmény nem függ tőle).
const compareNames = (a, b) => a < b ? -1 : a > b ? 1 : 0;

export function dependents(changed, doc) {
  const single = new Map(), ranges = [];
  for (const [name, cell] of Object.entries(doc.cells)) {
    if (cell.f == null) continue;
    const expr = parsed(cell.f);
    if (!expr) continue;
    const refs = references(expr);
    for (const ref of refs.cells) if (ref.table == null) {
      const key = cellName(ref.row ?? 0, ref.col);
      if (!single.has(key)) single.set(key, []);
      single.get(key).push(name);
    }
    for (const [a, b] of refs.ranges) if (a.table == null) ranges.push([a, b, name]);
  }
  const result = new Set(changed.filter(name => doc.cells[name]?.f != null));
  const queue = [...changed], seen = new Set(changed);
  while (queue.length) {
    const name = queue.pop(), address = parseAddress(name);
    if (!address) continue;
    const users = [...(single.get(name) ?? [])];
    for (const [a, b, user] of ranges) {
      const inRows = a.row == null || (address.row >= Math.min(a.row, b.row) && address.row <= Math.max(a.row, b.row));
      if (inRows && address.col >= Math.min(a.col, b.col) && address.col <= Math.max(a.col, b.col)) users.push(user);
    }
    for (const user of users) if (!seen.has(user)) { seen.add(user); result.add(user); queue.push(user); }
  }
  return result;
}

// Kiértékelés: skalár belső érték, vagy {range: [értékek]}.
function evaluate(expr, context) {
  switch (expr.type) {
    case "number": return num(expr.value);
    case "text": return {t: "text", v: expr.value};
    case "bool": return {t: "bool", v: expr.value};
    case "error": return err(expr.value);
    case "name": return err("#NAME?");
    case "ref": return context.lookup(expr.ref, expr.ref.row ?? 0);
    case "range": {
      const values = context.rangeValues(expr.a, expr.b);
      return values ? {range: values} : err("#REF!");
    }
    case "unary": {
      const value = number(scalar(expr.x, context));
      if (value.t !== "number") return value;
      return num(expr.op === "-" ? -value.v : value.v);
    }
    case "percent": {
      const value = number(scalar(expr.x, context));
      return value.t === "number" ? num(value.v / 100) : value;
    }
    case "binary": return binary(expr.op, scalar(expr.a, context), scalar(expr.b, context));
    case "call": return call(expr.name, expr.args, context);
  }
  return err("#VALUE!");
}

function scalar(expr, context) {
  const value = evaluate(expr, context);
  return value.range ? err("#VALUE!") : value;
}

function number(value) {
  switch (value.t) {
    case "empty": return num(0);
    case "number": case "error": return value;
    case "bool": return num(value.v ? 1 : 0);
    case "text": {
      const trimmed = value.v.replace(/^[ \t ]+|[ \t ]+$/g, "");
      if (!trimmed) return num(0);
      const input = parseInput(trimmed);
      if (input.kind === "value" && typeof input.value === "number" && !trimmed.startsWith("=")) return num(input.value);
      return err("#VALUE!");
    }
  }
  return err("#VALUE!");
}

function text(value) {
  switch (value.t) {
    case "empty": return {t: "text", v: ""};
    case "number": return {t: "text", v: general(value.v)};
    case "bool": return {t: "text", v: value.v ? "IGAZ" : "HAMIS"};
    default: return value;
  }
}

function binary(op, left, right) {
  if (left.t === "error") return left;
  if (right.t === "error") return right;
  switch (op) {
    case "&": return {t: "text", v: text(left).v + text(right).v};
    case "=": case "<>": case "<": case ">": case "<=": case ">=": {
      const order = compare(left, right);
      return {t: "bool", v: {"=": order === 0, "<>": order !== 0, "<": order < 0, ">": order > 0, "<=": order <= 0, ">=": order >= 0}[op]};
    }
  }
  const a = number(left), b = number(right);
  if (a.t !== "number") return a;
  if (b.t !== "number") return b;
  switch (op) {
    case "+": return checked(a.v + b.v);
    case "-": return checked(a.v - b.v);
    case "*": return checked(a.v * b.v);
    case "/": return b.v === 0 ? err("#DIV/0!") : checked(a.v / b.v);
    case "^": return a.v === 0 && b.v === 0 ? err("#NUM!") : checked(Math.pow(a.v, b.v));
  }
  return err("#VALUE!");
}

// Excel-sorrend: szám < szöveg < logikai; a szöveg kis- és nagybetűtől függetlenül (Swift lowercased + <).
function compare(left, right) {
  const rank = v => ({number: 0, empty: 0, text: 1, bool: 2, error: 3})[v.t];
  let a = left, b = right;
  if (a.t === "empty") a = b.t === "text" ? {t: "text", v: ""} : b.t === "bool" ? {t: "bool", v: false} : num(0);
  if (b.t === "empty") b = a.t === "text" ? {t: "text", v: ""} : a.t === "bool" ? {t: "bool", v: false} : num(0);
  if (rank(a) !== rank(b)) return rank(a) < rank(b) ? -1 : 1;
  if (a.t === "number") return a.v < b.v ? -1 : a.v > b.v ? 1 : 0;
  if (a.t === "text") {
    const p = a.v.toLowerCase(), q = b.v.toLowerCase();
    return p < q ? -1 : p > q ? 1 : 0;
  }
  if (a.t === "bool") return a.v === b.v ? 0 : !a.v ? -1 : 1;
  return 0;
}

// Cellahivatkozás argumentumként úgy viselkedik, mint egy egycellás tartomány (Excel).
function asRange(arg, context) {
  const value = evaluate(arg, context);
  return arg.type === "ref" && !value.range ? {range: [value]} : value;
}

// Függvényargumentumok számai; hiba esetén {error}.
function numbers(args, context) {
  const result = [];
  for (const arg of args) {
    const value = asRange(arg, context);
    if (value.range) {
      for (const item of value.range) {
        if (item.t === "error") return {error: item.v};
        if (item.t === "number") result.push(item.v);
      }
    } else {
      if (value.t === "empty") continue;
      const n = number(value);
      if (n.t === "number") result.push(n.v);
      else if (n.t === "error") return {error: n.v};
    }
  }
  return {values: result};
}

function call(name, args, context) {
  switch (name) {
    case "SUM": case "AVERAGE": case "MIN": case "MAX": {
      if (!args.length) return err("#VALUE!");
      const {values, error} = numbers(args, context);
      if (error) return err(error);
      const sum = () => values.reduce((total, n) => total + n, 0);
      if (name === "SUM") return checked(sum());
      if (name === "AVERAGE") return values.length ? checked(sum() / values.length) : err("#DIV/0!");
      if (!values.length) return num(0);
      return num(name === "MIN" ? values.reduce((m, n) => n < m ? n : m) : values.reduce((m, n) => n > m ? n : m));
    }
    case "COUNT": {
      let count = 0;
      for (const arg of args) {
        const value = asRange(arg, context);
        if (value.range) count += value.range.filter(item => item.t === "number").length;
        else if (value.t !== "empty" && number(value).t === "number") count++;
      }
      return num(count);
    }
    case "ROUND": {
      if (args.length < 1 || args.length > 2) return err("#VALUE!");
      const value = number(scalar(args[0], context));
      if (value.t !== "number") return value;
      let digits = 0;
      if (args.length === 2) {
        const d = number(scalar(args[1], context));
        if (d.t !== "number") return d;
        digits = Math.trunc(d.v);
      }
      return checked(roundHalfAway(value.v, digits));
    }
    case "IF": {
      if (args.length < 2 || args.length > 3) return err("#VALUE!");
      const condition = scalar(args[0], context);
      let truth;
      switch (condition.t) {
        case "error": return condition;
        case "empty": truth = false; break;
        case "bool": truth = condition.v; break;
        case "number": truth = condition.v !== 0; break;
        case "text": {
          const upper = condition.v.toUpperCase();
          if (upper === "TRUE" || upper === "IGAZ") truth = true;
          else if (upper === "FALSE" || upper === "HAMIS") truth = false;
          else return err("#VALUE!");
        }
      }
      const pick = index => { const v = scalar(args[index], context); return v.t === "empty" ? num(0) : v; };
      if (truth) return pick(1);
      return args.length === 3 ? pick(2) : {t: "bool", v: false};
    }
  }
  return err("#NAME?");
}

export {same as sameValue};
