/// CSS: megjegyzés, szelektor, @-szabály, tulajdonságnév, érték (szám mértékegységgel, szín, szöveg, függvény,
/// `!important`), írásjelek. Egymásba ágyazott szabályokat is kezel.
///
/// A fájl tételek sora. Egy tétel vagy bevezető (szelektor, @-szabály feje), amelyet `{` követ, vagy deklaráció
/// (`tulajdonság: érték`), amelyet `;` vagy `}` zár. Hogy melyik, azt az dönti el, melyik jel jön előbb – így a
/// blokkon belüli `a:hover { … }` szelektor, a `color: red;` deklaráció marad.
struct CSSLanguage: CodeLanguage {
    let extensions = ["css"]

    func scan(_ scanner: inout CodeScanner) {
        while !scanner.atEnd {
            skipBlank(&scanner)
            guard !scanner.atEnd else { break }
            let start = scanner.position
            if scanner.current == UInt8(ascii: "}") || scanner.current == UInt8(ascii: ";") || scanner.current == UInt8(ascii: "{") {
                scanner.position += 1
                scanner.mark(.punctuation, from: start)
            } else if scanner.current == UInt8(ascii: "@") || terminator(scanner) == UInt8(ascii: "{") {
                prelude(&scanner)
            } else {
                declaration(&scanner)
            }
            // Biztosíték: a tétel mindig halad előre.
            if scanner.position == start { scanner.position += 1 }
        }
    }

    /// Szóközök és megjegyzések átlépése.
    private func skipBlank(_ scanner: inout CodeScanner) {
        while !scanner.atEnd {
            if scanner.current.isSpace { scanner.position += 1 }
            else if scanner.starts(with: "/*") { scanner.scanBlockComment() }
            else { break }
        }
    }

