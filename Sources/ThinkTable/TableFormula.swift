import Foundation

// Képletek: lexer, parser (AST), hivatkozás-átírás (EXCEL.md 4. fejezet).
// A JavaScript párja: Public/table/table-formula.js – a kettő viselkedése egyezzen (Tests/TableFixtures).

/// Cellahivatkozás a képletben. `row == nil`: egész oszlop (`B:B`). `table`: másik táblázat neve vagy `{id}` (9. fejezet).
public struct FormulaRef: Equatable, Sendable {
    public var table: String?
    public var row: Int?
    public var col: Int
    public var rowAbs = false
    public var colAbs = false

    public var text: String {
        (colAbs ? "$" : "") + CellAddress.columnName(col) + (row.map { (rowAbs ? "$" : "") + String($0 + 1) } ?? "")
    }
}

public indirect enum FormulaExpr: Equatable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case error(String)
    case ref(FormulaRef)
    case range(FormulaRef, FormulaRef)
    case unary(String, FormulaExpr)
    case percent(FormulaExpr)
    case binary(String, FormulaExpr, FormulaExpr)
    case call(String, [FormulaExpr])
    case name(String)
}

public enum FormulaToken: Equatable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case error(String)
    /// Hivatkozás; `prefix` a táblázat-előtag eredeti szövege (`'Bevétel'!`), átíráskor változatlan marad.
    case ref(FormulaRef, prefix: String)
    case function(String)
    case name(String)
    case op(String)
    case open, close, separator
}

public struct LocatedToken: Equatable, Sendable {
    public var token: FormulaToken
    public var start: String.Index
    public var end: String.Index
}

public enum TableFormula {
    /// Magyar függvénynevek → belső név.
    public static let aliases: [String: String] = [
        "SZUM": "SUM", "ÁTLAG": "AVERAGE", "DARAB": "COUNT", "KEREKÍTÉS": "ROUND", "HA": "IF",
    ]
    public static let functions: Set<String> = ["SUM", "AVERAGE", "MIN", "MAX", "COUNT", "ROUND", "IF"]
    static let errorCodes = ["#DIV/0!", "#REF!", "#VALUE!", "#NAME?", "#N/A", "#NUM!", "#CIRC!", "#NULL!"]

    public struct SyntaxError: Error, Equatable {}

    static func isIdentifier(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "." || c == "$"
    }

    // MARK: Lexer

