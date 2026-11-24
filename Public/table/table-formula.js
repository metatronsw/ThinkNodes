// Képletek: lexer, parser (AST), hivatkozás-átírás (EXCEL.md 4. fejezet).
// Swift párja: Sources/ThinkTable/TableFormula.swift – a kettő viselkedése egyezzen (Tests/TableFixtures).

import {columnIndex, columnName} from "./table-document.js";

export const aliases = {"SZUM": "SUM", "ÁTLAG": "AVERAGE", "DARAB": "COUNT", "KEREKÍTÉS": "ROUND", "HA": "IF"};
export const functions = new Set(["SUM", "AVERAGE", "MIN", "MAX", "COUNT", "ROUND", "IF"]);
const errorCodes = ["#DIV/0!", "#REF!", "#VALUE!", "#NAME?", "#N/A", "#NUM!", "#CIRC!", "#NULL!"];

export class FormulaSyntaxError extends Error {}
const fail = () => { throw new FormulaSyntaxError("Hibás képlet."); };

const isDigit = ch => ch != null && ch >= "0" && ch <= "9";
const isLetter = ch => ch != null && /\p{L}/u.test(ch);
const isIdentifier = ch => ch != null && /[\p{L}\p{N}_.$]/u.test(ch);
const isAsciiLetter = ch => ch != null && /[A-Za-z]/.test(ch);

export const refText = ref =>
  (ref.colAbs ? "$" : "") + columnName(ref.col) + (ref.row == null ? "" : (ref.rowAbs ? "$" : "") + (ref.row + 1));

// "A1", "$A$1", oszlop ("B", ha utána `:` jön).
export function parseRef(identifier, columnOnlyAllowed) {
  const chars = [...identifier];
  const ref = {table: null, row: null, col: 0, rowAbs: false, colAbs: false};
  let index = 0;
  if (chars[index] === "$") { ref.colAbs = true; index++; }
  let letters = "";
  while (index < chars.length && isAsciiLetter(chars[index])) letters += chars[index++];
  const col = letters ? columnIndex(letters) : null;
  if (!letters || letters.length > 3 || col == null) return null;
  ref.col = col;
  if (index === chars.length) return columnOnlyAllowed ? ref : null;
  if (chars[index] === "$") { ref.rowAbs = true; index++; }
  const digits = chars.slice(index).join("");
  if (!/^[1-9][0-9]*$/.test(digits)) return null;
  const row = Number(digits);
  if (row > 1048576) return null;
  ref.row = row - 1;
  return ref;
}

