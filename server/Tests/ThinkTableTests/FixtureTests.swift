import Foundation
import Testing
@testable import ThinkTable

// Közös tesztesetek (Tests/TableFixtures): a JavaScript-oldal (Tests/Editor/table-engine.mjs) ugyanezeket futtatja.

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("TableFixtures")

private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(contentsOf: fixtures.appendingPathComponent(name)))
}

private struct FormulaCase: Decodable {
    var name: String
    var cells: [String: String]
    var expect: [String: CellValue]
    var change: [String: String]?
    var after: [String: CellValue]?
}

private func apply(_ inputs: [String: String], to document: inout TableDocument) {
    for (name, input) in inputs {
        let address = CellAddress(name)!
        var cell = TableCell()
        switch TableFormat.parseInput(input) {
        case .empty: break
        case .formula(let formula): cell.f = formula
        case .value(let value, let format):
            cell.v = value
            if let format { cell.s = document.styleIndex(CellStyle(fmt: format)) }
        }
        document[address] = cell
        document.size.rows = max(document.size.rows, address.row + 1)
        document.size.cols = max(document.size.cols, address.col + 1)
    }
}

@Test func sharedFormulaFixtures() throws {
    for test in try load("formulas.json", as: [FormulaCase].self) {
        var document = TableDocument(rows: 1, cols: 1)
        apply(test.cells, to: &document)
        TableEngine.recalculate(&document)
        for (name, expected) in test.expect {
            #expect(document.cells[name]?.v == expected, "\(test.name): \(name)")
        }
        if let change = test.change, let after = test.after {
            apply(change, to: &document)
            TableEngine.recalculate(&document, changed: Array(change.keys))
            for (name, expected) in after {
                #expect(document.cells[name]?.v == expected, "\(test.name) (változás után): \(name)")
            }
            var full = document
            TableEngine.recalculate(&full)
            #expect(full == document, "\(test.name): a részleges újraszámolás eltér a teljestől")
        }
    }
}

private struct FormatCase: Decodable { var value: CellValue; var fmt: NumberFormat?; var text: String }

@Test func sharedFormatFixtures() throws {
    for test in try load("formats.json", as: [FormatCase].self) {
        #expect(TableFormat.display(test.value, test.fmt) == test.text, "\(test.value) \(String(describing: test.fmt))")
    }
}

private struct InputCase: Decodable { var input: String; var kind: String; var formula: String?; var v: CellValue?; var fmt: NumberFormat? }

@Test func sharedInputFixtures() throws {
    for test in try load("inputs.json", as: [InputCase].self) {
        let parsed = TableFormat.parseInput(test.input)
        switch test.kind {
        case "empty": #expect(parsed == .empty, "\(test.input)")
        case "formula": #expect(parsed == .formula(test.formula!), "\(test.input)")
        default: #expect(parsed == .value(test.v!, test.fmt), "\(test.input) → \(parsed)")
        }
    }
}

private struct RewriteCase: Decodable {
    var formula: String; var op: String; var axis: String?; var at: Int?; var count: Int?; var rows: Int?; var cols: Int?; var expect: String
}

@Test func sharedRewriteFixtures() throws {
    for test in try load("rewrite.json", as: [RewriteCase].self) {
        let result = test.op == "shift"
            ? TableFormula.shift(test.formula, axis: test.axis == "row" ? .row : .col, at: test.at!, count: test.count!)
            : TableFormula.move(test.formula, rows: test.rows!, cols: test.cols!)
        #expect(result == test.expect, "\(test.formula) \(test.op)")
    }
}

@Test func documentRoundTripAndLimits() throws {
    var document = TableDocument(id: "tbl-test", name: "Próba", rows: 3, cols: 2)
    document[CellAddress("B2")!] = TableCell(v: .number(2), f: "1+1", s: document.styleIndex(CellStyle(b: true, border: CellBorder(bottom: BorderLine(w: 2, color: "#333333")))))
    let data = try document.encoded()
    #expect(try TableDocument.decode(data) == document)
    #expect(String(decoding: data, as: UTF8.self).contains(#""b":1"#))
    #expect(throws: TableDocument.Problem.self) { try TableDocument.decode(Data(#"{"format":"x","version":1,"id":"a","size":{"rows":1,"cols":1},"styles":[],"cells":{}}"#.utf8)) }
    #expect(throws: (any Error).self) { try TableDocument.decode(Data(#"{"format":"thinknodes-table","version":1,"id":"a","size":{"rows":1,"cols":1},"styles":[],"cells":{"ZZZZ1":{"v":1}}}"#.utf8)) }
}

/// A táblázat független a forrásfájltól: a régi fájlok `source` / `edited` mezője beolvasáskor elmarad, mentéskor nem kerül vissza.
@Test func oldSourceLinkIsDropped() throws {
    let old = #"{"format":"thinknodes-table","version":1,"id":"tbl-1","size":{"rows":1,"cols":1},"styles":[{}],"cells":{"A1":{"v":1}},"source":{"name":"file-x","hash":"ab"},"edited":true}"#
    let encoded = String(decoding: try TableDocument.decode(Data(old.utf8)).encoded(), as: UTF8.self)
    #expect(!encoded.contains("source") && !encoded.contains("edited"))
}

