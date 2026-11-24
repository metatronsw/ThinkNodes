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
    #expect(html.contains("text-decoration:underline overline"))
    #expect(html.contains("border-top:3px double #000"))
    #expect(!html.contains("javascript"))
    #expect(html.contains("&lt;b&gt;&amp;&lt;/b&gt;"))
}
