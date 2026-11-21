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

func htmlPage(title: String, body: String, scripts: Bool = false) -> Response {
    let assets = scripts ? """
        <script defer src="/vendor/vue.js"></script>
        <script defer src="/vendor/d3.js"></script>
        <script type="module" src="/editor.js?v=6"></script>
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
                         value: "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' blob:; media-src 'self'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
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

func uiIcon(_ symbol: String) -> String {
    "<svg class=\"ui-icon\" aria-hidden=\"true\" viewBox=\"0 0 24 24\"><use href=\"/icons.svg#\(symbol)\"/></svg>"
}

func headerLink(_ url: String, _ label: String, symbol: String) -> String {
    "<a class=\"button small\" href=\"\(escaped(url))\">\(uiIcon(symbol))\(escaped(label))</a>"
}

func siteHeader(path: String? = nil, project: String? = nil, user: User?, csrf: String?, actions: String = "", canEdit: Bool = false, editing: Bool = false, showAdminLogout: Bool = false) -> String {
    let parts = path?.split(separator: "/").map(String.init) ?? []
    let base = editing ? "/edit/" : "/"
    let crumb = parts.indices.map { i in
        let last = i == parts.count - 1
        let prefix = last && editing ? "/" : last && canEdit ? "/edit/" : base
        let url = prefix + parts[...i].joined(separator: "/")
        let label = last ? (project ?? parts[i]) : (parts[i].removingPercentEncoding ?? parts[i])
        return "<span class=\"slash\" aria-hidden=\"true\">/</span><a \(last ? "aria-current='page'" : "") href=\"\(escaped(url))\">\(escaped(label))</a>"
    }.joined()
    let parent = parts.count > 1 ? "<a class=\"button small\" aria-label=\"Szülő munkalap\" href=\"\(escaped(base + parts.dropLast().joined(separator: "/")))\">\(uiIcon("up"))</a>" : ""
    let session: String
    if let user, let csrf {
        let logout = (user.role != .admin || showAdminLogout) ? "<button class=\"button small\" type=\"submit\" aria-label=\"Kijelentkezés\" title=\"Kijelentkezés\">\(uiIcon("logout"))</button>" : ""
        session = """
            <form method="post" action="/logout" class="account">
              \(csrfInput(csrf))
              \(isTesterName(user.name) ? headerLink("/login", "Bejelentkezés", symbol: "login") : "")
              \(user.role == .admin && user.name.lowercased() == "admin" ? "" : "<span>\(escaped(user.name))</span>")\(logout)
            </form>
            """
    } else {
        session = """
            <a class="button small" href="/login\(path.map { "?next=/\($0)" } ?? "")">\(uiIcon("login"))Bejelentkezés</a>
            """
    }
    return """
        <header class="site-header"><div class="header-left"><nav aria-label="Fő navigáció" class="breadcrumbs">
          <a class="brand" href="/"><span class="brand-icon" aria-hidden="true"><span></span><span></span><span></span></span>ThinkNodes</a>
          \(crumb)
        </nav></div><div class="header-parent">\(parent)</div><div class="header-actions">\(actions)<div class="header-user">\(user?.role == .admin ? headerLink("/admin", "Admin", symbol: "settings") : "")\(session)</div></div></header>
        """
}

private func number(_ value: Double) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
}

private extension Shape {
    // Clockwise vertices relative to the center, in units of half-width and half-height.
    var vertices: [(x: Double, y: Double)] {
        switch self {
        case .diamond: [(0, -1), (1, 0), (0, 1), (-1, 0)]
        case .triangle: [(0, -1), (1, 1), (-1, 1)]
        case .pentagon: [(0, -1), (1, -0.24), (0.62, 1), (-0.62, 1), (-1, -0.24)]
        case .hexagon: [(-0.5, -1), (0.5, -1), (1, 0), (0.5, 1), (-0.5, 1), (-1, 0)]
        case .parallelogram: [(-0.55, -1), (1, -1), (0.55, 1), (-1, 1)]
        case .rounded, .rectangle, .ellipse: []
        }
    }

    var labelRatios: (width: Double, height: Double, link: Double) {
        switch self {
        case .diamond: (0.50, 0.47, 0.45)
        case .ellipse: (0.72, 0.72, 0.70)
        case .triangle: (0.42, 0.42, 0.38)
        case .pentagon: (0.58, 0.58, 0.60)
        case .hexagon: (0.68, 0.76, 0.65)
        case .parallelogram: (0.60, 0.75, 0.58)
        case .rounded, .rectangle: (0.94, 0.94, 0.94)
        }
    }
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
    case .rectangle, .rounded: scale = 1 / max(abs(x), abs(y))
    case .diamond, .triangle, .pentagon, .hexagon, .parallelogram:
        let vertices = idea.shape.vertices
        // Normalize each edge's linear distance to one at its boundary.
        var distance = 0.0
        for (i, a) in vertices.enumerated() {
            let b = vertices[(i + 1) % vertices.count]
            let cross = x * (b.y - a.y) - y * (b.x - a.x)
            let boundary = a.x * b.y - a.y * b.x
            distance = max(distance, cross / boundary)
        }
        scale = 1 / distance
    }
    return Point(x: idea.position.x + dx * scale, y: idea.position.y + dy * scale)
}

private func edgeRoute(_ type: ConnectionType, from source: Point, to target: Point) -> (command: String, points: [Point]) {
    let dx = target.x - source.x, dy = target.y - source.y
    let length = hypot(dx, dy)
    let x = (source.x + target.x) / 2, y = (source.y + target.y) / 2
    switch type {
    case .sCurve where dx != 0 && dy != 0:
        return ("C", abs(dx) >= abs(dy)
            ? [Point(x: x, y: source.y), Point(x: x, y: target.y)]
            : [Point(x: source.x, y: y), Point(x: target.x, y: y)])
    case .lightning where length > 0:
        let offset = 0.2 * tan(Double.pi / 6)
        return ("L", [
            Point(x: source.x + dx * 0.4 + dy * offset, y: source.y + dy * 0.4 - dx * offset),
            Point(x: source.x + dx * 0.6 - dy * offset, y: source.y + dy * 0.6 + dx * offset),
        ])
    case .zigzag where length > 0:
        let offset = 0.028
        return ("L", [
            Point(x: source.x + dx * 0.515 - dy * offset, y: source.y + dy * 0.515 + dx * offset),
            Point(x: source.x + dx * 0.485 + dy * offset, y: source.y + dy * 0.485 - dx * offset),
        ])
    case .arc where length > 0:
        let rise = min(110, length * 0.28)
        return ("Q", [Point(x: dx == 0 ? x + rise : x, y: y - rise)])
    case .rope where dx != 0:
        return ("Q", [Point(x: x, y: y + min(330, length * 0.85))])
    default:
        return ("L", [])
    }
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
    var runs: [MarkdownRun] = []
    var outsideX: Double?
    var outsideTop: Double?
    var gap: Double = 0
    var justify = false
    var wrapped = false
    var style: TextStyle?

    var step: Double { size * 1.25 + gap }
}

private struct IdeaDrawing {
    var node: Idea
    let labelWidth: Double
    var iconSpace: Double = 0
    var available: Double = 0
    var overflow = false
    let lines: [IdeaLabelLine]
    var extentX: Double = 0
    var extentY: Double = 0
}

private func textWidth(_ value: String, size: Double) -> Double {
    value.reduce(0.0) { sum, letter in
        if "MW@#%&".contains(letter) { return sum + 0.95 }
        if " ilI1.,:!|'".contains(letter) { return sum + 0.33 }
        return sum + 0.65
    } * size
}

private func shortenLine(_ line: IdeaLabelLine, width: Double) -> IdeaLabelLine {
    var result = line
    var remaining = width - textWidth("…", size: line.size)
    var runs: [MarkdownRun] = []
    for run in line.runs.isEmpty ? [MarkdownRun(text: line.text)] : line.runs {
        var prefix = ""
        for letter in run.text {
            remaining -= textWidth(String(letter), size: line.size)
            if remaining < 0 { break }
            prefix.append(letter)
        }
        if !prefix.isEmpty { runs.append(MarkdownRun(text: prefix, format: run.format)) }
        if remaining < 0 { break }
    }
    runs.append(MarkdownRun(text: "…"))
    result.text = runs.map(\.text).joined()
    result.wrapped = false
    if !line.runs.isEmpty { result.runs = runs }
    return result
}

private func ideaDrawing(_ idea: Idea) -> IdeaDrawing {
    var node = idea
    if node.kind == .connectionPoint {
        node.shape = .ellipse
        return IdeaDrawing(node: node, labelWidth: 0, lines: [])
    }
    let (widthRatio, heightRatio, _) = node.shape.labelRatios
    let bounded = node.backgroundEnabled != false
    let fitText = node.fitText == true && node.file == nil
    let wrapToBox = bounded || fitText
    let text = node.hideText != true ? canvasMarkdown(node.text) :
        (node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [MarkdownBlock(kind: .body, runs: [MarkdownRun(text: "•••")])])
    let labelWidth = max(12, node.width * widthRatio - 16)
    let iconSpace: Double = (node.link ?? "").isEmpty ? 0 : 18
    let labelHeight = node.height * heightRatio - 12 - iconSpace

    func makeLines(titleSize: Double, bodySize: Double) -> [IdeaLabelLine] {
        var lines: [IdeaLabelLine] = []
        func add(_ value: String, size: Double, weight: Int, color: String, style: TextStyle?) {
            let text = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { return }
            let columns = max(2, Int(labelWidth / (size * 0.65)))
            let rendered = !wrapToBox || textWidth(text, size: size) <= labelWidth ? [text] : wrap(text, columns: columns)
            lines.append(contentsOf: rendered.map { IdeaLabelLine(text: $0, size: size, weight: weight, color: color, style: style) })
        }
        add(node.title, size: titleSize, weight: node.bold ? 650 : 400, color: node.textColor,
            style: TextStyle(italic: node.italic, underline: node.underline, verticalAlignment: node.verticalAlignment))
        for (index, block) in text.enumerated() {
            let size = block.kind == .heading ? (fitText ? bodySize * 1.15 : (bodySize * 1.15).rounded()) : bodySize
            let columns = wrapToBox || node.textStyle?.justified == true ? max(node.hideText == true ? 3 : 2, Int(labelWidth / (size * 0.65))) : Int.max
            var runs = block.runs
            if block.kind == .quote { runs.insert(MarkdownRun(text: "› "), at: 0) }
            for (row, wrappedLine) in wrapMarkdown(runs, columns: columns, preformatted: block.kind == .code).enumerated() {
                let pieces = wrappedLine.pieces
                let blockGap: Double = index == 0 ? 8 : 3
                let gap = row == 0 ? (fitText ? min(blockGap, bodySize * 0.4) : blockGap) : 0
                lines.append(IdeaLabelLine(text: pieces.map(\.text).joined(), size: size,
                                           weight: block.kind == .heading || node.textStyle?.bold == true ? 700 : 400,
                                           color: node.textStyle?.color ?? node.textColor, runs: pieces, gap: gap,
                                           justify: node.textStyle?.justified == true && block.kind != .code,
                                           wrapped: wrappedLine.wrapped,
                                           style: node.textStyle))
            }
        }
        return lines
    }

    var lines: [IdeaLabelLine]
    if fitText {
        var low = 1
        var high = Int((labelHeight / 1.25).rounded(.down))
        lines = makeLines(titleSize: 1.4, bodySize: 1)
        while low <= high {
            let size = (low + high) / 2
            let candidate = makeLines(titleSize: Double(size) * 1.4, bodySize: Double(size))
            var insideHeight = 0.0
            var outsideHeight = 0.0
            for line in candidate {
                if node.titleOutside == true && line.runs.isEmpty { outsideHeight += line.step }
                else { insideHeight += line.step }
            }
            if max(insideHeight, outsideHeight) <= labelHeight &&
                candidate.allSatisfy({ textWidth($0.text, size: $0.size) <= labelWidth }) {
                lines = candidate
                low = size + 1
            } else {
                high = size - 1
            }
        }
    } else {
        lines = makeLines(titleSize: node.fontSize, bodySize: node.textStyle?.size ?? 13)
    }
    var groups: [String: [IdeaLabelLine]] = [:]
    lines.removeAll { line in
        guard line.runs.isEmpty, node.titleOutside == true else { return false }
        let horizontal = node.alignment
        var vertical = node.verticalAlignment ?? .middle
        if horizontal == .center && vertical == .middle { vertical = .top }
        groups[horizontal.rawValue + "/" + vertical.rawValue, default: []].append(line)
        return true
    }
    let available = bounded ? max(0, labelHeight) : max(0, labelHeight, lines.reduce(0) { $0 + $1.step })
    var visible: [IdeaLabelLine] = []
    var remaining = available
    for line in lines {
        if bounded && remaining < line.step { break }
        visible.append(line)
        remaining -= line.step
    }
    let omitted = visible.count < lines.count
    if bounded && omitted && visible.isEmpty { visible.append(lines[0]); remaining -= lines[0].step }
    var overflow = omitted
    if bounded {
        for index in visible.indices {
            let line = visible[index]
            if textWidth(line.text, size: line.size) > labelWidth || (omitted && index == visible.count - 1) {
                visible[index] = shortenLine(line, width: labelWidth)
                overflow = true
            }
        }
    }
    if node.hideText == true,
       let marker = lines.last, !marker.runs.isEmpty, !visible.contains(where: { !$0.runs.isEmpty }) {
        while !visible.isEmpty && remaining < marker.step { remaining += visible.removeLast().step }
        visible.append(marker)
    }
    var extentX = node.width / 2, extentY = max(node.height, available + iconSpace) / 2
    if !bounded {
        for line in visible {
            extentX = max(extentX, labelWidth/2 + textWidth(line.text, size: line.size) * 1.25 + line.size)
        }
    }
    for key in groups.keys.sorted() {
        let rows = groups[key] ?? []
        let total = rows.reduce(0) { $0 + $1.step }
        let side: Double = key.hasPrefix("left/") ? -1 : key.hasPrefix("right/") ? 1 : 0
        let center = side * (node.width/2 + 8 + labelWidth/2)
        var top = key.hasSuffix("/top") ? -node.height/2-8-total : key.hasSuffix("/bottom") ? node.height/2+8 : -total/2
        extentX = max(extentX, abs(center) + labelWidth/2 + 4)
        extentY = max(extentY, abs(top), abs(top+total))
        for var line in rows {
            extentX = max(extentX, abs(center - side * labelWidth/2) + textWidth(line.text, size: line.size) * 1.25 + line.size)
            line.outsideX = center
            line.outsideTop = top
            visible.append(line)
            top += line.step
        }
    }
    return IdeaDrawing(node: node, labelWidth: labelWidth, iconSpace: iconSpace, available: available,
                       overflow: overflow, lines: visible, extentX: extentX, extentY: extentY)
}

func needsTextTooltip(_ node: Idea) -> Bool {
    !node.text.isEmpty && (node.file?.type == .image || node.hideText == true || ideaDrawing(node).overflow)
}

private func nodeSVG(_ drawing: IdeaDrawing, siteHost: String?) -> String {
    let node = drawing.node
    if node.kind == .connectionPoint {
        let label = node.title.isEmpty ? "" : "<text x=\"\(number(node.position.x + node.width/2 + 4))\" y=\"\(number(node.position.y + 4))\" font-size=\"14\" fill=\"\(node.textColor)\">\(escaped(node.title))</text>"
        return """
            <circle cx="\(number(node.position.x))" cy="\(number(node.position.y))" r="\(number(node.width/2))" fill="\(escaped(node.fill))" aria-label="\(escaped(node.title))"/>\(label)
            """
    }
    let width = node.width
    let height = node.height
    let x = width / 2
    let y = height / 2
    let strokeWidth = node.kind == .container && node.locked == true ? "3.2" : "1.6"
    let dash = node.link.flatMap(WorksheetLink.init) == nil ? "" : " stroke-dasharray=\"7 4\""
    let appearance = node.backgroundEnabled == false
        ? "fill=\"none\" stroke=\"none\" pointer-events=\"fill\""
        : "fill=\"\(escaped(node.fill))\" stroke=\"\(escaped(node.border))\" stroke-width=\"\(strokeWidth)\"\(dash)"
    let geometry: String
    switch node.shape {
    case .rectangle, .rounded:
        geometry = """
            <rect x="\(number(-x))" y="\(number(-y))" width="\(number(width))" height="\(number(height))" rx="\(node.shape == .rounded ? "12" : "0")" \(appearance)/>
            """
    case .ellipse:
        geometry = "<ellipse rx=\"\(number(x))\" ry=\"\(number(y))\" \(appearance)/>"
    case .diamond, .triangle, .pentagon, .hexagon, .parallelogram:
        let points = node.shape.vertices.map { "\(number($0.x * x)),\(number($0.y * y))" }.joined(separator: " ")
        geometry = "<polygon points=\"\(points)\" \(appearance)/>"
    }
    let labelWidth = drawing.labelWidth
    func rank(_ line: IdeaLabelLine) -> Double {
        switch line.style?.verticalAlignment {
        case .top: 0
        case .bottom: 1
        default: 0.5
        }
    }
    let extra = drawing.available - drawing.lines.filter { $0.outsideTop == nil }.reduce(0) { $0 + $1.step }
    var offset = -(drawing.available + drawing.iconSpace) / 2
    let spans = drawing.lines.sorted { rank($0) < rank($1) }.map { line in
        let top = line.outsideTop ?? (offset + extra * rank(line))
        let textX: Double
        let anchor: String
        if let center = line.outsideX {
            let side: Double = center < 0 ? -1 : center > 0 ? 1 : 0
            (textX, anchor) = (center - side * labelWidth/2, side < 0 ? "end" : side > 0 ? "start" : "middle")
        } else { switch line.justify ? .left : line.style?.alignment ?? node.alignment {
        case .left: (textX, anchor) = (-labelWidth / 2, "start")
        case .right: (textX, anchor) = (labelWidth / 2, "end")
        case .center: (textX, anchor) = (0, "middle")
        } }
        var style = line.runs.isEmpty ? " class=\"link-label\"" : ""
        if line.justify && line.wrapped {
            let spaces = line.text.filter { $0 == " " }.count
            let width = textWidth(line.text, size: line.size)
            if spaces > 0 && width < labelWidth {
                style += " word-spacing=\"\(number((labelWidth - width) / Double(spaces)))\""
            }
        }
        if line.style?.italic == true { style += " font-style=\"italic\"" }
        if line.style?.underline == true { style += " text-decoration=\"underline\"" }
        let baseline = top + line.gap + line.size * (1.25 / 2 + 0.33)
        if line.outsideTop == nil { offset += line.step }
        let content = line.runs.isEmpty ? escaped(line.text) : line.runs.map { run in
            let format = run.format
            var attributes = ""
            if format.bold { attributes += " font-weight=\"700\"" }
            if format.italic { attributes += " font-style=\"italic\"" }
            if format.code { attributes += " font-family=\"monospace\" xml:space=\"preserve\"" }
            if format.link { attributes += " text-decoration=\"underline\"" }
            return attributes.isEmpty ? escaped(run.text) : "<tspan\(attributes)>\(escaped(run.text))</tspan>"
        }.joined()
        return """
            <tspan text-anchor="\(anchor)"\(style) x="\(number(textX))" y="\(number(baseline))" fill="\(escaped(line.color))" font-size="\(number(line.size))" font-weight="\(line.weight)">\(content)</tspan>
            """
    }.joined()
    let symbol = node.link.flatMap(WorksheetLink.init).map { link in
        let inset = node.shape.labelRatios.link
        let linkWidth = max(12, node.width * inset - 22)
        let fit = textWidth(node.link ?? "", size: 11) > linkWidth ? " textLength=\"\(number(linkWidth))\" lengthAdjust=\"spacingAndGlyphs\"" : ""
        return """
            <text class="box-link"\(fit) x="\(number(x * inset - 19))" y="\(number(y * inset - 5))" text-anchor="end" font-size="11" fill="\(node.textColor)">\(escaped(node.link ?? ""))</text><svg x="\(number(x * inset - 15))" y="\(number(y * inset - 16))" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="\(node.textColor)" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="\(link.iconPath(siteHost: siteHost))"/></svg>
            """
    } ?? ""
    return """
        <g aria-label="\(escaped(node.title))" transform="translate(\(number(node.position.x)) \(number(node.position.y)))">
          \(geometry)
          <text font-family="system-ui, sans-serif" pointer-events="none">\(spans)</text>
          \(symbol)
        </g>
        """
}

func boardSVG(_ board: Worksheet, noteBase: String? = nil, siteHost: String? = nil, assetBase: String? = nil) -> String {
    let drawings = board.nodes.map(ideaDrawing)
    let renderedIdeas = drawings.map(\.node)
    let nodes = Dictionary(uniqueKeysWithValues: renderedIdeas.map { ($0.id, $0) })
    var halfWidth = 360.0
    var halfHeight = 240.0
    for drawing in drawings {
        let node = drawing.node
        halfWidth = max(halfWidth, abs(node.position.x) + max(node.width/2, drawing.extentX) + 40)
        if node.kind == .connectionPoint && !node.title.isEmpty {
            let labelEnd = node.position.x + node.width / 2 + 4 + textWidth(node.title, size: 14)
            halfWidth = max(halfWidth, labelEnd + 40)
        }
        halfHeight = max(halfHeight, abs(node.position.y) + max(node.height/2, drawing.extentY) + 40)
    }
    var definitions: [String] = []
    let edges = board.edges.compactMap { edge -> String? in
        let sourceNode = edge.source.flatMap { nodes[$0] }
        let targetNode = edge.target.node.flatMap { nodes[$0] }
        guard let source = sourceNode?.position ?? edge.sourcePoint,
              let target = targetNode?.position ?? edge.target.point else { return nil }
        let (command, points) = edgeRoute(edge.type, from: source, to: target)
        let beginning = sourceNode.map { borderPoint($0, toward: points.first ?? target) } ?? source
        let ending = targetNode.map { borderPoint($0, toward: points.last ?? source) } ?? target
        let segments = (points + [ending]).map { "\(number($0.x)) \(number($0.y))" }.joined(separator: " ")
        let drawing = "M \(number(beginning.x)) \(number(beginning.y)) \(command) \(segments)"
        for point in [beginning, ending] + points {
            halfWidth = max(halfWidth, abs(point.x) + 40)
            halfHeight = max(halfHeight, abs(point.y) + 40)
        }
        let color = escaped(edge.strokeColor)
        let marker = "arrow-" + edge.id
        var markers = ""
        if edge.hasStartArrow || edge.hasEndArrow {
            definitions.append("""
                <marker id="\(marker)" markerWidth="6.75" markerHeight="6.75" viewBox="0 0 10 10" refX="9" refY="5" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="\(color)"/></marker>
                """)
        }
        if edge.hasStartArrow && sourceNode != nil { markers += " marker-start=\"url(#\(marker))\"" }
        if edge.hasEndArrow && targetNode != nil { markers += " marker-end=\"url(#\(marker))\"" }
        switch edge.appearance {
        case .thick:
            markers += " stroke-linecap=\"round\""
        case .dashed:
            markers += " stroke-dasharray=\"\(number(edge.strokeWidth * 3.5)) \(number(edge.strokeWidth * 2.5))\""
        case .dotted:
            markers += " stroke-linecap=\"round\" stroke-dasharray=\"0 \(number(edge.strokeWidth * 8))\""
        default: break
        }
        let wire: String
        if noteBase != nil, let data = try? JSONEncoder().encode(edge) {
            wire = " data-wire=\"\(escaped(String(decoding: data, as: UTF8.self)))\""
        } else { wire = "" }
        var heads = ""
        func arrow(_ end: String, tip: Point, toward: Point) -> String {
            let angle = atan2(tip.y-toward.y, tip.x-toward.x)*180/Double.pi
            return """
                <path data-arrow-end="\(end)" d="M0 0L-1 -.5V.5Z" transform="translate(\(number(tip.x)) \(number(tip.y))) rotate(\(number(angle))) scale(\(number(edge.strokeWidth*6.75)))" fill="\(color)" stroke="none" pointer-events="none"/>
                """
        }
        if edge.hasStartArrow && sourceNode == nil { heads += arrow("source", tip: beginning, toward: points.first ?? ending) }
        if edge.hasEndArrow && targetNode == nil { heads += arrow("target", tip: ending, toward: points.last ?? beginning) }
        let lineWidth = edge.strokeWidth * (edge.appearance == .dotted ? 2 : 1)
        let stroke = "<path\(wire) d=\"\(drawing)\" stroke=\"\(color)\" stroke-width=\"\(number(lineWidth))\"\(markers)/>"
        let path = heads.isEmpty ? stroke : "<g data-free-arrows=\"\">\(heads)\(stroke)</g>"
        guard let label = edge.label, !label.trimmingCharacters(in: .whitespaces).isEmpty else { return path }
        let vertices = [beginning] + points + [ending]
        let samples: [Point] = command == "L" ? vertices : (0...32).map { i in
            let t = Double(i) / 32, u = 1 - t
            let weights = command == "Q" ? [u*u, 2*u*t, t*t] : [u*u*u, 3*u*u*t, 3*u*t*t, t*t*t]
            return zip(vertices, weights).reduce(Point(x: 0, y: 0)) { sum, pair in
                Point(x: sum.x + pair.0.x * pair.1, y: sum.y + pair.0.y * pair.1)
            }
        }
        let lengths = zip(samples, samples.dropFirst()).map { hypot($1.x-$0.x, $1.y-$0.y) }
        var remaining = lengths.reduce(0,+)/2
        var i = 0
        while i < lengths.count-1 && remaining > lengths[i] {
            remaining -= lengths[i]
            i += 1
        }
        let a = samples[i], b = samples[i+1], fraction = lengths[i] == 0 ? 0 : remaining/lengths[i]
        let center = Point(x: a.x+(b.x-a.x)*fraction, y: a.y+(b.y-a.y)*fraction)
        var angle = atan2(b.y-a.y,b.x-a.x) * 180 / Double.pi
        if angle > 90 { angle -= 180 }
        if angle < -90 { angle += 180 }
        let labelRadius = textWidth(label, size: 14) / 2
        let radians = angle * Double.pi / 180
        halfWidth = max(halfWidth, abs(center.x) + abs(cos(radians)) * labelRadius + 28)
        halfHeight = max(halfHeight, abs(center.y) + abs(sin(radians)) * labelRadius + 28)
        return path + """
            <text transform="translate(\(number(center.x)) \(number(center.y))) rotate(\(number(angle)))" y="\(number(-edge.strokeWidth / 2 - 6))" font-family="system-ui, sans-serif" font-size="14" text-anchor="middle" stroke="none" fill="\(color)">\(escaped(label))</text>
            """
    }.joined(separator: "\n")
    func render(_ drawing: IdeaDrawing) -> String {
        let node = drawing.node
        let graphic: String
        if let file = node.file {
            let url = escaped("/api/attachment" + (assetBase ?? noteBase ?? "") + "?inline=1&name=" + encodeQuery(file.asset ?? ""))
            let title = file.hideTitle == true || node.title.isEmpty ? "" : "<strong>\(escaped(node.title))</strong>"
            let justification = node.textStyle?.justified == true ? " justified-text" : ""
            let commentClass = justification.isEmpty ? "" : " class=\"justified-text\""
            let content: String
            switch file.type {
            case .image:
                let filename = file.showFilename == true ? "<span>\(escaped(file.imageStem))</span>" : ""
                let alt = escaped(node.title.isEmpty ? file.imageStem : node.title)
                content = "<img alt=\"\(alt)\" src=\"\(url)\"/>" + filename
            case .mp3:
                content = """
                    <div class="canvas-audio" data-audio-player="">
                      <audio hidden="hidden" preload="metadata" src="\(url)"></audio>
                      <button type="button" class="button" data-audio-toggle="" aria-label="Lejátszás" title="Lejátszás">\(uiIcon("play"))</button>
                      <input type="range" min="0" max="0" step="any" disabled="disabled" data-audio-seek="" aria-label="Lejátszási pozíció"/>
                      <small data-audio-status="" role="status"></small>
                    </div><small\(commentClass)>\(escaped(node.text))</small>
                    """
            case .md: content = "<div class=\"formatted-text\(justification)\">\(markdownHTML(node.text))</div>"
            case .txt, .json: content = "<pre\(commentClass)>\(escaped(node.text))</pre>"
            case .attachment:
                let download = escaped("/api/attachment" + (assetBase ?? noteBase ?? "") + "?name=" + encodeQuery(file.asset ?? ""))
                content = "<a class=\"button small\" href=\"\(download)\">Letöltés</a><small\(commentClass)>\(escaped(node.text))</small>"
            }
            let image = file.type == .image
            let above: Double = image && !title.isEmpty ? 22 : 0
            let below: Double = image && file.showFilename == true ? 22 : 0
            let background = image ? (file.alphaEnabled == false ? "#ffffff" : file.alphaBackground) : nil
            let radius = file.asset?.hasSuffix(".svg") == true ? 0 : 6
            let imageBackground = background.map {
                "<rect x=\"\(number(node.position.x-node.width/2))\" y=\"\(number(node.position.y-node.height/2))\" width=\"\(number(node.width))\" height=\"\(number(node.height))\" rx=\"\(radius)\" fill=\"\(escaped($0))\"/>"
            } ?? ""
            graphic = """
                \(imageBackground)<foreignObject x="\(number(node.position.x-node.width/2))" y="\(number(node.position.y-node.height/2-above))" width="\(number(node.width))" height="\(number(node.height+above+below))"><div xmlns="http://www.w3.org/1999/xhtml" class="\(image ? "canvas-image" : "canvas-file")">\(title)\(content)</div></foreignObject>
                """
        } else { graphic = nodeSVG(drawing, siteHost: siteHost) }
        guard let noteBase else { return graphic }
        let parts = noteBase.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        let path = try? WorksheetPath(parts)
        let destination = node.link.flatMap(WorksheetLink.init).flatMap { link in path.flatMap { link.destination(from: $0) } }
        let tag = destination == nil ? "g" : "a"
        var linked = destination.map { " data-link=\"true\" href=\"\(escaped($0))\"" } ?? ""
        if let raw = node.link, let link = WorksheetLink(raw), link.isExternal(siteHost: siteHost) {
            linked += " target=\"_blank\" rel=\"noopener noreferrer\""
        }
        let geometry = "data-x=\"\(node.position.x)\" data-y=\"\(node.position.y)\" data-width=\"\(node.width)\" data-height=\"\(node.height)\" data-shape=\"\(node.kind == .connectionPoint ? "ellipse" : node.shape.rawValue)\" data-parent=\"\(node.parent ?? "")\""
        return "<\(tag) id=\"object-\(node.id)\" data-node=\"\(node.id)\" \(geometry)\(linked) aria-label=\"\(escaped(node.title))\">\(graphic)</\(tag)>"
    }
    let ordered = drawings.sorted { a, b in
        if (a.node.kind == .container) != (b.node.kind == .container) { return a.node.kind == .container }
        return a.node.width * a.node.height > b.node.width * b.node.height
    }
    let renderedNodes = ordered.map(render).joined(separator: "\n")
    let width = number(halfWidth * 2)
    let height = number(halfHeight * 2)
    return """
        <svg xmlns="http://www.w3.org/2000/svg" class="passive-canvas" role="\(noteBase == nil ? "img" : "group")" aria-label="\(escaped(board.title))" width="\(width)" height="\(height)" viewBox="\(number(-halfWidth)) \(number(-halfHeight)) \(width) \(height)">
          \(noteBase == nil ? "<title>\(escaped(board.title))</title>" : "")
          <defs>\(definitions.joined())</defs>
          <rect x="\(number(-halfWidth))" y="\(number(-halfHeight))" width="\(width)" height="\(height)" fill="\(escaped(board.backgroundColor))"/>
          \(renderedNodes)
          <g fill="none" stroke-linecap="round">
            \(edges)
          </g>
        </svg>
        """
}

func worksheetMarkdown(_ worksheet: Worksheet) -> String {
    func inline(_ text: String) -> String {
        let syntax = "\\`*_{}[]<>()#+-.!|"
        return text.map { syntax.contains($0) ? "\\" + String($0) : String($0) }.joined()
    }
    var sections = ["# \(inline(worksheet.title))\n"]
    if let text = worksheet.text, !text.isEmpty { sections.append(text) }
    for node in worksheet.nodes {
        sections.append("## \(inline(node.title))\n")
        if node.file?.type != .image && !node.text.isEmpty { sections.append(node.text) }
    }
    if !worksheet.edges.isEmpty {
        sections.append("## Kapcsolatok\n")
        let names = Dictionary(uniqueKeysWithValues: worksheet.nodes.map { ($0.id, inline($0.title)) })
        func endpoint(_ endpoint: ConnectionTarget) -> String {
            if let id = endpoint.node, let name = names[id] { return name }
            return endpoint.point.map { "(\(number($0.x)), \(number($0.y)))" } ?? ""
        }
        for edge in worksheet.edges {
            let description = edge.label.flatMap { $0.isEmpty ? nil : inline($0) } ?? edge.type.label
            let arrow = edge.hasStartArrow ? (edge.hasEndArrow ? "↔" : "←") : (edge.hasEndArrow ? "→" : "—")
            sections.append("- \(endpoint(edge.origin)) \(arrow) \(endpoint(edge.target)) · \(description)")
        }
    }
    return sections.joined(separator: "\n\n") + "\n"
}
