/// JSON (és a megjegyzéseket megengedő JSONC): kulcs, szöveg, szám, `true` / `false` / `null`, írásjelek.
struct JSONLanguage: CodeLanguage {
    let extensions = ["json"]

    func scan(_ scanner: inout CodeScanner) {
        while !scanner.atEnd {
            let byte = scanner.current, start = scanner.position
            switch byte {
            case UInt8(ascii: "\""):
                scanner.scanString()
                // Kulcs az a szöveg, amelyet (szóközök után) kettőspont követ.
                var next = scanner.position
                while next < scanner.end, scanner.bytes[next].isSpace { next += 1 }
                if next < scanner.end, scanner.bytes[next] == UInt8(ascii: ":") { scanner.relabelLast(.name, from: start) }
            case UInt8(ascii: "/") where scanner.peek() == UInt8(ascii: "/"):
                scanner.scanLineComment()
            case UInt8(ascii: "/") where scanner.peek() == UInt8(ascii: "*"):
                scanner.scanBlockComment()
            case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: ","), UInt8(ascii: ":"):
                scanner.position += 1
                scanner.mark(.punctuation, from: start)
            case UInt8(ascii: "-") where scanner.peek().isDigit, _ where byte.isDigit:
                scanner.position += 1
                scanner.skipWhile { $0.isDigit }
                if scanner.current == UInt8(ascii: "."), scanner.peek().isDigit {
                    scanner.position += 1
                    scanner.skipWhile { $0.isDigit }
                }
                if scanner.current | 0x20 == UInt8(ascii: "e") {
                    let sign = scanner.peek() == UInt8(ascii: "+") || scanner.peek() == UInt8(ascii: "-") ? 1 : 0
                    if scanner.peek(1 + sign).isDigit {
                        scanner.position += 1 + sign
                        scanner.skipWhile { $0.isDigit }
                    }
                }
                scanner.mark(.number, from: start)
            case _ where byte.isWord:
                scanner.skipWhile { $0.isWord }
                let word = scanner.bytes[start..<scanner.position]
                if word.elementsEqual("true".utf8) || word.elementsEqual("false".utf8) || word.elementsEqual("null".utf8) {
                    scanner.mark(.keyword, from: start)
                }
            default:
                scanner.position += 1
            }
        }
    }
}
