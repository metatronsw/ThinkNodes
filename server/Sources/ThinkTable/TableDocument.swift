import Foundation

// Táblázat doboz adatmodellje (docs/EXCEL.md, 3. fejezet). A JavaScript párja: Public/table/table-document.js.
// A fájl (`.tntable`) JSON; a cellák ritkán, "A1" kulccsal tárolódnak, a stílusok indexelve.

public enum TableLimits {
    public static let maxRows = 1000
    public static let maxCols = 100
    public static let maxCells = 50_000
    public static let maxBytes = 5 * 1024 * 1024
}

/// Cella értéke: szám, szöveg, logikai érték vagy hiba (`#DIV/0!` …). JSON: szám / szöveg / bool / {"err": "…"}.
public enum CellValue: Equatable, Sendable, Codable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case error(String)

    private struct ErrorBox: Codable { var err: String }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .text(value) }
        else { self = .error(try container.decode(ErrorBox.self).err) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value.isFinite ? value : 0)
        case .text(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .error(let code): try container.encode(ErrorBox(err: code))
        }
    }
}

/// Cellakeret egy oldala: vastagság (1–3), szín, stílus (solid, dashed, dotted, double).
public struct BorderLine: Codable, Equatable, Sendable {
    public var w: Int?
    public var color: String?
    public var style: String?
    public init(w: Int? = nil, color: String? = nil, style: String? = nil) { self.w = w; self.color = color; self.style = style }
}

public struct CellBorder: Codable, Equatable, Sendable {
    public var top: BorderLine?
    public var right: BorderLine?
    public var bottom: BorderLine?
    public var left: BorderLine?
    public init(top: BorderLine? = nil, right: BorderLine? = nil, bottom: BorderLine? = nil, left: BorderLine? = nil) {
        self.top = top; self.right = right; self.bottom = bottom; self.left = left
    }
}

/// Számformátum (docs/EXCEL.md 3. fejezet): general, number, currency, percent, date, text.
public struct NumberFormat: Codable, Equatable, Sendable {
    public var kind: String
    public var dec: Int?
    public var group: Bool?
    public var symbol: String?
    public var before: Bool?
    public var pattern: String?
    public init(kind: String, dec: Int? = nil, group: Bool? = nil, symbol: String? = nil, before: Bool? = nil, pattern: String? = nil) {
        self.kind = kind; self.dec = dec; self.group = group; self.symbol = symbol; self.before = before; self.pattern = pattern
    }
}

/// Cellastílus. Bool helyett 0/1 is olvasható (a fájlban `"b": 1`).
public struct CellStyle: Codable, Equatable, Sendable {
    public var b: Bool?
    public var i: Bool?
    public var u: Bool?
    /// Áthúzott (korábban felülvonás volt; a fájlbeli kulcs maradt).
    public var o: Bool?
    public var color: String?
    public var fill: String?
    public var align: String?
    public var fmt: NumberFormat?
    public var border: CellBorder?

    public init(b: Bool? = nil, i: Bool? = nil, u: Bool? = nil, o: Bool? = nil, color: String? = nil, fill: String? = nil,
                align: String? = nil, fmt: NumberFormat? = nil, border: CellBorder? = nil) {
        self.b = b; self.i = i; self.u = u; self.o = o; self.color = color; self.fill = fill; self.align = align; self.fmt = fmt; self.border = border
    }

    enum CodingKeys: String, CodingKey { case b, i, u, o, color, fill, align, fmt, border }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool? {
            if let value = try? c.decode(Bool.self, forKey: key) { return value ? true : nil }
            if let value = try? c.decode(Int.self, forKey: key) { return value != 0 ? true : nil }
            return nil
        }
        b = flag(.b); i = flag(.i); u = flag(.u); o = flag(.o)
        color = try? c.decode(String.self, forKey: .color)
        fill = try? c.decode(String.self, forKey: .fill)
        align = try? c.decode(String.self, forKey: .align)
        fmt = try? c.decode(NumberFormat.self, forKey: .fmt)
        border = try? c.decode(CellBorder.self, forKey: .border)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if b == true { try c.encode(1, forKey: .b) }
        if i == true { try c.encode(1, forKey: .i) }
        if u == true { try c.encode(1, forKey: .u) }
        if o == true { try c.encode(1, forKey: .o) }
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(fill, forKey: .fill)
        try c.encodeIfPresent(align, forKey: .align)
        try c.encodeIfPresent(fmt, forKey: .fmt)
        try c.encodeIfPresent(border, forKey: .border)
    }
}

/// Egy cella: érték (`v`), képlet (`f`, `=` nélkül), stílusindex (`s`), importált, nem támogatott képlet (`fx`).
public struct TableCell: Codable, Equatable, Sendable {
    public var v: CellValue?
    public var f: String?
    public var s: Int?
    public var fx: String?
    public init(v: CellValue? = nil, f: String? = nil, s: Int? = nil, fx: String? = nil) { self.v = v; self.f = f; self.s = s; self.fx = fx }
    var isEmpty: Bool { v == nil && f == nil && (s ?? 0) == 0 && fx == nil }
}

public struct TableSize: Codable, Equatable, Sendable {
    public var rows: Int
    public var cols: Int
    public init(rows: Int, cols: Int) { self.rows = rows; self.cols = cols }
}

