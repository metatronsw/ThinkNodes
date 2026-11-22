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

func htmlPage(title: String, body: String, scripts: Bool = false, updates: PageUpdates.Subscription? = nil) -> Response {
    let assets = scripts ? """
        <script defer src="/vendor/vue.js"></script>
        <script defer src="/vendor/d3.js"></script>
        <script type="module" src="/editor.js?v=29"></script>
        """ : ""
    let live = updates.map { "<meta name=\"thinknodes-updates\" data-id=\"\($0.id)\" content=\"\($0.version)\">" } ?? ""
    return response("""
        <!doctype html>
        <html lang="hu">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escaped(title)) · ThinkNodes</title>
          \(live)
          <link rel="stylesheet" href="/app.css?v=13">
          <script defer src="/site-mode.js"></script>
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

let headerButtonClass = "button header-button"

func buttonLink(_ url: String, _ label: String, symbol: String, classes: String) -> String {
    "<a class=\"\(classes)\" href=\"\(escaped(url))\">\(uiIcon(symbol))\(escaped(label))</a>"
}

func siteHeader(path: String? = nil, project: String? = nil, user: User?, csrf: String?, actions: String = "", centerAction: String = "", canEdit: Bool = false, editing: Bool = false, showAdminLogout: Bool = false) -> String {
    let parts = path?.split(separator: "/").map(String.init) ?? []
    let base = editing ? "/edit/" : "/"
    let crumb = parts.indices.map { i in
        let last = i == parts.count - 1
        let prefix = last && editing ? "/" : last && canEdit ? "/edit/" : base
        let url = prefix + parts[...i].joined(separator: "/")
        let label = last ? (project ?? parts[i]) : (parts[i].removingPercentEncoding ?? parts[i])
        return "<span class=\"slash\" aria-hidden=\"true\">/</span><a \(last ? "aria-current='page'" : "") href=\"\(escaped(url))\">\(escaped(label))</a>"
    }.joined()
    let parent = editing && parts.count > 1
        ? "<a class=\"\(headerButtonClass)\" aria-label=\"Szülő munkalap\" title=\"Szülő munkalap\" href=\"/edit/\(parts.dropLast().joined(separator: "/"))\">\(uiIcon("parent-up"))</a>"
        : ""
    let session: String
    if let user, let csrf {
        let logout = (user.role != .admin || showAdminLogout) ? "<button class=\"\(headerButtonClass)\" type=\"submit\" aria-label=\"Kijelentkezés\" title=\"Kijelentkezés\">\(uiIcon("logout"))</button>" : ""
        session = """
            <form method="post" action="/logout" class="account">
              \(csrfInput(csrf))
              \(isTesterName(user.name) ? buttonLink("/login", "Bejelentkezés", symbol: "login", classes: headerButtonClass) : "")
              \(user.role == .admin && user.name.lowercased() == "admin" ? "" : "<span>\(escaped(user.name))</span>")\(logout)
            </form>
            """
    } else {
        session = buttonLink("/login" + (path.map { "?next=/\($0)" } ?? ""), "Bejelentkezés", symbol: "login", classes: headerButtonClass)
    }
    let tag = path == nil ? "header" : "div"
    let admin = user?.role == .admin ? buttonLink("/admin", "Admin", symbol: "settings", classes: headerButtonClass) : ""
    let appearanceActions = """
        <div class="header-appearance">
          <button type="button" class="\(headerButtonClass)" data-site-mode-picker data-mode="auto" aria-label="Megjelenés: automatikus">\(uiIcon("display-auto"))</button>
          \(admin)
        </div>
        """
    let navigationClass = path == nil ? "site-header" : "worksheet-nav"
    return """
        <\(tag) class="\(navigationClass)"><div class="header-left"><nav aria-label="Fő navigáció" class="breadcrumbs">
          <a class="\(headerButtonClass) brand" href="/"><span class="brand-icon" aria-hidden="true"><span></span><span></span><span></span></span>ThinkNodes</a>
          \(crumb)\(parent)
        </nav></div><div class="header-parent">\(centerAction)</div><div class="header-actions">\(actions)<div class="header-user">\(session)</div>\(editing ? "" : appearanceActions)</div>\(editing ? appearanceActions : "")</\(tag)>
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

private func vertices(_ shape: Shape, _ graphics: VisualTheme.Graphics?) -> [(x: Double, y: Double)] {
    if graphics?.box == shape, let contour = graphics?.contour { return contour.map { ($0.x, $0.y) } }
    return shape.vertices
}

private func chamferedBox(_ node: Idea, _ graphics: VisualTheme.Graphics?) -> [(x: Double, y: Double)]? {
    guard node.shape == .rounded, let cut = graphics?.boxChamfer, cut > 0 else { return nil }
    let x = node.width / 2, y = node.height / 2, c = min(x, y, cut)
    return [(-x+c,-y), (x-c,-y), (x,-y+c), (x,y-c), (x-c,y), (-x+c,y), (-x,y-c), (-x,-y+c)]
}

private func borderPoint(_ idea: Idea, toward point: Point, graphics: VisualTheme.Graphics?) -> Point {
    let dx = point.x - idea.position.x
    let dy = point.y - idea.position.y
    guard dx != 0 || dy != 0 else { return idea.position }
    let x = dx / (idea.width / 2)
    let y = dy / (idea.height / 2)
    let chamfer = chamferedBox(idea, graphics)
    let outline = chamfer?.map { (x: $0.x / (idea.width / 2), y: $0.y / (idea.height / 2)) }
        ?? vertices(idea.shape, graphics)
    let scale: Double
    if outline.isEmpty {
        scale = 1 / (idea.shape == .ellipse ? hypot(x, y) : max(abs(x), abs(y)))
    } else {
        // Normalize each edge's linear distance to one at its boundary.
        var distance = 0.0
        for (i, a) in outline.enumerated() {
            let b = outline[(i + 1) % outline.count]
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
        let offset = min(0.08, 24 / length)
        return ("L", (1...6).map { index in
            let along = Double(index) / 7, across = index.isMultiple(of: 2) ? -offset : offset
            return Point(x: source.x + dx * along + dy * across, y: source.y + dy * along - dx * across)
        })
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

private func roundedWireCorners(_ vertices: [Point], wide: Bool) -> [(entry: Point, corner: Point, exit: Point)] {
    vertices.indices.dropFirst().dropLast().map { i in
        let previous = vertices[i - 1], corner = vertices[i], next = vertices[i + 1]
        let before = hypot(previous.x - corner.x, previous.y - corner.y)
        let after = hypot(next.x - corner.x, next.y - corner.y)
        let trim = min(wide ? 24 : 5, min(before, after) * (wide ? 0.45 : 0.22))
        func toward(_ point: Point, distance: Double) -> Point {
            let fraction = distance > 0 ? trim / distance : 0
            return Point(x: corner.x + (point.x - corner.x) * fraction, y: corner.y + (point.y - corner.y) * fraction)
        }
        return (toward(previous, distance: before), corner, toward(next, distance: after))
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
        if ![.ellipse,.rectangle,.diamond].contains(node.shape) { node.shape = .ellipse }
        return IdeaDrawing(node: node, labelWidth: 0, lines: [])
    }
    let (widthRatio, heightRatio, _) = node.shape.labelRatios
    let fitText = node.fitText == true && node.file == nil
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
            let rendered = textWidth(text, size: size) <= labelWidth ? [text] : wrap(text, columns: columns)
            lines.append(contentsOf: rendered.map { IdeaLabelLine(text: $0, size: size, weight: weight, color: color, style: style) })
        }
        add(node.title, size: titleSize, weight: node.bold ? 650 : 400, color: node.textColor,
            style: TextStyle(italic: node.italic, underline: node.underline, verticalAlignment: node.verticalAlignment))
        for (index, block) in text.enumerated() {
            let size = block.kind == .heading ? (fitText ? bodySize * 1.15 : (bodySize * 1.15).rounded()) : bodySize
            let columns = max(node.hideText == true ? 3 : 2, Int(labelWidth / (size * 0.65)))
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
    let available = max(0, labelHeight)
    var visible: [IdeaLabelLine] = []
    var remaining = available
    for line in lines {
        if remaining < line.step { break }
        visible.append(line)
        remaining -= line.step
    }
    let omitted = visible.count < lines.count
    if omitted && visible.isEmpty { visible.append(lines[0]); remaining -= lines[0].step }
    var overflow = omitted
    for index in visible.indices {
        let line = visible[index]
        if textWidth(line.text, size: line.size) > labelWidth || (omitted && index == visible.count - 1) {
            visible[index] = shortenLine(line, width: labelWidth)
            overflow = true
        }
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

/// Egységes vászon-osztálynév: `node` + fajta szerinti módosító. Az editor.js `nodeClasses` ugyanezt adja.
func nodeClasses(_ node: Idea) -> String {
    let kind: String? = switch (node.kind, node.file?.type) {
    case (.container?, _): "is-container"
    case (.connectionPoint?, _): "is-point"
    case (nil, .image?): "is-image"
    case (nil, .txt?), (nil, .md?), (nil, .json?): "is-note"
    case (nil, .mp3?): "is-audio"
    case (nil, .web?): "is-web"
    case (nil, .worksheet?): "is-worksheet"
    case (nil, .attachment?): "is-file"
    case (nil, nil): nil
    }
    return kind.map { "node " + $0 } ?? "node"
}

func needsTextTooltip(_ node: Idea, overflow: @autoclosure () -> Bool) -> Bool {
    !node.text.isEmpty && (node.file?.type == .image || node.hideText == true || overflow())
}

func needsTextTooltip(_ node: Idea) -> Bool {
    needsTextTooltip(node, overflow: ideaDrawing(node).overflow)
}

private func animatedBox(_ contents: String, mode: BoxAnimation?, speed: Double) -> String {
    let duration: String
    let times: String
    let tracks: [(type: String, values: String)]
    switch mode ?? .none {
    case .none: return contents
    case .pulse:
        (duration, times, tracks) = ("2.8s", "0;.5;1", [("scale", "1;1.09;1")])
    case .blink:
        (duration, times, tracks) = ("2.4s", "0;.5;1", [("opacity", "1;.28;1")])
    case .rock:
        (duration, times, tracks) = ("4.8s", "0;.08;.19;.3;.4;.49;1", [("rotate", "0;8;-6;3;-1;0;0")])
    case .hop:
        (duration, times, tracks) = ("5.8s", "0;.06;.15;.24;.32;.4;1", [
            ("translate", "0 0;0 1;0 -17;0 0;0 -4;0 0;0 0"),
            ("scale", "1 1;1.03 .95;1.035 1.06;1.045 .96;.99 1.02;1 1;1 1"),
        ])
    }
    let splines = Array(repeating: ".33 0 .67 1", count: times.split(separator: ";").count - 1).joined(separator: ";")
    let seconds = Double(duration.dropLast()) ?? 1
    let timing = "dur=\"\(speed == 1 ? duration : number(seconds / speed) + "s")\" repeatCount=\"indefinite\" calcMode=\"spline\" keyTimes=\"\(times)\" keySplines=\"\(splines)\""
    let animations = tracks.map { type, values in
        if type == "opacity" { return "<animate attributeName=\"opacity\" values=\"\(values)\" \(timing)/>" }
        return "<animateTransform attributeName=\"transform\" type=\"\(type)\" additive=\"sum\" values=\"\(values)\" \(timing)/>"
    }.joined()
    return "<g class=\"node-motion\" data-box-animation=\"\(mode?.rawValue ?? "")\">\(animations)\(contents)</g>"
}

private func boxGeometry(_ node: Idea, graphics: VisualTheme.Graphics?) -> String {
    let x = node.width / 2, y = node.height / 2
    if let chamfer = chamferedBox(node, graphics) {
        return "polygon points=\"\(chamfer.map { "\(number($0.x)),\(number($0.y))" }.joined(separator: " "))\""
    }
    switch node.shape {
    case .rectangle, .rounded:
        return "rect x=\"\(number(-x))\" y=\"\(number(-y))\" width=\"\(number(node.width))\" height=\"\(number(node.height))\" rx=\"\(node.shape == .rounded ? "12" : "0")\""
    case .ellipse:
        return "ellipse rx=\"\(number(x))\" ry=\"\(number(y))\""
    case .diamond, .triangle, .pentagon, .hexagon, .parallelogram:
        let points = vertices(node.shape, graphics).map { "\(number($0.x * x)),\(number($0.y * y))" }.joined(separator: " ")
        return "polygon points=\"\(points)\""
    }
}

private func boxOutline(_ node: Idea, graphics: VisualTheme.Graphics?) -> String {
    let x = node.width / 2, y = node.height / 2
    if let chamfer = chamferedBox(node, graphics) {
        return "M" + chamfer.map { "\(number($0.x)) \(number($0.y))" }.joined(separator: " L") + "Z"
    }
    switch node.shape {
    case .rectangle, .rounded:
        let r: Double = node.shape == .rounded ? 12 : 0
        return "M\(number(-x+r)) \(number(-y))H\(number(x-r))Q\(number(x)) \(number(-y)) \(number(x)) \(number(-y+r))"
            + "V\(number(y-r))Q\(number(x)) \(number(y)) \(number(x-r)) \(number(y))"
            + "H\(number(-x+r))Q\(number(-x)) \(number(y)) \(number(-x)) \(number(y-r))"
            + "V\(number(-y+r))Q\(number(-x)) \(number(-y)) \(number(-x+r)) \(number(-y))Z"
    case .ellipse:
        let arc = "A\(number(x)) \(number(y)) 0 1 0 "
        return "M\(number(-x)) 0" + arc + "\(number(x)) 0" + arc + "\(number(-x)) 0Z"
    case .diamond, .triangle, .pentagon, .hexagon, .parallelogram:
        let points = vertices(node.shape, graphics).map { "\(number($0.x*x)) \(number($0.y*y))" }
        return "M" + points.joined(separator: " L") + "Z"
    }
}

private func elevationShadow(_ node: Idea, geometry: String, graphics: VisualTheme.Graphics?) -> String {
    guard node.elevated == true, node.resolvedBackgroundMode != .free else { return "" }
    let clip = "elevated-clip-" + node.id
    let x = node.width / 2 + 24, y = node.height / 2 + 40
    let outside = "M\(number(-x)) \(number(-y))H\(number(x))V\(number(y))H\(number(-x))Z" + boxOutline(node, graphics: graphics)
    return """
        <g class="node-shadow" pointer-events="none" aria-hidden="true">
          <clipPath id="\(clip)"><path d="\(outside)" clip-rule="evenodd"/></clipPath>
          <g clip-path="url(#\(clip))">
            <\(geometry) transform="translate(12 28)" fill="#11172b" fill-opacity=".44"/>
          </g>
        </g>
        """
}

private func boxSurface(_ node: Idea, geometry: String, graphics: VisualTheme.Graphics?, interactive: Bool) -> String {
    let mode = node.resolvedBackgroundMode
    guard mode != .free else {
        return interactive ? "<\(geometry) fill=\"none\" pointer-events=\"fill\"/>" : ""
    }
    let blurred = mode == .blurred
    let empty = mode == .empty
    if node.file?.type == .image && mode == .solid && node.file?.alphaEnabled != false && node.file?.alphaBackground == nil { return "" }
    let image = node.file?.type == .image
    let locked = node.kind == .container && node.locked == true
    let glass = graphics?.glass == true && mode == .solid && !image
    let fill = image ? (node.file?.alphaEnabled == false ? "#ffffff" : node.file?.alphaBackground ?? node.fill) : node.fill
    let stroke = image && !empty ? "none" : glass ? "url(#glass-rim)" : escaped(node.border)
    let width = locked ? "6.4" : glass ? "3" : "1.6"
    let dash = node.file == nil && node.link.flatMap(WorksheetLink.init) != nil ? " stroke-dasharray=\"7 4\"" : ""
    let closed = locked ? " data-locked-outline=\"\"" : ""
    let effect = blurred ? " opacity=\".5\" filter=\"url(#box-background-blur)\"" : glass ? " fill-opacity=\".66\"" : ""
    let pointer = empty && interactive ? " pointer-events=\"fill\"" : ""
    let surface = "<\(geometry) class=\"node-surface\" fill=\"\(empty ? "none" : escaped(fill))\" stroke=\"\(stroke)\" stroke-width=\"\(width)\"\(closed)\(dash)\(effect)\(pointer)/>"
    return surface + (glass ? "<\(geometry) fill=\"url(#glass-sheen)\" pointer-events=\"none\" aria-hidden=\"true\"/>" : "")
}

private func nodeSVG(_ drawing: IdeaDrawing, siteHost: String?, graphics: VisualTheme.Graphics?, interactive: Bool) -> String {
    let node = drawing.node
    if node.kind == .connectionPoint {
        let label = node.title.isEmpty ? "" : "<text class=\"node-label\" x=\"\(number(node.position.x + node.width/2 + 4))\" y=\"\(number(node.position.y + 4))\" font-size=\"14\" fill=\"\(node.textColor)\">\(escaped(node.title))</text>"
        let r = node.width / 2
        let x = node.position.x, y = node.position.y
        if node.shape == .rectangle {
            return "<rect x='\(number(x-r))' y='\(number(y-r))' width='\(number(2*r))' height='\(number(2*r))' fill='\(escaped(node.fill))'/>" + label
        }
        if node.shape == .diamond {
            return "<path d='M \(number(x)) \(number(y-r)) l \(number(r)) \(number(r)) l \(number(-r)) \(number(r)) l \(number(-r)) \(number(-r)) Z' fill='\(escaped(node.fill))'/>" + label
        }
        return """
            <circle cx="\(number(node.position.x))" cy="\(number(node.position.y))" r="\(number(node.width/2))" fill="\(escaped(node.fill))" aria-label="\(escaped(node.title))"/>\(label)
            """
    }
    let width = node.width
    let height = node.height
    let x = width / 2
    let y = height / 2
    let geometry = boxGeometry(node, graphics: graphics)
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
        var style = line.runs.isEmpty ? " class=\"node-link-label\"" : ""
        if line.justify && line.wrapped {
            let spaces = line.text.filter { $0 == " " }.count
            let width = textWidth(line.text, size: line.size)
            if spaces > 0 && width < labelWidth {
                style += " word-spacing=\"\(number((labelWidth - width) / Double(spaces)))px\""
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
        let fit = textWidth(node.link ?? "", size: 16) > linkWidth ? " textLength=\"\(number(linkWidth))\" lengthAdjust=\"spacingAndGlyphs\"" : ""
        return """
            <text class="node-link"\(fit) x="\(number(x * inset - 19))" y="\(number(y * inset - 5))" text-anchor="end" font-size="16" fill="\(node.textColor)">\(escaped(node.link ?? ""))</text><svg x="\(number(x * inset - 15))" y="\(number(y * inset - 16))" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="\(node.textColor)" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="\(link.iconPath(siteHost: siteHost))"/></svg>
            """
    } ?? ""
    let contents = """
        \(elevationShadow(node, geometry: geometry, graphics: graphics))
        \(boxSurface(node, geometry: geometry, graphics: graphics, interactive: interactive))
        <text class="node-label" font-family="system-ui, sans-serif" pointer-events="none">\(spans)</text>
        \(symbol)
        """
    return """
        <g aria-label="\(escaped(node.title))" transform="translate(\(number(node.position.x)) \(number(node.position.y)))">
          \(animatedBox(contents, mode: node.animation, speed: graphics?.motionSpeed ?? 1))
        </g>
        """
}

private func wireArrowLength(_ width: Double) -> Double {
    min(width * 6.75, 13.5 + (width - 2) * 2)
}

private func taperedWireArc(_ edge: Connection, from: Point, control: Point, to: Point)
    -> (startLength: Double, endLength: Double, outline: String, expanded: String?) {
    let span = hypot(to.x - from.x, to.y - from.y)
    let arrowLength = min(wireArrowLength(edge.strokeWidth), span * 0.4)
    func trim(_ tip: Point, arrow: Bool) -> (base: Point, length: Double) {
        let dx = control.x - tip.x, dy = control.y - tip.y
        let distance = hypot(dx, dy)
        guard arrow && distance > 0 else { return (tip, 0) }
        let length = min(arrowLength, distance)
        return (Point(x: tip.x + dx * length / distance, y: tip.y + dy * length / distance), length)
    }
    let (start, startLength) = trim(from, arrow: edge.hasStartArrow)
    let (end, endLength) = trim(to, arrow: edge.hasEndArrow)
    func sample(_ t: Double) -> Point {
        let u = 1 - t
        return Point(x: u*u*start.x + 2*u*t*control.x + t*t*end.x,
                     y: u*u*start.y + 2*u*t*control.y + t*t*end.y)
    }
    let steps = 32
    var previous = start
    var lengths = [0.0]
    for i in 1...steps {
        let point = sample(Double(i) / Double(steps))
        lengths.append(lengths[i - 1] + hypot(point.x - previous.x, point.y - previous.y))
        previous = point
    }
    let halfWidth = min(edge.strokeWidth, span * 0.3) / 2
    var segment = 1
    let sections = (0...steps).map { i -> (point: Point, x: Double, y: Double) in
        let progress = Double(i) / Double(steps)
        let distance = progress * lengths[steps]
        while segment < steps && lengths[segment] < distance { segment += 1 }
        let length = lengths[segment] - lengths[segment - 1]
        let t = length > 0 ? (Double(segment - 1) + (distance - lengths[segment - 1]) / length) / Double(steps) : progress
        let dx = (1 - t) * (control.x - start.x) + t * (end.x - control.x)
        let dy = (1 - t) * (control.y - start.y) + t * (end.y - control.y)
        let tangent = hypot(dx, dy)
        let weight = edge.hasStartArrow && edge.hasEndArrow ? abs(2 * progress - 1)
            : edge.hasStartArrow ? 1 - progress : progress
        let offset = tangent > 0 ? halfWidth * (0.25 + 0.75 * weight) / tangent : 0
        return (sample(t), -dy * offset, dx * offset)
    }
    func outline(_ scale: Double) -> String {
        func side(_ direction: Double) -> [String] {
            sections.map { point, x, y in
                "\(number(point.x + x * scale * direction)) \(number(point.y + y * scale * direction))"
            }
        }
        return "M " + (side(1) + side(-1).reversed()).joined(separator: " L ") + " Z"
    }
    return (startLength, endLength, outline(1), edge.animated == true && edge.appearance == .thick ? outline(edge.pulseWidth / edge.lineWidth) : nil)
}

private func wireAnimation(_ edge: Connection, from: Point, to: Point) -> (stroke: String, shaft: String, gradient: String) {
    let color = escaped(edge.strokeColor)
    guard edge.animated == true else { return (color, "", "") }
    let width = edge.strokeWidth
    if edge.appearance == .thick {
        let values = [width, edge.pulseWidth, width].map(number).joined(separator: ";")
        return (color, "<animate attributeName=\"stroke-width\" values=\"\(values)\" dur=\"3s\" repeatCount=\"indefinite\"/>", "")
    }
    let reverse = edge.hasStartArrow && !edge.hasEndArrow
    let roundTrip = edge.hasStartArrow && edge.hasEndArrow
    if edge.appearance == .dashed || edge.appearance == .dotted {
        let shift = width * (edge.appearance == .dotted ? 8 : 6) * (reverse ? 1 : -1)
        let values = "0;" + number(shift) + (roundTrip ? ";0" : "")
        return (color, "<animate attributeName=\"stroke-dashoffset\" values=\"\(values)\" dur=\"\(roundTrip ? "3.2s" : "1.6s")\" repeatCount=\"indefinite\"/>", "")
    }
    let dx = to.x - from.x, dy = to.y - from.y
    guard dx != 0 || dy != 0 else { return (color, "", "") }
    let id = "wire-gradient-" + edge.id
    let first: Double = reverse ? 1 : -1
    let directions = roundTrip ? [first, -first, first] : [first, -first]
    let values = directions.map { "\(number($0 * dx)) \(number($0 * dy))" }.joined(separator: ";")
    let gradient = """
        <linearGradient id="\(id)" color="\(color)" gradientUnits="userSpaceOnUse" x1="\(number(from.x))" y1="\(number(from.y))" x2="\(number(to.x))" y2="\(number(to.y))">
          <stop offset="0" stop-color="currentColor"/><stop offset=".25" stop-color="currentColor"/>
          <stop offset=".5" stop-color="currentColor" stop-opacity=".5"/>
          <stop offset=".75" stop-color="currentColor"/><stop offset="1" stop-color="currentColor"/>
          <animateTransform attributeName="gradientTransform" type="translate" values="\(values)" dur="\(roundTrip ? "12s" : "6s")" repeatCount="indefinite"/>
        </linearGradient>
        """
    return ("url(#" + id + ")", "", gradient)
}

func boardSVG(_ board: Worksheet, noteBase: String? = nil, siteHost: String? = nil, assetBase: String? = nil, mode: String? = nil) -> String {
    renderWorksheetCanvas(board.painted(mode: mode), noteBase: noteBase, siteHost: siteHost, assetBase: assetBase).svg
}

func renderWorksheetCanvas(_ board: Worksheet, noteBase: String?, siteHost: String?, assetBase: String? = nil) -> (svg: String, tooltipNodes: [Idea]) {
    let graphics = Themes.catalog.first { $0.id == board.appearance?.theme }?.graphics
    let drawings = board.nodes.map(ideaDrawing)
    let renderedIdeas = drawings.map(\.node)
    let nodes = Dictionary(uniqueKeysWithValues: renderedIdeas.map { ($0.id, $0) })
    var halfWidth = 360.0
    var halfHeight = 240.0
    for drawing in drawings {
        let node = drawing.node
        var extentX = max(node.width/2, drawing.extentX)
        var extentY = max(node.height/2, drawing.extentY)
        if node.file == nil && node.kind != .connectionPoint {
            switch node.animation ?? .none {
            case .pulse: (extentX, extentY) = (extentX * 1.09, extentY * 1.09)
            case .rock: (extentX, extentY) = (extentX + extentY * 0.14, extentY + extentX * 0.14)
            case .hop: (extentX, extentY) = (extentX * 1.045, extentY * 1.06 + 17)
            case .none, .blink: break
            }
        }
        let padding: Double = node.elevated == true ? 84 : 40
        halfWidth = max(halfWidth, abs(node.position.x) + extentX + padding)
        if node.kind == .connectionPoint && !node.title.isEmpty {
            let labelEnd = node.position.x + node.width / 2 + 4 + textWidth(node.title, size: 14)
            halfWidth = max(halfWidth, labelEnd + 40)
        }
        halfHeight = max(halfHeight, abs(node.position.y) + extentY + padding)
    }
    var elevated = Set(renderedIdeas.filter { $0.elevated == true }.map(\.id))
    if !elevated.isEmpty {
        let children = Dictionary(grouping: renderedIdeas, by: \.parent)
        var parents = Array(elevated)
        while let parent = parents.popLast() {
            for child in children[parent, default: []] where elevated.insert(child.id).inserted {
                parents.append(child.id)
            }
        }
    }
    let ordered = drawings.sorted { a, b in
        let raisedA = elevated.contains(a.node.id), raisedB = elevated.contains(b.node.id)
        if raisedA != raisedB { return raisedB }
        if (a.node.kind == .container) != (b.node.kind == .container) { return a.node.kind == .container }
        return a.node.width * a.node.height > b.node.width * b.node.height
    }
    let nodeLayers = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.node.id, $0.offset) })
    let freeWireLayer = ordered.firstIndex { elevated.contains($0.node.id) } ?? ordered.count
    func isInside(_ node: Idea?, _ outer: Idea?) -> Bool {
        guard let outer else { return false }
        var parent = node?.parent
        while let id = parent {
            if id == outer.id { return true }
            parent = nodes[id]?.parent
        }
        return false
    }
    var definitions: [String] = []
    let edges = board.edges.compactMap { edge -> (layer: Int, markup: String)? in
        let sourceNode = edge.source.flatMap { nodes[$0] }
        let targetNode = edge.target.node.flatMap { nodes[$0] }
        guard let source = sourceNode?.position ?? edge.sourcePoint,
              let target = targetNode?.position ?? edge.target.point else { return nil }
        let command: String
        var points: [Point]
        let rise = edge.type == .straight ? graphics?.lineArc ?? 0 : 0
        func arcControl(_ from: Point, _ to: Point) -> Point {
            Point(x: (from.x + to.x) / 2 + (to.y - from.y) * rise * 2,
                  y: (from.y + to.y) / 2 - (to.x - from.x) * rise * 2)
        }
        let custom = graphics?.line == edge.type ? graphics?.linePoints : nil
        if let bends = custom {
            let dx = target.x-source.x, dy = target.y-source.y
            command = "L"
            points = bends.map { Point(x: source.x+dx*$0.x-dy*$0.y, y: source.y+dy*$0.x+dx*$0.y) }
        } else if rise > 0, source != target {
            command = "Q"
            points = [arcControl(source, target)]
        } else { (command, points) = edgeRoute(edge.type, from: source, to: target) }
        let multiBend = edge.type == .lightning && custom == nil
        let targetInside = isInside(targetNode, sourceNode)
        let sourceInside = isInside(sourceNode, targetNode)
        let centeredDirection = Point(x: source.x + 1, y: source.y)
        let beginning: Point
        let ending: Point
        if targetInside, let sourceNode, let targetNode {
            beginning = borderPoint(sourceNode, toward: source == target ? centeredDirection : target, graphics: graphics)
            ending = borderPoint(targetNode, toward: beginning, graphics: graphics)
        } else if sourceInside, let sourceNode, let targetNode {
            ending = borderPoint(targetNode, toward: source == target ? centeredDirection : source, graphics: graphics)
            beginning = borderPoint(sourceNode, toward: ending, graphics: graphics)
        } else {
            beginning = sourceNode.map { borderPoint($0, toward: multiBend ? target : points.first ?? target, graphics: graphics) } ?? source
            ending = targetNode.map { borderPoint($0, toward: multiBend ? source : points.last ?? source, graphics: graphics) } ?? target
        }
        if multiBend { points = edgeRoute(edge.type, from: beginning, to: ending).points }
        if command == "Q", rise > 0 { points[0] = arcControl(beginning, ending) }
        let vertices = [beginning] + points + [ending]
        let corners = graphics?.roundedWires == true && command == "L" && (edge.type == .lightning || edge.type == .zigzag)
            ? roundedWireCorners(vertices, wide: edge.type == .lightning) : []
        func pair(_ point: Point) -> String { "\(number(point.x)) \(number(point.y))" }
        let segments = corners.isEmpty
            ? command + " " + (points + [ending]).map(pair).joined(separator: " ")
            : corners.map { "L \(pair($0.entry)) Q \(pair($0.corner)) \(pair($0.exit))" }.joined(separator: " ") + " L " + pair(ending)
        let drawing = "M \(pair(beginning)) \(segments)"
        let taper = custom == nil && (edge.type == .arc || rise > 0)
            && (edge.appearance == .plain || edge.appearance == .thick) && (edge.hasStartArrow || edge.hasEndArrow)
            ? taperedWireArc(edge, from: beginning, control: points.first ?? arcControl(beginning, ending), to: ending) : nil
        for point in vertices {
            halfWidth = max(halfWidth, abs(point.x) + 40)
            halfHeight = max(halfHeight, abs(point.y) + 40)
        }
        let color = escaped(edge.strokeColor)
        let motion = wireAnimation(edge, from: beginning, to: ending)
        if !motion.gradient.isEmpty { definitions.append(motion.gradient) }
        let label = edge.label.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let inlineLabel = edge.labelInLine == true && label != nil
        let gapID = "wire-gap-" + edge.id
        let marker = "arrow-" + edge.id
        let arrowLength = wireArrowLength(edge.strokeWidth)
        let usesMarkers = taper == nil && !inlineLabel
        var markers = ""
        if usesMarkers && ((edge.hasStartArrow && sourceNode != nil) || (edge.hasEndArrow && targetNode != nil)) {
            let pulse = edge.animated == true && edge.appearance == .thick
                ? "<animateTransform attributeName=\"transform\" type=\"scale\" additive=\"sum\" values=\"1;1.12;1\" dur=\"3s\" repeatCount=\"indefinite\"/>" : ""
            definitions.append("""
                <marker id="\(marker)" color="\(color)" markerUnits="userSpaceOnUse" markerWidth="\(number(arrowLength))" markerHeight="\(number(arrowLength))" viewBox="0 0 10 10" refX="9" refY="5" orient="auto-start-reverse" overflow="visible"><path d="M 1 0 L -9 -5 L -9 5 Z" transform="translate(9 5)" fill="currentColor">\(pulse)</path></marker>
                """)
        }
        if usesMarkers && edge.hasStartArrow && sourceNode != nil { markers += " marker-start=\"url(#\(marker))\"" }
        if usesMarkers && edge.hasEndArrow && targetNode != nil { markers += " marker-end=\"url(#\(marker))\"" }
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
        func arrow(_ end: String, tip: Point, toward: Point, length: Double) -> String {
            let angle = atan2(tip.y-toward.y, tip.x-toward.x)*180/Double.pi
            let animation = edge.animated == true && edge.appearance == .thick
                ? "><animateTransform attributeName=\"transform\" type=\"scale\" additive=\"sum\" values=\"1;1.12;1\" dur=\"3s\" repeatCount=\"indefinite\"/></path>"
                : "/>"
            return """
                <path class="wire-arrow" data-arrow-end="\(end)" d="M0 0L-1 -.5V.5Z" transform="translate(\(number(tip.x)) \(number(tip.y))) rotate(\(number(angle))) scale(\(number(length)))" fill="\(color)" stroke="none" pointer-events="none"\(animation)
                """
        }
        if edge.hasStartArrow && (sourceNode == nil || !usesMarkers) {
            heads += arrow("source", tip: beginning, toward: points.first ?? ending, length: taper?.startLength ?? arrowLength)
        }
        if edge.hasEndArrow && (targetNode == nil || !usesMarkers) {
            heads += arrow("target", tip: ending, toward: points.last ?? beginning, length: taper?.endLength ?? arrowLength)
        }
        let lineWidth = edge.lineWidth
        let shaft = motion.shaft.isEmpty ? "/>" : ">\(motion.shaft)</path>"
        func wirePath(gap: Bool = false) -> String {
            let clip = gap ? " clip-path=\"url(#\(gapID))\"" : ""
            if let taper {
                let animation = taper.expanded.map {
                    "><animate attributeName=\"d\" values=\"\(taper.outline);\($0);\(taper.outline)\" dur=\"3s\" repeatCount=\"indefinite\"/></path>"
                } ?? "/>"
                let fill = "<path class=\"wire-line\"\(wire) data-wire-taper=\"\" d=\"\(taper.outline)\" fill=\"\(motion.stroke)\" stroke=\"none\"\(clip)\(animation)"
                return "<g class=\"wire\" fill=\"none\">\(fill)\(heads)</g>"
            }
            let stroke = "<path class=\"wire-line\"\(wire) d=\"\(drawing)\" stroke=\"\(motion.stroke)\" stroke-width=\"\(number(lineWidth))\"\(markers)\(clip)\(shaft)"
            return "<g class=\"wire\" fill=\"none\" stroke-linecap=\"round\">\(heads)\(stroke)</g>"
        }
        let sourceLayer = edge.source.flatMap { nodeLayers[$0] }
        let targetLayer = edge.target.node.flatMap { nodeLayers[$0] }
        let sourceIndex = sourceLayer ?? ordered.count
        let targetIndex = targetLayer ?? ordered.count
        let layer = targetInside || sourceInside ? max(sourceIndex, targetIndex) : min(sourceIndex, targetIndex)
        let wireLayer = layer == ordered.count ? freeWireLayer : layer
        guard let label else { return (wireLayer, wirePath()) }
        let samples: [Point]
        if !corners.isEmpty {
            samples = [beginning] + corners.flatMap { bend in
                (0...8).map { i in
                    let t = Double(i) / 8, u = 1 - t
                    return Point(x: bend.entry.x*u*u + bend.corner.x*2*u*t + bend.exit.x*t*t,
                                 y: bend.entry.y*u*u + bend.corner.y*2*u*t + bend.exit.y*t*t)
                }
            } + [ending]
        } else if command == "L" {
            samples = vertices
        } else {
            samples = (0...32).map { i in
                let t = Double(i) / 32, u = 1 - t
                let weights = command == "Q" ? [u*u, 2*u*t, t*t] : [u*u*u, 3*u*u*t, 3*u*t*t, t*t*t]
                return zip(vertices, weights).reduce(Point(x: 0, y: 0)) { sum, pair in
                    Point(x: sum.x + pair.0.x * pair.1, y: sum.y + pair.0.y * pair.1)
                }
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
        let thick = edge.appearance == .thick
        let fontSize = thick ? 18 + 2 * lineWidth : 12 + lineWidth
        let fontWeight = thick ? 700 : 400
        let labelRadius = textWidth(label, size: fontSize) * (thick ? 1.08 : 1) / 2
        let radians = angle * Double.pi / 180
        let cosine = cos(radians), sine = sin(radians)
        let transform = "translate(\(pair(center))) rotate(\(number(angle)))"
        func alongLabel(_ point: Point) -> Double {
            abs((point.x - center.x) * cosine + (point.y - center.y) * sine)
        }
        let room = min(alongLabel(beginning), alongLabel(ending))
        let hasGap = inlineLabel && room >= 2
        var labelAttributes = ""
        var displayedRadius = labelRadius
        if hasGap {
            let padding = min(8, room / 5)
            displayedRadius = min(labelRadius, room - padding - min(20, room / 3))
            let gap = number(displayedRadius + padding), extent = number(
                (vertices.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0) + 40 + 2 * lineWidth
            )
            let clip = "M -\(extent) -\(extent) H -\(gap) V \(extent) H -\(extent) Z M \(gap) -\(extent) H \(extent) V \(extent) H \(gap) Z"
            definitions.append("<clipPath id=\"\(gapID)\"><path d=\"\(clip)\" transform=\"\(transform)\"/></clipPath>")
            labelAttributes = " textLength=\"\(number(displayedRadius * 2))\" lengthAdjust=\"spacingAndGlyphs\" dominant-baseline=\"central\""
        } else if inlineLabel && noteBase != nil {
            definitions.append("<clipPath id=\"\(gapID)\"><path/></clipPath>")
        }
        let clearance = samples.reduce(0.0) { offset, point in
            let x = point.x - center.x, y = point.y - center.y
            return abs(x * cosine + y * sine) <= labelRadius ? min(offset, y * cosine - x * sine) : offset
        }
        let labelY = hasGap ? 0 : clearance - lineWidth / 2 - 10 - (fontSize - 14) / 4
        let padding = max(28, fontSize + 12)
        halfWidth = max(halfWidth, abs(center.x - sine * labelY) + abs(cosine) * displayedRadius + padding)
        halfHeight = max(halfHeight, abs(center.y + cosine * labelY) + abs(sine) * displayedRadius + padding)
        return (wireLayer, wirePath(gap: hasGap) + """
            <text class="wire-label" transform="\(transform)" y="\(number(labelY))"\(labelAttributes) font-family="system-ui, sans-serif" font-size="\(number(fontSize))" font-weight="\(fontWeight)" text-anchor="middle" stroke="none" fill="\(color)">\(escaped(label))</text>
            """)
    }
    let base = assetBase ?? noteBase ?? ""
    let project = base.split(separator: "/").first.flatMap { $0.removingPercentEncoding }
    func render(_ drawing: IdeaDrawing) -> String {
        let node = drawing.node
        let webURL = node.file?.webPath.flatMap { reference in
            project.flatMap { name in (try? WebPresentationReference(reference))?.url(in: name) }
        }
        let graphic: String
        if let file = node.file {
            let url = escaped("/api/attachment" + (assetBase ?? noteBase ?? "") + "?inline=1&name=" + encodeQuery(file.asset ?? ""))
            let title = file.hideTitle == true || node.title.isEmpty ? "" : "<strong>\(escaped(node.title))</strong>"
            let justification = node.textStyle?.justified == true ? " justified-text" : ""
            let commentClass = justification.isEmpty ? "" : " class=\"justified-text\""
            let content: String
            switch file.type {
            case .image:
                let alt = escaped(node.title.isEmpty ? file.imageStem : node.title)
                content = "<img alt=\"\(alt)\" src=\"\(url)\"/>"
            case .mp3:
                content = """
                    <div class="node-audio" data-audio-player="">
                      <audio hidden="hidden" preload="metadata" src="\(url)"></audio>
                      <button type="button" class="button" data-audio-toggle="" aria-label="Lejátszás" title="Lejátszás">\(uiIcon("play"))</button>
                      <input type="range" min="0" max="0" step="any" disabled="disabled" data-audio-seek="" aria-label="Lejátszási pozíció"/>
                      <small data-audio-status="" role="status"></small>
                    </div><small\(commentClass)>\(escaped(node.text))</small>
                    """
            case .md: content = "<div class=\"formatted-text\(justification)\">\(markdownHTML(node.text))</div>"
            case .txt, .json: content = "<pre\(commentClass)>\(escaped(node.text))</pre>"
            case .web:
                let preview = webURL.map { "<img class=\"node-web-preview\" alt=\"\" src=\"\(escaped($0 + "_tn-preview"))\"/>" } ?? ""
                let path = escaped(file.webPath ?? "")
                content = "<div class=\"node-web\">\(preview)<span>\(uiIcon("website"))\(path)</span></div>"
            case .attachment, .worksheet: content = ""
            }
            let note = file.type == .md || file.type == .txt
            let filename = escaped(file.displayName(title: node.title))
            let download = escaped("/api/box-file" + (assetBase ?? noteBase ?? "") + "?id=" + encodeQuery(node.id))
            let filenameLabel = file.showFilename != false ? "<span>\(filename)</span>" : ""
            let packageIcon = uiIcon("package")
            let footer = file.type == .web ? "" : noteBase == nil
                ? (assetBase == nil ? filenameLabel : "<a href=\"\(download)\" aria-label=\"Letöltés · \(filename)\">\(packageIcon)\(filenameLabel)</a>")
                :
                "<button type=\"button\" class=\"node-download\" title=\"\(filename)\" aria-label=\"Letöltés · \(filename)\" data-download=\"\(download)\">\(packageIcon)\(filenameLabel)</button>"
            let fold = node.resolvedBackgroundMode == .solid ? " with-fold" : ""
            let body = note ? "<div class=\"node-note\(fold)\">\(content)</div>" : content
            let image = file.type == .image
            let above: Double = (image || note) && !title.isEmpty ? 22 : 0
            let below: Double = image || note ? 22 : 0
            let geometry = boxGeometry(node, graphics: graphics)
            let chrome = elevationShadow(node, geometry: geometry, graphics: graphics) +
                boxSurface(node, geometry: geometry, graphics: graphics, interactive: noteBase != nil)
            let translated = chrome.isEmpty ? "" : "<g transform=\"translate(\(number(node.position.x)) \(number(node.position.y)))\">\(chrome)</g>"
            graphic = """
                \(translated)<foreignObject x="\(number(node.position.x-node.width/2))" y="\(number(node.position.y-node.height/2-above))" width="\(number(node.width))" height="\(number(node.height+above+below))"><div xmlns="http://www.w3.org/1999/xhtml" data-file-ink="\(escaped(node.textColor))" style="color:\(escaped(node.textColor))" class="\(image || note ? "node-image" : "node-file")">\(title)\(body)\(footer)</div></foreignObject>
                """
        } else { graphic = nodeSVG(drawing, siteHost: siteHost, graphics: graphics, interactive: noteBase != nil) }
        guard let noteBase else { return "<g class=\"\(nodeClasses(node))\">\(graphic)</g>" }
        let parts = noteBase.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        let path = try? WorksheetPath(parts)
        let destination = webURL ?? node.link.flatMap(WorksheetLink.init).flatMap { link in path.flatMap { link.destination(from: $0) } }
        let tag = destination == nil ? "g" : "a"
        var linked = destination.map { " data-link=\"true\" href=\"\(escaped($0))\"" } ?? ""
        if webURL != nil {
            linked += " data-web-presentation=\"true\" target=\"_blank\" rel=\"noopener noreferrer\""
        } else if let raw = node.link, let link = WorksheetLink(raw), link.isExternal(siteHost: siteHost) {
            linked += " target=\"_blank\" rel=\"noopener noreferrer\""
        }
        let geometry = "data-x=\"\(node.position.x)\" data-y=\"\(node.position.y)\" data-width=\"\(node.width)\" data-height=\"\(node.height)\" data-shape=\"\(node.shape.rawValue)\" data-parent=\"\(node.parent ?? "")\""
        return "<\(tag) id=\"object-\(node.id)\" class=\"\(nodeClasses(node))\" data-node=\"\(node.id)\" \(geometry)\(linked) aria-label=\"\(escaped(node.title))\">\(graphic)</\(tag)>"
    }
    let wiresByLayer = Dictionary(grouping: edges, by: \.layer)
    var scene: [String] = []
    for (index, drawing) in ordered.enumerated() {
        scene.append(contentsOf: wiresByLayer[index, default: []].map(\.markup))
        scene.append(render(drawing))
    }
    scene.append(contentsOf: wiresByLayer[ordered.count, default: []].map(\.markup))
    let width = number(halfWidth * 2)
    let height = number(halfHeight * 2)
    let step = board.gridSpacing ?? 32
    let glass = graphics?.glass == true
    let grid: String
    switch graphics?.grid {
    case "drafting":
        let size = number(step * 5)
        func gridLine(_ index: Int) -> String {
            let at = number((Double(index) + 0.5) * step)
            return "M0 \(at) H\(size) M\(at) 0 V\(size)"
        }
        grid = """
            <pattern id="draft-grid" x="\(number(-step / 2))" y="\(number(-step / 2))" width="\(size)" height="\(size)" patternUnits="userSpaceOnUse">
              <path d="\((1...4).map(gridLine).joined(separator: " "))" stroke="#789bb0" stroke-opacity=".08" fill="none"/>
              <path d="\(gridLine(0))" stroke="#789bb0" stroke-opacity=".22" fill="none"/>
            </pattern>
            """
    case "lines":
        let size = number(step)
        grid = """
            <pattern id="draft-grid" width="\(size)" height="\(size)" patternUnits="userSpaceOnUse"><path d="M \(size) 0 H 0 V \(size)" stroke="#789BB0" stroke-opacity=".22" fill="none"/></pattern>
            """
    case _ where glass:
        let halfStep = number(step / 2)
        let size = number(step)
        grid = """
            <pattern id="draft-grid" x="-\(halfStep)" y="-\(halfStep)" width="\(size)" height="\(size)" patternUnits="userSpaceOnUse">
              <circle cx="\(halfStep)" cy="\(halfStep)" r="1" fill="#a397bf" fill-opacity=".24"/>
            </pattern>
            """
    default:
        grid = ""
    }
    let glassDefinitions = glass ? """
        <linearGradient id="glass-rim" x2="25%" y2="100%">
          <stop offset="0%" stop-color="#f4eeff" stop-opacity=".93"/>
          <stop offset="40%" stop-color="#b39bd8" stop-opacity=".72"/>
          <stop offset="76%" stop-color="#6e5a98" stop-opacity=".62"/>
          <stop offset="100%" stop-color="#ab91df" stop-opacity=".78"/>
        </linearGradient>
        <linearGradient id="glass-sheen" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#fff" stop-opacity=".30"/>
          <stop offset="34%" stop-color="#fff" stop-opacity=".08"/>
          <stop offset="58%" stop-color="#fff" stop-opacity="0"/>
          <stop offset="100%" stop-color="#a58ade" stop-opacity=".17"/>
        </linearGradient>
        """ : ""
    func backdrop(_ fill: String) -> String {
        "<rect x=\"\(number(-halfWidth))\" y=\"\(number(-halfHeight))\" width=\"\(width)\" height=\"\(height)\" fill=\"\(fill)\"/>"
    }
    let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" class="canvas passive-canvas" role="\(noteBase == nil ? "img" : "group")" aria-label="\(escaped(board.title))" width="\(width)" height="\(height)" viewBox="\(number(-halfWidth)) \(number(-halfHeight)) \(width) \(height)">
          \(noteBase == nil ? "<title>\(escaped(board.title))</title>" : "")
          <defs>\(definitions.joined())\(grid)\(glassDefinitions)\(board.nodes.contains { $0.resolvedBackgroundMode == .blurred } ? "<filter id=\"box-background-blur\" x=\"-30%\" y=\"-30%\" width=\"160%\" height=\"160%\"><feGaussianBlur stdDeviation=\"2\"/></filter>" : "")</defs>
          \(backdrop(escaped(board.backgroundColor)))
          \(grid.isEmpty ? "" : backdrop("url(#draft-grid)"))
          \(scene.joined(separator: "\n"))
        </svg>
        """
    let tooltipNodes = noteBase == nil ? [] : drawings.compactMap { drawing in
        needsTextTooltip(drawing.node, overflow: drawing.overflow) ? drawing.node : nil
    }
    return (svg, tooltipNodes)
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
