/// HTML: megjegyzés, `<!DOCTYPE>`, elemnév, attribútumnév és -érték, karakterhivatkozás (`&amp;`), írásjelek.
/// A `<script>` tartalma JavaScriptként (JSON típusnál JSON-ként), a `<style>` tartalma CSS-ként színeződik.
struct HTMLLanguage: CodeLanguage {
    let extensions = ["html", "htm"]

    func scan(_ scanner: inout CodeScanner) {
        while !scanner.atEnd {
            let byte = scanner.current, start = scanner.position
            if scanner.starts(with: "<!--") {
                scanner.position += 4
                while !scanner.atEnd, !scanner.starts(with: "-->") { scanner.position += 1 }
                scanner.position = min(scanner.position + 3, scanner.end)
                scanner.mark(.comment, from: start)
            } else if byte == UInt8(ascii: "<"), scanner.peek() == UInt8(ascii: "!") || scanner.peek() == UInt8(ascii: "?") {
                // <!DOCTYPE html>, <?xml … ?>
                scanner.skipWhile { $0 != UInt8(ascii: ">") }
                scanner.position = min(scanner.position + 1, scanner.end)
                scanner.mark(.keyword, from: start)
            } else if byte == UInt8(ascii: "<"), scanner.peek().isLetter || (scanner.peek() == UInt8(ascii: "/") && scanner.peek(2).isLetter) {
                tag(&scanner)
            } else if byte == UInt8(ascii: "&"), entity(&scanner) {
                continue
            } else {
                scanner.position += 1
            }
        }
    }

    /// `&név;`, `&#123;`, `&#x1F;` – legfeljebb 32 bájt; más `&` sima szöveg.
    private func entity(_ scanner: inout CodeScanner) -> Bool {
        var index = scanner.position + 1
        while index < scanner.end, index - scanner.position < 32, scanner.bytes[index].isLetter || scanner.bytes[index].isDigit || scanner.bytes[index] == UInt8(ascii: "#") { index += 1 }
        guard index < scanner.end, index > scanner.position + 1, scanner.bytes[index] == UInt8(ascii: ";") else { return false }
        let start = scanner.position
        scanner.position = index + 1
        scanner.mark(.keyword, from: start)
        return true
    }

    /// Nyitó vagy záró címke a `>` jelig; `<script>` és `<style>` után a tartalom a beágyazott nyelv szerint.
    private func tag(_ scanner: inout CodeScanner) {
        var start = scanner.position
        let closing = scanner.peek() == UInt8(ascii: "/")
        scanner.position += closing ? 2 : 1
        scanner.mark(.punctuation, from: start)
        start = scanner.position
        scanner.skipWhile { $0.isWord || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: ":") }
        let name = String(decoding: scanner.bytes[start..<scanner.position], as: UTF8.self).lowercased()
        scanner.mark(.type, from: start)
        // A script nyelvét a `type` attribútum dönti el (nélküle JavaScript).
        var scriptType = "", attribute = ""
        while !scanner.atEnd {
            let byte = scanner.current
            start = scanner.position
            if byte == UInt8(ascii: ">") || (byte == UInt8(ascii: "/") && scanner.peek() == UInt8(ascii: ">")) {
                scanner.position += byte == UInt8(ascii: ">") ? 1 : 2
                scanner.mark(.punctuation, from: start)
                break
            }
            // Lezáratlan címke: a következő címke kezdeténél abbahagyjuk.
            if byte == UInt8(ascii: "<") { return }
            if byte.isSpace || byte == UInt8(ascii: "/") { scanner.position += 1; continue }
            if byte == UInt8(ascii: "=") {
                scanner.position += 1
                scanner.mark(.punctuation, from: start)
                scanner.skipWhile { $0.isSpace }
                let value = scanner.position, quote = scanner.current
                if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
                    // A HTML-ben nincs `\` védés, és az érték több soros is lehet.
                    scanner.position += 1
                    scanner.skipWhile { $0 != quote }
                    scanner.position = min(scanner.position + 1, scanner.end)
                } else {
                    scanner.skipWhile { !$0.isSpace && $0 != UInt8(ascii: ">") }
                }
                scanner.mark(.string, from: value)
                if name == "script", attribute == "type" { scriptType = String(decoding: scanner.bytes[value..<scanner.position], as: UTF8.self).lowercased() }
                continue
            }
            // Attribútumnév.
            scanner.skipWhile { !$0.isSpace && $0 != UInt8(ascii: "=") && $0 != UInt8(ascii: ">") && $0 != UInt8(ascii: "/") && $0 != UInt8(ascii: "<") }
            if scanner.position == start { scanner.position += 1 }
            attribute = String(decoding: scanner.bytes[start..<scanner.position], as: UTF8.self).lowercased()
            scanner.mark(.name, from: start)
        }
        guard !closing, name == "script" || name == "style" else { return }
        // A tartalom a záró címkéig (kis- és nagybetűtől függetlenül), annak híján a végéig.
        let terminator = Array(("</" + name).utf8)
        var limit = scanner.position
        search: while limit < scanner.end {
            if scanner.bytes[limit] == UInt8(ascii: "<"), limit + terminator.count <= scanner.end {
                var matches = true
                for offset in 1..<terminator.count where scanner.bytes[limit + offset] | 0x20 != terminator[offset] | 0x20 { matches = false; break }
                if matches { break search }
            }
            limit += 1
        }
        if name == "style" { scanner.scan(CSSLanguage(), until: limit) }
        else if scriptType.contains("json") { scanner.scan(JSONLanguage(), until: limit) }
        else if scriptType.isEmpty || scriptType.contains("javascript") || scriptType.contains("module") { scanner.scan(JavaScriptLanguage(), until: limit) }
        else { scanner.position = limit }
    }
}
