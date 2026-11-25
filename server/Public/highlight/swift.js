import {code, isDigit, isLetter, isSpace, isWord} from "./scanner.js";
import {number} from "./javascript.js";

// Swift (SwiftLanguage.swift).
const keywords = new Set(["Any", "Self", "any", "as", "associatedtype", "async", "await", "borrowing", "break", "case", "catch", "class", "consuming",
  "continue", "convenience", "default", "defer", "deinit", "didSet", "do", "else", "enum", "extension", "fallthrough", "false",
  "fileprivate", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "mutating", "nil",
  "nonisolated", "nonmutating", "override", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "some",
  "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "unowned", "var", "weak",
  "where", "while", "willSet"]);
/// Csak bizonyos helyzetben kulcsszavak; ha hívás, értékadás vagy tagelérés követi őket, nem kapnak kulcsszó-színt.
const contextual = new Set(["actor", "dynamic", "final", "get", "indirect", "infix", "isolated", "lazy", "macro", "open", "operator", "optional",
  "package", "postfix", "precedencegroup", "prefix", "required", "set"]);
/// Egymásba ágyazott szövegbeágyazások legnagyobb mélysége: a rekurzió korlátja.
const maximumDepth = 24;

const SLASH = code("/"), STAR = code("*"), DQ = code('"'), HASH = code("#"), AT = code("@"), UNDERSCORE = code("_"), BACKTICK = code("`"), DOLLAR = code("$"),
  DOT = code("."), LPAREN = code("("), RPAREN = code(")"), NEWLINE = 10, BACKSLASH = code("\\");
/// Ami egy név (és nem kulcsszó) után áll: hívás, értékadás, tagelérés, felsorolás vége.
const afterName = new Set(["(", "=", ".", ",", ")", ":", "]"].map(code)).add(0);

/// Kód olvasása a végéig, illetve `depth > 0` esetén a `\(` beágyazást záró `)` jelig (a jelet nem lépi át).
function scanCode(scanner, depth) {
  let parentheses = 0;
  while (!scanner.atEnd) {
    const unit = scanner.current, start = scanner.position;
    if (isSpace(unit)) scanner.position++;
    else if (unit === SLASH && scanner.peek() === SLASH) scanner.scanLineComment();
    else if (unit === SLASH && scanner.peek() === STAR) blockComment(scanner);
    else if (unit === DQ) string(scanner, 0, depth);
    else if (unit === HASH) {
      let hashes = 0;
      while (scanner.peek(hashes) === HASH) hashes++;
      if (scanner.peek(hashes) === DQ) {
        string(scanner, hashes, depth);
      } else if (isLetter(scanner.peek())) {
        scanner.position++;
        scanner.skipWhile(isWord);
        scanner.mark("k", start);
      } else {
        scanner.position++;
        scanner.mark("o", start);
      }
    } else if (unit === AT && (isLetter(scanner.peek()) || scanner.peek() === UNDERSCORE)) {
      scanner.position++;
      scanner.skipWhile(isWord);
      scanner.mark("k", start);
    } else if (isDigit(unit)) {
      number(scanner);
    } else if (unit === BACKTICK) {
      // `class` – kulcsszó névként: színezetlen.
      scanner.position++;
      scanner.skipWhile(isWord);
      if (scanner.current === BACKTICK) scanner.position++;
    } else if (isLetter(unit) || unit === UNDERSCORE || unit === DOLLAR || unit >= 0x80) {
      scanner.skipWhile(next => isWord(next) || next === DOLLAR);
      const word = scanner.slice(start);
      const member = start > 0 && scanner.unit(start - 1) === DOT && !(start > 1 && scanner.unit(start - 2) === DOT);
      const next = scanner.nextSignificant;
      if (!member && keywords.has(word)) scanner.mark("k", start);
      else if (!member && contextual.has(word) && !afterName.has(next)) scanner.mark("k", start);
      else if (unit >= 65 && unit <= 90) scanner.mark("t", start);
      else if (next === LPAREN && scanner.current === next) scanner.mark("f", start);
      else if (member) scanner.mark("p", start);
    } else {
      if (unit === LPAREN) parentheses++;
      if (unit === RPAREN) {
        if (depth > 0 && parentheses === 0) return;
        parentheses--;
      }
      scanner.position++;
      scanner.mark("o", start);
    }
  }
}

/// `/* … */`, egymásba ágyazva is; lezáratlanul a végéig tart.
function blockComment(scanner) {
  const start = scanner.position;
  let depth = 0;
  while (!scanner.atEnd) {
    if (scanner.startsWith("/*")) { depth++; scanner.position += 2; }
    else if (scanner.startsWith("*/")) {
      depth--;
      scanner.position += 2;
      if (depth === 0) break;
    } else scanner.position++;
  }
  scanner.position = Math.min(scanner.position, scanner.end);
  scanner.mark("c", start);
}

/// Szöveg `hashes` darab `#` jellel (nyers szöveg) és egy vagy három idézőjellel; a beágyazás belseje kódként.
function string(scanner, hashes, depth) {
  let start = scanner.position;
  scanner.position += hashes;
  const multiline = scanner.startsWith('"""');
  scanner.position += multiline ? 3 : 1;
  const hashesFollow = offset => {
    for (let index = 0; index < hashes; index++) if (scanner.peek(offset + index) !== HASH) return false;
    return true;
  };
  while (!scanner.atEnd) {
    const unit = scanner.current;
    if (unit === NEWLINE && !multiline) break;
    if (unit === BACKSLASH && hashesFollow(1)) {
      if (scanner.peek(1 + hashes) === LPAREN && depth < maximumDepth) {
        scanner.mark("s", start);
        const open = scanner.position;
        scanner.position += 2 + hashes;
        scanner.mark("o", open);
        scanCode(scanner, depth + 1);
        if (scanner.current === RPAREN) {
          const close = scanner.position;
          scanner.position++;
          scanner.mark("o", close);
        }
        start = scanner.position;
        continue;
      }
      // Védett karakter (\" \\ \n …): a következő egység nem zárhatja a szöveget.
      const next = scanner.peek(1 + hashes);
      scanner.position = Math.min(scanner.position + 1 + hashes + (next === NEWLINE ? 0 : 1), scanner.end);
      continue;
    }
    if (unit === DQ && (!multiline || scanner.startsWith('"""')) && hashesFollow(multiline ? 3 : 1)) {
      scanner.position += (multiline ? 3 : 1) + hashes;
      break;
    }
    scanner.position++;
  }
  scanner.mark("s", start);
}

export const swiftLanguage = {
  extensions: ["swift"],
  scan(scanner) { scanCode(scanner, 0); },
};
