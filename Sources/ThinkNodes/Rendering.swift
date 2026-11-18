import Foundation
import Vapor
import cmark_gfm

func escaped(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

func markdownHTML(_ source: String) -> String {
    source.withCString { bytes in
        guard let html = cmark_markdown_to_html(bytes, source.utf8.count, CMARK_OPT_DEFAULT) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }
}

func canvasMarkdown(_ source: String) -> String {
    source.withCString { bytes in
        guard let document = cmark_parse_document(bytes, source.utf8.count, CMARK_OPT_DEFAULT) else { return "" }
        defer { cmark_node_free(document) }
        guard let plain = cmark_render_plaintext(document, CMARK_OPT_DEFAULT, 0) else { return "" }
        defer { free(plain) }
        return String(String(cString: plain).prefix(6_000))
    }
}

func renderedComment(_ value: String?) -> String {
    guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
    return "<p class=\"comment\">\(escaped(value))</p>"
}

func htmlPage(title: String, body: String, scripts: Bool = false) -> Response {
    let assets = scripts ? """
        <script defer src="/vendor/vue.js"></script>
        <script defer src="/vendor/d3.js"></script>
        <script type="module" src="/editor.js"></script>
        """ : ""
    return response("""
        <!doctype html>
        <html lang="hu">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escaped(title)) · ThinkNodes</title>
          <link rel="stylesheet" href="/app.css">
          \(assets)
        </head>
        <body>\(body)</body>
        </html>
        """, type: "text/html; charset=utf-8")
}

func response(_ content: String, type: String, filename: String? = nil) -> Response {
    var headers: HTTPHeaders = ["Content-Type": type, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"]
    headers.replaceOrAdd(name: "Content-Security-Policy",
                         value: "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
    if let filename {
        let encoded = filename.utf8.map { byte in
            switch byte {
            case 48...57, 65...90, 97...122, 45, 46, 95: String(UnicodeScalar(byte))
            default: String(format: "%%%02X", byte)
            }
        }.joined()
        let fallback = encoded.contains("%") ? "munkalap." + (filename.split(separator: ".").last.map(String.init) ?? "txt") : encoded
        headers.replaceOrAdd(name: "Content-Disposition",
                             value: "attachment; filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)")
    }
    return Response(status: .ok, headers: headers, body: .init(string: content))
}

func csrfInput(_ token: String) -> String {
    "<input type=\"hidden\" name=\"csrf\" value=\"\(escaped(token))\">"
}

func siteHeader(path: String? = nil, project: String? = nil, user: User?, csrf: String?) -> String {
    let crumb = path.map { "<span class=\"slash\">/</span><a href=\"/\($0)\">\(escaped(project ?? $0))</a>" } ?? ""
    let session: String
    if let user, let csrf {
        session = """
            <form method="post" action="/logout" class="account">
              \(csrfInput(csrf))
              <span>\(escaped(user.name))</span><button class="button small" type="submit">Kijelentkezés</button>
            </form>
            """
    } else {
        session = """
            <a class="button small" href="/login\(path.map { "?next=/\($0)" } ?? "")">Bejelentkezés</a>
            """
    }
    return """
        <header class="site-header"><nav aria-label="Fő navigáció" class="breadcrumbs">
          <a class="brand" href="/"><span class="brand-icon" aria-hidden="true"><span></span><span></span><span></span></span>ThinkNodes</a>
          \(crumb)
        </nav><div class="header-user">\(user?.role == .admin ? "<a class=\"button small\" href=\"/admin\">Admin</a>" : "")\(session)</div></header>
        """
}

private func number(_ value: Double) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
}

private func borderPoint(_ idea: Idea, toward point: Point) -> Point {
    let dx = point.x - idea.position.x
    let dy = point.y - idea.position.y
    guard dx != 0 || dy != 0 else { return idea.position }
    let x = dx / (idea.width / 2)
    let y = dy / (idea.height / 2)
    let scale: Double
    switch idea.shape {
    case .ellipse: scale = 1 / hypot(x, y)
    case .diamond: scale = 1 / (abs(x) + abs(y))
    case .rectangle, .rounded: scale = 1 / max(abs(x), abs(y))
    }
    return Point(x: idea.position.x + dx * scale, y: idea.position.y + dy * scale)
}

private func edgePath(from: Point, to: Point, style: ConnectionStyle) -> (path: String, control: Point?) {
    let start = "\(number(from.x)) \(number(from.y))"
    let end = "\(number(to.x)) \(number(to.y))"
    guard style == .rope else { return ("M \(start) L \(end)", nil) }
    let control = Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + min(110, hypot(to.x - from.x, to.y - from.y) * 0.28))
    return ("M \(start) Q \(number(control.x)) \(number(control.y)) \(end)", control)
}

private func wrap(_ title: String, columns: Int) -> [String] {
    var lines: [String] = []
    var line = ""
    for word in title.split(whereSeparator: \.isWhitespace).map(String.init) {
        if !line.isEmpty && line.count + word.count + 1 > columns {
            lines.append(line)
            line = ""
        }
        var remaining = word
        while remaining.count > columns {
            lines.append(String(remaining.prefix(columns)))
            remaining = String(remaining.dropFirst(columns))
        }
        line += line.isEmpty ? remaining : " " + remaining
    }
    if !line.isEmpty { lines.append(line) }
    return lines
}

private struct IdeaLabelLine {
    var text: String
    let size: Double
    let weight: Int
    let color: String

    var step: Double { size * 1.25 }
}

private struct IdeaDrawing {
    var node: Idea
    let labelWidth: Double
    let lines: [IdeaLabelLine]
}

private func textWidth(_ value: String, size: Double) -> Double {
    value.reduce(0.0) { sum, letter in
        if "MW@#%&".contains(letter) { return sum + 0.95 }
        if " ilI1.,:!|'".contains(letter) { return sum + 0.33 }
        return sum + 0.65
    } * size
}

private func darker(_ color: String) -> String {
    let channels = Array(color.dropFirst())
    return "#" + stride(from: 0, to: 6, by: 2).map { index in
        let value = Int(String(channels[index...index + 1]), radix: 16) ?? 0
        return String(format: "%02x", Int(Double(value) * 0.83))
    }.joined()
}

private func ideaDrawing(_ idea: Idea) -> IdeaDrawing {
    var node = idea
    let widthRatio = node.shape == .diamond ? 0.50 : node.shape == .ellipse ? 0.72 : 0.94
    let heightRatio = node.shape == .diamond ? 0.47 : node.shape == .ellipse ? 0.72 : 0.94
    let detailSize = max(10, node.fontSize * 0.80)
    let comment = node.comment ?? ""
    let markdown = node.showMarkdown == true && !node.markdown.isEmpty ? canvasMarkdown(node.markdown) : ""
    if node.autoSize != false {
        let targetWidth = max(textWidth(node.title, size: node.fontSize),
                              min(245, textWidth(comment, size: detailSize)),
                              markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 200)
        node.width = min(880, max(64, ceil((targetWidth + 24) / widthRatio)))
    }
    let labelWidth = max(12, node.width * widthRatio - 16)
    var lines: [IdeaLabelLine] = []
    func add(_ value: String, size: Double, weight: Int, color: String) {
        let text = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return }
        let columns = max(2, Int(labelWidth / (size * 0.65)))
        let rendered = textWidth(text, size: size) <= labelWidth ? [text] : wrap(text, columns: columns)
        lines.append(contentsOf: rendered.map { IdeaLabelLine(text: $0, size: size, weight: weight, color: color) })
    }
    add(node.title, size: node.fontSize, weight: node.bold ? 650 : 400, color: node.textColor)
    add(comment, size: detailSize, weight: 400, color: darker(node.textColor))
    for paragraph in markdown.split(whereSeparator: \.isNewline) {
        add(String(paragraph), size: detailSize, weight: 400, color: node.textColor)
    }
    if node.autoSize != false {
        let targetHeight = lines.reduce(0) { $0 + $1.step } + 16
        node.height = min(680, max(40, ceil(targetHeight / heightRatio)))
    }
    var visible: [IdeaLabelLine] = []
    var remaining = max(node.fontSize * 1.25, node.height * heightRatio - 12)
    for line in lines {
        guard remaining >= line.step else { break }
        visible.append(line)
        remaining -= line.step
    }
    if !visible.isEmpty && visible.count < lines.count {
        visible[visible.count - 1].text += "…"
    }
    return IdeaDrawing(node: node, labelWidth: labelWidth, lines: visible)
}