// Tokenek: {type, value?, ref?, prefix?, start, end}.
export function tokenize(source) {
  const decimalComma = source.includes(";");
  const chars = [...source];
  // Karakterindex → UTF-16 index (a Swift String.Index párja), hogy az átírás a forrásszöveget szeletelhesse.
  const offsets = [0];
  for (const ch of chars) offsets.push(offsets[offsets.length - 1] + ch.length);
  const tokens = [];
  let i = 0;
  const peek = (offset = 0) => chars[i + offset];
  const add = (token, start) => tokens.push({...token, start: offsets[start], end: offsets[i]});
  // Zárójelek: függvényhívásé-e. Függvényhíváson kívül a számjegyek közötti vessző tizedesvessző (=1,5*2),
  // belül elválasztó (SUM(1,5) = 6); pontosvesszős képletben mindig tizedesvessző (Swift: calls).
  const calls = [];

  // Egész oszlop (`B:B`): az első tag után `:` jön, a második előtt `:` és egy oszlophivatkozás áll.
  const afterColumnColon = () => {
    const last = tokens[tokens.length - 1], before = tokens[tokens.length - 2];
    return last?.type === "op" && last.value === ":" && before?.type === "ref" && before.ref.row == null;
  };
  const readRef = () => {
    let j = i, identifier = "";
    while (j < chars.length && isIdentifier(chars[j])) identifier += chars[j++];
    const ref = parseRef(identifier, chars[j] === ":" || afterColumnColon());
    if (ref) { i = j; return ref; }
    return null;
  };

  while (i < chars.length) {
    const c = chars[i], start = i;
    if (/\s/.test(c)) { i++; continue; }
    if (isDigit(c) || (c === "." && isDigit(peek(1)))) {
      let text = "";
      while (isDigit(peek())) text += chars[i++];
      if ((peek() === "." || (peek() === "," && (decimalComma || !calls.includes(true)))) && isDigit(peek(1))) {
        text += "."; i++;
        while (isDigit(peek())) text += chars[i++];
      } else if (peek() === ".") i++;
      if (peek() === "e" || peek() === "E") {
        const sign = peek(1), digitAt = sign === "+" || sign === "-" ? 2 : 1;
        if (isDigit(peek(digitAt))) {
          text += "e"; i++;
          if (digitAt === 2) { text += sign; i++; }
          while (isDigit(peek())) text += chars[i++];
        }
      }
      const value = Number(text.startsWith(".") ? "0" + text : text);
      if (Number.isNaN(value)) fail();
      add({type: "number", value}, start);
      continue;
    }
    if (c === "\"") {
      i++;
      let text = "", closed = false;
      while (i < chars.length) {
        const d = chars[i++];
        if (d === "\"") {
          if (peek() === "\"") { text += "\""; i++; } else { closed = true; break; }
        } else text += d;
      }
      if (!closed) fail();
      add({type: "text", value: text}, start);
      continue;
    }
    if (c === "#") {
      const rest = chars.slice(i).join("").toUpperCase();
      const code = errorCodes.find(code => rest.startsWith(code));
      if (!code) fail();
      i += [...code].length;
      add({type: "error", value: code}, start);
      continue;
    }
    if (c === "'" || c === "{") {
      const close = c === "'" ? "'" : "}";
      i++;
      let name = "", closed = false;
      while (i < chars.length) {
        const d = chars[i++];
        if (d === close) {
          if (close === "'" && peek() === "'") { name += "'"; i++; } else { closed = true; break; }
        } else name += d;
      }
      if (!closed || peek() !== "!") fail();
      i++;
      const prefix = chars.slice(start, i).join("");
      const ref = readRef();
      if (!ref) fail();
      ref.table = c === "{" ? "{" + name + "}" : name;
      add({type: "ref", ref, prefix}, start);
      continue;
    }
    if (isLetter(c) || c === "_" || c === "$") {
      let identifier = "";
      while (isIdentifier(peek())) identifier += chars[i++];
      if (peek() === "!") {
        i++;
        const prefix = chars.slice(start, i).join("");
        const ref = readRef();
        if (!ref) fail();
        ref.table = identifier;
        add({type: "ref", ref, prefix}, start);
        continue;
      }
      if (peek() === "(") {
        const upper = identifier.toUpperCase();
        add({type: "function", value: aliases[upper] ?? upper}, start);
        continue;
      }
      const ref = parseRef(identifier, peek() === ":" || afterColumnColon());
      if (ref) { add({type: "ref", ref, prefix: ""}, start); continue; }
      const upper = identifier.toUpperCase();
      if (upper === "TRUE" || upper === "IGAZ") add({type: "bool", value: true}, start);
      else if (upper === "FALSE" || upper === "HAMIS") add({type: "bool", value: false}, start);
      else add({type: "name", value: identifier}, start);
      continue;
    }
    const two = c + (peek(1) ?? "");
    if (["<=", ">=", "<>"].includes(two)) { i += 2; add({type: "op", value: two}, start); continue; }
    if ("+-*/^&=<>%:".includes(c)) { i++; add({type: "op", value: c}, start); continue; }
    if (c === "(") { calls.push(tokens[tokens.length - 1]?.type === "function"); i++; add({type: "open"}, start); continue; }
    if (c === ")") { calls.pop(); i++; add({type: "close"}, start); continue; }
    if (c === "," || c === ";") { i++; add({type: "separator"}, start); continue; }
    fail();
  }
  return tokens;
}

// AST: {type: "number"|"text"|"bool"|"error"|"name", value} | {type: "ref", ref} | {type: "range", a, b}
//      | {type: "unary", op, x} | {type: "percent", x} | {type: "binary", op, a, b} | {type: "call", name, args}
export function parse(source) {
  const tokens = tokenize(source);
  let position = 0;
  const peek = () => tokens[position];
  const next = () => tokens[position++];
  const isOp = op => peek()?.type === "op" && peek().value === op;
  const isOpIn = ops => peek()?.type === "op" && ops.includes(peek().value);

  const comparison = () => {
    let left = concat();
    while (isOpIn(["=", "<>", "<", ">", "<=", ">="])) { const op = next().value; left = {type: "binary", op, a: left, b: concat()}; }
    return left;
  };
  const concat = () => {
    let left = additive();
    while (isOp("&")) { next(); left = {type: "binary", op: "&", a: left, b: additive()}; }
    return left;
  };
  const additive = () => {
    let left = multiplicative();
    while (isOpIn(["+", "-"])) { const op = next().value; left = {type: "binary", op, a: left, b: multiplicative()}; }
    return left;
  };
  const multiplicative = () => {
    let left = power();
    while (isOpIn(["*", "/"])) { const op = next().value; left = {type: "binary", op, a: left, b: power()}; }
    return left;
  };
  const power = () => {
    let left = unary();
    while (isOp("^")) { next(); left = {type: "binary", op: "^", a: left, b: unary()}; }
    return left;
  };
  const unary = () => {
    if (isOpIn(["-", "+"])) { const op = next().value; return {type: "unary", op, x: unary()}; }
    return postfix();
  };
  const postfix = () => {
    let value = primary();
    while (isOp("%")) { next(); value = {type: "percent", x: value}; }
    return value;
  };
  const primary = () => {
    const token = next();
    if (!token) fail();
    switch (token.type) {
      case "number": case "text": case "bool": case "error": case "name": return {type: token.type, value: token.value};
      case "ref": {
        const first = token.ref;
        if (isOp(":") && tokens[position + 1]?.type === "ref") {
          const second = {...tokens[position + 1].ref};
          position += 2;
          if (second.table == null) second.table = first.table;
          if ((first.row == null) !== (second.row == null)) fail();
          return {type: "range", a: first, b: second};
        }
        if (first.row == null) fail();
        return {type: "ref", ref: first};
      }
      case "function": {
        if (next()?.type !== "open") fail();
        const args = [];
        if (peek()?.type === "close") { next(); return {type: "call", name: token.value, args}; }
        for (;;) {
          if (peek()?.type === "separator" || peek()?.type === "close") args.push({type: "text", value: ""});
          else args.push(comparison());
          const separator = next();
          if (!separator) fail();
          if (separator.type === "close") break;
          if (separator.type !== "separator") fail();
        }
        return {type: "call", name: token.value, args};
      }
      case "open": {
        const inner = comparison();
        if (next()?.type !== "close") fail();
        return inner;
      }
      default: fail();
    }
  };

  const expression = comparison();
  if (position !== tokens.length) fail();
  return expression;
}