@Test func csvImportDetectsSeparatorTypesAndHeader() {
    let csv = "\u{FEFF}Termék;Ár;Arány\r\nAlma;\"1 200\";12%\r\n\"Körte; sárga\";850,5;=1+1\r\n"
    let imported = TableCSV.importCSV(Data(csv.utf8), name: "lista", ext: "csv")
    let doc = imported.document
    #expect(doc.size == TableSize(rows: 3, cols: 3))
    #expect(doc.header?.rows == 1)
    #expect(doc.cells["A3"]?.v == .text("Körte; sárga"))
    #expect(doc.cells["B2"]?.v == .number(1200))
    #expect(doc.cells["B3"]?.v == .number(850.5))
    #expect(doc.cells["C2"]?.v == .number(0.12))
    #expect(doc.cells["C3"]?.v == .text("=1+1"))
    #expect(doc.cells["C3"]?.f == nil)
    #expect(doc.style(of: doc.cells["A1"]).b == true)
    let latin2 = Data([0x4E, 0xE9, 0x76, 0x2C, 0x4B, 0xF5, 0x0A])  // "Név,Kő" Windows-1250 kódolással
    #expect(TableCSV.importCSV(latin2, name: "x").document.cells["B1"]?.v == .text("Kő"))
    let exported = String(decoding: TableCSV.export(doc), as: UTF8.self)
    #expect(exported.contains("Körte; sárga,850.5,'=1+1"))
}

@Test func htmlRendersFormatsStylesAndEscapes() {
    var doc = TableDocument(rows: 2, cols: 2)
    let style = doc.styleIndex(CellStyle(b: true, u: true, o: true, color: "#b00020", fill: "javascript:x", fmt: NumberFormat(kind: "currency", symbol: "Ft"),
                                         border: CellBorder(top: BorderLine(w: 3, color: "#000", style: "double"))))
    doc[CellAddress("A1")!] = TableCell(v: .number(1500), s: style)
    doc[CellAddress("B2")!] = TableCell(v: .text("<b>&</b>"))
    let html = TableHTML.render(doc)
    #expect(html.contains("1\u{00A0}500 Ft"))
    #expect(html.contains("text-decoration:underline line-through"))
    #expect(html.contains("border-top:3px double #000"))
    #expect(!html.contains("javascript"))
    #expect(html.contains("&lt;b&gt;&amp;&lt;/b&gt;"))
}

@Test func separatorDetectionIsDeterministic() {
    #expect(TableCSV.detectSeparator("a;b,c\n", ext: "csv") == ",")
    #expect(TableCSV.detectSeparator("a;b;c,d\n", ext: "csv") == ";")
    #expect(TableCSV.detectSeparator("a\tb\n", ext: "csv") == "\t")
    #expect(TableCSV.detectSeparator("abc\n", ext: "csv") == ",")
    #expect(TableCSV.detectSeparator("a,b\n", ext: "tsv") == "\t")
}

/// Újraimportálás: részlegesnél teljes adatcsere, a formázás marad; teljesnél minden cserélődik, az azonosító marad.
@Test func reimportReplacesDataAndKeepsFormattingWhenPartial() {
    var old = TableDocument(id: "tbl-regi", name: "Régi", rows: 4, cols: 3)
    let red = old.styleIndex(CellStyle(fill: "#ff0000", border: CellBorder(bottom: BorderLine(w: 2))))
    old[CellAddress("A1")!] = TableCell(v: .text("régi fej"), s: red)
    old[CellAddress("B2")!] = TableCell(v: .number(5), s: red)
    old[CellAddress("C3")!] = TableCell(v: .text("eltűnik"))
    old[CellAddress("C4")!] = TableCell(v: .number(9), s: red)
    old.cols = ["A": ColumnInfo(w: 150)]
    old.header = HeaderInfo(rows: 1)
    let csv = "Név;Ár\nAlma;12%\n;=1+1\n"
    let new = TableCSV.importCSV(Data(csv.utf8), name: "uj").document

    let partial = TableMerge.reimport(old, with: new, mode: .partial)
    #expect(partial.id == "tbl-regi" && partial.name == "Régi")
    #expect(partial.size == TableSize(rows: 3, cols: 2))
    #expect(partial.cells["A1"]?.v == .text("Név"))
    #expect(partial.style(of: partial.cells["A1"]).fill == "#ff0000")      // régi formázás marad
    #expect(partial.cells["B2"]?.v == .number(0.12))
    #expect(partial.style(of: partial.cells["B2"]).fill == "#ff0000")      // régi stílus nyer az importált % felett
    #expect(partial.style(of: partial.cells["B1"]).b == true)              // új cella: az import stílusa (fejléc félkövér)
    #expect(partial.cells["C3"] == nil)                                    // az újban üres → itt is üres
    #expect(partial.cells["C4"] == nil)                                    // az új méreten kívül
    #expect(partial.cells["B3"]?.v == .text("=1+1"))
    #expect(partial.cols?["A"]?.w == 150 && partial.header?.rows == 1)

    let full = TableMerge.reimport(old, with: new, mode: .full)
    #expect(full.id == "tbl-regi" && full.name == "Régi")
    #expect(full.style(of: full.cells["A1"]).fill == nil)
    #expect(full.style(of: full.cells["B2"]).fmt?.kind == "percent")
    #expect(full.cols == nil)
}

