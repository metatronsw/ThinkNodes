import Foundation

// Kiértékelés, függőségi gráf, újraszámolás (docs/EXCEL.md 4. fejezet). JS párja: Public/table/table-engine.js.

/// Másik táblázat celláinak feloldása (9. fejezet). Az első körben nincs ilyen: a hivatkozás `#REF!`.
public protocol TableResolver {
    /// A táblázat (`name` vagy `{id}`) cellájának értéke; nil, ha a táblázat nem érhető el.
    func value(table: String, at address: CellAddress) -> CellValue??
    func bounds(table: String) -> TableSize?
}

/// Függőségi csúcs: (táblázat-id, cella). A gráf így később több táblázatra is kiterjeszthető.
public struct CellKey: Hashable, Sendable {
    public var table: String
    public var address: CellAddress
}

public enum TableEngine {
    /// Belső érték: a cellaérték, kiegészítve az üres cellával és a tartománnyal.
    enum Value: Equatable {
        case empty
        case number(Double)
        case text(String)
        case bool(Bool)
        case error(String)

        init(_ cell: CellValue?) {
            switch cell {
            case nil: self = .empty
            case .number(let v)?: self = .number(v)
            case .text(let v)?: self = .text(v)
            case .bool(let v)?: self = .bool(v)
            case .error(let v)?: self = .error(v)
            }
        }

        var cellValue: CellValue {
            switch self {
            case .empty: return .number(0)
            case .number(let v): return v.isFinite ? .number(v == 0 ? 0 : v) : .error("#NUM!")  // -0 → 0
            case .text(let v): return .text(v)
            case .bool(let v): return .bool(v)
            case .error(let v): return .error(v)
            }
        }
    }

    /// Argumentum: egyetlen érték vagy tartomány értékei.
    enum Argument { case scalar(Value), range([Value]) }

    final class Context {
        var document: TableDocument
        let resolver: TableResolver?
        var computed: [String: Value] = [:]
        var visiting: Set<String> = []
        /// Az újraszámolandó képletes cellák; nil: mind.
        let dirty: Set<String>?

        init(_ document: TableDocument, resolver: TableResolver?, dirty: Set<String>?) {
            self.document = document; self.resolver = resolver; self.dirty = dirty
        }

        func cellValue(_ name: String) -> Value {
            guard let cell = document.cells[name] else { return .empty }
            guard let formula = cell.f, dirty == nil || dirty!.contains(name) else { return Value(cell.v) }
            if let done = computed[name] { return done }
            if visiting.contains(name) { return .error("#CIRC!") }
            visiting.insert(name)
            let result: Value
            if let expr = try? TableFormula.parse(formula) {
                switch TableEngine.evaluate(expr, self) {
                case .scalar(let value): result = value == .empty ? .number(0) : value
                case .range: result = .error("#VALUE!")
                }
            } else { result = .error("#NAME?") }
            visiting.remove(name)
            // Körben lévő cella: ha a saját értékelése közben körbe futott, az eredmény #CIRC!.
            computed[name] = result
            return result
        }

        func lookup(_ ref: FormulaRef, row: Int) -> Value {
            if let table = ref.table {
                guard let resolver, let value = resolver.value(table: table, at: CellAddress(row: row, col: ref.col)) else { return .error("#REF!") }
                return Value(value)
            }
            return cellValue(CellAddress(row: row, col: ref.col).name)
        }

        func rangeValues(_ a: FormulaRef, _ b: FormulaRef) -> [Value]? {
            let size: TableSize
            if let table = a.table {
                guard let bounds = resolver?.bounds(table: table) else { return nil }
                size = bounds
            } else { size = document.size }
            let c0 = min(a.col, b.col), c1 = min(max(a.col, b.col), size.cols - 1)
            let r0 = min(a.row ?? 0, b.row ?? 0)
            let r1 = a.row == nil ? size.rows - 1 : min(max(a.row!, b.row!), size.rows - 1)
            guard c0 <= c1, r0 <= r1 else { return [] }
            var values: [Value] = []
            for r in r0...r1 { for c in c0...c1 { values.append(lookup(FormulaRef(table: a.table, row: r, col: c), row: r)) } }
            return values
        }
    }

    // MARK: Újraszámolás

    /// Minden képletes cella újraszámolása (`changed == nil`), vagy csak a megváltozott cellák és a tőlük függők.
    @discardableResult
    public static func recalculate(_ document: inout TableDocument, changed: [String]? = nil, resolver: TableResolver? = nil) -> [String] {
        var dirty: Set<String>?
        if let changed { dirty = dependents(of: changed, in: document) }
        let context = Context(document, resolver: resolver, dirty: dirty)
        let targets = dirty.map { Array($0) } ?? document.cells.compactMap { $0.value.f == nil ? nil : $0.key }
        var updated: [String] = []
        for name in targets.sorted() where document.cells[name]?.f != nil {
            let value = context.cellValue(name).cellValue
            if document.cells[name]?.v != value { updated.append(name) }
            document.cells[name]?.v = value
        }
        return updated
    }

