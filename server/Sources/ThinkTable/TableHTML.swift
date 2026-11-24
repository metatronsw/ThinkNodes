import Foundation

// A táblázat HTML-je a megtekintőhöz, az SVG-exporthoz és az előnézeti képhez (docs/EXCEL.md 5. fejezet).
// A szerkesztő ugyanezt a szerkezetet rajzolja (Public/table/table-view.js); a CSS: Public/app.css `.tn-table`.

public enum TableHTML {
    public static let defaultColumnWidth = 80.0
    public static let defaultRowHeight = 24.0
    public static let maxPreviewRows = 200

    static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    /// Szín: csak #rgb / #rrggbb (a fájl idegen adat, CSS-be kerül).
    static func color(_ value: String?) -> String? {
        guard let value, value.hasPrefix("#"), [4, 7, 9].contains(value.count),
              value.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return value
    }

    static func borderCSS(_ line: BorderLine?) -> String? {
        guard let line, let w = line.w, w > 0 else { return nil }
        let style = ["solid", "dashed", "dotted", "double"].contains(line.style ?? "") ? line.style! : "solid"
        let width = style == "double" ? 3 : min(max(w, 1), 3)
        return "\(width)px \(style) \(color(line.color) ?? "#000000")"
    }

    /// Cella stílusa CSS-ként (a szerkesztő `cellCSS`-ével egyezően).
    public static func cellCSS(_ style: CellStyle, value: CellValue?) -> String {
        var css: [String] = []
        if style.b == true { css.append("font-weight:700") }
        if style.i == true { css.append("font-style:italic") }
        let decorations = [style.u == true ? "underline" : nil, style.o == true ? "line-through" : nil].compactMap { $0 }
        if !decorations.isEmpty { css.append("text-decoration:" + decorations.joined(separator: " ")) }
        if let c = color(style.color) { css.append("color:" + c) }
        if let c = color(style.fill) { css.append("background:" + c) }
        if let align = style.align, ["left", "center", "right"].contains(align) { css.append("text-align:" + align) }
        if let border = style.border {
            for (side, line) in [("top", border.top), ("right", border.right), ("bottom", border.bottom), ("left", border.left)] {
                if let value = borderCSS(line) { css.append("border-\(side):\(value)") }
            }
        }
        return css.joined(separator: ";")
    }

    static func kind(_ value: CellValue?) -> String {
        switch value {
        case .number?: return "num"
        case .bool?: return "bool"
        case .error?: return "err"
        default: return "txt"
        }
    }

    public static func render(_ document: TableDocument, maxRows: Int = maxPreviewRows) -> String {
        let rows = min(document.size.rows, maxRows), cols = document.size.cols
        let headerRows = min(document.header?.rows ?? 0, rows)
        // A teljes szélesség kifejezett: rögzített oszlopszélességekhez (table-layout: fixed) kell, különben a böngésző
        // a tartalomhoz igazít (pl. a félkövér betű szélesíti az oszlopot). A szerkesztő `tableWidth`-jének párja.
        let widths = (0..<cols).map { Int(max(16, min(document.cols?[CellAddress.columnName($0)]?.w ?? defaultColumnWidth, 2000))) }
        var html = "<table class=\"tn-table\(document.grid == false ? " no-grid" : "")\" style=\"width:\(widths.reduce(0, +))px\"><colgroup>"
        for width in widths { html += "<col style=\"width:\(width)px\">" }
        html += "</colgroup>"
        func row(_ r: Int, cell tag: String) -> String {
            let height = document.rows?[String(r + 1)]?.h ?? defaultRowHeight
            var line = height == defaultRowHeight ? "<tr>" : "<tr style=\"height:\(Int(max(12, min(height, 2000))))px\">"
            for c in 0..<cols {
                let cell = document[CellAddress(row: r, col: c)]
                let style = document.style(of: cell)
                let css = cellCSS(style, value: cell?.v)
                let classes = kind(cell?.v) + (cell?.fx != nil ? " fixed" : "")
                line += "<\(tag) class=\"\(classes)\"\(css.isEmpty ? "" : " style=\"\(escaped(css))\"")>"
                line += escaped(TableFormat.display(cell?.v, style.fmt)) + "</\(tag)>"
            }
            return line + "</tr>"
        }
        if headerRows > 0 { html += "<thead>" + (0..<headerRows).map { row($0, cell: "th") }.joined() + "</thead>" }
        html += "<tbody>" + (headerRows..<max(headerRows, rows)).map { row($0, cell: "td") }.joined() + "</tbody></table>"
        if document.size.rows > rows { html += "<p class=\"tn-table-more\">… további \(document.size.rows - rows) sor</p>" }
        return html
    }
}
