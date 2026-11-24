import Foundation

// Újraimportálás meglévő táblázatba (docs/EXCEL.md 7. fejezet). CSV-re és (a második körben) xls-re ugyanígy.

public enum TableImportMode: String, Sendable {
    /// Minden cserélődik (adat, formázás, oszlopszélesség, fejléc); az azonosító és a név marad.
    case full
    /// Teljes adatcsere, de a formázás marad: a táblázat értékei pontosan az új fájléi (ami ott üres, itt is üres lesz),
    /// a cellák stílusa, az oszlopszélesség, a sormagasság, a fejléc és a rács a régi. Ahol a régi cellának nem volt
    /// stílusa, az importban felismert stílus (pl. számformátum) kerül rá.
    case partial
}

public enum TableMerge {
    public static func reimport(_ old: TableDocument, with new: TableDocument, mode: TableImportMode) -> TableDocument {
        var result: TableDocument
        switch mode {
        case .full:
            result = new
            result.id = old.id
            result.name = old.name ?? new.name
        case .partial:
            result = old
            result.size = new.size
            result.cells = [:]
            let names = Set(old.cells.keys).union(new.cells.keys)
            for name in names.sorted() {
                guard let address = CellAddress(name), address.row < new.size.rows, address.col < new.size.cols else { continue }
                let before = old.cells[name], incoming = new.cells[name]
                var cell = TableCell(v: incoming?.v, f: incoming?.f, fx: incoming?.fx)
                if let style = before?.s, style > 0, old.styles.indices.contains(style) {
                    cell.s = style
                } else if let style = incoming?.s, style > 0, new.styles.indices.contains(style) {
                    cell.s = result.styleIndex(new.styles[style])
                }
                result[address] = cell
            }
        }
        TableEngine.recalculate(&result)
        return result
    }
}
