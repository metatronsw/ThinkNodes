/// Swift: megjegyzés (egymásba ágyazott `/* */` is), szöveg (`\(…)` beágyazással, többsoros `"""`, nyers `#"…"#`),
/// szám, kulcsszó, attribútum (`@MainActor`), fordítási utasítás (`#if`), nagybetűs név (típus), függvényhívás,
/// pont utáni tag, írásjelek.
struct SwiftLanguage: CodeLanguage {
    let extensions = ["swift"]

    private static let keywords: Set<String> = [
        "Any", "Self", "any", "as", "associatedtype", "async", "await", "borrowing", "break", "case", "catch", "class", "consuming",
        "continue", "convenience", "default", "defer", "deinit", "didSet", "do", "else", "enum", "extension", "fallthrough", "false",
        "fileprivate", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "mutating", "nil",
        "nonisolated", "nonmutating", "override", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "some",
        "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "unowned", "var", "weak",
        "where", "while", "willSet",
    ]
    /// Csak bizonyos helyzetben kulcsszavak; névként is gyakoriak (`prefix(3)`, `set = …`), ezért ha hívás, értékadás
    /// vagy tagelérés követi őket, nem kapnak kulcsszó-színt.
    private static let contextual: Set<String> = [
        "actor", "dynamic", "final", "get", "indirect", "infix", "isolated", "lazy", "macro", "open", "operator", "optional",
        "package", "postfix", "precedencegroup", "prefix", "required", "set",
    ]
    /// Egymásba ágyazott szövegbeágyazások legnagyobb mélysége: a rekurzió korlátja.
    private static let maximumDepth = 24

    func scan(_ scanner: inout CodeScanner) {
        code(&scanner, depth: 0)
    }