    /// A megváltozott cellák és az összes, tőlük (közvetve is) függő képletes cella.
    public static func dependents(of changed: [String], in document: TableDocument) -> Set<String> {
        var single: [String: [String]] = [:]
        var ranges: [(FormulaRef, FormulaRef, String)] = []
        for (name, cell) in document.cells {
            guard let formula = cell.f, let expr = try? TableFormula.parse(formula) else { continue }
            let refs = TableFormula.references(expr)
            for ref in refs.cells where ref.table == nil {
                single[CellAddress(row: ref.row ?? 0, col: ref.col).name, default: []].append(name)
            }
            for (a, b) in refs.ranges where a.table == nil { ranges.append((a, b, name)) }
        }
        var result = Set(changed.filter { document.cells[$0]?.f != nil })
        var queue = changed
        var seen = Set(changed)
        while let name = queue.popLast() {
            guard let address = CellAddress(name) else { continue }
            var users = single[name] ?? []
            for (a, b, user) in ranges {
                let c0 = min(a.col, b.col), c1 = max(a.col, b.col)
                let inRows = a.row == nil || (min(a.row!, b.row!)...max(a.row!, b.row!)).contains(address.row)
                if inRows && (c0...c1).contains(address.col) { users.append(user) }
            }
            for user in users where seen.insert(user).inserted {
                result.insert(user)
                queue.append(user)
            }
        }
        return result
    }

    // MARK: Kiértékelés

    static func evaluate(_ expr: FormulaExpr, _ context: Context) -> Argument {
        switch expr {
        case .number(let v): return .scalar(.number(v))
        case .text(let v): return .scalar(.text(v))
        case .bool(let v): return .scalar(.bool(v))
        case .error(let code): return .scalar(.error(code))
        case .name: return .scalar(.error("#NAME?"))
        case .ref(let ref): return .scalar(context.lookup(ref, row: ref.row ?? 0))
        case .range(let a, let b):
            guard let values = context.rangeValues(a, b) else { return .scalar(.error("#REF!")) }
            return .range(values)
        case .unary(let op, let inner):
            let value = scalar(inner, context)
            guard case .number(let n) = number(value) else { return .scalar(number(value)) }
            return .scalar(.number(op == "-" ? -n : n))
        case .percent(let inner):
            let value = number(scalar(inner, context))
            guard case .number(let n) = value else { return .scalar(value) }
            return .scalar(.number(n / 100))
        case .binary(let op, let left, let right):
            return .scalar(binary(op, scalar(left, context), scalar(right, context)))
        case .call(let name, let arguments):
            return .scalar(call(name, arguments, context))
        }
    }

    static func scalar(_ expr: FormulaExpr, _ context: Context) -> Value {
        switch evaluate(expr, context) {
        case .scalar(let value): return value
        case .range: return .error("#VALUE!")
        }
    }