    /// A tételt záró jel: `{`, `}` bárhol, `;` csak zárójelen kívül (a `url(data:…;base64,…)` miatt). 0 = fájl vége.
    private func terminator(_ scanner: CodeScanner) -> UInt8 {
        let bytes = scanner.bytes
        var index = scanner.position, depth = 0
        while index < scanner.end {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                index += 1
                while index < scanner.end, bytes[index] != byte, bytes[index] != UInt8(ascii: "\n") {
                    index += bytes[index] == UInt8(ascii: "\\") ? 2 : 1
                }
            case UInt8(ascii: "/") where index + 1 < scanner.end && bytes[index + 1] == UInt8(ascii: "*"):
                index += 2
                while index < scanner.end, !(bytes[index] == UInt8(ascii: "*") && index + 1 < scanner.end && bytes[index + 1] == UInt8(ascii: "/")) { index += 1 }
                index += 1
            case UInt8(ascii: "("): depth += 1
            case UInt8(ascii: ")"): depth = max(0, depth - 1)
            case UInt8(ascii: "{"), UInt8(ascii: "}"): return byte
            case UInt8(ascii: ";") where depth == 0: return byte
            default: break
            }
            index += 1
        }
        return 0
    }

    /// Szelektor vagy @-szabály feje a `{` jelig (a jelet a fő ciklus dolgozza fel).
    private func prelude(_ scanner: inout CodeScanner) {
        if scanner.current == UInt8(ascii: "@") {
            let start = scanner.position
            scanner.position += 1
            scanner.skipWhile { $0.isWord || $0 == UInt8(ascii: "-") }
            scanner.mark(.keyword, from: start)
            values(&scanner)
            return
        }
        while !scanner.atEnd {
            let byte = scanner.current, start = scanner.position
            if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "}") { return }
            if byte.isSpace { scanner.position += 1 }
            else if scanner.starts(with: "/*") { scanner.scanBlockComment() }
            else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") { scanner.scanString() }
            else if isSelectorByte(byte) {
                while !scanner.atEnd, isSelectorByte(scanner.current) {
                    scanner.position += scanner.current == UInt8(ascii: "\\") ? 2 : 1
                }
                scanner.position = min(scanner.position, scanner.end)
                scanner.mark(.type, from: start)
            } else {
                scanner.position += 1
                scanner.mark(.punctuation, from: start)
            }
        }
    }

    private func isSelectorByte(_ byte: UInt8) -> Bool {
        byte.isWord || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "#") || byte == UInt8(ascii: ":")
            || byte == UInt8(ascii: "&") || byte == UInt8(ascii: "*") || byte == UInt8(ascii: "%") || byte == UInt8(ascii: "\\")
    }

    /// `tulajdonság: érték` a záró `;` vagy `}` jelig.
    private func declaration(_ scanner: inout CodeScanner) {
        let start = scanner.position
        scanner.skipWhile { $0.isWord || $0 == UInt8(ascii: "-") }
        var next = scanner.position
        while next < scanner.end, scanner.bytes[next].isSpace { next += 1 }
        if scanner.position > start, next < scanner.end, scanner.bytes[next] == UInt8(ascii: ":") {
            scanner.mark(.name, from: start)
            scanner.position = next + 1
            scanner.mark(.punctuation, from: next)
        } else {
            scanner.position = start
        }
        values(&scanner)
    }

    /// Értékek a tétel végéig: a `{`, `}` és a zárójelen kívüli `;` előtt áll meg.
    private func values(_ scanner: inout CodeScanner) {
        var depth = 0
        while !scanner.atEnd {
            let byte = scanner.current, start = scanner.position
            switch byte {
            case UInt8(ascii: "{"), UInt8(ascii: "}"): return
            case UInt8(ascii: ";") where depth == 0: return
            case _ where byte.isSpace:
                scanner.position += 1
            case UInt8(ascii: "/") where scanner.peek() == UInt8(ascii: "*"):
                scanner.scanBlockComment()
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                scanner.scanString()
            case UInt8(ascii: "("), UInt8(ascii: ")"):
                depth = byte == UInt8(ascii: "(") ? depth + 1 : max(0, depth - 1)
                scanner.position += 1
                scanner.mark(.punctuation, from: start)
            case UInt8(ascii: "!") where scanner.peek().isLetter:
                scanner.position += 1
                scanner.skipWhile { $0.isWord || $0 == UInt8(ascii: "-") }
                scanner.mark(.keyword, from: start)
            case UInt8(ascii: "#") where scanner.peek().isHexDigit:
                scanner.position += 1
                scanner.skipWhile { $0.isWord }
                scanner.mark(.number, from: start)
            case _ where startsNumber(scanner):
                if byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") { scanner.position += 1 }
                scanner.skipWhile { $0.isDigit }
                if scanner.current == UInt8(ascii: "."), scanner.peek().isDigit {
                    scanner.position += 1
                    scanner.skipWhile { $0.isDigit }
                }
                // Mértékegység: px, em, %, …
                if scanner.current == UInt8(ascii: "%") { scanner.position += 1 } else { scanner.skipWhile { $0.isLetter } }
                scanner.mark(.number, from: start)
            case _ where byte.isLetter || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-") && (scanner.peek().isLetter || scanner.peek() == UInt8(ascii: "-") || scanner.peek() == UInt8(ascii: "_")) || byte >= 0x80:
                scanner.skipWhile { $0.isWord || $0 == UInt8(ascii: "-") }
                if scanner.current == UInt8(ascii: "(") {
                    scanner.mark(.function, from: start)
                    let name = scanner.bytes[start..<scanner.position]
                    let quoted = scanner.peek() == UInt8(ascii: "\"") || scanner.peek() == UInt8(ascii: "'")
                    if name.count == 3, name.lazy.map({ $0 | 0x20 }).elementsEqual("url".utf8), !quoted {
                        // Idézőjel nélküli url(…): a cím egyben, szövegként.
                        let open = scanner.position
                        scanner.position += 1
                        scanner.mark(.punctuation, from: open)
                        let content = scanner.position
                        scanner.skipWhile { $0 != UInt8(ascii: ")") && $0 != UInt8(ascii: "\n") }
                        scanner.mark(.string, from: content)
                        if scanner.current == UInt8(ascii: ")") {
                            let close = scanner.position
                            scanner.position += 1
                            scanner.mark(.punctuation, from: close)
                        }
                    }
                } else if scanner.starts(with: "--", at: start) {
                    scanner.mark(.name, from: start)
                }
            case UInt8(ascii: ","), UInt8(ascii: "/"), UInt8(ascii: ":"), UInt8(ascii: "="), UInt8(ascii: "<"), UInt8(ascii: ">"),
                 UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "["), UInt8(ascii: "]"):
                scanner.position += 1
                scanner.mark(.punctuation, from: start)
            default:
                scanner.position += 1
            }
        }
    }

    /// Szám kezdete: számjegy, `.5`, vagy előjel után ezek egyike.
    private func startsNumber(_ scanner: CodeScanner) -> Bool {
        let byte = scanner.current
        if byte.isDigit { return true }
        if byte == UInt8(ascii: ".") { return scanner.peek().isDigit }
        guard byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") else { return false }
        return scanner.peek().isDigit || (scanner.peek() == UInt8(ascii: ".") && scanner.peek(2).isDigit)
    }
}
