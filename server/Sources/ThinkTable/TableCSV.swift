import Foundation

// CSV/TSV import és export (docs/EXCEL.md 7. fejezet).

public enum TableCSV {
    public struct Imported: Sendable {
        public var document: TableDocument
        /// Levágott sorok / oszlopok (a korlátok miatt).
        public var truncated: Bool
    }

    /// Szöveg dekódolása: UTF-8 (BOM-mal vagy anélkül), különben Windows-1250.
    public static func decode(_ data: Data) -> String {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if let text = String(data: bytes, encoding: .utf8) { return text }
        return String(data: bytes, encoding: .windowsCP1250) ?? String(decoding: bytes, as: UTF8.self)
    }

    /// Elválasztó: tsv-nél tabulátor, egyébként az első sorban (idézőjelen kívül) leggyakoribb `,` `;` tab;
    /// döntetlennél ebben a sorrendben az első (a JS párja ugyanígy dönt).
    public static func detectSeparator(_ text: String, ext: String) -> Character {
        if ext.lowercased() == "tsv" { return "\t" }
        let candidates: [Character] = [",", ";", "\t"]
        var counts = [0, 0, 0]
        var quoted = false
        for character in text {
            if character == "\"" { quoted.toggle() }
            else if !quoted && character.isNewline { break }
            else if !quoted, let index = candidates.firstIndex(of: character) { counts[index] += 1 }
        }
        var best = 0
        for index in 1..<3 where counts[index] > counts[best] { best = index }
        return counts[best] > 0 ? candidates[best] : ","
    }

    /// Mezők soronként (idézőjeles mezők, `""` escape, CRLF).
    public static func rows(_ text: String, separator: Character, limit: Int = TableLimits.maxRows + 1) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, fieldStarted = false
        var iterator = text.makeIterator()
        var pending: Character?
        func next() -> Character? { if let p = pending { pending = nil; return p }; return iterator.next() }
        while let character = next() {
            if rows.count >= limit { break }
            if quoted {
                if character == "\"" {
                    if let following = next() {
                        if following == "\"" { field.append("\"") } else { quoted = false; pending = following }
                    } else { quoted = false }
                } else { field.append(character) }
                continue
            }
            if character == "\"" && !fieldStarted { quoted = true; fieldStarted = true }
            else if character == separator { row.append(field); field = ""; fieldStarted = false }
            else if character.isNewline { row.append(field); rows.append(row); row = []; field = ""; fieldStarted = false }
            else { field.append(character); fieldStarted = true }
        }
        if fieldStarted || !row.isEmpty { row.append(field); rows.append(row) }
        while let last = rows.last, last.allSatisfy({ $0.isEmpty }) { rows.removeLast() }
        return rows
    }

    /// CSV → táblázat. A mezők a beírt szöveghez hasonlóan értelmeződnek (szám, százalék, pénznem, dátum),
    /// de `=`-vel kezdődő mezőből nem lesz képlet (idegen fájl, CSV-befecskendezés ellen).
    public static func importCSV(_ data: Data, name: String, ext: String = "csv") -> Imported {
        let text = decode(data)
        let separator = detectSeparator(text, ext: ext)
        let parsed = rows(text, separator: separator)
        var document = TableDocument(name: name, rows: 1, cols: 1)
        var truncated = parsed.count > TableLimits.maxRows
        var cells = 0
        outer: for (r, fields) in parsed.prefix(TableLimits.maxRows).enumerated() {
            if fields.count > TableLimits.maxCols { truncated = true }
            for (c, field) in fields.prefix(TableLimits.maxCols).enumerated() {
                let address = CellAddress(row: r, col: c)
                var cell = TableCell()
                switch TableFormat.parseInput(field, dotGrouping: separator == ";") {
                case .empty: continue
                case .formula: cell.v = .text(field.trimmingCharacters(in: .whitespaces))
                case .value(let value, let format):
                    cell.v = value
                    if let format { cell.s = document.styleIndex(CellStyle(fmt: format)) }
                }
                document[address] = cell
                cells += 1
                if cells >= TableLimits.maxCells { truncated = true; break outer }
            }
        }
        let usedRows = min(parsed.count, TableLimits.maxRows)
        let usedCols = min(parsed.map(\.count).max() ?? 1, TableLimits.maxCols)
        document.size = TableSize(rows: max(usedRows, 1), cols: max(usedCols, 1))
        // Fejlécsor: ha az első sor csupa szöveg, és alatta van szám.
        if usedRows > 1 {
            let first = (0..<usedCols).compactMap { document[CellAddress(row: 0, col: $0)]?.v }
            let second = (0..<usedCols).compactMap { document[CellAddress(row: 1, col: $0)]?.v }
            let allText = !first.isEmpty && first.allSatisfy { if case .text = $0 { return true }; return false }
            let hasNumber = second.contains { if case .number = $0 { return true }; return false }
            if allText && hasNumber {
                document.header = HeaderInfo(rows: 1, cols: 0)
                for c in 0..<usedCols {
                    let address = CellAddress(row: 0, col: c)
                    guard var cell = document[address] else { continue }
                    var style = document.style(of: cell)
                    style.b = true
                    cell.s = document.styleIndex(style)
                    document[address] = cell
                }
            }
        }
        return Imported(document: document, truncated: truncated)
    }

    /// Táblázat → CSV (vessző, tizedespont, UTF-8 BOM, CRLF). Képletnél az eredmény; a `=`-vel kezdődő szöveg elé `'` kerül.
    public static func export(_ document: TableDocument) -> Data {
        var lines: [String] = []
        let usedRows = (document.cells.keys.compactMap { CellAddress($0)?.row }.max() ?? -1) + 1
        let usedCols = (document.cells.keys.compactMap { CellAddress($0)?.col }.max() ?? -1) + 1
        for r in 0..<usedRows {
            var fields: [String] = []
            for c in 0..<usedCols {
                var text: String
                switch document[CellAddress(row: r, col: c)]?.v {
                case nil: text = ""
                case .number(let n)?: text = n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
                case .text(let t)?:
                    // CSV-befecskendezés ellen: táblázatkezelőben képletként futna (OWASP).
                    text = t.first.map { "=+-@".contains($0) } == true ? "'" + t : t
                case .bool(let b)?: text = b ? "TRUE" : "FALSE"
                case .error(let code)?: text = code
                }
                if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
                    text = "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                fields.append(text)
            }
            lines.append(fields.joined(separator: ","))
        }
        return Data([0xEF, 0xBB, 0xBF]) + Data(lines.joined(separator: "\r\n").utf8)
    }
}
