import Foundation
import cmark_gfm

struct MarkdownFormat: Codable, Equatable, Sendable {
    var bold = false
    var italic = false
    var code = false
    var link = false
}

struct MarkdownRun: Codable, Sendable {
    var text: String
    var format = MarkdownFormat()
}

struct MarkdownBlock: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case body, heading, code, quote
    }

    var kind: Kind
    var runs: [MarkdownRun]
    /// Címsorszint (1–6), csak `heading` blokknál.
    var level: Int? = nil
    /// Listaelem mélysége (1 = legfelső szint).
    var indent: Int? = nil
    /// A blokk előtti üres sorok száma a forrásban: ahány sortörés, annyi üres sor marad a dobozon.
    var blankLines: Int? = nil
}

func canvasMarkdown(_ source: String) -> [MarkdownBlock] {
    let preview = String(source.prefix(6_000))
    return preview.withCString { bytes in
        guard let document = cmark_parse_document(bytes, preview.utf8.count, CMARK_OPT_DEFAULT) else { return [] }
        defer { cmark_node_free(document) }

        func children(_ node: UnsafeMutablePointer<cmark_node>, _ visit: (UnsafeMutablePointer<cmark_node>) -> Void) {
            var child = cmark_node_first_child(node)
            while let current = child {
                visit(current)
                child = cmark_node_next(current)
            }
        }

        func literal(_ node: UnsafeMutablePointer<cmark_node>) -> String {
            cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
        }

        func inline(_ node: UnsafeMutablePointer<cmark_node>, format: MarkdownFormat, depth: Int, runs: inout [MarkdownRun]) {
            guard depth < 64 else { return }
            var format = format
            switch cmark_node_get_type(node) {
            case CMARK_NODE_TEXT:
                runs.append(MarkdownRun(text: literal(node), format: format))
                return
            case CMARK_NODE_CODE:
                format.code = true
                runs.append(MarkdownRun(text: literal(node), format: format))
                return
            case CMARK_NODE_LINEBREAK:
                runs.append(MarkdownRun(text: "\n", format: format))
                return
            case CMARK_NODE_SOFTBREAK:
                // A sor végi sortörés új sort kezd (nem olvad össze a következő sorral).
                runs.append(MarkdownRun(text: "\n", format: format))
                return
            case CMARK_NODE_STRONG: format.bold = true
            case CMARK_NODE_EMPH: format.italic = true
            case CMARK_NODE_LINK: format.link = true
            default: break
            }
            children(node) { inline($0, format: format, depth: depth + 1, runs: &runs) }
        }

        var blocks: [MarkdownBlock] = []
        var previousEnd = 0
        // Az új blokk elé beírja, hány üres sor volt a forrásban az előző blokk vége óta.
        func place(_ node: UnsafeMutablePointer<cmark_node>, _ item: MarkdownBlock) {
            var item = item
            let start = Int(cmark_node_get_start_line(node))
            let blank = max(0, start - previousEnd - 1)
            if blank > 0 { item.blankLines = blank }
            previousEnd = max(previousEnd, Int(cmark_node_get_end_line(node)))
            blocks.append(item)
        }
        func block(_ node: UnsafeMutablePointer<cmark_node>, depth: Int, quote: Bool = false, list: Int = 0) {
            guard depth < 64 else { return }
            let type = cmark_node_get_type(node)
            switch type {
            case CMARK_NODE_PARAGRAPH, CMARK_NODE_HEADING:
                var runs: [MarkdownRun] = []
                inline(node, format: MarkdownFormat(), depth: 0, runs: &runs)
                if !runs.isEmpty {
                    let heading = type == CMARK_NODE_HEADING
                    place(node, MarkdownBlock(kind: heading ? .heading : quote ? .quote : .body, runs: runs,
                                              level: heading ? Int(cmark_node_get_heading_level(node)) : nil,
                                              indent: list > 0 ? list : nil))
                }
            case CMARK_NODE_CODE_BLOCK:
                place(node, MarkdownBlock(kind: .code, runs: [MarkdownRun(text: literal(node), format: MarkdownFormat(code: true))]))
            case CMARK_NODE_THEMATIC_BREAK:
                place(node, MarkdownBlock(kind: .body, runs: [MarkdownRun(text: "────")]))
            case CMARK_NODE_LIST:
                let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
                var index = Int(cmark_node_get_list_start(node))
                children(node) { item in
                    let first = blocks.count
                    block(item, depth: depth + 1, quote: quote, list: list + 1)
                    if first < blocks.count {
                        blocks[first].runs.insert(MarkdownRun(text: ordered ? "\(index). " : "• "), at: 0)
                    }
                    index += 1
                }
            default:
                children(node) { block($0, depth: depth + 1, quote: quote || type == CMARK_NODE_BLOCK_QUOTE, list: list) }
            }
        }

        block(document, depth: 0)
        return blocks
    }
}

func wrapMarkdown(_ runs: [MarkdownRun], columns: Int, preformatted: Bool = false) -> [(pieces: [MarkdownRun], wrapped: Bool)] {
    wrapMarkdown(runs, limit: Double(columns), preformatted: preformatted) { _, _ in 1 }.map { ($0.pieces, $0.wrapped) }
}

/// Tördelés becsült szélesség szerint (geometry.js wrapRuns párja; a két oldalnak pontosan egyeznie kell).
/// `width(betű, formátum)` egy betű szélessége, `limit` a sor szélessége; a szóköz formátuma `nil`.
func wrapMarkdown(_ runs: [MarkdownRun], limit: Double, preformatted: Bool = false,
                  width: (Character, MarkdownFormat?) -> Double) -> [(pieces: [MarkdownRun], wrapped: Bool, width: Double)] {
    var rows: [(pieces: [MarkdownRun], wrapped: Bool, width: Double)] = []
    var line: [MarkdownRun] = []
    var word: [(Character, MarkdownFormat, Double)] = []
    var used = 0.0

    func endLine(wrapped: Bool = false) {
        if !line.isEmpty { rows.append((line, wrapped, used)) }
        line = []
        used = 0
    }

    func append(_ character: Character, format: MarkdownFormat?, size: Double) {
        let format = format ?? MarkdownFormat()
        if let last = line.indices.last, line[last].format == format {
            line[last].text.append(character)
        } else {
            line.append(MarkdownRun(text: String(character), format: format))
        }
        used += size
    }

    func endWord() {
        guard !word.isEmpty else { return }
        var wordWidth = 0.0
        for (_, _, size) in word { wordWidth += size }
        if used > 0 {
            let space = width(" ", nil)
            if used + space + wordWidth > limit { endLine(wrapped: true) }
            else { append(" ", format: nil, size: space) }
        }
        for (character, format, size) in word {
            if used > 0 && used + size > limit { endLine(wrapped: true) }
            append(character, format: format, size: size)
        }
        word.removeAll(keepingCapacity: true)
    }

    for run in runs {
        for character in run.text {
            if preformatted {
                if character.isNewline {
                    if line.isEmpty { line.append(MarkdownRun(text: "", format: run.format)) }
                    endLine()
                } else {
                    let size = width(character, run.format)
                    if used > 0 && used + size > limit { endLine(wrapped: true) }
                    append(character, format: run.format, size: size)
                }
            } else if character.isNewline {
                endWord()
                endLine()
            } else if character.isWhitespace {
                endWord()
            } else {
                word.append((character, run.format, width(character, run.format)))
            }
        }
    }
    endWord()
    endLine()
    return rows
}