    public static func tokenize(_ source: String) throws -> [LocatedToken] {
        let decimalComma = source.contains(";")
        var tokens: [LocatedToken] = []
        var i = source.startIndex
        func peek(_ offset: Int = 0) -> Character? {
            var j = i
            for _ in 0..<offset { guard j < source.endIndex else { return nil }; j = source.index(after: j) }
            return j < source.endIndex ? source[j] : nil
        }
        func advance(_ n: Int = 1) { for _ in 0..<n where i < source.endIndex { i = source.index(after: i) } }
        func add(_ token: FormulaToken, from start: String.Index) { tokens.append(LocatedToken(token: token, start: start, end: i)) }

        /// Egész oszlop (`B:B`): az első tag után `:` jön, a második előtt `:` és egy oszlophivatkozás áll.
        func afterColumnColon() -> Bool {
            guard tokens.count >= 2, tokens[tokens.count - 1].token == .op(":"),
                  case .ref(let ref, _) = tokens[tokens.count - 2].token else { return false }
            return ref.row == nil
        }

        /// Hivatkozás olvasása a jelenlegi helyről (előtag után). nil, ha nem hivatkozás.
        func readRef() -> FormulaRef? {
            let start = i
            var j = i
            var identifier = ""
            while j < source.endIndex, isIdentifier(source[j]) { identifier.append(source[j]); j = source.index(after: j) }
            let next: Character? = j < source.endIndex ? source[j] : nil
            if let ref = parseRef(identifier, columnOnlyAllowed: next == ":" || afterColumnColon()) { i = j; return ref }
            i = start
            return nil
        }

        while i < source.endIndex {
            let c = source[i]
            let start = i
            if c.isWhitespace { advance(); continue }
            if c.isASCII && c.isNumber || (c == "." && peek(1)?.isASCII == true && peek(1)!.isNumber) {
                var text = ""
                while let d = peek(), d.isASCII && d.isNumber { text.append(d); advance() }
                if let d = peek(), d == "." || (decimalComma && d == ","), let e = peek(1), e.isASCII && e.isNumber {
                    text.append("."); advance()
                    while let d = peek(), d.isASCII && d.isNumber { text.append(d); advance() }
                } else if peek() == "." { advance() }
                if let e = peek(), e == "e" || e == "E" {
                    let sign = peek(1)
                    let digitAt = sign == "+" || sign == "-" ? 2 : 1
                    if let d = peek(digitAt), d.isASCII && d.isNumber {
                        text.append("e")
                        advance()
                        if digitAt == 2 { text.append(sign!); advance() }
                        while let d = peek(), d.isASCII && d.isNumber { text.append(d); advance() }
                    }
                }
                guard let value = Double(text) else { throw SyntaxError() }
                add(.number(value), from: start)
                continue
            }
            if c == "\"" {
                advance()
                var text = ""
                var closed = false
                while let d = peek() {
                    advance()
                    if d == "\"" {
                        if peek() == "\"" { text.append("\""); advance() } else { closed = true; break }
                    } else { text.append(d) }
                }
                guard closed else { throw SyntaxError() }
                add(.text(text), from: start)
                continue
            }
            if c == "#" {
                let rest = source[i...].uppercased()
                guard let code = errorCodes.first(where: { rest.hasPrefix($0) }) else { throw SyntaxError() }
                advance(code.count)
                add(.error(code), from: start)
                continue
            }
            if c == "'" || c == "{" {
                // Táblázat-előtag: 'Név'! vagy {id}!
                let close: Character = c == "'" ? "'" : "}"
                advance()
                var name = ""
                var closed = false
                while let d = peek() {
                    advance()
                    if d == close {
                        if close == "'" && peek() == "'" { name.append("'"); advance() } else { closed = true; break }
                    } else { name.append(d) }
                }
                guard closed, peek() == "!" else { throw SyntaxError() }
                advance()
                let prefix = String(source[start..<i])
                guard var ref = readRef() else { throw SyntaxError() }
                ref.table = c == "{" ? "{" + name + "}" : name
                add(.ref(ref, prefix: prefix), from: start)
                continue
            }
            if c.isLetter || c == "_" || c == "$" {
                var identifier = ""
                while let d = peek(), isIdentifier(d) { identifier.append(d); advance() }
                if peek() == "!" {
                    advance()
                    let prefix = String(source[start..<i])
                    guard var ref = readRef() else { throw SyntaxError() }
                    ref.table = identifier
                    add(.ref(ref, prefix: prefix), from: start)
                    continue
                }
                if peek() == "(" {
                    let upper = identifier.uppercased()
                    add(.function(aliases[upper] ?? upper), from: start)
                    continue
                }
                if let ref = parseRef(identifier, columnOnlyAllowed: peek() == ":" || afterColumnColon()) {
                    add(.ref(ref, prefix: ""), from: start)
                    continue
                }
                switch identifier.uppercased() {
                case "TRUE", "IGAZ": add(.bool(true), from: start)
                case "FALSE", "HAMIS": add(.bool(false), from: start)
                default: add(.name(identifier), from: start)
                }
                continue
            }
            let two = String(source[i...].prefix(2))
            if ["<=", ">=", "<>"].contains(two) { advance(2); add(.op(two), from: start); continue }
            switch c {
            case "+", "-", "*", "/", "^", "&", "=", "<", ">", "%", ":": advance(); add(.op(String(c)), from: start)
            case "(": advance(); add(.open, from: start)
            case ")": advance(); add(.close, from: start)
            case ",", ";": advance(); add(.separator, from: start)
            default: throw SyntaxError()
            }
        }
        return tokens
    }