public struct ColumnInfo: Codable, Equatable, Sendable { public var w: Double? ; public init(w: Double? = nil) { self.w = w } }
public struct RowInfo: Codable, Equatable, Sendable { public var h: Double? ; public init(h: Double? = nil) { self.h = h } }
public struct HeaderInfo: Codable, Equatable, Sendable {
    public var rows: Int
    public var cols: Int
    public init(rows: Int = 0, cols: Int = 0) { self.rows = rows; self.cols = cols }
}

public struct TableDocument: Codable, Equatable, Sendable {
    public var format = "thinknodes-table"
    public var version = 1
    public var id: String
    public var name: String?
    public var size: TableSize
    public var cols: [String: ColumnInfo]?
    public var rows: [String: RowInfo]?
    public var header: HeaderInfo?
    public var grid: Bool?
    public var styles: [CellStyle]
    public var cells: [String: TableCell]
    // Nincs forrásfájl-hivatkozás: az importált táblázat független másolat (docs/EXCEL.md, 2026-11-24-i döntés).
    // A régi fájlok `source` / `edited` mezőjét a dekódoló figyelmen kívül hagyja, a következő mentés elhagyja.

    public init(id: String = TableDocument.newID(), name: String? = nil, rows: Int = 10, cols: Int = 5) {
        self.id = id
        self.name = name
        self.size = TableSize(rows: rows, cols: cols)
        self.styles = [CellStyle()]
        self.cells = [:]
        self.grid = true
    }

    public static func newID() -> String { "tbl-" + UUID().uuidString.prefix(8).lowercased() }

    public subscript(address: CellAddress) -> TableCell? {
        get { cells[address.name] }
        set {
            if let newValue, !newValue.isEmpty { cells[address.name] = newValue } else { cells[address.name] = nil }
        }
    }

    public func style(of cell: TableCell?) -> CellStyle {
        guard let index = cell?.s, styles.indices.contains(index) else { return CellStyle() }
        return styles[index]
    }

    /// Stílus indexe; ha még nincs ilyen, hozzáadja.
    public mutating func styleIndex(_ style: CellStyle) -> Int {
        if style == CellStyle() { return 0 }
        if let index = styles.firstIndex(of: style) { return index }
        styles.append(style)
        return styles.count - 1
    }

    public enum Problem: Error, Equatable { case invalidFormat, tooLarge, invalidAddress(String) }

    /// Beolvasás és ellenőrzés (formátum, korlátok, címek).
    public static func decode(_ data: Data) throws -> TableDocument {
        guard data.count <= TableLimits.maxBytes else { throw Problem.tooLarge }
        var document = try JSONDecoder().decode(TableDocument.self, from: data)
        guard document.format == "thinknodes-table", document.version >= 1 else { throw Problem.invalidFormat }
        guard document.cells.count <= TableLimits.maxCells else { throw Problem.tooLarge }
        document.size.rows = min(max(document.size.rows, 1), TableLimits.maxRows)
        document.size.cols = min(max(document.size.cols, 1), TableLimits.maxCols)
        if document.styles.isEmpty { document.styles = [CellStyle()] }
        for key in document.cells.keys {
            guard let address = CellAddress(key), address.row < TableLimits.maxRows, address.col < TableLimits.maxCols else {
                throw Problem.invalidAddress(key)
            }
            document.size.rows = max(document.size.rows, address.row + 1)
            document.size.cols = max(document.size.cols, address.col + 1)
        }
        return document
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// Cellacím: 0-tól számolt sor és oszlop. Név: "A1", "AB12".
public struct CellAddress: Hashable, Sendable, Comparable {
    public var row: Int
    public var col: Int
    public init(row: Int, col: Int) { self.row = row; self.col = col }

    public init?(_ name: String) {
        var letters = 0, index = name.startIndex, sawLetter = false
        while index < name.endIndex, let ascii = name[index].asciiValue, (65...90).contains(ascii) || (97...122).contains(ascii) {
            letters = letters * 26 + Int((ascii & 0xDF) - 64)
            sawLetter = true
            index = name.index(after: index)
            if letters > 16384 { return nil }
        }
        guard sawLetter, let row = Int(name[index...]), row >= 1, name[index...].allSatisfy(\.isASCII), name[index...].first != "+" else { return nil }
        self.init(row: row - 1, col: letters - 1)
    }

    public var name: String { Self.columnName(col) + String(row + 1) }

    public static func columnName(_ col: Int) -> String {
        var n = col + 1, result = ""
        while n > 0 { let r = (n - 1) % 26; result = String(UnicodeScalar(UInt8(65 + r))) + result; n = (n - 1) / 26 }
        return result
    }

    public static func columnIndex(_ letters: String) -> Int? {
        var value = 0
        for character in letters.uppercased() {
            guard let ascii = character.asciiValue, (65...90).contains(ascii) else { return nil }
            value = value * 26 + Int(ascii - 64)
            if value > 16384 { return nil }
        }
        return value > 0 ? value - 1 : nil
    }

    public static func < (a: CellAddress, b: CellAddress) -> Bool { (a.row, a.col) < (b.row, b.col) }
}