private func nodeSVG(_ drawing: IdeaDrawing) -> String {
    let node = drawing.node
    let width = node.width
    let height = node.height
    let x = width / 2
    let y = height / 2
    let appearance = "fill=\"\(escaped(node.fill))\" stroke=\"\(escaped(node.border))\" stroke-width=\"1.6\""
    let geometry: String
    switch node.shape {
    case .rectangle, .rounded:
        geometry = """
            <rect x="\(number(-x))" y="\(number(-y))" width="\(number(width))" height="\(number(height))" rx="\(node.shape == .rounded ? "12" : "0")" \(appearance)/>
            """
    case .ellipse:
        geometry = "<ellipse rx=\"\(number(x))\" ry=\"\(number(y))\" \(appearance)/>"
    case .diamond:
        geometry = "<polygon points=\"0,\(number(-y)) \(number(x)),0 0,\(number(y)) \(number(-x)),0\" \(appearance)/>"
    }
    let labelWidth = drawing.labelWidth
    let textX: Double
    let anchor: String
    switch node.alignment {
    case .left: (textX, anchor) = (-labelWidth / 2, "start")
    case .right: (textX, anchor) = (labelWidth / 2, "end")
    case .center: (textX, anchor) = (0, "middle")
    }
    var top = -drawing.lines.reduce(0) { $0 + $1.step } / 2
    let spans = drawing.lines.map { line in
        let baseline = top + line.step / 2 + line.size * 0.33
        top += line.step
        let fit = textWidth(line.text, size: line.size) > labelWidth
            ? " textLength=\"\(number(labelWidth))\" lengthAdjust=\"spacingAndGlyphs\"" : ""
        return """
            <tspan x="\(number(textX))" y="\(number(baseline))" fill="\(escaped(line.color))" font-size="\(number(line.size))" font-weight="\(line.weight)"\(fit)>\(escaped(line.text))</tspan>
            """
    }.joined()
    return """
        <g transform="translate(\(number(node.position.x)) \(number(node.position.y)))">
          <title>\(escaped(node.title))</title>
          \(geometry)
          <text font-family="system-ui, sans-serif" text-anchor="\(anchor)" pointer-events="none">\(spans)</text>
        </g>
        """
}