    /// "A1", "$A$1", oszlop ("B", ha utána `:` jön).
    static func parseRef(_ identifier: String, columnOnlyAllowed: Bool) -> FormulaRef? {
        var chars = Array(identifier)
        var ref = FormulaRef(col: 0)
        var index = 0
        if index < chars.count, chars[index] == "$" { ref.colAbs = true; index += 1 }
        var letters = ""
        while index < chars.count, chars[index].isASCII, chars[index].isLetter { letters.append(chars[index]); index += 1 }
        guard !letters.isEmpty, letters.count <= 3, let col = CellAddress.columnIndex(letters), col < TableLimits.maxCols * 200 else { return nil }
        ref.col = col
        if index == chars.count { return columnOnlyAllowed ? ref : nil }
        if chars[index] == "$" { ref.rowAbs = true; index += 1 }
        chars = Array(chars[index...])
        guard !chars.isEmpty, chars.allSatisfy({ $0.isASCII && $0.isNumber }), chars.first != "0",
              let row = Int(String(chars)), row >= 1, row <= 1_048_576 else { return nil }
        ref.row = row - 1
        return ref
    }

    // MARK: Parser

    public static func parse(_ source: String) throws -> FormulaExpr {
        let tokens = try tokenize(source).map(\.token)
        var position = 0
        func peek() -> FormulaToken? { position < tokens.count ? tokens[position] : nil }
        func next() -> FormulaToken? { defer { position += 1 }; return peek() }
        func isOp(_ op: String) -> Bool { peek() == .op(op) }

        func comparison() throws -> FormulaExpr {
            var left = try concat()
            while case .op(let op)? = peek(), ["=", "<>", "<", ">", "<=", ">="].contains(op) {
                position += 1
                left = .binary(op, left, try concat())
            }
            return left
        }
        func concat() throws -> FormulaExpr {
            var left = try additive()
            while isOp("&") { position += 1; left = .binary("&", left, try additive()) }
            return left
        }
        func additive() throws -> FormulaExpr {
            var left = try multiplicative()
            while case .op(let op)? = peek(), op == "+" || op == "-" { position += 1; left = .binary(op, left, try multiplicative()) }
            return left
        }
        func multiplicative() throws -> FormulaExpr {
            var left = try power()
            while case .op(let op)? = peek(), op == "*" || op == "/" { position += 1; left = .binary(op, left, try power()) }
            return left
        }
        func power() throws -> FormulaExpr {
            var left = try unary()
            while isOp("^") { position += 1; left = .binary("^", left, try unary()) }
            return left
        }
        func unary() throws -> FormulaExpr {
            if case .op(let op)? = peek(), op == "-" || op == "+" {
                position += 1
                return .unary(op, try unary())
            }
            return try postfix()
        }
        func postfix() throws -> FormulaExpr {
            var value = try primary()
            while isOp("%") { position += 1; value = .percent(value) }
            return value
        }
        func primary() throws -> FormulaExpr {
            guard let token = next() else { throw SyntaxError() }
            switch token {
            case .number(let value): return .number(value)
            case .text(let value): return .text(value)
            case .bool(let value): return .bool(value)
            case .error(let code): return .error(code)
            case .name(let name): return .name(name)
            case .ref(let first, _):
                if isOp(":"), position + 1 < tokens.count, case .ref(var second, _) = tokens[position + 1] {
                    position += 2
                    if second.table == nil { second.table = first.table }
                    guard (first.row == nil) == (second.row == nil) else { throw SyntaxError() }
                    return .range(first, second)
                }
                guard first.row != nil else { throw SyntaxError() }
                return .ref(first)
            case .function(let name):
                guard next() == .open else { throw SyntaxError() }
                var arguments: [FormulaExpr] = []
                if peek() == .close { position += 1; return .call(name, arguments) }
                while true {
                    if peek() == .separator || peek() == .close { arguments.append(.text("")) /* üres argumentum */ }
                    else { arguments.append(try comparison()) }
                    guard let separator = next() else { throw SyntaxError() }
                    if separator == .close { break }
                    guard separator == .separator else { throw SyntaxError() }
                }
                return .call(name, arguments)
            case .open:
                let inner = try comparison()
                guard next() == .close else { throw SyntaxError() }
                return inner
            default: throw SyntaxError()
            }
        }

        let expression = try comparison()
        guard position == tokens.count else { throw SyntaxError() }
        return expression
    }

    // MARK: Függőségek

