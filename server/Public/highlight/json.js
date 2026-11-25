import {code, isDigit, isSpace, isWord} from "./scanner.js";

// JSON (JSONLanguage.swift).
const QUOTE = code('"'), SLASH = code("/"), STAR = code("*"), COLON = code(":"), MINUS = code("-"), DOT = code("."), PLUS = code("+"), E = code("e");
const punctuation = new Set(["{", "}", "[", "]", ",", ":"].map(code));

export const jsonLanguage = {
  extensions: ["json"],
  scan(scanner) {
    while (!scanner.atEnd) {
      const unit = scanner.current, start = scanner.position;
      if (unit === QUOTE) {
        scanner.scanString();
        // Kulcs az a szöveg, amelyet (szóközök után) kettőspont követ.
        let next = scanner.position;
        while (next < scanner.end && isSpace(scanner.unit(next))) next++;
        if (next < scanner.end && scanner.unit(next) === COLON) scanner.relabelLast("p", start);
      } else if (unit === SLASH && scanner.peek() === SLASH) {
        scanner.scanLineComment();
      } else if (unit === SLASH && scanner.peek() === STAR) {
        scanner.scanBlockComment();
      } else if (punctuation.has(unit)) {
        scanner.position++;
        scanner.mark("o", start);
      } else if ((unit === MINUS && isDigit(scanner.peek())) || isDigit(unit)) {
        scanner.position++;
        scanner.skipWhile(isDigit);
        if (scanner.current === DOT && isDigit(scanner.peek())) {
          scanner.position++;
          scanner.skipWhile(isDigit);
        }
        if ((scanner.current | 0x20) === E) {
          const sign = scanner.peek() === PLUS || scanner.peek() === MINUS ? 1 : 0;
          if (isDigit(scanner.peek(1 + sign))) {
            scanner.position += 1 + sign;
            scanner.skipWhile(isDigit);
          }
        }
        scanner.mark("n", start);
      } else if (isWord(unit)) {
        scanner.skipWhile(isWord);
        const word = scanner.slice(start);
        if (word === "true" || word === "false" || word === "null") scanner.mark("k", start);
      } else {
        scanner.position++;
      }
    }
  },
};
