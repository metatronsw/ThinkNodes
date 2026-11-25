import {code, isDigit, isLetter, isSpace, isWord} from "./scanner.js";

// JavaScript (JavaScriptLanguage.swift). A `/` jelről a megelőző szakasz dönt: érték után osztás, egyébként
// reguláris kifejezés.
const keywords = new Set(["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else",
  "export", "extends", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "let", "new", "of", "return",
  "static", "switch", "throw", "try", "typeof", "var", "void", "while", "with", "yield"]);
/// Érték jellegű kulcsszavak: utánuk a `/` osztás.
const values = new Set(["false", "Infinity", "NaN", "null", "super", "this", "true", "undefined"]);
/// Egymásba ágyazott sablonszövegek legnagyobb mélysége: a rekurzió korlátja.
const maximumDepth = 24;

const SLASH = code("/"), STAR = code("*"), HASH = code("#"), BANG = code("!"), DQ = code('"'), SQ = code("'"), BACKTICK = code("`"), DOT = code("."),
  UNDERSCORE = code("_"), DOLLAR = code("$"), LPAREN = code("("), RPAREN = code(")"), LBRACKET = code("["), RBRACKET = code("]"), OPEN = code("{"),
  CLOSE = code("}"), PLUS = code("+"), MINUS = code("-"), E = code("e"), ZERO = code("0"), NEWLINE = 10, BACKSLASH = code("\\");

const isNameStart = unit => isLetter(unit) || unit === UNDERSCORE || unit === DOLLAR || unit >= 0x80;

/// Kód olvasása a végéig, illetve `depth > 0` esetén a sablonszöveg `${`-ját záró `}` jelig (a jelet nem lépi át).
function scanCode(scanner, depth) {
  let braces = 0;
  // Érték áll-e közvetlenül előttünk (ekkor a `/` osztás).
  let afterValue = false;
  while (!scanner.atEnd) {
    const unit = scanner.current, start = scanner.position;
    if (isSpace(unit)) scanner.position++;
    else if (unit === SLASH && scanner.peek() === SLASH) scanner.scanLineComment();
    else if (unit === SLASH && scanner.peek() === STAR) scanner.scanBlockComment();
    else if (unit === HASH && start === 0 && scanner.peek() === BANG) scanner.scanLineComment();
    else if (unit === DQ || unit === SQ) {
      scanner.scanString();
      afterValue = true;
    } else if (unit === BACKTICK) {
      template(scanner, depth);
      afterValue = true;
    } else if (unit === SLASH && !afterValue && regularExpression(scanner)) {
      afterValue = true;
    } else if (isDigit(unit) || (unit === DOT && isDigit(scanner.peek()))) {
      number(scanner);
      afterValue = true;
    } else if (isNameStart(unit)) {
      scanner.skipWhile(next => isWord(next) || next === DOLLAR);
      const word = scanner.slice(start);
      const member = start > 0 && scanner.unit(start - 1) === DOT && !(start > 1 && scanner.unit(start - 2) === DOT);
      afterValue = true;
      if (!member && keywords.has(word)) {
        scanner.mark("k", start);
        afterValue = false;
      } else if (!member && values.has(word)) {
        scanner.mark("k", start);
      } else if (unit >= 65 && unit <= 90) {
        scanner.mark("t", start);
      } else if (scanner.nextSignificant === LPAREN) {
        scanner.mark("f", start);
      } else if (member) {
        scanner.mark("p", start);
      }
    } else {
      if (unit === OPEN) braces++;
      if (unit === CLOSE) {
        if (depth > 0 && braces === 0) return;
        braces--;
      }
      scanner.position++;
      scanner.mark("o", start);
      afterValue = unit === RPAREN || unit === RBRACKET || unit === CLOSE;
    }
  }
}

/// Szám: tizedes, hexadecimális (0x…), kitevő (1e-5), elválasztó (1_000), BigInt (10n).
export function number(scanner) {
  const start = scanner.position;
  const prefixed = scanner.current === ZERO && isLetter(scanner.peek());
  while (!scanner.atEnd) {
    const unit = scanner.current;
    if (isWord(unit) || (unit === DOT && isDigit(scanner.peek()))) scanner.position++;
    else if (!prefixed && (unit === PLUS || unit === MINUS) && (scanner.peek(-1) | 0x20) === E && isDigit(scanner.peek())) scanner.position++;
    else break;
  }
  scanner.mark("n", start);
}

/// `/…/flags` a sor végéig; ha a sorban nincs záró `/`, nem reguláris kifejezés (`false`, a pozíció változatlan).
function regularExpression(scanner) {
  const start = scanner.position;
  let index = start + 1, inClass = false;
  while (index < scanner.end) {
    const unit = scanner.unit(index);
    if (unit === NEWLINE) return false;
    if (unit === BACKSLASH) { index += 2; continue; }
    if (unit === LBRACKET) inClass = true;
    else if (unit === RBRACKET) inClass = false;
    else if (unit === SLASH && !inClass) {
      scanner.position = index + 1;
      scanner.skipWhile(isLetter);
      scanner.mark("s", start);
      return true;
    }
    index++;
  }
  return false;
}

/// Sablonszöveg: a szövegrészek szövegként, a `${…}` belseje kódként.
function template(scanner, depth) {
  let start = scanner.position;
  scanner.position++;
  while (!scanner.atEnd) {
    const unit = scanner.current;
    if (unit === BACKSLASH) { scanner.position = Math.min(scanner.position + 2, scanner.end); continue; }
    if (unit === BACKTICK) { scanner.position++; break; }
    if (unit === DOLLAR && scanner.peek() === OPEN && depth < maximumDepth) {
      scanner.mark("s", start);
      const open = scanner.position;
      scanner.position += 2;
      scanner.mark("o", open);
      scanCode(scanner, depth + 1);
      if (scanner.current === CLOSE) {
        const close = scanner.position;
        scanner.position++;
        scanner.mark("o", close);
      }
      start = scanner.position;
      continue;
    }
    scanner.position++;
  }
  scanner.mark("s", start);
}

export const javaScriptLanguage = {
  extensions: ["js", "mjs", "cjs"],
  scan(scanner) { scanCode(scanner, 0); },
};
