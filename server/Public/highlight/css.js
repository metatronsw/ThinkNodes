import {code, isDigit, isHexDigit, isLetter, isSpace, isWord} from "./scanner.js";

// CSS (CSSLanguage.swift): tételek sora; bevezető (szelektor, @-szabály feje), amelyet `{` követ, vagy deklaráció.
const OPEN = code("{"), CLOSE = code("}"), SEMI = code(";"), AT = code("@"), DQ = code('"'), SQ = code("'"), NEWLINE = 10, BACKSLASH = code("\\"),
  SLASH = code("/"), STAR = code("*"), LPAREN = code("("), RPAREN = code(")"), MINUS = code("-"), COLON = code(":"), BANG = code("!"), HASH = code("#"),
  PLUS = code("+"), DOT = code("."), PERCENT = code("%"), UNDERSCORE = code("_");
const selectorExtra = new Set(["-", ".", "#", ":", "&", "*", "%", "\\"].map(code));
const valuePunctuation = new Set([",", "/", ":", "=", "<", ">", "+", "-", "*", "[", "]"].map(code));
const isSelectorUnit = unit => isWord(unit) || selectorExtra.has(unit);
const isNameUnit = unit => isWord(unit) || unit === MINUS;

function skipBlank(scanner) {
  while (!scanner.atEnd) {
    if (isSpace(scanner.current)) scanner.position++;
    else if (scanner.startsWith("/*")) scanner.scanBlockComment();
    else break;
  }
}

/// A tételt záró jel: `{`, `}` bárhol, `;` csak zárójelen kívül. 0 = vége.
function terminator(scanner) {
  let index = scanner.position, depth = 0;
  while (index < scanner.end) {
    const unit = scanner.unit(index);
    if (unit === DQ || unit === SQ) {
      index++;
      while (index < scanner.end && scanner.unit(index) !== unit && scanner.unit(index) !== NEWLINE) index += scanner.unit(index) === BACKSLASH ? 2 : 1;
    } else if (unit === SLASH && index + 1 < scanner.end && scanner.unit(index + 1) === STAR) {
      index += 2;
      while (index < scanner.end && !(scanner.unit(index) === STAR && index + 1 < scanner.end && scanner.unit(index + 1) === SLASH)) index++;
      index++;
    } else if (unit === LPAREN) depth++;
    else if (unit === RPAREN) depth = Math.max(0, depth - 1);
    else if (unit === OPEN || unit === CLOSE) return unit;
    else if (unit === SEMI && depth === 0) return unit;
    index++;
  }
  return 0;
}

function prelude(scanner) {
  if (scanner.current === AT) {
    const start = scanner.position;
    scanner.position++;
    scanner.skipWhile(isNameUnit);
    scanner.mark("k", start);
    values(scanner);
    return;
  }
  while (!scanner.atEnd) {
    const unit = scanner.current, start = scanner.position;
    if (unit === OPEN || unit === CLOSE) return;
    if (isSpace(unit)) scanner.position++;
    else if (scanner.startsWith("/*")) scanner.scanBlockComment();
    else if (unit === DQ || unit === SQ) scanner.scanString();
    else if (isSelectorUnit(unit)) {
      while (!scanner.atEnd && isSelectorUnit(scanner.current)) scanner.position += scanner.current === BACKSLASH ? 2 : 1;
      scanner.position = Math.min(scanner.position, scanner.end);
      scanner.mark("t", start);
    } else {
      scanner.position++;
      scanner.mark("o", start);
    }
  }
}

function declaration(scanner) {
  const start = scanner.position;
  scanner.skipWhile(isNameUnit);
  let next = scanner.position;
  while (next < scanner.end && isSpace(scanner.unit(next))) next++;
  if (scanner.position > start && next < scanner.end && scanner.unit(next) === COLON) {
    scanner.mark("p", start);
    scanner.position = next + 1;
    scanner.mark("o", next);
  } else {
    scanner.position = start;
  }
  values(scanner);
}

