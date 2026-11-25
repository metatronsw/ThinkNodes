import {CodeScanner} from "./scanner.js";
import {jsonLanguage} from "./json.js";
import {cssLanguage} from "./css.js";
import {javaScriptLanguage} from "./javascript.js";
import {swiftLanguage} from "./swift.js";
import {htmlLanguage} from "./html.js";

// A színezett nyelvek (CodeHighlight.languages). Új nyelv: egy fájl itt és a Sources/ThinkHighlight mappában, egy-egy
// sor a két listában, és esetek a közös tesztkészletben (Tests/Fixtures/highlight.json).
const languages = [jsonLanguage, cssLanguage, javaScriptLanguage, swiftLanguage, htmlLanguage];
const byExtension = new Map(languages.flatMap(language => language.extensions.map(ext => [ext, language])));

/// E fölött (kódegység) a szakaszok már nem kapnak színt (CodeHighlight.colouredLimit).
export const colouredLimit = 100000;

export const supportsHighlight = ext => byExtension.has(String(ext ?? "").toLowerCase());

/// A forrás szakaszai: [{kind, start, end}]; `null`, ha a kiterjesztéshez nincs nyelv.
export function highlightTokens(text, ext) {
  const language = byExtension.get(String(ext ?? "").toLowerCase());
  if (!language) return null;
  const scanner = new CodeScanner(text);
  language.scan(scanner);
  return scanner.tokens;
}

const escapes = {"&": "&amp;", "<": "&lt;", ">": "&gt;"};
const escaped = text => text.replace(/[&<>]/g, character => escapes[character]);

/// A forrás HTML-ként, a szakaszok `<span class="hl-…">` elemekben; `null`, ha a kiterjesztéshez nincs nyelv.
export function highlightHTML(text, ext) {
  const tokens = highlightTokens(text, ext);
  if (!tokens) return null;
  let output = "", position = 0;
  for (const token of tokens) {
    if (token.start < position || token.end > text.length) continue;
    if (token.start >= colouredLimit) break;
    output += escaped(text.slice(position, token.start)) + '<span class="hl-' + token.kind + '">' + escaped(text.slice(token.start, token.end)) + "</span>";
    position = token.end;
  }
  return output + escaped(text.slice(position));
}
