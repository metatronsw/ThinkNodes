import {code, isDigit, isLetter, isSpace, isWord} from "./scanner.js";
import {cssLanguage} from "./css.js";
import {javaScriptLanguage} from "./javascript.js";
import {jsonLanguage} from "./json.js";

// HTML (HTMLLanguage.swift): a `<script>` tartalma JavaScriptként (JSON típusnál JSON-ként), a `<style>` tartalma CSS-ként.
const LT = code("<"), GT = code(">"), BANG = code("!"), QUESTION = code("?"), SLASH = code("/"), AMP = code("&"), HASH = code("#"), SEMI = code(";"),
  MINUS = code("-"), COLON = code(":"), EQUALS = code("="), DQ = code('"'), SQ = code("'");

/// `&név;`, `&#123;`, `&#x1F;` – legfeljebb 32 egység; más `&` sima szöveg.
function entity(scanner) {
  let index = scanner.position + 1;
  while (index < scanner.end && index - scanner.position < 32 && (isLetter(scanner.unit(index)) || isDigit(scanner.unit(index)) || scanner.unit(index) === HASH)) index++;
  if (!(index < scanner.end && index > scanner.position + 1 && scanner.unit(index) === SEMI)) return false;
  const start = scanner.position;
  scanner.position = index + 1;
  scanner.mark("k", start);
  return true;
}

/// Nyitó vagy záró címke a `>` jelig; `<script>` és `<style>` után a tartalom a beágyazott nyelv szerint.
function tag(scanner) {
  let start = scanner.position;
  const closing = scanner.peek() === SLASH;
  scanner.position += closing ? 2 : 1;
  scanner.mark("o", start);
  start = scanner.position;
  scanner.skipWhile(unit => isWord(unit) || unit === MINUS || unit === COLON);
  const name = scanner.slice(start).toLowerCase();
  scanner.mark("t", start);
  // A script nyelvét a `type` attribútum dönti el (nélküle JavaScript).
  let scriptType = "", attribute = "", ended = false;
  while (!scanner.atEnd) {
    const unit = scanner.current;
    start = scanner.position;
    if (unit === GT || (unit === SLASH && scanner.peek() === GT)) {
      scanner.position += unit === GT ? 1 : 2;
      scanner.mark("o", start);
      ended = true;
      break;
    }
    // Lezáratlan címke: a következő címke kezdeténél abbahagyjuk.
    if (unit === LT) return;
    if (isSpace(unit) || unit === SLASH) { scanner.position++; continue; }
    if (unit === EQUALS) {
      scanner.position++;
      scanner.mark("o", start);
      scanner.skipWhile(isSpace);
      const value = scanner.position, quote = scanner.current;
      if (quote === DQ || quote === SQ) {
        // A HTML-ben nincs `\` védés, és az érték több soros is lehet.
        scanner.position++;
        scanner.skipWhile(next => next !== quote);
        scanner.position = Math.min(scanner.position + 1, scanner.end);
      } else {
        scanner.skipWhile(next => !isSpace(next) && next !== GT);
      }
      scanner.mark("s", value);
      if (name === "script" && attribute === "type") scriptType = scanner.slice(value).toLowerCase();
      continue;
    }
    // Attribútumnév.
    scanner.skipWhile(next => !isSpace(next) && next !== EQUALS && next !== GT && next !== SLASH && next !== LT);
    if (scanner.position === start) scanner.position++;
    attribute = scanner.slice(start).toLowerCase();
    scanner.mark("p", start);
  }
  if (closing || !(name === "script" || name === "style")) return;
  // A tartalom a záró címkéig (kis- és nagybetűtől függetlenül), annak híján a végéig.
  const terminator = "</" + name;
  let limit = scanner.position;
  while (limit < scanner.end) {
    if (scanner.unit(limit) === LT && limit + terminator.length <= scanner.end) {
      let matches = true;
      for (let offset = 1; offset < terminator.length; offset++) {
        if ((scanner.unit(limit + offset) | 0x20) !== (terminator.charCodeAt(offset) | 0x20)) { matches = false; break; }
      }
      if (matches) break;
    }
    limit++;
  }
  if (name === "style") scanner.scan(cssLanguage, limit);
  else if (scriptType.includes("json")) scanner.scan(jsonLanguage, limit);
  else if (scriptType === "" || scriptType.includes("javascript") || scriptType.includes("module")) scanner.scan(javaScriptLanguage, limit);
  else scanner.position = limit;
}

export const htmlLanguage = {
  extensions: ["html", "htm"],
  scan(scanner) {
    while (!scanner.atEnd) {
      const unit = scanner.current, start = scanner.position;
      if (scanner.startsWith("<!--")) {
        scanner.position += 4;
        while (!scanner.atEnd && !scanner.startsWith("-->")) scanner.position++;
        scanner.position = Math.min(scanner.position + 3, scanner.end);
        scanner.mark("c", start);
      } else if (unit === LT && (scanner.peek() === BANG || scanner.peek() === QUESTION)) {
        // <!DOCTYPE html>, <?xml … ?>
        scanner.skipWhile(next => next !== GT);
        scanner.position = Math.min(scanner.position + 1, scanner.end);
        scanner.mark("k", start);
      } else if (unit === LT && (isLetter(scanner.peek()) || (scanner.peek() === SLASH && isLetter(scanner.peek(2))))) {
        tag(scanner);
      } else if (unit === AMP && entity(scanner)) {
        continue;
      } else {
        scanner.position++;
      }
    }
  },
};
