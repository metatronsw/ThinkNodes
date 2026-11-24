import Foundation

// Számformátumok és a beírt szöveg értelmezése (EXCEL.md 3. fejezet). JS párja: Public/table/table-format.js.
// A kerekítés és a kiírás saját, mert a printf és a JS toFixed az egzakt feleknél eltérően kerekít.

public enum TableFormat {
    /// Nem törő szóköz az ezreselválasztóhoz.
    public static let groupSeparator = "\u{00A0}"

    /// Kerekítés `digits` tizedesre, a feleket nullától elfelé (Excel ROUND).
    public static func roundHalfAway(_ value: Double, _ digits: Int) -> Double {
        let rounded: Double
        if digits >= 0 {
            let factor = pow(10.0, Double(digits))
            rounded = (abs(value) * factor + 0.5).rounded(.down) / factor
        } else {
            let factor = pow(10.0, Double(-digits))
            rounded = (abs(value) / factor + 0.5).rounded(.down) * factor
        }
        return value < 0 ? -rounded : rounded
    }

    /// Tizedestört alak `decimals` jeggyel, tizedesvesszővel, opcionális ezreselválasztással.
    public static func fixed(_ value: Double, decimals: Int, group: Bool = false) -> String {
        let decimals = max(0, min(decimals, 15))
        let rounded = roundHalfAway(value, decimals)
        var text = String(format: "%.\(decimals)f", abs(rounded))
        if text.hasPrefix("-") { text.removeFirst() }
        var integer = text, fraction = ""
        if let dot = text.firstIndex(of: ".") { integer = String(text[..<dot]); fraction = String(text[text.index(after: dot)...]) }
        if group { integer = grouped(integer) }
        let negative = rounded < 0 && (Double(text) ?? 0) != 0
        return (negative ? "-" : "") + integer + (fraction.isEmpty ? "" : "," + fraction)
    }

    static func grouped(_ digits: String) -> String {
        var result = ""
        for (offset, character) in digits.enumerated() {
            if offset > 0 && (digits.count - offset) % 3 == 0 { result += groupSeparator }
            result.append(character)
        }
        return result
    }

    /// Általános számalak: legfeljebb 10 értékes jegy, a felesleges nullák nélkül; nagyon nagy/kicsi számnál exponens.
    public static func general(_ value: Double) -> String {
        guard value.isFinite else { return "#NUM!" }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e11 || magnitude < 1e-9 {
            var exponent = Int(floor(log10(magnitude)))
            var mantissa = roundHalfAway(magnitude / pow(10.0, Double(exponent)), 5)
            if mantissa >= 10 { mantissa /= 10; exponent += 1 }
            let body = trimmed(fixed(mantissa, decimals: 5))
            return (value < 0 ? "-" : "") + body + "E" + (exponent < 0 ? "-" : "+") + String(format: "%02d", abs(exponent))
        }
        let integerDigits = magnitude >= 1 ? String(Int64(magnitude)).count : 0
        return trimmed(fixed(value, decimals: min(10, max(0, 10 - integerDigits))))
    }

    static func trimmed(_ text: String) -> String {
        guard text.contains(",") else { return text }
        var result = text
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(",") { result.removeLast() }
        return result == "-0" ? "0" : result
    }

    /// Cellaérték megjelenített szövege a formátum szerint.
    public static func display(_ value: CellValue?, _ format: NumberFormat?) -> String {
        guard let value else { return "" }
        switch value {
        case .text(let text): return text
        case .bool(let flag): return flag ? "IGAZ" : "HAMIS"
        case .error(let code): return code
        case .number(let number):
            guard let format else { return general(number) }
            switch format.kind {
            case "number": return fixed(number, decimals: format.dec ?? 2, group: format.group ?? false)
            case "currency":
                let amount = fixed(number, decimals: format.dec ?? 0, group: true)
                let symbol = format.symbol ?? "Ft"
                if format.before == true {
                    return amount.hasPrefix("-") ? "-" + symbol + " " + amount.dropFirst() : symbol + " " + amount
                }
                return amount + " " + symbol
            case "percent": return fixed(number * 100, decimals: format.dec ?? 0) + "%"
            case "date": return date(number, pattern: format.pattern ?? "yyyy.MM.dd.")
            default: return general(number)
            }
        }
    }