    /// Számmá alakítás: üres → 0, logikai → 1/0, számszerű szöveg → szám, egyéb szöveg → #VALUE!.
    static func number(_ value: Value) -> Value {
        switch value {
        case .empty: return .number(0)
        case .number: return value
        case .bool(let flag): return .number(flag ? 1 : 0)
        case .error: return value
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return .number(0) }
            if case .value(.number(let n), _) = TableFormat.parseInput(trimmed), !trimmed.hasPrefix("=") { return .number(n) }
            return .error("#VALUE!")
        }
    }

    static func text(_ value: Value) -> Value {
        switch value {
        case .empty: return .text("")
        case .number(let n): return .text(TableFormat.general(n))
        case .bool(let flag): return .text(flag ? "IGAZ" : "HAMIS")
        case .text, .error: return value
        }
    }

    static func checked(_ n: Double) -> Value { n.isFinite ? .number(n) : .error("#NUM!") }

    static func binary(_ op: String, _ left: Value, _ right: Value) -> Value {
        if case .error = left { return left }
        if case .error = right { return right }
        switch op {
        case "&":
            guard case .text(let a) = text(left), case .text(let b) = text(right) else { return .error("#VALUE!") }
            return .text(a + b)
        case "=", "<>", "<", ">", "<=", ">=":
            let order = compare(left, right)
            switch op {
            case "=": return .bool(order == 0)
            case "<>": return .bool(order != 0)
            case "<": return .bool(order < 0)
            case ">": return .bool(order > 0)
            case "<=": return .bool(order <= 0)
            default: return .bool(order >= 0)
            }
        default:
            let a = number(left), b = number(right)
            guard case .number(let x) = a else { return a }
            guard case .number(let y) = b else { return b }
            switch op {
            case "+": return checked(x + y)
            case "-": return checked(x - y)
            case "*": return checked(x * y)
            case "/": return y == 0 ? .error("#DIV/0!") : checked(x / y)
            case "^": return x == 0 && y == 0 ? .error("#NUM!") : checked(pow(x, y))
            default: return .error("#VALUE!")
            }
        }
    }

    /// Összehasonlítás Excel szerint: szám < szöveg < logikai; a szöveg kis- és nagybetűtől függetlenül.
    static func compare(_ left: Value, _ right: Value) -> Int {
        func rank(_ v: Value) -> Int {
            switch v { case .number, .empty: return 0; case .text: return 1; case .bool: return 2; case .error: return 3 }
        }
        var a = left, b = right
        if a == .empty { a = b.isText ? .text("") : b.isBool ? .bool(false) : .number(0) }
        if b == .empty { b = a.isText ? .text("") : a.isBool ? .bool(false) : .number(0) }
        if rank(a) != rank(b) { return rank(a) < rank(b) ? -1 : 1 }
        switch (a, b) {
        case (.number(let x), .number(let y)): return approximatelyEqual(x, y) ? 0 : x < y ? -1 : 1
        case (.text(let x), .text(let y)):
            let p = x.lowercased(), q = y.lowercased()
            return p < q ? -1 : p > q ? 1 : 0
        case (.bool(let x), .bool(let y)): return x == y ? 0 : (!x ? -1 : 1)
        default: return 0
        }
    }

    /// Az Excel 15 értékes jegyig hasonlít: a csak a 15. jegy után eltérő számok egyenlők (`0,1+0,2 = 0,3` IGAZ).
    static func approximatelyEqual(_ x: Double, _ y: Double) -> Bool {
        x == y || abs(x - y) <= max(abs(x), abs(y)) * 1e-15
    }

    /// Függvényargumentumok számai: a tartományban csak a számok számítanak, a közvetlen argumentum számmá alakul.
    static func numbers(_ arguments: [FormulaExpr], _ context: Context) -> Result<[Double], ValueError> {
        var result: [Double] = []
        for argument in arguments {
            // Cellahivatkozás argumentumként úgy viselkedik, mint egy egycellás tartomány (Excel).
            let evaluated: Argument
            if case .ref = argument, case .scalar(let value) = evaluate(argument, context) { evaluated = .range([value]) }
            else { evaluated = evaluate(argument, context) }
            switch evaluated {
            case .range(let values):
                for value in values {
                    if case .error(let code) = value { return .failure(ValueError(code: code)) }
                    if case .number(let n) = value { result.append(n) }
                }
            case .scalar(let value):
                if value == .empty { continue }
                switch number(value) {
                case .number(let n): result.append(n)
                case .error(let code): return .failure(ValueError(code: code))
                default: break
                }
            }
        }
        return .success(result)
    }

    struct ValueError: Error { var code: String }

    static func call(_ name: String, _ arguments: [FormulaExpr], _ context: Context) -> Value {
        switch name {
        case "SUM", "AVERAGE", "MIN", "MAX":
            guard !arguments.isEmpty else { return .error("#VALUE!") }
            switch numbers(arguments, context) {
            case .failure(let error): return .error(error.code)
            case .success(let values):
                switch name {
                case "SUM": return checked(values.reduce(0, +))
                case "AVERAGE": return values.isEmpty ? .error("#DIV/0!") : checked(values.reduce(0, +) / Double(values.count))
                case "MIN": return .number(values.min() ?? 0)
                default: return .number(values.max() ?? 0)
                }
            }
        case "COUNT":
            var count = 0
            for argument in arguments {
                let evaluated: Argument
                if case .ref = argument, case .scalar(let value) = evaluate(argument, context) { evaluated = .range([value]) }
                else { evaluated = evaluate(argument, context) }
                switch evaluated {
                case .range(let values): count += values.filter { if case .number = $0 { return true }; return false }.count
                case .scalar(let value): if value != .empty, case .number = number(value) { count += 1 }
                }
            }
            return .number(Double(count))
        case "ROUND":
            guard (1...2).contains(arguments.count) else { return .error("#VALUE!") }
            let value = number(scalar(arguments[0], context))
            guard case .number(let x) = value else { return value }
            var digits = 0.0
            if arguments.count == 2 {
                let d = number(scalar(arguments[1], context))
                guard case .number(let n) = d else { return d }
                digits = n < 0 ? -floor(-n) : floor(n)
            }
            return checked(TableFormat.roundHalfAway(x, Int(digits)))
        case "IF":
            guard (2...3).contains(arguments.count) else { return .error("#VALUE!") }
            let condition = scalar(arguments[0], context)
            let truth: Bool
            switch condition {
            case .error: return condition
            case .empty: truth = false
            case .bool(let flag): truth = flag
            case .number(let n): truth = n != 0
            case .text(let t):
                switch t.uppercased() {
                case "TRUE", "IGAZ": truth = true
                case "FALSE", "HAMIS": truth = false
                default: return .error("#VALUE!")
                }
            }
            if truth { let v = scalar(arguments[1], context); return v == .empty ? .number(0) : v }
            if arguments.count == 3 { let v = scalar(arguments[2], context); return v == .empty ? .number(0) : v }
            return .bool(false)
        default:
            return .error("#NAME?")
        }
    }
}

extension TableEngine.Value {
    var isText: Bool { if case .text = self { return true }; return false }
    var isBool: Bool { if case .bool = self { return true }; return false }
}
