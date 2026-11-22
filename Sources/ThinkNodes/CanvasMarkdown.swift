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
                runs.append(MarkdownRun(text: " ", format: format))
                return
            case CMARK_NODE_STRONG: format.bold = true
            case CMARK_NODE_EMPH: format.italic = true
            case CMARK_NODE_LINK: format.link = true
            default: break
            }
            children(node) { inline($0, format: format, depth: depth + 1, runs: &runs) }
        }

        var blocks: [MarkdownBlock] = []
        func block(_ node: UnsafeMutablePointer<cmark_node>, depth: Int, quote: Bool = false, list: Int = 0) {
            guard depth < 64 else { return }
            let type = cmark_node_get_type(node)
            switch type {
            case CMARK_NODE_PARAGRAPH, CMARK_NODE_HEADING:
                var runs: [MarkdownRun] = []
                inline(node, format: MarkdownFormat(), depth: 0, runs: &runs)
                if !runs.isEmpty {
                    let heading = type == CMARK_NODE_HEADING
                    blocks.append(MarkdownBlock(kind: heading ? .heading : quote ? .quote : .body, runs: runs,
                                                level: heading ? Int(cmark_node_get_heading_level(node)) : nil,
                                                indent: list > 0 ? list : nil))
                }
            case CMARK_NODE_CODE_BLOCK:
                blocks.append(MarkdownBlock(kind: .code, runs: [MarkdownRun(text: literal(node), format: MarkdownFormat(code: true))]))
            case CMARK_NODE_THEMATIC_BREAK:
                blocks.append(MarkdownBlock(kind: .body, runs: [MarkdownRun(text: "────")]))
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
    var rows: [(pieces: [MarkdownRun], wrapped: Bool)] = []
    var line: [MarkdownRun] = []
    var word: [(Character, MarkdownFormat)] = []
    var count = 0

    func endLine(wrapped: Bool = false) {
        if !line.isEmpty { rows.append((line, wrapped)) }
        line = []
        count = 0
    }

    func append(_ character: Character, format: MarkdownFormat) {
        if let last = line.indices.last, line[last].format == format {
            line[last].text.append(character)
        } else {
            line.append(MarkdownRun(text: String(character), format: format))
        }
        count += 1
    }

    func endWord() {
        guard !word.isEmpty else { return }
        if count > 0 {
            if count + word.count + 1 > columns { endLine(wrapped: true) }
            else { append(" ", format: MarkdownFormat()) }
        }
        for (character, format) in word {
            if count == columns { endLine(wrapped: true) }
            append(character, format: format)
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
                    if count == columns { endLine(wrapped: true) }
                    append(character, format: run.format)
                }
            } else if character.isNewline {
                endWord()
                endLine()
            } else if character.isWhitespace {
                endWord()
            } else {
                word.append((character, run.format))
            }
        }
    }
    endWord()
    endLine()
    return rows
}
