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
        <script type="module" src="/editor.js?v=2"></script>
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
        let logout = (user.role != .admin || showAdminLogout) ? "<button class=\"button small\" type=\"submit\">\(uiIcon("logout"))Kijelentkezés</button>" : ""
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
        let offset = 0.06
        return ("L", [
            Point(x: source.x + dx * 0.53 - dy * offset, y: source.y + dy * 0.53 + dx * offset),
            Point(x: source.x + dx * 0.47 + dy * offset, y: source.y + dy * 0.47 - dx * offset),
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
    var style: TextStyle?

    var step: Double { size * 1.25 + gap }
}

private struct IdeaDrawing {
    var node: Idea
    let labelWidth: Double
    var iconSpace: Double = 0
    var available: Double = 0
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

private func ideaDrawing(_ idea: Idea) -> IdeaDrawing {
    var node = idea
    if node.kind == .connectionPoint {
        node.shape = .ellipse
        return IdeaDrawing(node: node, labelWidth: 0, lines: [])
    }
    let widthRatio = node.shape == .diamond ? 0.50 : node.shape == .ellipse ? 0.72 : 0.94
    let heightRatio = node.shape == .diamond ? 0.47 : node.shape == .ellipse ? 0.72 : 0.94
    let bodySize = node.textStyle?.size ?? 13
    let text = node.hideText != true ? canvasMarkdown(node.text) :
        (node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [MarkdownBlock(kind: .body, runs: [MarkdownRun(text: "•••")])])
    let labelWidth = max(12, node.width * widthRatio - 16)
    var lines: [IdeaLabelLine] = []
    func add(_ value: String, size: Double, weight: Int, color: String, style: TextStyle?) {
        let text = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return }
        let columns = max(2, Int(labelWidth / (size * 0.65)))
        let rendered = textWidth(text, size: size) <= labelWidth ? [text] : wrap(text, columns: columns)
        lines.append(contentsOf: rendered.map { IdeaLabelLine(text: $0, size: size, weight: weight, color: color, style: style) })
    }
    add(node.title, size: node.fontSize, weight: node.bold ? 650 : 400, color: node.textColor,
        style: TextStyle(italic: node.italic, underline: node.underline, verticalAlignment: node.verticalAlignment))
    for (index, block) in text.enumerated() {
        let size = block.kind == .heading ? (bodySize * 1.15).rounded() : bodySize
        let columns = max(node.hideText == true ? 3 : 2, Int(labelWidth / (size * 0.65)))
        var runs = block.runs
        if block.kind == .quote { runs.insert(MarkdownRun(text: "› "), at: 0) }
        for (row, pieces) in wrapMarkdown(runs, columns: columns, preformatted: block.kind == .code).enumerated() {
            let gap: Double = row == 0 ? (index == 0 ? 8 : 3) : 0
            lines.append(IdeaLabelLine(text: pieces.map(\.text).joined(), size: size,
                                       weight: block.kind == .heading || node.textStyle?.bold == true ? 700 : 400,
                                       color: node.textStyle?.color ?? node.textColor, runs: pieces, gap: gap, style: node.textStyle))
        }
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
    let iconSpace: Double = (node.link ?? "").isEmpty ? 0 : 18
    var visible: [IdeaLabelLine] = []
    let available = max(node.fontSize * 1.25, node.height * heightRatio - 12 - iconSpace)
    var remaining = available
    for line in lines {
        guard remaining >= line.step else { break }
        visible.append(line)
        remaining -= line.step
    }
    if !visible.isEmpty && visible.count < lines.count {
        let last = visible.count - 1
        visible[last].text += "…"
        if !visible[last].runs.isEmpty { visible[last].runs.append(MarkdownRun(text: "…")) }
    }
    if node.hideText == true,
       let marker = lines.last, !marker.runs.isEmpty, !visible.contains(where: { !$0.runs.isEmpty }) {
        while !visible.isEmpty && remaining < marker.step { remaining += visible.removeLast().step }
        visible.append(marker)
    }
    var extentX = node.width / 2, extentY = max(node.height, available + iconSpace) / 2
    for key in groups.keys.sorted() {
        let rows = groups[key] ?? []
        let total = rows.reduce(0) { $0 + $1.step }
        let side: Double = key.hasPrefix("left/") ? -1 : key.hasPrefix("right/") ? 1 : 0
        let center = side * (node.width/2 + 8 + labelWidth/2)
        var top = key.hasSuffix("/top") ? -node.height/2-8-total : key.hasSuffix("/bottom") ? node.height/2+8 : -total/2
        extentX = max(extentX, abs(center) + labelWidth/2 + 4)
        extentY = max(extentY, abs(top), abs(top+total))
        for var line in rows {
            line.outsideX = center
            line.outsideTop = top
            visible.append(line)
            top += line.step
        }
    }
    return IdeaDrawing(node: node, labelWidth: labelWidth, iconSpace: iconSpace, available: available,
                       lines: visible, extentX: extentX, extentY: extentY)
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
    let appearance = "fill=\"\(escaped(node.fill))\" stroke=\"\(escaped(node.border))\" stroke-width=\"\(strokeWidth)\"\(dash)"
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
    func rank(_ line: IdeaLabelLine) -> Double {
        switch line.style?.verticalAlignment {
        case .top: 0
        case .bottom: 1
        default: 0.5
        }
    }
    let extra = drawing.available - drawing.lines.filter { $0.outsideTop == nil }.reduce(0) { $0 + $1.step }
    var offset = -(drawing.available + drawing.iconSpace) / 2
    var bodyEnd: Double?
    var bodyX: Double = 0
    var bodyTop: Double?
    let spans = drawing.lines.sorted { rank($0) < rank($1) }.map { line in
        let top = line.outsideTop ?? (offset + extra * rank(line))
        if !line.runs.isEmpty { bodyEnd = max(bodyEnd ?? -Double.infinity, top + line.step); bodyX = line.outsideX ?? 0 }
        let textX: Double
        let anchor: String
        if let center = line.outsideX {
            let side: Double = center < 0 ? -1 : center > 0 ? 1 : 0
            (textX, anchor) = (center - side * labelWidth/2, side < 0 ? "end" : side > 0 ? "start" : "middle")
        } else { switch line.style?.alignment ?? node.alignment {
        case .left: (textX, anchor) = (-labelWidth / 2, "start")
        case .right: (textX, anchor) = (labelWidth / 2, "end")
        case .center: (textX, anchor) = (0, "middle")
        } }
        var style = line.runs.isEmpty ? " class=\"link-label\"" : ""
        if line.style?.italic == true { style += " font-style=\"italic\"" }
        if line.style?.underline == true { style += " text-decoration=\"underline\"" }
        if !line.runs.isEmpty && bodyTop == nil { bodyTop = top + line.gap - 3 }
        let baseline = top + line.gap + line.size * (1.25 / 2 + 0.33)
        if line.outsideTop == nil { offset += line.step }
        let fit = textWidth(line.text, size: line.size) > labelWidth
            ? " textLength=\"\(number(labelWidth))\" lengthAdjust=\"spacingAndGlyphs\"" : ""
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
            <tspan text-anchor="\(anchor)"\(style) x="\(number(textX))" y="\(number(baseline))" fill="\(escaped(line.color))" font-size="\(number(line.size))" font-weight="\(line.weight)"\(fit)>\(content)</tspan>
            """
    }.joined()
    var frame = ""
    let fill = node.textFill ?? node.fill
    let border = node.textBorder ?? node.border
    let distinctBorder = border.lowercased() != node.border.lowercased()
    if let bodyTop, let bodyEnd, distinctBorder || fill.lowercased() != node.fill.lowercased() {
        frame = """
            <rect x="\(number(bodyX-labelWidth/2-3))" y="\(number(bodyTop))" width="\(number(labelWidth+6))" height="\(number(bodyEnd+3-bodyTop))" fill="\(fill)" stroke="\(distinctBorder ? border : "none")"/>
            """
    }
    let symbol = node.link.flatMap(WorksheetLink.init).map { link in
        let inset = node.shape == .diamond ? 0.45 : node.shape == .ellipse ? 0.7 : 0.94
        return """
            <svg x="\(number(x * inset - 15))" y="\(number(y * inset - 16))" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="\(node.textColor)" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="\(link.iconPath(siteHost: siteHost))"/></svg>
            """
    } ?? ""
    return """
        <g aria-label="\(escaped(node.title))" transform="translate(\(number(node.position.x)) \(number(node.position.y)))">
          \(geometry)
          \(frame)
          <text font-family="system-ui, sans-serif" pointer-events="none">\(spans)</text>
          \(symbol)
        </g>
        """
}

func boardSVG(_ board: Worksheet, noteBase: String? = nil, siteHost: String? = nil) -> String {
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
        let center: Point
        switch command {
        case "Q":
            center = Point(x: (beginning.x + 2 * points[0].x + ending.x) / 4,
                           y: (beginning.y + 2 * points[0].y + ending.y) / 4)
        case "C":
            center = Point(x: (beginning.x + 3 * points[0].x + 3 * points[1].x + ending.x) / 8,
                           y: (beginning.y + 3 * points[0].y + 3 * points[1].y + ending.y) / 8)
        default:
            let first = points.first ?? beginning, last = points.last ?? ending
            center = Point(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        }
        var angle = atan2(ending.y - beginning.y, ending.x - beginning.x) * 180 / Double.pi
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
        let graphic = nodeSVG(drawing, siteHost: siteHost)
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
        return "<\(tag) data-node=\"\(node.id)\" \(geometry)\(linked) aria-label=\"\(escaped(node.title))\">\(graphic)</\(tag)>"
    }
    let ordered = drawings.sorted { a, b in
        if (a.node.kind == .container) != (b.node.kind == .container) { return a.node.kind == .container }
        return a.node.width * a.node.height > b.node.width * b.node.height
    }
    let split = ordered.firstIndex { $0.node.kind != .container } ?? ordered.endIndex
    let containers = ordered[..<split].map(render).joined(separator: "\n")
    let renderedNodes = ordered[split...].map(render).joined(separator: "\n")
    let width = number(halfWidth * 2)
    let height = number(halfHeight * 2)
    return """
        <svg xmlns="http://www.w3.org/2000/svg" class="passive-canvas" role="img" aria-label="\(escaped(board.title))" width="\(width)" height="\(height)" viewBox="\(number(-halfWidth)) \(number(-halfHeight)) \(width) \(height)">
          \(noteBase == nil ? "<title>\(escaped(board.title))</title>" : "")
          <defs>\(definitions.joined())</defs>
          <rect x="\(number(-halfWidth))" y="\(number(-halfHeight))" width="\(width)" height="\(height)" fill="\(escaped(board.backgroundColor))"/>
          \(containers)
          <g fill="none" stroke-linecap="round">
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
    if let text = worksheet.text, !text.isEmpty { sections.append(text) }
    for node in worksheet.nodes {
        sections.append("## \(inline(node.title))\n")
        if !node.text.isEmpty { sections.append(node.text) }
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