/// Szám kezdete: számjegy, `.5`, vagy előjel után ezek egyike.
function startsNumber(scanner) {
  const unit = scanner.current;
  if (isDigit(unit)) return true;
  if (unit === DOT) return isDigit(scanner.peek());
  if (unit !== PLUS && unit !== MINUS) return false;
  return isDigit(scanner.peek()) || (scanner.peek() === DOT && isDigit(scanner.peek(2)));
}

/// Értékek a tétel végéig: a `{`, `}` és a zárójelen kívüli `;` előtt áll meg.
function values(scanner) {
  let depth = 0;
  while (!scanner.atEnd) {
    const unit = scanner.current, start = scanner.position;
    if (unit === OPEN || unit === CLOSE) return;
    if (unit === SEMI && depth === 0) return;
    if (isSpace(unit)) scanner.position++;
    else if (unit === SLASH && scanner.peek() === STAR) scanner.scanBlockComment();
    else if (unit === DQ || unit === SQ) scanner.scanString();
    else if (unit === LPAREN || unit === RPAREN) {
      depth = unit === LPAREN ? depth + 1 : Math.max(0, depth - 1);
      scanner.position++;
      scanner.mark("o", start);
    } else if (unit === BANG && isLetter(scanner.peek())) {
      scanner.position++;
      scanner.skipWhile(isNameUnit);
      scanner.mark("k", start);
    } else if (unit === HASH && isHexDigit(scanner.peek())) {
      scanner.position++;
      scanner.skipWhile(isWord);
      scanner.mark("n", start);
    } else if (startsNumber(scanner)) {
      if (unit === PLUS || unit === MINUS) scanner.position++;
      scanner.skipWhile(isDigit);
      if (scanner.current === DOT && isDigit(scanner.peek())) {
        scanner.position++;
        scanner.skipWhile(isDigit);
      }
      // Mértékegység: px, em, %, …
      if (scanner.current === PERCENT) scanner.position++; else scanner.skipWhile(isLetter);
      scanner.mark("n", start);
    } else if (isLetter(unit) || unit === UNDERSCORE || (unit === MINUS && (isLetter(scanner.peek()) || scanner.peek() === MINUS || scanner.peek() === UNDERSCORE)) || unit >= 0x80) {
      scanner.skipWhile(isNameUnit);
      if (scanner.current === LPAREN) {
        scanner.mark("f", start);
        const name = scanner.slice(start);
        const quoted = scanner.peek() === DQ || scanner.peek() === SQ;
        if (name.length === 3 && [...name].every((character, index) => (code(character) | 0x20) === code("url"[index])) && !quoted) {
          // Idézőjel nélküli url(…): a cím egyben, szövegként.
          const open = scanner.position;
          scanner.position++;
          scanner.mark("o", open);
          const content = scanner.position;
          scanner.skipWhile(next => next !== RPAREN && next !== NEWLINE);
          scanner.mark("s", content);
          if (scanner.current === RPAREN) {
            const close = scanner.position;
            scanner.position++;
            scanner.mark("o", close);
          }
        }
      } else if (scanner.startsWith("--", start)) {
        scanner.mark("p", start);
      }
    } else if (valuePunctuation.has(unit)) {
      scanner.position++;
      scanner.mark("o", start);
    } else {
      scanner.position++;
    }
  }
}

export const cssLanguage = {
  extensions: ["css"],
  scan(scanner) {
    while (!scanner.atEnd) {
      skipBlank(scanner);
      if (scanner.atEnd) break;
      const start = scanner.position;
      if (scanner.current === CLOSE || scanner.current === SEMI || scanner.current === OPEN) {
        scanner.position++;
        scanner.mark("o", start);
      } else if (scanner.current === AT || terminator(scanner) === OPEN) {
        prelude(scanner);
      } else {
        declaration(scanner);
      }
      // Biztosíték: a tétel mindig halad előre.
      if (scanner.position === start) scanner.position++;
    }
  },
};
