// Kódszínezés a böngészőben, szerkesztés közben: a szerveroldali ThinkHighlight modul (Sources/ThinkHighlight) pontos
// mása. A két oldal egyezését közös tesztkészlet őrzi (Tests/Fixtures/highlight.json). Nyelvenként egy fájl; a
// felépítés és a nevek a Swift-fájlokét követik, hogy a kettő sorról sorra összevethető legyen.
//
// A Swift-változat UTF-8 bájtokon, ez UTF-16 kódegységeken dolgozik; a nyelvek minden jele ASCII, a 0x80 fölötti
// egység mindkét oldalon névkarakter, ezért a szakaszok szövege azonos.

export const code = character => character.charCodeAt(0);
export const isDigit = unit => unit >= 48 && unit <= 57;
export const isLetter = unit => (unit | 0x20) >= 97 && (unit | 0x20) <= 122 && unit < 0x80;
export const isHexDigit = unit => isDigit(unit) || ((unit | 0x20) >= 97 && (unit | 0x20) <= 102 && unit < 0x80);
export const isSpace = unit => unit === 32 || unit === 9 || unit === 10 || unit === 13 || unit === 12;
/// Névkarakter: betű, szám, `_`, vagy nem ASCII egység.
export const isWord = unit => isLetter(unit) || isDigit(unit) || unit === 95 || unit >= 0x80;

const NEWLINE = 10, BACKSLASH = 92, STAR = 42, SLASH = 47;

/// A nyelvek közös olvasója (CodeScanner). Szakasz: {kind, start, end}; kind a CSS-osztály betűje (`hl-` + kind).
export class CodeScanner {
  constructor(text) {
    this.text = text;
    this.position = 0;
    this.end = text.length;
    this.tokens = [];
  }
  /// Egység a megadott helyen, a szöveg határain kívül 0 (a Swiftben `bytes[index]`).
  unit(index) { return index >= 0 && index < this.text.length ? this.text.charCodeAt(index) : 0; }
  get atEnd() { return this.position >= this.end; }
  get current() { return this.position < this.end ? this.text.charCodeAt(this.position) : 0; }
  peek(offset = 1) {
    const index = this.position + offset;
    return index >= 0 && index < this.end ? this.text.charCodeAt(index) : 0;
  }
  startsWith(text, index = this.position) {
    return index + text.length <= this.end && this.text.startsWith(text, index);
  }
  slice(start, end = this.position) { return this.text.slice(start, end); }

  /// Beágyazott nyelv: a `limit` pozícióig a másik nyelv elemzője olvas, utána az olvasó ott folytatja.
  scan(language, limit) {
    const outer = this.end;
    this.end = Math.max(this.position, Math.min(limit, outer));
    language.scan(this);
    this.position = this.end;
    this.end = outer;
  }
  /// A következő nem szóköz egység az aktuális pozíciótól (0 a végén).
  get nextSignificant() {
    let index = this.position;
    while (index < this.end && isSpace(this.text.charCodeAt(index))) index++;
    return index < this.end ? this.text.charCodeAt(index) : 0;
  }

  /// Szakasz megjelölése `start`-tól az aktuális pozícióig; az azonos fajtájú szomszédok összeolvadnak.
  mark(kind, start) {
    if (start >= this.position) return;
    const last = this.tokens.at(-1);
    if (last && last.kind === kind && last.end === start) last.end = this.position;
    else this.tokens.push({kind, start, end: this.position});
  }
  /// Az utoljára megjelölt, `start`-nál kezdődő szakasz átsorolása.
  relabelLast(kind, start) {
    const last = this.tokens.at(-1);
    if (!last || last.end !== this.position || last.start > start) return;
    this.tokens.pop();
    if (last.start < start) this.tokens.push({kind: last.kind, start: last.start, end: start});
    this.tokens.push({kind, start, end: this.position});
  }
  skipWhile(matches) {
    while (this.position < this.end && matches(this.text.charCodeAt(this.position))) this.position++;
  }
  /// Idézőjeles szöveg a záró jelig (vagy a sor végéig, ha nincs lezárva); `\` a következő egységet védi.
  scanString(kind = "s") {
    const start = this.position, quote = this.current;
    this.position++;
    while (this.position < this.end) {
      const unit = this.text.charCodeAt(this.position);
      if (unit === BACKSLASH && this.position + 1 < this.end && this.text.charCodeAt(this.position + 1) !== NEWLINE) { this.position += 2; continue; }
      if (unit === NEWLINE) break;
      this.position++;
      if (unit === quote) break;
    }
    this.mark(kind, start);
  }
  /// `/* … */` megjegyzés; lezáratlanul a végéig tart.
  scanBlockComment() {
    const start = this.position;
    this.position += 2;
    while (this.position < this.end && !(this.text.charCodeAt(this.position) === STAR && this.peek() === SLASH)) this.position++;
    this.position = Math.min(this.position + 2, this.end);
    this.mark("c", start);
  }
  /// `// …` megjegyzés a sor végéig.
  scanLineComment() {
    const start = this.position;
    this.skipWhile(unit => unit !== NEWLINE);
    this.mark("c", start);
  }
}
