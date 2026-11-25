/// JavaScript: megjegyzés, szöveg, sablonszöveg (`${…}` beágyazással), reguláris kifejezés, szám, kulcsszó,
/// nagybetűs név (osztály), függvényhívás, pont utáni tulajdonság, írásjelek.
///
/// A `/` jelről a megelőző szakasz dönti el, hogy osztás vagy reguláris kifejezés kezdete: érték (név, szám, szöveg,
/// `)`, `]`, `}`) után osztás, egyébként (írásjel, kulcsszó, sor eleje) reguláris kifejezés.
struct JavaScriptLanguage: CodeLanguage {
    let extensions = ["js", "mjs", "cjs"]

    private static let keywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else",
        "export", "extends", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "let", "new", "of", "return",
        "static", "switch", "throw", "try", "typeof", "var", "void", "while", "with", "yield",
    ]
    /// Érték jellegű kulcsszavak: utánuk a `/` osztás.
    private static let values: Set<String> = ["false", "Infinity", "NaN", "null", "super", "this", "true", "undefined"]
    /// Egymásba ágyazott sablonszövegek legnagyobb mélysége (e fölött a tartalom sima szöveg): a rekurzió korlátja.
    private static let maximumDepth = 24

    func scan(_ scanner: inout CodeScanner) {
        code(&scanner, depth: 0)
    }

    /// Kód olvasása a végéig, illetve `depth > 0` esetén a sablonszöveg `${`-ját záró `}` jelig (a jelet nem lépi át).
    private func code(_ scanner: inout CodeScanner, depth: Int) {
        var braces = 0
        // Érték áll-e közvetlenül előttünk (ekkor a `/` osztás).
        var afterValue = false
        while !scanner.atEnd {
            let byte = scanner.current, start = scanner.position
            switch byte {
            case _ where byte.isSpace:
                scanner.position += 1
            case UInt8(ascii: "/") where scanner.peek() == UInt8(ascii: "/"):
                scanner.scanLineComment()
            case UInt8(ascii: "/") where scanner.peek() == UInt8(ascii: "*"):
                scanner.scanBlockComment()
            case UInt8(ascii: "#") where start == 0 && scanner.peek() == UInt8(ascii: "!"):
                scanner.scanLineComment()
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                scanner.scanString()
                afterValue = true
            case UInt8(ascii: "`"):
                template(&scanner, depth: depth)
                afterValue = true
            case UInt8(ascii: "/") where !afterValue && regularExpression(&scanner):
                afterValue = true
            case _ where byte.isDigit || (byte == UInt8(ascii: ".") && scanner.peek().isDigit):
                number(&scanner)
                afterValue = true
            case _ where isNameStart(byte):
                scanner.skipWhile { $0.isWord || $0 == UInt8(ascii: "$") }
                let word = String(decoding: scanner.bytes[start..<scanner.position], as: UTF8.self)
                let member = start > 0 && scanner.bytes[start - 1] == UInt8(ascii: ".") && !(start > 1 && scanner.bytes[start - 2] == UInt8(ascii: "."))
                afterValue = true
                if !member, Self.keywords.contains(word) {
                    scanner.mark(.keyword, from: start)
                    afterValue = false
                } else if !member, Self.values.contains(word) {
                    scanner.mark(.keyword, from: start)
                } else if byte >= 65 && byte <= 90 {
                    scanner.mark(.type, from: start)
                } else if scanner.nextSignificant == UInt8(ascii: "(") {
                    scanner.mark(.function, from: start)
                } else if member {
                    scanner.mark(.name, from: start)
                }
            default:
                if byte == UInt8(ascii: "{") { braces += 1 }
                if byte == UInt8(ascii: "}") {
                    if depth > 0 && braces == 0 { return }
                    braces -= 1
                }
                scanner.position += 1
                scanner.mark(.punctuation, from: start)
                afterValue = byte == UInt8(ascii: ")") || byte == UInt8(ascii: "]") || byte == UInt8(ascii: "}")
            }
        }
    }

    private func isNameStart(_ byte: UInt8) -> Bool {
        byte.isLetter || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "$") || byte >= 0x80
    }

    /// Szám: tizedes, hexadecimális (0x…), kitevő (1e-5), elválasztó (1_000), BigInt (10n).
    private func number(_ scanner: inout CodeScanner) {
        let start = scanner.position
        let prefixed = scanner.current == UInt8(ascii: "0") && scanner.peek().isLetter
        while !scanner.atEnd {
            let byte = scanner.current
            if byte.isWord || (byte == UInt8(ascii: ".") && scanner.peek().isDigit) { scanner.position += 1 }
            else if !prefixed, byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-"), scanner.peek(-1) | 0x20 == UInt8(ascii: "e"), scanner.peek().isDigit { scanner.position += 1 }
            else { break }
        }
        scanner.mark(.number, from: start)
    }

    /// `/…/flags` a sor végéig; ha a sorban nincs záró `/`, nem reguláris kifejezés (`false`, a pozíció változatlan).
    private func regularExpression(_ scanner: inout CodeScanner) -> Bool {
        let start = scanner.position
        var index = start + 1, inClass = false
        while index < scanner.end {
            let byte = scanner.bytes[index]
            if byte == UInt8(ascii: "\n") { return false }
            if byte == UInt8(ascii: "\\") { index += 2; continue }
            if byte == UInt8(ascii: "[") { inClass = true }
            else if byte == UInt8(ascii: "]") { inClass = false }
            else if byte == UInt8(ascii: "/") && !inClass {
                scanner.position = index + 1
                scanner.skipWhile { $0.isLetter }
                scanner.mark(.string, from: start)
                return true
            }
            index += 1
        }
        return false
    }

    /// Sablonszöveg: a szövegrészek szövegként, a `${…}` belseje kódként.
    private func template(_ scanner: inout CodeScanner, depth: Int) {
        var start = scanner.position
        scanner.position += 1
        while !scanner.atEnd {
            let byte = scanner.current
            if byte == UInt8(ascii: "\\") { scanner.position = min(scanner.position + 2, scanner.end); continue }
            if byte == UInt8(ascii: "`") { scanner.position += 1; break }
            if byte == UInt8(ascii: "$"), scanner.peek() == UInt8(ascii: "{"), depth < Self.maximumDepth {
                scanner.mark(.string, from: start)
                let open = scanner.position
                scanner.position += 2
                scanner.mark(.punctuation, from: open)
                code(&scanner, depth: depth + 1)
                if scanner.current == UInt8(ascii: "}") {
                    let close = scanner.position
                    scanner.position += 1
                    scanner.mark(.punctuation, from: close)
                }
                start = scanner.position
                continue
            }
            scanner.position += 1
        }
        scanner.mark(.string, from: start)
    }
}