// Differenciális fuzz (audit, 2026-11-24): a JS által előállított esetek (Tests/Editor/table-fuzz.mjs) Swiftben is ugyanazt adják.
// A számok "n:<szöveg>" alakban vannak (a Double(String) pontos; a JSONDecoder egyes platformokon 1 ulp-t téved).
private struct FuzzValue: Decodable {
    var value: CellValue
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self), text.hasPrefix("n:"), let number = Double(text.dropFirst(2)) { value = .number(number) }
        else { value = try container.decode(CellValue.self) }
    }
    var number: Double { if case .number(let n) = value { return n }; return .nan }
}

private struct FuzzCases: Decodable {
    struct Format: Decodable { var v: FuzzValue; var fmt: NumberFormat?; var text: String }
    struct Round: Decodable { var v: FuzzValue; var d: Int; var r: FuzzValue }
    struct Parse: Decodable { var input: String; var kind: String; var v: FuzzValue?; var fmt: NumberFormat? }
    struct Formula: Decodable { var f: String; var v: FuzzValue }
    var format: [Format]; var round: [Round]; var parse: [Parse]; var formula: [Formula]
}

@Test func sharedFuzzFixtures() throws {
    let cases = try load("numbers-fuzz.json", as: FuzzCases.self)
    var mismatches: [String] = []
    for c in cases.format where TableFormat.display(.number(c.v.number), c.fmt) != c.text {
        mismatches.append("display(\(c.v.number), \(String(describing: c.fmt?.kind))) = \(TableFormat.display(.number(c.v.number), c.fmt)) ≠ \(c.text)")
    }
    for c in cases.round where TableFormat.roundHalfAway(c.v.number, c.d) != c.r.number {
        mismatches.append("round(\(c.v.number), \(c.d)) = \(TableFormat.roundHalfAway(c.v.number, c.d)) ≠ \(c.r.number)")
    }
    for c in cases.parse {
        let parsed = TableFormat.parseInput(c.input)
        let expected: TableFormat.Input = c.kind == "empty" ? .empty : .value(c.v?.value ?? .text(""), c.fmt)
        if parsed != expected { mismatches.append("parse(\(c.input)) = \(parsed) ≠ \(expected)") }
    }
    for c in cases.formula {
        var document = TableDocument(rows: 1, cols: 1)
        document[CellAddress("A1")!] = TableCell(f: c.f)
        TableEngine.recalculate(&document)
        if document.cells["A1"]?.v != c.v.value { mismatches.append("=\(c.f) → \(String(describing: document.cells["A1"]?.v)) ≠ \(c.v.value)") }
    }
    let report = "\(mismatches.count) eltérés:\n" + mismatches.prefix(25).joined(separator: "\n")
    #expect(mismatches.isEmpty, "\(report)")
}

/// Audit-lelet rögzítése: a platform JSONDecoder-e pontosan olvassa-e a lebegőpontos literált. A macOS 13 Foundation
/// egyes számoknál 1 ulp-t téved (pl. 0.0020293361140076467); ha a teszt jelzi, a .tntable értékei a szerveren
/// az utolsó bináris jegyben elcsúszhatnak (a kiírt 15 jegyre nincs hatással). A Double(String) pontos.
@Test func platformJSONDecoderDoublePrecision() throws {
    let literals = ["0.0020293361140076467", "0.056338028169014086", "0.00009365358373615191", "452667510065700000000"]
    let decoded = try JSONDecoder().decode([Double].self, from: Data(("[" + literals.joined(separator: ",") + "]").utf8))
    let inexact = zip(literals, decoded).filter { Double($0.0)! != $0.1 }.map(\.0)
    if !inexact.isEmpty { print("FIGYELEM: a JSONDecoder pontatlan lebegőpontos literáloknál: \(inexact)") }
    #expect(Double("0.0020293361140076467")! == 729.8 / 359625)
}

@Test func hungarianCSVTreatsDotAsGrouping() {
    let semicolon = TableCSV.importCSV(Data("a;b;c\n1.234;1.234,5;12.5\n".utf8), name: "hu").document
    #expect(semicolon.cells["A2"]?.v == .number(1234))
    #expect(semicolon.cells["B2"]?.v == .number(1234.5))
    #expect(semicolon.cells["C2"]?.v == .number(12.5))
    let comma = TableCSV.importCSV(Data("a,b\n1.234,x\n".utf8), name: "en").document
    #expect(comma.cells["A2"]?.v == .number(1.234))
}
