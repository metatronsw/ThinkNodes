import Foundation

/// Kódszínezés (docs/node-types.md, `code` típus): saját, könnyű elemző. A szerver bontja szakaszokra a forrást,
/// a kliens csak megjeleníti a kész HTML-t. Nem nyelvtani elemzés: megjegyzés, szöveg, szám, kulcsszó, név szintjén
/// színez; a tévedés legfeljebb rossz szín, a fájl tartalmát nem érinti.
///
/// Önálló modul (ThinkHighlight): nem függ a szervertől, csak a Foundationtől.
///
/// Új nyelv: egy fájl ebben a mappában (`CodeLanguage`), és egy sor a `CodeHighlight.languages` listában.

/// Színkategóriák; a CSS-osztály `hl-` + a nyers érték (Public/app.css).
package enum CodeTokenKind: String, Sendable {
    case comment = "c"
    case string = "s"
    case number = "n"
    case keyword = "k"
    /// Tulajdonság- vagy kulcsnév (JSON kulcs, CSS tulajdonság).
    case name = "p"
    /// Típus jellegű név (CSS szelektor; később: Swift típus, HTML elem).
    case type = "t"
    case function = "f"
    case punctuation = "o"
}

package struct CodeToken: Equatable, Sendable {
    package var kind: CodeTokenKind
    /// UTF-8 bájtpozíciók a forrásban.
    package var range: Range<Int>
}

/// Egy nyelv elemzője: a forrás bájtjait olvassa, és a színezett szakaszokat a `scanner`-be írja.
/// Amit nem jelöl meg, az a doboz szövegszínével jelenik meg.
package protocol CodeLanguage: Sendable {
    /// Kisbetűs kiterjesztések, pont nélkül.
    var extensions: [String] { get }
    func scan(_ scanner: inout CodeScanner)
}

/// A nyelvek közös olvasója. Bájtokon dolgozik: a nyelvek minden jele ASCII, a 0x80 fölötti bájt névkarakternek
/// számít, így a szakaszhatárok sosem vágnak ketté UTF-8 karaktert.
package struct CodeScanner {
    package let bytes: [UInt8]
    package var position = 0
    package private(set) var tokens: [CodeToken] = []

    /// Az olvasás vége: a forrás vége, beágyazott nyelvnél (HTML-ben `<script>`, `<style>`) a beágyazott rész vége.
    package private(set) var end: Int

    package init(_ text: String) {
        bytes = Array(text.utf8)
        end = bytes.count
    }

    /// Beágyazott nyelv: a `limit` pozícióig a másik nyelv elemzője olvas, utána az olvasó ott folytatja.
    package mutating func scan(_ language: any CodeLanguage, until limit: Int) {
        let outer = end
        end = max(position, min(limit, outer))
        language.scan(&self)
        position = end
        end = outer
    }

    /// A következő nem szóköz bájt az aktuális pozíciótól (0 a végén).
    package var nextSignificant: UInt8 {
        var index = position
        while index < end, bytes[index].isSpace { index += 1 }
        return index < end ? bytes[index] : 0
    }

    /// Az utoljára megjelölt szakasz az aktuális pozíció előtt, a köztes szóközöket átlépve; `nil`, ha jelöletlen szöveg áll ott.
    package var previousToken: CodeToken? {
        var index = position
        while index > 0, bytes[index - 1].isSpace { index -= 1 }
        guard let last = tokens.last, last.range.upperBound == index else { return nil }
        return last
    }

    package var atEnd: Bool { position >= end }
    /// Az aktuális bájt, a végén 0.
    package var current: UInt8 { position < end ? bytes[position] : 0 }
    package func peek(_ offset: Int = 1) -> UInt8 {
        let index = position + offset
        return index >= 0 && index < end ? bytes[index] : 0
    }

    package func starts(with text: StaticString, at index: Int? = nil) -> Bool {
        let start = index ?? position
        guard start + text.utf8CodeUnitCount <= end else { return false }
        return text.withUTF8Buffer { buffer in
            for offset in 0..<buffer.count where bytes[start + offset] != buffer[offset] { return false }
            return true
        }
    }

    /// Szakasz megjelölése `start`-tól az aktuális pozícióig; az azonos fajtájú szomszédok összeolvadnak.
    package mutating func mark(_ kind: CodeTokenKind, from start: Int) {
        guard start < position else { return }
        if let last = tokens.last, last.kind == kind, last.range.upperBound == start {
            tokens[tokens.count - 1].range = last.range.lowerBound..<position
        } else {
            tokens.append(CodeToken(kind: kind, range: start..<position))
        }
    }

    /// Az utoljára megjelölt, `start`-nál kezdődő szakasz átsorolása (pl. a szövegről utólag derül ki, hogy kulcs).
    package mutating func relabelLast(_ kind: CodeTokenKind, from start: Int) {
        guard let last = tokens.last, last.range.upperBound == position, last.range.lowerBound <= start else { return }
        tokens.removeLast()
        if last.range.lowerBound < start { tokens.append(CodeToken(kind: last.kind, range: last.range.lowerBound..<start)) }
        tokens.append(CodeToken(kind: kind, range: start..<position))
    }

    package mutating func skipWhile(_ matches: (UInt8) -> Bool) {
        while position < end, matches(bytes[position]) { position += 1 }
    }

    /// Idézőjeles szöveg a záró jelig (vagy a sor végéig, ha nincs lezárva); `\` a következő bájtot védi.
    package mutating func scanString(as kind: CodeTokenKind = .string) {
        let start = position, quote = current
        position += 1
        while position < end {
            let byte = bytes[position]
            if byte == UInt8(ascii: "\\"), position + 1 < end, bytes[position + 1] != UInt8(ascii: "\n") { position += 2; continue }
            if byte == UInt8(ascii: "\n") { break }
            position += 1
            if byte == quote { break }
        }
        mark(kind, from: start)
    }

    /// `/* … */` megjegyzés; lezáratlanul a fájl végéig tart.
    package mutating func scanBlockComment() {
        let start = position
        position += 2
        while position < end, !(bytes[position] == UInt8(ascii: "*") && peek() == UInt8(ascii: "/")) { position += 1 }
        position = min(position + 2, end)
        mark(.comment, from: start)
    }

    /// `// …` megjegyzés a sor végéig.
    package mutating func scanLineComment() {
        let start = position
        skipWhile { $0 != UInt8(ascii: "\n") }
        mark(.comment, from: start)
    }
}