func boardSVG(_ board: Worksheet, noteBase: String? = nil) -> String {
    let drawings = board.nodes.map(ideaDrawing)
    let renderedIdeas = drawings.map(\.node)
    let nodes = Dictionary(uniqueKeysWithValues: renderedIdeas.map { ($0.id, $0) })
    var halfWidth = 360.0
    var halfHeight = 240.0
    for node in renderedIdeas {
        halfWidth = max(halfWidth, abs(node.position.x) + node.width / 2 + 40)
        halfHeight = max(halfHeight, abs(node.position.y) + node.height / 2 + 40)
    }
    let edges = board.edges.compactMap { edge -> String? in
        guard let source = nodes[edge.source] else { return nil }
        let targetNode = edge.target.node.flatMap { nodes[$0] }
        guard let target = targetNode?.position ?? edge.target.point else { return nil }
        let beginning = borderPoint(source, toward: target)
        let ending = targetNode.map { borderPoint($0, toward: source.position) } ?? target
        let drawing = edgePath(from: beginning, to: ending, style: edge.style)
        halfWidth = max(halfWidth, abs(ending.x) + 40, abs(drawing.control?.x ?? 0) + 40)
        halfHeight = max(halfHeight, abs(ending.y) + 40, abs(drawing.control?.y ?? 0) + 40)
        var markers = ""
        if edge.style == .both { markers += " marker-start=\"url(#arrow)\"" }
        if edge.style != .rope { markers += " marker-end=\"url(#arrow)\"" }
        if edge.style == .dashed { markers += " stroke-dasharray=\"7 5\"" }
        return "<path d=\"\(drawing.path)\"\(markers)/>"
    }.joined(separator: "\n")
    let renderedNodes = drawings.map { drawing in
        let node = drawing.node
        let graphic = nodeSVG(drawing)
        guard let noteBase else { return graphic }
        let separator = noteBase.contains("?") ? "&amp;" : "?"
        let url = escaped(noteBase) + separator + "note=\(node.id)"
        return "<a href=\"\(url)\" aria-label=\"\(escaped(node.title))\">\(graphic)</a>"
    }.joined(separator: "\n")
    let width = number(halfWidth * 2)
    let height = number(halfHeight * 2)
    return """
        <svg xmlns="http://www.w3.org/2000/svg" class="passive-canvas" role="img" aria-label="\(escaped(board.title))" width="\(width)" height="\(height)" viewBox="\(number(-halfWidth)) \(number(-halfHeight)) \(width) \(height)">
          <title>\(escaped(board.title))</title>
          <defs><marker id="arrow" markerWidth="9" markerHeight="9" viewBox="0 0 10 10" refX="9" refY="5" orient="auto-start-reverse" markerUnits="userSpaceOnUse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#526982"/></marker></defs>
          <rect x="\(number(-halfWidth))" y="\(number(-halfHeight))" width="\(width)" height="\(height)" fill="#f5f8fc"/>
          <g fill="none" stroke="#526982" stroke-width="2" stroke-linecap="round">
            \(edges)
          </g>
          \(renderedNodes)
        </svg>
        """
}

func worksheetMarkdown(_ worksheet: Worksheet) -> String {
    func inline(_ text: String) -> String {
        let syntax = "\\`*_{}[]<>()#+-.!|"
        return text.map { syntax.contains($0) ? "\\" + String($0) : String($0) }.joined()
    }
    var sections = ["# \(inline(worksheet.title))\n"]
    if let comment = worksheet.comment, !comment.isEmpty { sections.append(inline(comment)) }
    if let markdown = worksheet.markdown, !markdown.isEmpty { sections.append(markdown) }
    for node in worksheet.nodes {
        sections.append("## \(inline(node.title))\n")
        if let comment = node.comment, !comment.isEmpty { sections.append(inline(comment)) }
        if !node.markdown.isEmpty { sections.append(node.markdown) }
    }
    if !worksheet.edges.isEmpty {
        sections.append("## Kapcsolatok\n")
        let names = Dictionary(uniqueKeysWithValues: worksheet.nodes.map { ($0.id, inline($0.title)) })
        for edge in worksheet.edges {
            guard let source = names[edge.source] else { continue }
            let target = edge.target.node.flatMap { names[$0] }
                ?? edge.target.point.map { "(\(number($0.x)), \(number($0.y)))" } ?? ""
            sections.append("- \(source) → \(target) · \(edge.style.label)")
        }
    }
    return sections.joined(separator: "\n\n") + "\n"
}