    // MARK: Dátum (napok 1899-12-30 óta, mint az Excelben)

    static let epochOffset = 25569  // 1970-01-01 sorszáma

    /// Polgári dátum → napok 1970-01-01 óta (Howard Hinnant algoritmusa).
    static func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let year = m <= 2 ? y - 1 : y
        let era = (year >= 0 ? year : year - 399) / 400
        let yoe = year - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ z: Int) -> (Int, Int, Int) {
        let z = z + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    public static func serial(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Double {
        Double(daysFromCivil(year, month, day) + epochOffset) + Double(hour * 3600 + minute * 60 + second) / 86400
    }

    static func date(_ serial: Double, pattern: String) -> String {
        var days = Int(floor(serial))
        var seconds = Int((serial - Double(days)) * 86400 + 0.5)
        if seconds >= 86400 { days += 1; seconds -= 86400 }
        let (y, m, d) = civilFromDays(days - epochOffset)
        func two(_ n: Int) -> String { n < 10 ? "0" + String(n) : String(n) }
        var text = pattern
        for (token, value) in [("yyyy", String(y)), ("MM", two(m)), ("dd", two(d)), ("HH", two(seconds / 3600)),
                               ("mm", two(seconds / 60 % 60)), ("ss", two(seconds % 60))] {
            text = text.replacingOccurrences(of: token, with: value)
        }
        return text
    }

    // MARK: Beírt szöveg értelmezése

    public enum Input: Equatable, Sendable {
        case empty
        case formula(String)
        case value(CellValue, NumberFormat?)
    }

    static let currencySuffixes = ["Ft", "HUF", "€", "EUR", "$", "USD"]
    static let currencyPrefixes = ["€", "$"]

    /// Beírt vagy importált szöveg: képlet (`=`), kényszerített szöveg (`'`), logikai, százalék, pénznem, dátum, idő, szám.
    public static func parseInput(_ raw: String) -> Input {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return .empty }
        if text.hasPrefix("="), text.count > 1 { return .formula(String(text.dropFirst())) }
        if raw.hasPrefix("'") { return .value(.text(String(raw.dropFirst())), nil) }
        switch text.uppercased() {
        case "IGAZ", "TRUE": return .value(.bool(true), nil)
        case "HAMIS", "FALSE": return .value(.bool(false), nil)
        default: break
        }
        if text.hasSuffix("%"), let (number, decimals, _) = parseNumber(String(text.dropLast()).trimmingCharacters(in: .whitespaces)) {
            return .value(.number(number / 100), NumberFormat(kind: "percent", dec: decimals))
        }
        for symbol in currencySuffixes where text.hasSuffix(symbol) {
            let body = String(text.dropLast(symbol.count)).trimmingCharacters(in: .whitespaces)
            if let (number, decimals, _) = parseNumber(body) {
                return .value(.number(number), NumberFormat(kind: "currency", dec: decimals, symbol: symbol))
            }
        }
        for symbol in currencyPrefixes where text.hasPrefix(symbol) {
            let body = String(text.dropFirst(symbol.count)).trimmingCharacters(in: .whitespaces)
            if let (number, decimals, _) = parseNumber(body) {
                return .value(.number(number), NumberFormat(kind: "currency", dec: decimals, symbol: symbol, before: true))
            }
        }
        if let (serial, pattern) = parseDate(text) { return .value(.number(serial), NumberFormat(kind: "date", pattern: pattern)) }
        if let (number, decimals, grouped) = parseNumber(text) {
            return .value(.number(number), grouped ? NumberFormat(kind: "number", dec: decimals, group: true) : nil)
        }
        return .value(.text(raw), nil)
    }

    /// Szám: előjel, számjegyek, ezreselválasztó (szóköz, illetve a nem tizedes jel), tizedesvessző vagy -pont, exponens.
    /// Eredmény: érték, tizedesjegyek száma, volt-e ezreselválasztás.
    public static func parseNumber(_ text: String) -> (Double, Int, Bool)? {
        var body = text
        var negative = false
        if body.hasPrefix("-") || body.hasPrefix("+") { negative = body.hasPrefix("-"); body.removeFirst() }
        guard let first = body.first, first.isASCII && (first.isNumber || first == "." || first == ",") else { return nil }
        let lower = body.lowercased()
        if lower.contains("e") {
            guard lower.range(of: #"^([0-9]+\.?[0-9]*|\.[0-9]+)e[+-]?[0-9]+$"#, options: .regularExpression) != nil,
                  let value = Double(lower) else { return nil }
            return (negative ? -value : value, 0, false)
        }
        let separators: Set<Character> = [".", ",", " ", "\u{00A0}"]
        guard body.allSatisfy({ ($0.isASCII && $0.isNumber) || separators.contains($0) }) else { return nil }
        let dots = body.filter { $0 == "." }.count, commas = body.filter { $0 == "," }.count
        var mark: Character?
        if dots > 0 && commas > 0 { mark = body.lastIndex(of: ".")! > body.lastIndex(of: ",")! ? "." : "," }
        else if dots == 1 { mark = "." }
        else if commas == 1 { mark = "," }
        var integer = body, fraction = ""
        if let mark, let index = body.lastIndex(of: mark) {
            integer = String(body[..<index]); fraction = String(body[body.index(after: index)...])
        }
        guard fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var grouped = false
        if integer.contains(where: { separators.contains($0) }) {
            // Ezreselválasztás: az első csoport 1–3 jegy, a többi pontosan 3.
            guard integer.range(of: "^[0-9]{1,3}([., \u{00A0}][0-9]{3})+$", options: .regularExpression) != nil else { return nil }
            grouped = true
            integer.removeAll { separators.contains($0) }
        }
        guard !(integer.isEmpty && fraction.isEmpty),
              let value = Double((integer.isEmpty ? "0" : integer) + (fraction.isEmpty ? "" : "." + fraction)) else { return nil }
        return (negative ? -value : value, fraction.count, grouped)
    }

    /// Dátum: 2026.11.24. / 2026. 11. 24. / 2026-11-24, opcionális idővel; idő: 14:30 / 14:30:15.
    static func parseDate(_ text: String) -> (Double, String)? {
        func numbers(_ s: Substring, separators: Set<Character>) -> [Int]? {
            let parts = s.split(whereSeparator: { separators.contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
            return parts.compactMap { Int($0) }
        }
        func time(_ s: Substring) -> (Int, Int, Int)? {
            guard s.contains(":"), let parts = numbers(s, separators: [":"]), (2...3).contains(parts.count),
                  parts[0] < 24, parts[1] < 60, (parts.count == 2 || parts[2] < 60) else { return nil }
            return (parts[0], parts[1], parts.count == 3 ? parts[2] : 0)
        }
        if let (h, m, s) = time(Substring(text)) {
            return (Double(h * 3600 + m * 60 + s) / 86400, s > 0 ? "HH:mm:ss" : "HH:mm")
        }
        var datePart = Substring(text), timePart: Substring?
        if let colon = text.firstIndex(of: ":"), let space = text[..<colon].lastIndex(of: " ") {
            datePart = text[..<space]; timePart = text[text.index(after: space)...]
        }
        let dashed = datePart.contains("-")
        guard dashed || datePart.contains("."), let parts = numbers(datePart, separators: dashed ? ["-"] : ["."]), parts.count == 3 else { return nil }
        let normalized = datePart.replacingOccurrences(of: " ", with: "")
        if dashed { guard normalized.split(separator: "-").count == 3 else { return nil } }
        let (y, m, d) = (parts[0], parts[1], parts[2])
        guard y >= 1900, y <= 9999, (1...12).contains(m), (1...31).contains(d) else { return nil }
        let (cy, cm, cd) = civilFromDays(daysFromCivil(y, m, d))
        guard cy == y, cm == m, cd == d else { return nil }
        var pattern = "yyyy.MM.dd."
        var serial = self.serial(year: y, month: m, day: d)
        if let timePart {
            guard let (h, mi, s) = time(timePart) else { return nil }
            serial += Double(h * 3600 + mi * 60 + s) / 86400
            pattern += " HH:mm"
        }
        return (serial, pattern)
    }
}