    /// Kód olvasása a végéig, illetve `depth > 0` esetén a `\(` beágyazást záró `)` jelig (a jelet nem lépi át).
    private func code(_ scanner: inout CodeScanner, depth: Int) {
        var parentheses = 0
        while !scanner.atEnd {
            let byte = scanner.current, start = scanner.position
            switch byte {
            case _ where byte.isSpace:
                scanner.position += 1
            case UInt8(ascii: "/") where scanner.peek() == UInt8(ascii: "/"):
                scanner.scanLineComment()
            case UInt8(ascii: "/") where scanner.peek() == UInt8(ascii: "*"):
                blockComment(&scanner)
            case UInt8(ascii: "\""):
                string(&scanner, hashes: 0, depth: depth)
            case UInt8(ascii: "#"):
                var hashes = 0
                while scanner.peek(hashes) == UInt8(ascii: "#") { hashes += 1 }
                if scanner.peek(hashes) == UInt8(ascii: "\"") {
                    string(&scanner, hashes: hashes, depth: depth)
                } else if scanner.peek().isLetter {
                    scanner.position += 1
                    scanner.skipWhile { $0.isWord }
                    scanner.mark(.keyword, from: start)
                } else {
                    scanner.position += 1
                    scanner.mark(.punctuation, from: start)
                }
            case UInt8(ascii: "@") where scanner.peek().isLetter || scanner.peek() == UInt8(ascii: "_"):
                scanner.position += 1
                scanner.skipWhile { $0.isWord }
                scanner.mark(.keyword, from: start)
            case _ where byte.isDigit:
                number(&scanner)
            case UInt8(ascii: "`"):
                // `class` – kulcsszó névként: színezetlen.
                scanner.position += 1
                scanner.skipWhile { $0.isWord }
                if scanner.current == UInt8(ascii: "`") { scanner.position += 1 }
            case _ where byte.isLetter || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "$") || byte >= 0x80:
                scanner.skipWhile { $0.isWord || $0 == UInt8(ascii: "$") }
                let word = String(decoding: scanner.bytes[start..<scanner.position], as: UTF8.self)
                let member = start > 0 && scanner.bytes[start - 1] == UInt8(ascii: ".") && !(start > 1 && scanner.bytes[start - 2] == UInt8(ascii: "."))
                let next = scanner.nextSignificant
                if !member, Self.keywords.contains(word) {
                    scanner.mark(.keyword, from: start)
                } else if !member, Self.contextual.contains(word), !Self.followsName(next) {
                    scanner.mark(.keyword, from: start)
                } else if byte >= 65 && byte <= 90 {
                    scanner.mark(.type, from: start)
                } else if next == UInt8(ascii: "(") && scanner.current == next {
                    scanner.mark(.function, from: start)
                } else if member {
                    scanner.mark(.name, from: start)
                }
            default:
                if byte == UInt8(ascii: "(") { parentheses += 1 }
                if byte == UInt8(ascii: ")") {
                    if depth > 0 && parentheses == 0 { return }
                    parentheses -= 1
                }
                scanner.position += 1
                scanner.mark(.punctuation, from: start)
            }
        }
    }

    /// Ami egy név (és nem kulcsszó) után áll: hívás, értékadás, tagelérés, felsorolás vége.
    private static func followsName(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "(") || byte == UInt8(ascii: "=") || byte == UInt8(ascii: ".") || byte == UInt8(ascii: ",")
            || byte == UInt8(ascii: ")") || byte == UInt8(ascii: ":") || byte == UInt8(ascii: "]") || byte == 0
    }

    /// `/* … */`, egymásba ágyazva is; lezáratlanul a végéig tart.
    private func blockComment(_ scanner: inout CodeScanner) {
        let start = scanner.position
        var depth = 0
        while !scanner.atEnd {
            if scanner.starts(with: "/*") { depth += 1; scanner.position += 2 }
            else if scanner.starts(with: "*/") {
                depth -= 1
                scanner.position += 2
                if depth == 0 { break }
            } else { scanner.position += 1 }
        }
        scanner.position = min(scanner.position, scanner.end)
        scanner.mark(.comment, from: start)
    }

    /// Szám: tizedes (1_000.5), kitevő (1e-5), hexadecimális (0xFF), bináris, oktális.
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

    /// Szöveg `hashes` darab `#` jellel (nyers szöveg) és egy vagy három idézőjellel. A beágyazás (`\(…)`, nyers
    /// szövegben `\#(…)`) belseje kódként színeződik. Az egysoros szöveg lezáratlanul a sor végéig tart.
    private func string(_ scanner: inout CodeScanner, hashes: Int, depth: Int) {
        var start = scanner.position
        scanner.position += hashes
        let multiline = scanner.starts(with: "\"\"\"")
        scanner.position += multiline ? 3 : 1
        func hashesFollow(_ offset: Int) -> Bool {
            for index in 0..<hashes where scanner.peek(offset + index) != UInt8(ascii: "#") { return false }
            return true
        }
        while !scanner.atEnd {
            let byte = scanner.current
            if byte == UInt8(ascii: "\n") && !multiline { break }
            if byte == UInt8(ascii: "\\") && hashesFollow(1) {
                if scanner.peek(1 + hashes) == UInt8(ascii: "("), depth < Self.maximumDepth {
                    scanner.mark(.string, from: start)
                    let open = scanner.position
                    scanner.position += 2 + hashes
                    scanner.mark(.punctuation, from: open)
                    code(&scanner, depth: depth + 1)
                    if scanner.current == UInt8(ascii: ")") {
                        let close = scanner.position
                        scanner.position += 1
                        scanner.mark(.punctuation, from: close)
                    }
                    start = scanner.position
                    continue
                }
                // Védett karakter (\" \\ \n …): a következő bájt nem zárhatja a szöveget.
                let next = scanner.peek(1 + hashes)
                scanner.position = min(scanner.position + 1 + hashes + (next == UInt8(ascii: "\n") ? 0 : 1), scanner.end)
                continue
            }
            if byte == UInt8(ascii: "\""), !multiline || scanner.starts(with: "\"\"\""), hashesFollow(multiline ? 3 : 1) {
                scanner.position += (multiline ? 3 : 1) + hashes
                break
            }
            scanner.position += 1
        }
        scanner.mark(.string, from: start)
    }
}