package extension UInt8 {
    var isDigit: Bool { self >= 48 && self <= 57 }
    var isLetter: Bool { (self | 0x20) >= 97 && (self | 0x20) <= 122 }
    var isHexDigit: Bool { isDigit || ((self | 0x20) >= 97 && (self | 0x20) <= 102) }
    var isSpace: Bool { self == 32 || self == 9 || self == 10 || self == 13 || self == 12 }
    /// Névkarakter: betű, szám, `_`, vagy nem ASCII bájt.
    var isWord: Bool { isLetter || isDigit || self == 95 || self >= 0x80 }
}

package enum CodeHighlight {
    /// A színezett nyelvek. Új nyelv felvétele: egy új sor.
    static let languages: [any CodeLanguage] = [JSONLanguage(), CSSLanguage(), JavaScriptLanguage(), SwiftLanguage(), HTMLLanguage()]

    private static let byExtension: [String: any CodeLanguage] = {
        var result: [String: any CodeLanguage] = [:]
        for language in languages { for ext in language.extensions { result[ext] = language } }
        return result
    }()

    /// A színek szabályai, soronként egy; szó szerint megegyeznek a `Public/app.css` szabályaival (teszt őrzi).
    /// Az önálló SVG-be (letöltés, előnézeti kép) ezek ágyazódnak be, mert ott nincs stíluslap.
    package static let colourRules = [
        ".hl-c { color: color-mix(in srgb, currentColor 55%, transparent); font-style: italic; }",
        ".hl-o { color: color-mix(in srgb, currentColor 65%, transparent); }",
        ".hl-s { color: color-mix(in oklab, currentColor 35%, #2f9e44); }",
        ".hl-n { color: color-mix(in oklab, currentColor 35%, #e8750a); }",
        ".hl-k { color: color-mix(in oklab, currentColor 35%, #d6336c); }",
        ".hl-p { color: color-mix(in oklab, currentColor 35%, #1c7ed6); }",
        ".hl-t { color: color-mix(in oklab, currentColor 35%, #0c9aa6); }",
        ".hl-f { color: color-mix(in oklab, currentColor 35%, #7950f2); }",
    ]

    /// E fölött (bájt) a szakaszok már nem kapnak színt: a vásznon a sok ezer `<span>` lassítja a nagyítást.
    package static let colouredLimit = 100_000

    package static func supports(_ ext: String) -> Bool { byExtension[ext.lowercased()] != nil }

    package static func tokens(_ text: String, ext: String) -> [CodeToken]? {
        guard let language = byExtension[ext.lowercased()] else { return nil }
        var scanner = CodeScanner(text)
        language.scan(&scanner)
        return scanner.tokens
    }

    /// A forrás HTML-ként, a szakaszok `<span class="hl-…">` elemekben; `nil`, ha a kiterjesztéshez nincs nyelv.
    package static func html(_ text: String, ext: String) -> String? {
        guard let language = byExtension[ext.lowercased()] else { return nil }
        var scanner = CodeScanner(text)
        language.scan(&scanner)
        let bytes = scanner.bytes
        var output = [UInt8]()
        output.reserveCapacity(bytes.count + bytes.count / 2)
        func append(_ range: Range<Int>) {
            for byte in bytes[range] {
                switch byte {
                case UInt8(ascii: "&"): output.append(contentsOf: Array("&amp;".utf8))
                case UInt8(ascii: "<"): output.append(contentsOf: Array("&lt;".utf8))
                case UInt8(ascii: ">"): output.append(contentsOf: Array("&gt;".utf8))
                default: output.append(byte)
                }
            }
        }
        var position = 0
        for token in scanner.tokens {
            // A szakaszok növekvő sorrendben, átfedés nélkül követik egymást; a hibásat kihagyjuk.
            guard token.range.lowerBound >= position, token.range.upperBound <= bytes.count else { continue }
            if token.range.lowerBound >= colouredLimit { break }
            append(position..<token.range.lowerBound)
            output.append(contentsOf: Array("<span class=\"hl-\(token.kind.rawValue)\">".utf8))
            append(token.range)
            output.append(contentsOf: Array("</span>".utf8))
            position = token.range.upperBound
        }
        append(position..<bytes.count)
        return String(decoding: output, as: UTF8.self)
    }
}