    /// A képlet hivatkozásai: egyes cellák és tartományok (táblázat-előtaggal együtt).
    public static func references(_ expr: FormulaExpr) -> (cells: [FormulaRef], ranges: [(FormulaRef, FormulaRef)]) {
        var cells: [FormulaRef] = [], ranges: [(FormulaRef, FormulaRef)] = []
        func walk(_ e: FormulaExpr) {
            switch e {
            case .ref(let r): cells.append(r)
            case .range(let a, let b): ranges.append((a, b))
            case .unary(_, let x), .percent(let x): walk(x)
            case .binary(_, let a, let b): walk(a); walk(b)
            case .call(_, let args): args.forEach(walk)
            default: break
            }
        }
        walk(expr)
        return (cells, ranges)
    }

    // MARK: Átírás (sor/oszlop beszúrás, törlés, másolás)

    public enum Axis: Sendable { case row, col }

    /// Sorok vagy oszlopok beszúrása (`count > 0`) vagy törlése (`count < 0`) az `at` helytől.
    /// A saját táblázatra mutató hivatkozások eltolódnak; a törölt cellára mutatóból `#REF!` lesz, a tartomány szűkül.
    public static func shift(_ formula: String, axis: Axis, at: Int, count: Int) -> String {
        rewrite(formula) { first, second in
            func index(_ r: FormulaRef) -> Int? { axis == .row ? r.row : r.col }
            func set(_ r: inout FormulaRef, _ v: Int) { if axis == .row { r.row = v } else { r.col = v } }
            if var a = first, var b = second {
                guard let ia = index(a), let ib = index(b) else { return (a, b) }
                var lo = min(ia, ib), hi = max(ia, ib)
                if count > 0 {
                    if lo >= at { lo += count }
                    if hi >= at { hi += count }
                } else {
                    let end = at - count  // törölt: at ..< end
                    if lo >= at && hi < end { return nil }
                    if lo >= end { lo += count } else if lo >= at { lo = at }
                    if hi >= end { hi += count } else if hi >= at { hi = at - 1 }
                }
                set(&a, ia <= ib ? lo : hi); set(&b, ia <= ib ? hi : lo)
                return (a, b)
            }
            guard var a = first, let ia = index(a) else { return (first, nil) }
            if count > 0 { if ia >= at { set(&a, ia + count) } }
            else {
                let end = at - count
                if ia >= at && ia < end { return nil }
                if ia >= end { set(&a, ia + count) }
            }
            return (a, nil)
        }
    }

    /// Másolás / beillesztés: a relatív hivatkozások eltolódnak; ha a tábla szélén kívülre esnének, `#REF!`.
    public static func move(_ formula: String, rows: Int, cols: Int) -> String {
        rewrite(formula) { first, second in
            func moved(_ r: FormulaRef) -> FormulaRef? {
                var r = r
                if !r.colAbs { r.col += cols }
                if let row = r.row, !r.rowAbs { r.row = row + rows }
                guard r.col >= 0, (r.row ?? 0) >= 0 else { return nil }
                return r
            }
            guard let a = first.flatMap(moved) else { return nil }
            if let b = second { guard let mb = moved(b) else { return nil }; return (a, mb) }
            return (a, nil)
        }
    }

    /// Token szintű átírás: csak a saját táblázatra mutató hivatkozások szövege változik, minden más (szóközök, magyar
    /// függvénynevek, elválasztók) változatlan marad. A `transform` nil eredménye `#REF!`.
    static func rewrite(_ formula: String, _ transform: (FormulaRef?, FormulaRef?) -> (FormulaRef?, FormulaRef?)?) -> String {
        guard let tokens = try? tokenize(formula) else { return formula }
        var result = ""
        var cursor = formula.startIndex
        var index = 0
        while index < tokens.count {
            let located = tokens[index]
            guard case .ref(let first, let prefix) = located.token, first.table == nil else { index += 1; continue }
            result += formula[cursor..<located.start]
            var end = located.end
            var second: FormulaRef?
            if index + 2 < tokens.count, tokens[index + 1].token == .op(":"), case .ref(let b, _) = tokens[index + 2].token, b.table == nil {
                second = b
                end = tokens[index + 2].end
                index += 2
            }
            if let (a, b) = transform(first, second), let a {
                result += prefix + a.text + (b.map { ":" + $0.text } ?? "")
            } else {
                result += "#REF!"
            }
            cursor = end
            index += 1
        }
        result += formula[cursor...]
        return result
    }
}