export function references(expr) {
  const cells = [], ranges = [];
  const walk = e => {
    switch (e.type) {
      case "ref": cells.push(e.ref); break;
      case "range": ranges.push([e.a, e.b]); break;
      case "unary": case "percent": walk(e.x); break;
      case "binary": walk(e.a); walk(e.b); break;
      case "call": e.args.forEach(walk); break;
    }
  };
  walk(expr);
  return {cells, ranges};
}

// Token szintű átírás: csak a saját táblázatra mutató hivatkozások szövege változik (Swift rewrite).
function rewrite(formula, transform) {
  let tokens;
  try { tokens = tokenize(formula); } catch { return formula; }
  let result = "", cursor = 0;
  for (let index = 0; index < tokens.length; index++) {
    const token = tokens[index];
    if (token.type !== "ref" || token.ref.table != null) continue;
    result += formula.slice(cursor, token.start);
    let end = token.end, second = null;
    const colon = tokens[index + 1], following = tokens[index + 2];
    if (colon?.type === "op" && colon.value === ":" && following?.type === "ref" && following.ref.table == null) {
      second = following.ref; end = following.end; index += 2;
    }
    const out = transform({...token.ref}, second && {...second});
    result += out && out[0] ? token.prefix + refText(out[0]) + (out[1] ? ":" + refText(out[1]) : "") : "#REF!";
    cursor = end;
  }
  return result + formula.slice(cursor);
}

// Sorok/oszlopok beszúrása (count > 0) vagy törlése (count < 0) az `at` helytől (axis: "row" | "col").
export function shift(formula, axis, at, count) {
  const get = r => axis === "row" ? r.row : r.col;
  const set = (r, v) => { if (axis === "row") r.row = v; else r.col = v; };
  return rewrite(formula, (a, b) => {
    if (b) {
      const ia = get(a), ib = get(b);
      if (ia == null || ib == null) return [a, b];
      let lo = Math.min(ia, ib), hi = Math.max(ia, ib);
      if (count > 0) {
        if (lo >= at) lo += count;
        if (hi >= at) hi += count;
      } else {
        const end = at - count;
        if (lo >= at && hi < end) return null;
        if (lo >= end) lo += count; else if (lo >= at) lo = at;
        if (hi >= end) hi += count; else if (hi >= at) hi = at - 1;
      }
      set(a, ia <= ib ? lo : hi); set(b, ia <= ib ? hi : lo);
      return [a, b];
    }
    const ia = get(a);
    if (ia == null) return [a, null];
    if (count > 0) { if (ia >= at) set(a, ia + count); }
    else {
      const end = at - count;
      if (ia >= at && ia < end) return null;
      if (ia >= end) set(a, ia + count);
    }
    return [a, null];
  });
}

// Másolás / beillesztés: a relatív hivatkozások eltolódnak; ha a tábla szélén kívülre esnének, #REF!.
export function move(formula, rows, cols) {
  const moved = r => {
    if (!r.colAbs) r.col += cols;
    if (r.row != null && !r.rowAbs) r.row += rows;
    return r.col >= 0 && (r.row ?? 0) >= 0 ? r : null;
  };
  return rewrite(formula, (a, b) => {
    const ma = moved(a);
    if (!ma) return null;
    if (b) { const mb = moved(b); return mb ? [ma, mb] : null; }
    return [ma, null];
  });
}
