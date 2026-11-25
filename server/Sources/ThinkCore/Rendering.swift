import Foundation
import ThinkTable
import Vapor
import cmark_gfm

package func escaped(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

package func markdownHTML(_ source: String) -> String {
    let source = preservingBlankLines(source)
    return source.withCString { bytes in
        guard let html = cmark_markdown_to_html(bytes, source.utf8.count, CMARK_OPT_DEFAULT | CMARK_OPT_HARDBREAKS) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }
}

/// A markdown a több üres sort egyetlen bekezdéshatárrá vonja össze. Hogy ahány üres sor van a forrásban,
/// annyi látsszon (mint a vásznon, CanvasMarkdown blankLines), a második és további üres sorok
/// nem törhető szóközt kapnak (látható üres sor lesz belőlük). Kódblokkon belül nem változik semmi.
func preservingBlankLines(_ source: String) -> String {
    var lines = source.components(separatedBy: "\n")
    var fence: String?
    var previousBlank = false
    for index in lines.indices {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if let marker = ["```", "~~~"].first(where: { trimmed.hasPrefix($0) }) {
            fence = fence == nil ? marker : (fence == marker ? nil : fence)
            previousBlank = false
            continue
        }
        guard fence == nil else { continue }
        let blank = trimmed.isEmpty
        if blank && previousBlank { lines[index] = "\u{00A0}" }
        previousBlank = blank
    }
    return lines.joined(separator: "\n")
}

package func htmlPage(title: String, body: String, scripts: Bool = false, updates: PageUpdates.Subscription? = nil) -> Response {
    let assets = scripts ? """
        <script defer src="/vendor/vue.js"></script>
        <script defer src="/lib/d3-zoom.js?v=1"></script>
        <script defer src="/vendor/commonmark.js"></script>
        <script type="module" src="/editor.js?v=64"></script>
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
          <link rel="stylesheet" href="/app.css?v=36">
          <script defer src="/site-mode.js"></script>
          \(assets)
        </head>
        <body>\(body)</body>
        </html>
        """, type: "text/html; charset=utf-8")
}

/// `Content-Disposition` letöltéshez; nem ASCII névnél tartalék név + UTF-8 név.
package func attachmentDisposition(_ filename: String) -> String {
    let encoded = filename.utf8.map { byte in
        switch byte {
        case 48...57, 65...90, 97...122, 45, 46, 95: String(UnicodeScalar(byte))
        default: String(format: "%%%02X", byte)
        }
    }.joined()
    let fallback = encoded.contains("%") ? "munkalap." + (filename.split(separator: ".").last.map(String.init) ?? "txt") : encoded
    return "attachment; filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)"
}

package func response(_ content: String, type: String, filename: String? = nil) -> Response {
    var headers: HTTPHeaders = ["Content-Type": type, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"]
    headers.replaceOrAdd(name: "Content-Security-Policy",
                         value: "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' blob:; media-src 'self'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
    if let filename {
        headers.replaceOrAdd(name: "Content-Disposition", value: attachmentDisposition(filename))
    }
    return Response(status: .ok, headers: headers, body: .init(string: content))
}

package func csrfInput(_ token: String) -> String {
    "<input type=\"hidden\" name=\"csrf\" value=\"\(escaped(token))\">"
}

package func uiIcon(_ symbol: String) -> String {
    "<svg class=\"ui-icon\" aria-hidden=\"true\" viewBox=\"0 0 24 24\"><use href=\"/icons.svg#\(symbol)\"/></svg>"
}

package let headerButtonClass = "button header-button"

package func buttonLink(_ url: String, _ label: String, symbol: String, classes: String) -> String {
    "<a class=\"\(classes)\" href=\"\(escaped(url))\">\(uiIcon(symbol))\(escaped(label))</a>"
}

package func siteHeader(path: String? = nil, project: String? = nil, user: User?, csrf: String?, actions: String = "", centerAction: String = "", canEdit: Bool = false, editing: Bool = false, showAdminLogout: Bool = false) -> String {
    let parts = path?.split(separator: "/").map(String.init) ?? []
    let base = editing ? "/edit/" : "/"
    // Útvonal: munkalaponként egy gomb a mappa (könyvtár) nevével; a gombok ugyanabban a módban
    // (szerkesztő vagy megtekintő) nyitják meg a munkalapot. Az aktuális munkalap nem link.
    let crumb = parts.indices.map { i in
        let name = parts[i].removingPercentEncoding ?? parts[i]
        let separator = "<span class=\"crumb-sep\" aria-hidden=\"true\">›</span>"
        // Szűk fejlécben (header-fit.js) a név helyett a sorszám látszik; a név a súgóban és az akadálymentes névben marad.
        let label = "<span class=\"crumb-name\">\(escaped(name))</span><span class=\"crumb-number\" aria-hidden=\"true\">\(i + 1)</span>"
        let named = "title=\"\(escaped(name))\" aria-label=\"\(escaped(name))\""
        if i == parts.count - 1 {
            return separator + "<span class=\"\(headerButtonClass) crumb\" aria-current=\"page\" \(named)>\(label)</span>"
        }
        return separator + "<a class=\"\(headerButtonClass) crumb\" \(named) href=\"\(escaped(base + parts[...i].joined(separator: "/")))\">\(label)</a>"
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
    // Admin gomb; jelvény mutatja, hány adminisztrátori jelzés (AdminMessage) vár, pl. új hozzáférés-kérelem.
    let waiting = user?.adminMessages ?? 0
    let badge = waiting > 0 ? "<span class=\"admin-badge\" title=\"\(waiting) elintézendő jelzés\"><span class=\"visually-hidden\">, </span>\(waiting > 99 ? "99+" : String(waiting))<span class=\"visually-hidden\"> elintézendő jelzés</span></span>" : ""
    let admin = user?.role == .admin
        ? "<a class=\"\(headerButtonClass) admin-link\" href=\"/admin\(waiting > 0 ? "#admin-messages" : "")\">\(uiIcon("settings"))Admin\(badge)</a>" : ""
    // Névtér-azonosító (Public/ui-names.js): csak bejelentkezett adminoknak.
    let names = user?.role == .admin ? """
        <button type="button" class="\(headerButtonClass) ui-names-toggle" data-ui-names aria-pressed="false" aria-label="Névtér-azonosító" title="Névtér-azonosító: az elemek neve és class-a">\(uiIcon("namespace"))</button><script defer src="/ui-names.js?v=2"></script>
        """ : ""
    let appearanceActions = """
        <div class="header-appearance">
          <button type="button" class="\(headerButtonClass)" data-site-mode-picker data-mode="auto" aria-label="Megjelenés: automatikus">\(uiIcon("display-auto"))</button>
          \(names)\(admin)
        </div>
        """
    let navigationClass = path == nil ? "site-header" : "worksheet-nav"
    return """
        <\(tag) class="\(navigationClass)"><div class="header-left"><nav aria-label="Fő navigáció" class="breadcrumbs">
          <a class="\(headerButtonClass) brand" href="/"><span class="brand-icon" aria-hidden="true"><span></span><span></span><span></span></span>ThinkNodes</a>
          \(crumb)\(parent)
        </nav></div><div class="header-parent">\(centerAction)</div><div class="header-actions">\(actions)<div class="header-user">\(session)</div>\(editing ? "" : appearanceActions)</div>\(editing ? appearanceActions : "")</\(tag)><script defer src="/header-fit.js?v=2"></script>
        """
}

/// URL-lekérdezés értéke: minden nem alfanumerikus karakter százalékkódolva.
package func encodeQuery(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
}

/// SVG-szám három tizedesjeggyel. A `String(format:locale:)` minden hívásnál ICU-számformázót hozott létre
/// (a megtekintő oldal renderelési idejének jelentős része, docs/PLAN.md A1); a C `vsnprintf` ugyanazt a `%.3f` kimenetet adja.
private func number(_ value: Double) -> String {
    var buffer = [CChar](repeating: 0, count: 48)
    let length = withVaList([value]) { vsnprintf(&buffer, buffer.count, "%.3f", $0) }
    guard length > 0, length < buffer.count else { return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
    let text = String(cString: buffer)
    // Ha a folyamat C-locale-ja tizedesvesszőt használna, akkor is ponttal írjuk.
    let comma: Character = ","
    guard text.contains(comma) else { return text }
    return text.replacingOccurrences(of: ",", with: ".")
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

private struct IdeaLabelLine {
    package var text: String
    let size: Double
    let weight: Int
    let color: String
    var runs: [MarkdownRun] = []
    var gap: Double = 0
    var justify = false
    var wrapped = false
    var indent: Double = 0
    var code = false
    /// Becsült sorszélesség (a tördelés mérte).
    var width: Double = 0
    /// Körbefuttatott sor helye a címketerület bal széléhez mérve (nil = a teljes szélesség).
    var slotX: Double?
    var slotWidth: Double?

    var step: Double { size * 1.25 + gap }
}

private struct IdeaDrawing {
    package var node: Idea
    let labelWidth: Double
    var iconSpace: Double = 0
    var previewSpace: Double = 0
    var available: Double = 0
    var overflow = false
    /// A szöveg kikerüli a konténer gyermekdobozait: felülről folyik, a függőleges igazítás nem hat.
    var flow = false
    /// Körbefuttatásnál a szöveg kezdete a címketerület tetejétől (a függőleges igazításból).
    var flowStart: Double = 0
    let lines: [IdeaLabelLine]
    var extentX: Double = 0
    var extentY: Double = 0
}

/// Becsült betűszélesség em-ben, kalibrált értékek kis ráhagyással (geometry.js letterWidth párja; pontosan egyezniük kell).
private func letterWidth(_ letter: Character, monospace: Bool = false) -> Double {
    if monospace { return 0.62 }
    if letter == " " { return 0.28 }
    if letter == "…" { return 0.85 }
    if "ilIjf.,:;!|'`".contains(letter) { return 0.3 }
    if "tr()[]-/\"".contains(letter) { return 0.38 }
    if "MW@#%&".contains(letter) { return 0.88 }
    if letter == "m" || letter == "w" { return 0.82 }
    if ("0"..."9").contains(letter) { return 0.6 }
    let value = String(letter), lower = value.lowercased(), upper = value.uppercased()
    if lower != upper { return value == lower ? 0.55 : 0.7 }
    return 0.65
}

private let boldFactor = 1.07

/// A téma betűcsaládja rögzített szélességű-e (geometry.js isMonospaceFont).
func isMonospaceFont(_ family: String) -> Bool {
    let first = (family.split(separator: ",").first.map(String.init) ?? family).lowercased()
    return ["mono", "menlo", "courier", "consolas"].contains { first.contains($0) }
}

private func letterMeasure(size: Double, bold: Bool, monospace: Bool) -> (Character, MarkdownFormat?) -> Double {
    { letter, format in letterWidth(letter, monospace: monospace || format?.code == true) * size * (bold || format?.bold == true ? boldFactor : 1) }
}

private func textWidth(_ value: String, size: Double) -> Double {
    let measure = letterMeasure(size: size, bold: false, monospace: false)
    var width = 0.0
    for letter in value { width += measure(letter, nil) }
    return width
}

/// Egysoros felirat (link, fájlnév, címke): ha nem fér el, „…”-tal rövidül (geometry.js fitCaption).
func fitCaption(_ text: String, size: Double, available: Double) -> String {
    if textWidth(text, size: size) <= available { return text }
    let line = IdeaLabelLine(text: text, size: size, weight: 400, color: "")
    return shortenLine(line, width: available, measure: letterMeasure(size: size, bold: false, monospace: false)).text
}

private func shortenLine(_ line: IdeaLabelLine, width: Double, measure: (Character, MarkdownFormat?) -> Double) -> IdeaLabelLine {
    var result = line
    var remaining = width - measure("…", nil)
    var runs: [MarkdownRun] = []
    var used = 0.0
    for run in line.runs.isEmpty ? [MarkdownRun(text: line.text)] : line.runs {
        var prefix = ""
        for letter in run.text {
            let size = measure(letter, run.format)
            remaining -= size
            if remaining < 0 { break }
            used += size
            prefix.append(letter)
        }
        if !prefix.isEmpty { runs.append(MarkdownRun(text: prefix, format: run.format)) }
        if remaining < 0 { break }
    }
    runs.append(MarkdownRun(text: "…"))
    result.text = runs.map(\.text).joined()
    result.wrapped = false
    result.runs = runs
    result.width = used + measure("…", nil)
    return result
}

/// Címsor mérete az alapméret arányában (docs/node-types.md, Text képesség).
func headingScale(_ level: Int?) -> Double {
    switch level ?? 3 {
    case 1: 1.6
    case 2: 1.3
    default: 1.15
    }
}

/// A link rövid felirata a dobozon: domain, munkalap-útvonal vagy .web mappa neve.
func linkCaption(_ link: NodeLink) -> String {
    switch link.kind {
    case .url: URLComponents(string: link.target)?.host ?? link.target
    case .sheet: link.target
    case .web: link.webReference?.name ?? link.target
    }
}

/// A konténer szövegét kikerülendő gyermekdoboz: közepe a konténer közepéhez mérve, és a mérete.
struct TextObstacle {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// Körbefuttatott szöveg egy sorának helye (geometry.js textSlot párja; pontosan egyezniük kell).
private func textSlot(_ obstacles: [(left: Double, right: Double, top: Double, bottom: Double)], width: Double,
                      top start: Double, height: Double, indent: Double) -> TextSlot {
    var top = start
    let least = min(width - indent, max(40, height * 2))
    for _ in 0...obstacles.count {
        let blocking = obstacles.filter { $0.top < top + height && $0.bottom > top }
        var free: [(Double, Double)] = [(indent, width)]
        for o in blocking {
            free = free.flatMap { part -> [(Double, Double)] in
                if o.right <= part.0 || o.left >= part.1 { return [part] }
                return [(part.0, min(part.1, o.left)), (max(part.0, o.right), part.1)].filter { $0.1 > $0.0 }
            }
        }
        var best: (Double, Double)?
        for part in free where best == nil || part.1 - part.0 > best!.1 - best!.0 { best = part }
        if let best, best.1 - best.0 >= least { return TextSlot(x: best.0, width: best.1 - best.0, skip: top - start) }
        if blocking.isEmpty { break }
        top = max(top + 1, blocking.map(\.bottom).min()!)
    }
    return TextSlot(x: indent, width: width - indent, skip: top - start)
}

private func ideaDrawing(_ idea: Idea, graphics: VisualTheme.Graphics? = nil, obstacles: [TextObstacle] = []) -> IdeaDrawing {
    var node = idea
    if node.isJunction {
        if ![.ellipse,.rectangle,.diamond].contains(node.shape) { node.shape = .ellipse }
        return IdeaDrawing(node: node, labelWidth: 0, lines: [])
    }
    guard node.isBox else { return IdeaDrawing(node: node, labelWidth: node.width, lines: []) }
    // .web doboz: az előnézeti kép tölti ki, a szöveg csak buboréksúgóban jelenik meg (geometry.js labelLayout).
    if node.fillsWithPreview {
        return IdeaDrawing(node: node, labelWidth: node.width, previewSpace: node.height,
                           overflow: node.type == "preview" ? commentCollapsed(node) : !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, lines: [],
                           extentX: node.width / 2, extentY: node.height / 2)
    }
    let (widthRatio, heightRatio, _) = node.shape.labelRatios
    let fitText = node.fitText == true
    // NAGYBETŰS: a tördelés előtt, mert a nagybetűs szöveg szélesebb (geometry.js labelLayout).
    let blocks = canvasMarkdown(node.text).map { block in
        guard node.uppercase == true else { return block }
        var upper = block
        upper.runs = block.runs.map { MarkdownRun(text: $0.text.uppercased(with: Locale(identifier: "hu")), format: $0.format) }
        return upper
    }
    let labelWidth = max(12, node.width * widthRatio - 16)
    let iconSpace: Double = 0  // a link felirata a doboz alatt, a dobozon kívül áll
    let previewSpace: Double = 0  // előnézet csak teljes kitöltéssel (fillsWithPreview)
    let labelHeight = node.height * heightRatio - 12 - iconSpace - previewSpace
    let strong = false  // a Félkövér gomb megszűnt
    let monospace = isMonospaceFont((graphics ?? VisualTheme.Graphics()).fontFamily(node.font))
    func measure(for line: IdeaLabelLine) -> (Character, MarkdownFormat?) -> Double {
        letterMeasure(size: line.size, bold: line.weight >= 700, monospace: monospace || line.code)
    }
    // Körbefuttatás: az akadályok a címketerület bal felső sarkához mérve, térközzel: fent és lent 8, két oldalt 18 képpont (geometry.js labelLayout).
    let flow = !obstacles.isEmpty
    let margin = 8.0, sideMargin = 18.0
    let blocked = obstacles.map { o in
        (left: o.x - o.width / 2 - sideMargin + labelWidth / 2, right: o.x + o.width / 2 + sideMargin + labelWidth / 2,
         top: o.y - o.height / 2 - margin + max(0, labelHeight) / 2, bottom: o.y + o.height / 2 + margin + max(0, labelHeight) / 2)
    }
    func room(_ line: IdeaLabelLine) -> Double { line.slotWidth ?? labelWidth - line.indent }

    func makeLines(base: Double, start: Double = 0) -> [IdeaLabelLine] {
        var lines: [IdeaLabelLine] = []
        var cursor = start
        for (_, block) in blocks.enumerated() {
            let heading = block.kind == .heading
            var size = heading ? base * headingScale(block.level) * (strong ? 1.1 : 1) : base
            if !fitText { size = size.rounded() }
            let weight = heading ? (strong ? 900 : 700) : (strong ? 650 : 400)
            let indent = Double(max(0, (block.indent ?? 0) - 1)) * base * 1.2
            let code = block.kind == .code
            var runs = block.runs
            if block.kind == .quote { runs.insert(MarkdownRun(text: "› "), at: 0) }
            let measure = letterMeasure(size: size, bold: weight >= 700, monospace: monospace || code)
            let blank = Double(block.blankLines ?? 0) * base * 1.25
            var first = true
            let slots: (() -> TextSlot)? = !flow ? nil : {
                let lead = first ? blank : 0
                first = false
                let slot = textSlot(blocked, width: labelWidth, top: cursor + lead, height: size * 1.25, indent: indent)
                cursor += lead + slot.skip + size * 1.25
                return slot
            }
            for (row, wrappedLine) in wrapMarkdown(runs, limit: labelWidth - indent, slots: slots, preformatted: code, width: measure).enumerated() {
                let pieces = wrappedLine.pieces
                // Ahány üres sor van a forrásban, annyi üres sor marad a dobozon is.
                let gap = (row == 0 ? blank : 0) + (wrappedLine.slot?.skip ?? 0)
                lines.append(IdeaLabelLine(text: pieces.map(\.text).joined(), size: size, weight: weight,
                                           color: node.textColor, runs: pieces, gap: gap,
                                           justify: node.justified == true && !code && !heading,
                                           wrapped: wrappedLine.wrapped, indent: indent, code: code, width: wrappedLine.width,
                                           slotX: wrappedLine.slot?.x, slotWidth: wrappedLine.slot?.width))
            }
        }
        if node.hideText == true, lines.count > 1 {
            // Összecsukott állapot: az első sor marad, alatta egy sorközzel az ellipszis.
            let ellipsis = IdeaLabelLine(text: "…", size: lines[0].size, weight: lines[0].weight, color: node.textColor,
                                         runs: [MarkdownRun(text: "…")], gap: 0, justify: false, wrapped: false, indent: 0,
                                         code: lines[0].code, width: measure(for: lines[0])("…", nil))
            return [lines[0], ellipsis]
        }
        return lines
    }

    var lines: [IdeaLabelLine]
    if fitText {
        var low = 1
        var high = Int((labelHeight / 1.25).rounded(.down))
        lines = makeLines(base: 1)
        while low <= high {
            let size = (low + high) / 2
            let candidate = makeLines(base: Double(size))
            if candidate.reduce(0, { $0 + $1.step }) <= labelHeight &&
                candidate.allSatisfy({ $0.width <= room($0) }) {
                lines = candidate
                low = size + 1
            } else {
                high = size - 1
            }
        }
    } else {
        lines = makeLines(base: node.fontSize)
    }
    let available = max(0, labelHeight)
    // Körbefuttatás függőleges igazítással (geometry.js labelLayout): néhány lépésben közelítjük a kezdőpontot.
    let rank: Double = switch node.verticalAlignment {
    case .top: 0
    case .bottom: 1
    default: 0.5
    }
    var flowStart = 0.0
    if flow && rank > 0 && !fitText {
        func tall(_ rows: [IdeaLabelLine]) -> Double { rows.reduce(0) { $0 + $1.step } }
        for _ in 0..<3 {
            let next = max(0, ((available - tall(lines)) * rank).rounded())
            if next == flowStart { break }
            flowStart = next
            lines = makeLines(base: node.fontSize, start: flowStart)
        }
        var attempt = 0
        while attempt < 8 && flowStart > 0 && flowStart + tall(lines) > available {
            flowStart = max(0, flowStart - (flowStart + tall(lines) - available).rounded(.up))
            lines = makeLines(base: node.fontSize, start: flowStart)
            attempt += 1
        }
    }
    var visible: [IdeaLabelLine] = []
    var remaining = available - flowStart
    for line in lines {
        if remaining < line.step { break }
        visible.append(line)
        remaining -= line.step
    }
    let omitted = visible.count < lines.count
    var overflow = omitted || (node.hideText == true && canvasMarkdown(node.text).count > 1)
    for index in visible.indices {
        let line = visible[index]
        if line.width > room(line) || (omitted && index == visible.count - 1) {
            visible[index] = shortenLine(line, width: room(line), measure: measure(for: line))
            overflow = true
        }
    }
    return IdeaDrawing(node: node, labelWidth: labelWidth, iconSpace: iconSpace, previewSpace: previewSpace,
                       available: available, overflow: overflow, flow: flow, flowStart: flowStart, lines: visible,
                       extentX: node.width / 2, extentY: node.height / 2)
}

/// Egységes vászon-osztálynév: `node is-<típus>` (+ `has-children` konténernél). Az editor.js `nodeClasses` ugyanezt adja.
func nodeClasses(_ node: Idea, hasChildren: Bool = false) -> String {
    var classes = "node is-" + node.type
    if node.root != node.type { classes += " is-" + node.root }
    if node.link != nil { classes += " has-link" }
    if node.uppercase == true { classes += " is-uppercase" }
    if hasChildren { classes += " has-children" }
    return classes
}

func needsTextTooltip(_ node: Idea, overflow: @autoclosure () -> Bool) -> Bool {
    if node.hasComment { return commentCollapsed(node) }
    return node.isBox && !node.text.isEmpty && overflow()
}

extension Idea {
    /// Megjegyzés a doboz alatt: fájldoboz és előnézetes link-doboz (a `text` mező).
    var hasComment: Bool { file != nil || type == "preview" || type == "chart" }
    /// Táblázat és CSV: 5 px-es lekerekítésű téglalap; a grafikon adatforrása lehet.
    var isGrid: Bool { type == "table" || type == "csv" }
}

/// Összecsukott (elrejtett) megjegyzés, amelynek több sora van: a teljes szöveg buboréksúgóban.
func commentCollapsed(_ node: Idea) -> Bool {
    node.hideText == true && commentLines(node.text).count > 1
}

private func commentLines(_ text: String) -> [String] {
    text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
}

/// A doboz alatt látható megjegyzés: sima szöveg, minden sora; összecsukva az első sor és alatta „…”.
func visibleComment(_ node: Idea) -> String {
    let lines = commentLines(node.text)
    guard node.hideText == true, lines.count > 1 else { return lines.joined(separator: "\n") }
    return lines[0] + "\n…"
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
        return "rect x=\"\(number(-x))\" y=\"\(number(-y))\" width=\"\(number(node.width))\" height=\"\(number(node.height))\" rx=\"\(node.type == "preview" || node.isImage || node.isGrid ? "5" : node.shape == .rounded ? "12" : "0")\""
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
        let r: Double = node.type == "preview" || node.isGrid ? 5 : node.shape == .rounded ? 12 : 0
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
    // Képnél a láthatósági mód nem számít: a Kiemelés árnyéka mindig a teljes kép alatt van.
    guard node.elevated == true, node.isImage || node.resolvedBackgroundMode != .free else { return "" }
    // Üres dobozon csak a keret vet árnyékot; kitöltött doboznál a kitöltés (nincs clipPath: gyorsabb mozgatás).
    if !node.isImage && node.resolvedBackgroundMode == .empty {
        return """
            <g class="node-shadow" pointer-events="none" aria-hidden="true">
              <\(geometry) transform="translate(12 28)" fill="none" stroke="#11172b" stroke-opacity=".44" stroke-width="1.6"/>
            </g>
            """
    }
    return """
        <g class="node-shadow" pointer-events="none" aria-hidden="true">
          <\(geometry) transform="translate(12 28)" fill="#11172b" fill-opacity=".44"/>
        </g>
        """
}

/// Kép és előnézetes doboz kerete (editor.js frameOutline): a doboz színével, a beállított vastagsággal, a tartalom felett.
private func frameOutline(_ node: Idea) -> String {
    guard node.hasFrame else { return "" }
    return "<rect class=\"node-frame-outline\" x=\"\(number(-node.width / 2))\" y=\"\(number(-node.height / 2))\" width=\"\(number(node.width))\" height=\"\(number(node.height))\" rx=\"5\" fill=\"none\" stroke=\"\(escaped(node.fill))\" stroke-width=\"\(number(node.frameWidth ?? 1.6))\" pointer-events=\"none\"/>"
}

private func boxSurface(_ node: Idea, geometry: String, graphics: VisualTheme.Graphics?, interactive: Bool) -> String {
    let mode = node.resolvedBackgroundMode
    guard mode != .free else {
        return interactive ? "<\(geometry) fill=\"none\" pointer-events=\"fill\"/>" : ""
    }
    let blurred = mode == .blurred
    let empty = mode == .empty
    // A kép mindig háttér nélkül, a saját átlátszóságával jelenik meg (a régi alfa- és háttérbeállítások nem hatnak).
    // Vászonszín módban (canvas) a kép alatt a munkalap háttérszíne áll (a szín a `fill`-ben érkezik, lásd renderWorksheetCanvas).
    if node.isImage { return mode == .canvas ? "<\(geometry) class=\"node-surface\" fill=\"\(escaped(node.fill))\" stroke=\"none\"/>" : "" }
    let image = node.isImage
    let locked = node.isBox && node.locked == true
    let glass = graphics?.glass == true && mode == .solid && !image
    let fill = node.fill
    // Üres doboz keretének színe a doboz színe; elmosottnál a háttér elmosódik, a keret nem.
    // Szövegfájl- és táblázatdoboz kerete kikapcsolható (frame: false), bármelyik háttérmód mellett.
    let frameless = node.type == "preview" || (node.isTextFile && node.frame == false)
    let stroke = frameless ? "none" : empty ? escaped(node.fill) : image ? "none" : glass ? "url(#glass-rim)" : escaped(node.border)
    // Minden doboz kerete sima és egyforma vastag (a zárolt konténer jelzése kivétel).
    let width = locked ? "6.4" : "1.6"
    let dash = ""
    let closed = locked ? " data-locked-outline=\"\"" : ""
    let effect = glass ? " fill-opacity=\".66\"" : mode == .translucent ? " fill-opacity=\".75\"" : ""
    let pointer = empty && interactive ? " pointer-events=\"fill\"" : ""
    if blurred {
        return "<\(geometry) class=\"node-surface\" fill=\"\(escaped(fill))\" opacity=\".98\" filter=\"url(#box-background-blur)\" stroke=\"none\"/>"
            + "<\(geometry) class=\"node-frame\" fill=\"none\" stroke=\"\(frameless ? "none" : escaped(node.border))\" stroke-width=\"\(width)\"\(closed)\(dash)/>"
    }
    let surface = "<\(geometry) class=\"node-surface\" fill=\"\(empty ? "none" : escaped(fill))\" stroke=\"\(stroke)\" stroke-width=\"\(width)\"\(closed)\(dash)\(effect)\(pointer)/>"
    return surface + (glass ? "<\(geometry) fill=\"url(#glass-sheen)\" pointer-events=\"none\" aria-hidden=\"true\"/>" : "")
}

/// Link jel a doboz alján középen: ikon + rövid felirat (docs/node-types.md, link képesség).
private func linkMarker(_ link: NodeLink, node: Idea, bottom: Double, width: Double, siteHost: String?) -> String {
    let caption = linkCaption(link)
    let available = max(12, width - 22)
    // Egysoros felirat: ha nem fér el, „…”-tal rövidül (nincs tördelés, nincs összenyomás).
    let shown = textWidth(fitCaption(caption, size: 13, available: available), size: 13)
    let icon = link.kind == .web ? WorksheetLink.globe : link.worksheetLink?.iconPath(siteHost: siteHost) ?? WorksheetLink.chain
    let left = -(shown + 18) / 2
    return """
        <g class="node-link" data-link-kind="\(link.kind.rawValue)" pointer-events="none"><svg x="\(number(left))" y="\(number(bottom - 14))" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="\(escaped(node.textColor))" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="\(icon)"/></svg><text x="\(number(left + 18))" y="\(number(bottom - 2))" font-size="13" fill="\(escaped(node.textColor))">\(escaped(fitCaption(caption, size: 13, available: available)))</text></g>
        """
}

private func nodeSVG(_ drawing: IdeaDrawing, siteHost: String?, graphics: VisualTheme.Graphics?, interactive: Bool, preview: String? = nil) -> String {
    let node = drawing.node
    if node.isJunction {
        let r = node.width / 2
        let x = node.position.x, y = node.position.y
        let label = node.text.isEmpty ? "" : """
            <g class="node-label-turn" transform="translate(\(number(x)) \(number(y))) rotate(\(number(node.angle ?? 0)))"><text class="node-label" x="\(number(r + 4))" y="4" font-size="14" fill="\(escaped(node.textColor))">\(escaped(node.text))</text></g>
            """
        if node.shape == .rectangle {
            return "<rect x='\(number(x-r))' y='\(number(y-r))' width='\(number(2*r))' height='\(number(2*r))' fill='\(escaped(node.fill))'/>" + label
        }
        if node.shape == .diamond {
            return "<path d='M \(number(x)) \(number(y-r)) l \(number(r)) \(number(r)) l \(number(-r)) \(number(r)) l \(number(-r)) \(number(-r)) Z' fill='\(escaped(node.fill))'/>" + label
        }
        return """
            <circle cx="\(number(x))" cy="\(number(y))" r="\(number(r))" fill="\(escaped(node.fill))"/>\(label)
            """
    }
    let width = node.width
    let height = node.height
    let x = width / 2
    let y = height / 2
    let geometry = boxGeometry(node, graphics: graphics)
    let labelWidth = drawing.labelWidth
    let aligned: Double = switch node.verticalAlignment {
    case .top: 0
    case .bottom: 1
    default: 0.5
    }
    let rank = aligned
    let strong = false  // a Félkövér/Dőlt/Aláhúzott gombok megszűntek; a markdown formázás marad
    let extra = drawing.available - drawing.lines.reduce(0) { $0 + $1.step }
    var offset = -(drawing.available + drawing.iconSpace + drawing.previewSpace) / 2 + drawing.previewSpace
    let spans = drawing.lines.map { line in
        let top = offset + (drawing.flow ? drawing.flowStart : extra * rank)
        let textX: Double
        let anchor: String
        let left = -labelWidth / 2 + (line.slotX ?? line.indent)
        let span = line.slotWidth ?? labelWidth - line.indent
        switch line.justify || line.indent > 0 ? .left : node.alignment {
        case .left: (textX, anchor) = (left, "start")
        case .right: (textX, anchor) = (line.slotWidth == nil ? labelWidth / 2 : left + span, "end")
        case .center: (textX, anchor) = (line.slotWidth == nil ? 0 : left + span / 2, "middle")
        }
        var style = ""
        // Sorkizárás: csak a tördelt (nem bekezdés-záró) sorok érnek a doboz mindkét széléig; a rövid sor balra zárt marad.
        if line.justify && line.wrapped && line.text.contains(" ") && line.width < span {
            // A szóközöket a böngésző tágítja (Public/justify.js); JavaScript nélkül a sor balra zárt marad.
            style += " data-justify=\"\(number(span))\""
        }
        let baseline = top + line.gap + line.size * (1.25 / 2 + 0.33)
        offset += line.step
        let content = line.runs.map { run in
            let format = run.format
            var attributes = ""
            if format.bold {
                attributes += " font-weight=\"\(strong ? 900 : 700)\""
                if strong { attributes += " font-size=\"\(number(line.size * 1.1))\"" }
            }
            if format.italic { attributes += " font-style=\"italic\"" }
            if format.code { attributes += " font-family=\"monospace\" xml:space=\"preserve\"" }
            if format.link { attributes += " text-decoration=\"underline\"" }
            return attributes.isEmpty ? escaped(run.text) : "<tspan\(attributes)>\(escaped(run.text))</tspan>"
        }.joined()
        return """
            <tspan text-anchor="\(anchor)"\(style) x="\(number(textX))" y="\(number(baseline))" fill="\(escaped(line.color))" font-size="\(number(line.size))" font-weight="\(line.weight)">\(content)</tspan>
            """
    }.joined()
    let inset = node.shape.labelRatios.link
    // Előnézetes doboz: a link felirata a doboz felett (mint a fájlnév), a megjegyzés alatta.
    let marker = node.link.map { linkMarker($0, node: node, bottom: node.type == "preview" ? -y - 6 : y + 20, width: node.width, siteHost: siteHost) } ?? ""
    // Kikapcsolt előnézetnél (`staticPreview`) a szöveg a dobozban van, alatta nem ismétlődik.
    let noteBelow = node.type == "preview" && node.fillsWithPreview && !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "<foreignObject x=\"\(number(-x))\" y=\"\(number(y))\" width=\"\(number(width))\" height=\"4000\" pointer-events=\"none\"><div xmlns=\"http://www.w3.org/1999/xhtml\" class=\"node-below\" style=\"color:\(escaped(node.textColor))\"><footer class=\"node-comment formatted-text align-\(node.alignment.rawValue)\">\(markdownHTML(visibleComment(node)))</footer></div></foreignObject>" : ""
    let previewImage = preview.map { url in
        if node.fillsWithPreview {
            // Teljes kitöltés a doboz alakjára vágva; .web-nél az arányt a doboz határozza meg.
            let clip = "web-clip-" + node.id
            let url = node.link?.kind != .web ? url
                : url + (WebScreenshot.boxSize(width: width, height: height).map { "?w=\($0.width)&h=\($0.height)" } ?? "") + (node.staticPreview == true ? "&live=0" : "")
            return "<clipPath id=\"\(escaped(clip))\"><\(geometry)/></clipPath><image class=\"node-link-preview node-site-preview\" href=\"\(escaped(url))\" x=\"\(number(-x))\" y=\"\(number(-y))\" width=\"\(number(max(1, width)))\" height=\"\(number(max(1, height)))\" preserveAspectRatio=\"xMidYMid slice\" clip-path=\"url(#\(escaped(clip)))\" pointer-events=\"none\"/>"
        }
        let top = -y * inset + 6, previewHeight = drawing.previewSpace - 6
        return "<image class=\"node-link-preview\" href=\"\(escaped(url))\" x=\"\(number(-x * inset + 6))\" y=\"\(number(top))\" width=\"\(number(max(1, node.width * inset - 12)))\" height=\"\(number(max(1, previewHeight)))\" preserveAspectRatio=\"xMidYMid meet\" pointer-events=\"none\"/>"
    } ?? ""
    let publicMark = node.link?.kind == .web && node.webPublic == true
        ? "<svg class=\"ui-icon web-public-mark\" x=\"-10\" y=\"\(number(-y - (node.type == "preview" ? 44 : 26)))\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" color=\"\(escaped(node.textColor))\" pointer-events=\"none\"><use href=\"/icons.svg#butterfly\"/></svg>" : ""
    let contents = """
        \(elevationShadow(node, geometry: geometry, graphics: graphics))
        \(boxSurface(node, geometry: geometry, graphics: graphics, interactive: interactive))
        \(previewImage)\(frameOutline(node))<text class="node-text" text-rendering="geometricPrecision" font-family="\(escaped((graphics ?? VisualTheme.Graphics()).fontFamily(node.font)))" pointer-events="none">\(spans)</text>
        \(marker)\(noteBelow)\(publicMark)
        """
    return """
        <g aria-label="\(escaped(node.name))" transform="translate(\(number(node.position.x)) \(number(node.position.y)))">
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

/// Egyszerű CSV/TSV feldolgozás a táblázatnézethez (idézőjeles mezők, legfeljebb 200 sor × 30 oszlop).
func parseCSV(_ source: String, separator: Character = ",") -> [[String]] {
    var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
    var iterator = source.makeIterator()
    while let character = iterator.next(), rows.count < 200 {
        if quoted {
            if character == "\"" {
                if let next = iterator.next() {
                    if next == "\"" { field.append("\"") }
                    else {
                        quoted = false
                        if next == separator { row.append(field); field = "" }
                        else if next.isNewline { row.append(field); field = ""; rows.append(Array(row.prefix(30))); row = [] }
                        else { field.append(next) }
                    }
                } else { quoted = false }
            } else { field.append(character) }
        } else if character == "\"" && field.isEmpty {
            quoted = true
        } else if character == separator {
            row.append(field); field = ""
        } else if character.isNewline {
            row.append(field); field = ""
            rows.append(Array(row.prefix(30))); row = []
        } else { field.append(character) }
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(Array(row.prefix(30))) }
    return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
}

/// Táblázat dobozok kész HTML-je a `.tntable` fájl szövege szerint (a legutóbb használt néhány táblázat).
final class RenderedTables: @unchecked Sendable {
    static let shared = RenderedTables()
    private let lock = NSLock()
    private var entries: [String: String] = [:]
    private var order: [String] = []      // a legrégebben használt elöl
    private var bytes = 0
    private let maximumEntries = 32, maximumBytes = 48 * 1024 * 1024

    func html(for text: String, render: () -> String) -> String {
        lock.lock()
        if let known = entries[text] {
            if let index = order.firstIndex(of: text) { order.append(order.remove(at: index)) }
            lock.unlock()
            return known
        }
        lock.unlock()
        let html = render()     // zár nélkül: a nagy táblázat rajzolása ne tartsa fel a többi kérést
        lock.lock()
        defer { lock.unlock() }
        if entries[text] == nil {
            entries[text] = html
            order.append(text)
            bytes += text.utf8.count + html.utf8.count
            while order.count > maximumEntries || (bytes > maximumBytes && order.count > 1) {
                let oldest = order.removeFirst()
                if let removed = entries.removeValue(forKey: oldest) { bytes -= oldest.utf8.count + removed.utf8.count }
            }
        }
        return html
    }
}

/// Szövegfájl tartalmának HTML-je a vásznon: `.md` formázva, `code` egyenközű, `csv` táblázat, egyéb egyszerű szöveg.
func fileTextHTML(_ node: Idea, text: String?) -> String {
    guard let text else { return "<p class=\"muted\">…</p>" }
    let preview = String(text.prefix(200_000))
    let ext = (node.file?.filename.map { ($0 as NSString).pathExtension } ?? "").lowercased()
    switch node.type {
    case "table":
        // Táblázat doboz (docs/EXCEL.md): a szerver által számolt értékek, a teljes fájlból (nem csak az elejéből).
        // A kész HTML a fájl tartalma szerint gyorsítótárazva: a megtekintő és az előnézet minden kérésnél újradekódolta
        // és újrarajzolta a táblázatot (egy nagy táblázatnál ez adta a kirajzolás idejének nagy részét).
        return RenderedTables.shared.html(for: text) {
            guard let document = try? TableDocument.decode(Data(text.utf8)) else { return "<p class=\"muted\">A táblázat nem olvasható.</p>" }
            return "<div class=\"tn-table-wrap\">" + TableHTML.render(document) + "</div>"
        }
    case "csv":
        let rows = parseCSV(preview, separator: TableCSV.detectSeparator(preview, ext: ext))
        guard let head = rows.first else { return "<table class=\"node-csv\"></table>" }
        let header = "<tr>" + head.map { "<th>\(escaped($0))</th>" }.joined() + "</tr>"
        let body = rows.dropFirst().map { "<tr>" + $0.map { "<td>\(escaped($0))</td>" }.joined() + "</tr>" }.joined()
        return "<table class=\"node-csv\"><thead>\(header)</thead><tbody>\(body)</tbody></table>"
    case "code":
        return "<pre class=\"node-code\"><code>\(escaped(preview))</code></pre>"
    default:
        if ext == "md" || ext == "markdown" {
            return "<div class=\"formatted-text\(node.justified == true ? " justified-text" : "")\">\(markdownHTML(preview))</div>"
        }
        return "<pre class=\"node-plain\(node.justified == true ? " justified-text" : "")\">\(escaped(preview))</pre>"
    }
}

/// A fájl tartalmának címe. Közös fájl a projekt másik lapjáról: a tulajdonos lap címén töltődik be.
private func attachmentAddress(_ file: CanvasFile, base: String) -> String {
    var fileBase = base
    if let source = file.source {
        let project: String = base.split(separator: "/").first.map(String.init) ?? ""
        let folders: [String] = source.split(separator: "/").map { WorksheetPath.encodeSegment(String($0)) }
        fileBase = "/" + ([project] + folders).joined(separator: "/")
    }
    return file.commonURL ?? "/api/attachment" + fileBase + "?inline=1&name=" + encodeQuery(file.asset)
}

/// Grafikon (docs/node-types.md): önálló objektum, az adatát a vonallal bekötött táblázat vagy CSV fájlja adja.
/// A megtekintő szkriptje rajzolja ki (viewer.js, chart.js); szkript nélkül (SVG-export, előnézeti kép) és bekötött
/// táblázat nélkül a doboz üres.
private func chartBox(_ node: Idea, source: Idea?, base: String, interactive: Bool, graphics: VisualTheme.Graphics?) -> String {
    var content = ""
    if interactive, let source, let file = source.file, let settings = try? JSONEncoder().encode(node.chart ?? ChartSettings(kind: "bar")) {
        let surface = [.free, .empty].contains(node.resolvedBackgroundMode) ? "" : node.fill
        content = "<div class=\"node-chart\" data-chart=\"\(escaped(String(decoding: settings, as: UTF8.self)))\" data-chart-type=\"\(escaped(source.type))\" data-chart-source=\"\(escaped(attachmentAddress(file, base: base)))\" data-chart-name=\"\(escaped(file.filename ?? file.asset))\" data-chart-surface=\"\(escaped(surface))\"><p class=\"muted\">…</p></div>"
    } else if interactive {
        content = "<div class=\"node-chart\"><p class=\"muted\">Nincs bekötött táblázat.</p></div>"
    }
    let comment = node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" :
        "<div class=\"node-below\"><footer class=\"node-comment formatted-text align-\(node.alignment.rawValue)\">\(markdownHTML(visibleComment(node)))</footer></div>"
    let geometry = boxGeometry(node, graphics: graphics)
    let chrome = elevationShadow(node, geometry: geometry, graphics: graphics) + boxSurface(node, geometry: geometry, graphics: graphics, interactive: interactive)
    let height = node.height + (comment.isEmpty ? 0 : 4000)
    return """
        <g transform="translate(\(number(node.position.x)) \(number(node.position.y)))">\(chrome)</g><foreignObject class="node-file-frame" x="\(number(node.position.x - node.width / 2))" y="\(number(node.position.y - node.height / 2))" width="\(number(node.width))" height="\(number(height))"><div xmlns="http://www.w3.org/1999/xhtml" class="node-file-stack" style="color:\(escaped(node.textColor))"><div data-file-ink="\(escaped(node.textColor))" style="height:\(number(node.height))px" class="node-file node-chart-box mode-\(node.resolvedBackgroundMode.rawValue)"><div class="node-body">\(content)</div></div>\(comment)</div></foreignObject>
        """
}

/// Adatvonal: táblázatot (vagy CSV-t) és grafikont összekötő vonal. Nem tárolt tulajdonság, a két végpont típusa adja;
/// nyíl helyett a két végén félkorong áll (geometry.js isDataLink, plugTransform).
func isDataLink(_ edge: Connection, nodes: [String: Idea]) -> Bool {
    guard let a = edge.source.flatMap({ nodes[$0] }), let b = edge.target.node.flatMap({ nodes[$0] }) else { return false }
    return (a.type == "chart" && b.isGrid) || (b.type == "chart" && a.isGrid)
}

/// A doboz `toward` felé eső oldalának közepe (geometry.js sideMidpoint).
private func sideMidpoint(_ node: Idea, toward: Point) -> Point {
    let dx = (toward.x - node.position.x) / (node.width / 2), dy = (toward.y - node.position.y) / (node.height / 2)
    return abs(dx) >= abs(dy)
        ? Point(x: node.position.x + (dx < 0 ? -1 : 1) * node.width / 2, y: node.position.y)
        : Point(x: node.position.x, y: node.position.y + (dy < 0 ? -1 : 1) * node.height / 2)
}

/// A félkorong helye: a lapos oldala a doboz oldalára simul, a domború a vonal felé néz (geometry.js plugTransform).
private func plugMarkup(_ end: String, node: Idea, tip: Point, width: Double, color: String) -> String {
    let dx = (tip.x - node.position.x) / (node.width / 2), dy = (tip.y - node.position.y) / (node.height / 2)
    let normal = abs(dx) >= abs(dy) ? Point(x: dx < 0 ? -1 : 1, y: 0) : Point(x: 0, y: dy < 0 ? -1 : 1)
    let angle = atan2(-normal.y, -normal.x) * 180 / Double.pi
    let size = max(16, width * 6)
    return "<path class=\"wire-arrow wire-plug\" data-arrow-end=\"\(end)\" data-plug=\"\" d=\"M0 -.5A.5 .5 0 0 0 0 .5Z\" transform=\"translate(\(number(tip.x)) \(number(tip.y))) rotate(\(number(angle))) scale(\(number(size)))\" fill=\"\(color)\" stroke=\"none\" pointer-events=\"none\"/>"
}

/// Fájlt tároló objektum (szöveg, kép, hang, dokumentum) a vásznon: felül fájlnév, középen tartalom, alul megjegyzés.
private func fileBox(_ node: Idea, file: CanvasFile, base: String, interactive: Bool, exported: Bool, text: String?,
                     graphics: VisualTheme.Graphics?, siteHost: String?) -> String {
    let url = escaped(attachmentAddress(file, base: base))
    let filename = escaped(file.displayName(image: node.isImage))
    let download = escaped(file.commonURL ?? "/api/box-file" + base + "?id=" + encodeQuery(node.id))
    let packageIcon = uiIcon("package")
    let ext = escaped(((file.filename ?? file.asset) as NSString).pathExtension.uppercased())
    func downloadControl(_ label: String, classes: String = "node-download") -> String {
        if interactive {
            return "<button type=\"button\" class=\"\(classes)\" title=\"\(filename)\" aria-label=\"Letöltés · \(filename)\" data-download=\"\(download)\">\(packageIcon)\(label)</button>"
        }
        return exported ? "<a class=\"\(classes)\" href=\"\(download)\" aria-label=\"Letöltés · \(filename)\">\(packageIcon)\(label)</a>" : "<span class=\"\(classes)\">\(label)</span>"
    }
    let header = file.showFilename != false ? "<header class=\"node-file-name\">\(downloadControl("<span>\(filename)</span>"))</header>" : ""
    let content: String
    switch node.root {
    case "image":
        content = "<img alt=\"\(filename)\" src=\"\(url)\"\(file.asset.lowercased().hasSuffix(".svg") ? " class=\"is-svg\"" : "")/>"
    case "audio":
        content = """
            <div class="node-audio" data-audio-player="">
              <audio hidden="hidden" preload="metadata" src="\(url)"></audio>
              <button type="button" class="button" data-audio-toggle="" aria-label="Lejátszás" title="Lejátszás">\(uiIcon("play"))</button>
              <input type="range" min="0" max="0" step="any" disabled="disabled" data-audio-seek="" aria-label="Lejátszási pozíció"/>
              <small data-audio-time="">0:00</small>
              <small data-audio-status="" role="status"></small>
            </div>
            """
    case "text":
        // A mentett görgetési helyzetet a megtekintő szkriptje állítja be (viewer.js).
        let scroll = node.scroll.map { " data-scroll-x=\"\(number($0.x))\" data-scroll-y=\"\(number($0.y))\"" } ?? ""
        content = "<div class=\"node-note\" data-font-size=\"\(number(node.fontSize))\"\(scroll)>\(fileTextHTML(node, text: text))</div>"
    default:
        content = "<div class=\"node-document\"><span class=\"node-document-icon\">\(packageIcon)<b>\(ext)</b></span>\(downloadControl("Letöltés", classes: "node-download button small"))</div>"
    }
    let marker = node.link.map { link in
        "<p class=\"node-link-caption\" data-link-kind=\"\(link.kind.rawValue)\">\(uiIcon(link.kind == .url ? "website" : "link"))<span>\(escaped(linkCaption(link)))</span></p>"
    } ?? ""
    let comment = node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" :
        "<footer class=\"node-comment formatted-text align-\(node.alignment.rawValue)\">\(markdownHTML(visibleComment(node)))</footer>"
    let below = marker + comment
    let geometry = boxGeometry(node, graphics: graphics)
    let chrome = elevationShadow(node, geometry: geometry, graphics: graphics) +
        boxSurface(node, geometry: geometry, graphics: graphics, interactive: interactive)
    let translated = chrome.isEmpty ? "" : "<g transform=\"translate(\(number(node.position.x)) \(number(node.position.y)))\">\(chrome)</g>"
    let outline = frameOutline(node)
    let framed = outline.isEmpty ? "" : "<g transform=\"translate(\(number(node.position.x)) \(number(node.position.y)))\">\(outline)</g>"
    // A fájlnév a doboz felett, a link és a megjegyzés alatta, egyetlen foreignObjectben normál
    // (nem abszolút) elrendezéssel: a Safari így is jó helyre rajzolja, és nagyításkor kevesebb a munka.
    let top = node.position.y - node.height / 2 - 30
    let height = 30 + node.height + (below.isEmpty ? 0 : 4000)
    let underneath = below.isEmpty ? "" : "<div class=\"node-below\">\(below)</div>"
    // Publikus fájl: pillangó ikon a fájlnév-sor fölött középen.
    let publicMark = node.webPublic == true
        ? "<svg class=\"ui-icon web-public-mark\" x=\"\(number(node.position.x - 10))\" y=\"\(number(top - 24))\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" color=\"\(escaped(node.textColor))\" pointer-events=\"none\"><use href=\"/icons.svg#butterfly\"/></svg>" : ""
    return """
        \(translated)\(publicMark)<foreignObject class="node-file-frame" x="\(number(node.position.x - node.width / 2))" y="\(number(top))" width="\(number(node.width))" height="\(number(height))"><div xmlns="http://www.w3.org/1999/xhtml" class="node-file-stack" style="color:\(escaped(node.textColor))"><div class="node-above" style="height:30px">\(header)</div><div data-file-ink="\(escaped(node.textColor))" style="height:\(number(node.height))px" class="node-file node-\(node.root)\(node.isImage ? "" : " mode-" + node.resolvedBackgroundMode.rawValue)"><div class="node-body">\(content)</div></div>\(underneath)</div></foreignObject>\(framed)
        """
}

package func boardSVG(_ board: Worksheet, noteBase: String? = nil, siteHost: String? = nil, assetBase: String? = nil, mode: String? = nil,
              fileText: (Idea) -> String? = { _ in nil }) -> String {
    renderWorksheetCanvas(board.painted(mode: mode), noteBase: noteBase, siteHost: siteHost, assetBase: assetBase, fileText: fileText).svg
}

/// - Parameter fileText: szövegfájl-objektum (`text`, `code`, `csv`) tartalma; a vásznon csak az eleje jelenik meg.
package func renderWorksheetCanvas(_ board: Worksheet, noteBase: String?, siteHost: String?, assetBase: String? = nil,
                           fileText: (Idea) -> String? = { _ in nil }) -> (svg: String, tooltipNodes: [Idea]) {
    let graphics = Themes.catalog.first { $0.id == board.appearance?.theme }?.graphics
    // Vászonszín háttérmód: a doboz felülete a munkalap háttérszínét kapja (editor.js surfaceColor).
    var board = board
    for index in board.nodes.indices where board.nodes[index].backgroundMode == .canvas { board.nodes[index].fill = board.backgroundColor }
    // Szövegkörbefuttatás: a konténer szövege kikerüli a közvetlen gyermekdobozait; alapból be, `autoLayout: false` kapcsolja ki.
    let flowing = Set(board.nodes.filter { $0.autoLayout != false && $0.isContainer }.map(\.id))
    var obstacles: [String: [TextObstacle]] = [:]
    if !flowing.isEmpty {
        let places = Dictionary(board.nodes.map { ($0.id, $0.position) }, uniquingKeysWith: { first, _ in first })
        for child in board.nodes where !child.isJunction {
            guard let parent = child.parent, flowing.contains(parent), let center = places[parent] else { continue }
            obstacles[parent, default: []].append(TextObstacle(x: child.position.x - center.x, y: child.position.y - center.y,
                                                               width: child.width, height: child.height))
        }
    }
    let drawings = board.nodes.map { ideaDrawing($0, graphics: graphics, obstacles: obstacles[$0.id] ?? []) }
    let renderedIdeas = drawings.map(\.node)
    let nodes = Dictionary(uniqueKeysWithValues: renderedIdeas.map { ($0.id, $0) })
    // Adatvonalak: nyíl nélkül, félkoronggal; a grafikon forrása a bekötött táblázat (több közül az utolsó vonalé).
    var dataLinks = Set<String>(), chartSources: [String: Idea] = [:]
    for index in board.edges.indices where isDataLink(board.edges[index], nodes: nodes) {
        let edge = board.edges[index]
        dataLinks.insert(edge.id)
        board.edges[index].startArrow = false
        board.edges[index].endArrow = false
        if let a = edge.source.flatMap({ nodes[$0] }), let b = edge.target.node.flatMap({ nodes[$0] }) {
            if a.type == "chart" { chartSources[a.id] = b } else { chartSources[b.id] = a }
        }
    }
    // A kép kerete a tartalom tényleges széleihez igazodik (nem az origó köré szimmetrikus).
    var bounds = (minX: Double.infinity, minY: Double.infinity, maxX: -Double.infinity, maxY: -Double.infinity)
    func include(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        bounds = (min(bounds.minX, x - rx), min(bounds.minY, y - ry), max(bounds.maxX, x + rx), max(bounds.maxY, y + ry))
    }
    for drawing in drawings {
        let node = drawing.node
        var extentX = max(node.width/2, drawing.extentX)
        var extentY = max(node.height/2, drawing.extentY)
        if node.isBox {
            switch node.animation ?? .none {
            case .pulse: (extentX, extentY) = (extentX * 1.09, extentY * 1.09)
            case .rock: (extentX, extentY) = (extentX + extentY * 0.14, extentY + extentX * 0.14)
            case .hop: (extentX, extentY) = (extentX * 1.045, extentY * 1.06 + 17)
            case .none, .blink: break
            }
        }
        let padding: Double = node.elevated == true ? 84 : 40
        include(node.position.x, node.position.y, extentX + padding, extentY + padding)
        if node.isJunction && !node.text.isEmpty {
            let reach = node.width / 2 + 4 + textWidth(node.text, size: 14)
            include(node.position.x, node.position.y, reach + 40, reach + 40)
        }
        if node.file != nil {
            // A fájlnév a doboz felett, a link és a megjegyzés alatta áll.
            include(node.position.x, node.position.y - node.height / 2 - 30, node.width / 2 + padding, padding)
            if node.link != nil || !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                include(node.position.x, node.position.y + node.height / 2 + 60, node.width / 2 + padding, padding)
            }
        } else if node.link != nil {
            include(node.position.x, node.position.y + node.height / 2 + 20, node.width / 2 + padding, padding)
        }
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
    let containers = Set(renderedIdeas.filter(\.isContainer).map(\.id))
    // A konténer és a teljes tartalma egy tömb a sorrendben: ami a konténer fölött van és nem a része,
    // az a tartalmát is kitakarja. Testvérek között: előbb a konténerek, aztán a nagyobb doboz.
    // Kiemelt rétegben csak a méret számít (a kisebb takarja a nagyobbat), a konténer-szabály ott nem hat.
    let bySize: (IdeaDrawing, IdeaDrawing) -> Bool = { $0.node.width * $0.node.height > $1.node.width * $1.node.height }
    let siblings: (IdeaDrawing, IdeaDrawing) -> Bool = { a, b in
        let outerA = containers.contains(a.node.id), outerB = containers.contains(b.node.id)
        return outerA != outerB ? outerA : bySize(a, b)
    }
    let lower = drawings.filter { !elevated.contains($0.node.id) }
    let lowerIDs = Set(lower.map(\.node.id))
    let inner = Dictionary(grouping: lower) { drawing -> String in
        guard let parent = drawing.node.parent, parent != drawing.node.id, lowerIDs.contains(parent) else { return "" }
        return parent
    }
    var ordered: [IdeaDrawing] = []
    var placed = Set<String>()
    var stack = Array(inner["", default: []].sorted(by: siblings).reversed())
    while let drawing = stack.popLast() {
        guard placed.insert(drawing.node.id).inserted else { continue }
        ordered.append(drawing)
        stack.append(contentsOf: inner[drawing.node.id, default: []].sorted(by: siblings).reversed())
    }
    ordered += lower.filter { !placed.contains($0.node.id) }.sorted(by: siblings)
    ordered += drawings.filter { elevated.contains($0.node.id) }.sorted(by: bySize)
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
    // Oda-vissza kötés (A → B és B → A): mindkét vonal a saját haladási irányához képest jobbra tolódik (a két doboz
    // eltolt helyéből számolva), így egymás mellett futnak; az eltolás a két vonal vastagságával és nyílhegyével nő
    // (geometry.js edgeGeometry, pairShift).
    var routes: [String: Double] = [:]
    for edge in board.edges {
        guard let from = edge.source, let to = edge.target.node else { continue }
        routes[from + ">" + to] = max(routes[from + ">" + to] ?? 0, edge.lineWidth)
    }
    let edges = board.edges.compactMap { edge -> (layer: Int, markup: String)? in
        var sourceNode = edge.source.flatMap { nodes[$0] }
        var targetNode = edge.target.node.flatMap { nodes[$0] }
        if let from = sourceNode, let to = targetNode, from.id != to.id, let partner = routes[to.id + ">" + from.id],
           !dataLinks.contains(edge.id), !isInside(to, from), !isInside(from, to) {
            let across = to.position.x - from.position.x, down = to.position.y - from.position.y
            let length = (across * across + down * down).squareRoot()
            if length > 0 {
                // A nyílhegy hossza (geometry.js arrowLength); a fél szélessége a fél hossza.
                func arrow(_ width: Double) -> Double { min(width * 6.75, 13.5 + (width - 2) * 2) }
                func reach(_ own: Double, _ other: Double) -> Double { arrow(own) / 2 + other / 2 + 4 }
                let gap = max(12, reach(edge.lineWidth, partner), reach(partner, edge.lineWidth)) / 2
                let shift = Point(x: -down / length * gap, y: across / length * gap)
                sourceNode?.position = Point(x: from.position.x + shift.x, y: from.position.y + shift.y)
                targetNode?.position = Point(x: to.position.x + shift.x, y: to.position.y + shift.y)
            }
        }
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
        if dataLinks.contains(edge.id), let sourceNode, let targetNode {
            // Adatvonal: mindig a doboz másik doboz felé eső oldalának közepéhez csatlakozik.
            beginning = sideMidpoint(sourceNode, toward: target)
            ending = sideMidpoint(targetNode, toward: source)
        } else if targetInside, let sourceNode, let targetNode {
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
        // A vonal a nyílhegy talpáig tart, nem a csúcsáig (editor.js wireDrawing, geometry.js wireArrow): vastag vonal
        // különben kilógna a nyílhegy mellett. Két nyílhegy rövid, egyenes vonalon legfeljebb a fél hosszig ér.
        let arrowLength = wireArrowLength(edge.strokeWidth)
        let headLimit = !points.isEmpty || !(edge.hasStartArrow && edge.hasEndArrow)
            ? Double.infinity : hypot(ending.x - beginning.x, ending.y - beginning.y) / 2
        func head(_ tip: Point, _ toward: Point, _ shown: Bool) -> (length: Double, base: Point) {
            let distance = hypot(toward.x - tip.x, toward.y - tip.y)
            let length = min(arrowLength, distance, headLimit)
            guard shown, distance > 0 else { return (length, tip) }
            return (length, Point(x: tip.x + (toward.x - tip.x) * length / distance, y: tip.y + (toward.y - tip.y) * length / distance))
        }
        let startHead = head(beginning, points.first ?? ending, edge.hasStartArrow)
        let endHead = head(ending, points.last ?? beginning, edge.hasEndArrow)
        let lineCorners = corners.isEmpty ? corners
            : roundedWireCorners([startHead.base] + points + [endHead.base], wide: edge.type == .lightning)
        let segments = lineCorners.isEmpty
            ? command + " " + (points + [endHead.base]).map(pair).joined(separator: " ")
            : lineCorners.map { "L \(pair($0.entry)) Q \(pair($0.corner)) \(pair($0.exit))" }.joined(separator: " ") + " L " + pair(endHead.base)
        let drawing = "M \(pair(startHead.base)) \(segments)"
        let taper = custom == nil && (edge.type == .arc || rise > 0)
            && (edge.appearance == .plain || edge.appearance == .thick) && (edge.hasStartArrow || edge.hasEndArrow)
            ? taperedWireArc(edge, from: beginning, control: points.first ?? arcControl(beginning, ending), to: ending) : nil
        for point in vertices { include(point.x, point.y, 40, 40) }
        let color = escaped(edge.strokeColor)
        let motion = wireAnimation(edge, from: beginning, to: ending)
        if !motion.gradient.isEmpty { definitions.append(motion.gradient) }
        let label = edge.label.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let inlineLabel = edge.labelInLine == true && label != nil
        let gapID = "wire-gap-" + edge.id
        let marker = "arrow-" + edge.id
        // Rövid, kétnyilas vonalon a nyílhegyek kisebbek a szokottnál: ilyenkor külön rajzolt nyílhegy kell (a jelölő mérete fix).
        let usesMarkers = taper == nil && !inlineLabel && headLimit >= arrowLength
        var markers = ""
        if usesMarkers && ((edge.hasStartArrow && sourceNode != nil) || (edge.hasEndArrow && targetNode != nil)) {
            let pulse = edge.animated == true && edge.appearance == .thick
                ? "<animateTransform attributeName=\"transform\" type=\"scale\" additive=\"sum\" values=\"1;1.12;1\" dur=\"3s\" repeatCount=\"indefinite\"/>" : ""
            definitions.append("""
                <marker id="\(marker)" color="\(color)" markerUnits="userSpaceOnUse" markerWidth="\(number(arrowLength))" markerHeight="\(number(arrowLength))" viewBox="0 0 10 10" refX="0" refY="5" orient="auto-start-reverse" overflow="visible"><path d="M 1 0 L -9 -5 L -9 5 Z" transform="translate(9 5)" fill="currentColor">\(pulse)</path></marker>
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
            heads += arrow("source", tip: beginning, toward: points.first ?? ending, length: taper?.startLength ?? startHead.length)
        }
        if edge.hasEndArrow && (targetNode == nil || !usesMarkers) {
            heads += arrow("target", tip: ending, toward: points.last ?? beginning, length: taper?.endLength ?? endHead.length)
        }
        if dataLinks.contains(edge.id), let sourceNode, let targetNode {
            heads += plugMarkup("source", node: sourceNode, tip: beginning, width: edge.strokeWidth, color: color)
            heads += plugMarkup("target", node: targetNode, tip: ending, width: edge.strokeWidth, color: color)
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
        // Vonalak rétege (editor.js wireLayers): minden vonal minden doboz fölött fut, a Kiemelt objektumok alatt;
        // a data-connection (táblázat ↔ grafikon adatvonal) mindig minden objektum mögött van.
        let wireLayer = dataLinks.contains(edge.id) ? 0 : freeWireLayer
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
        // A felirat mindig eredeti betűmérettel és arányokkal látszik: ha a vonalba nem fér el, a vonal fölé kerül.
        let gapPadding = min(8, room / 5)
        let hasGap = inlineLabel && room >= 2 && labelRadius <= room - gapPadding - min(20, room / 3)
        var labelAttributes = ""
        var displayedRadius = labelRadius
        if hasGap {
            let padding = gapPadding
            let gap = number(displayedRadius + padding), extent = number(
                (vertices.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0) + 40 + 2 * lineWidth
            )
            let clip = "M -\(extent) -\(extent) H -\(gap) V \(extent) H -\(extent) Z M \(gap) -\(extent) H \(extent) V \(extent) H \(gap) Z"
            definitions.append("<clipPath id=\"\(gapID)\"><path d=\"\(clip)\" transform=\"\(transform)\"/></clipPath>")
            labelAttributes = " dominant-baseline=\"central\""
        } else if inlineLabel && noteBase != nil {
            definitions.append("<clipPath id=\"\(gapID)\"><path/></clipPath>")
        }
        let clearance = samples.reduce(0.0) { offset, point in
            let x = point.x - center.x, y = point.y - center.y
            return abs(x * cosine + y * sine) <= labelRadius ? min(offset, y * cosine - x * sine) : offset
        }
        let labelY = hasGap ? 0 : clearance - lineWidth / 2 - 10 - (fontSize - 14) / 4
        let padding = max(28, fontSize + 12)
        include(center.x - sine * labelY, center.y + cosine * labelY,
                abs(cosine) * displayedRadius + padding, abs(sine) * displayedRadius + padding)
        return (wireLayer, wirePath(gap: hasGap) + """
            <text class="wire-label" transform="\(transform)" y="\(number(labelY))"\(labelAttributes) font-family="system-ui, sans-serif" font-size="\(number(fontSize))" font-weight="\(fontWeight)" text-anchor="middle" stroke="none" fill="\(color)">\(escaped(label))</text>
            """)
    }
    let base = assetBase ?? noteBase ?? ""
    let project = base.split(separator: "/").first.flatMap { $0.removingPercentEncoding }
    let path = (noteBase ?? assetBase).flatMap { base in
        try? WorksheetPath(base.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) })
    }
    /// A link célja (href) és előnézete: .web mappánál a prezentáció, munkalapnál a céllap képe.
    func target(_ link: NodeLink) -> (href: String, preview: String?)? {
        switch link.kind {
        case .web:
            guard let project, let url = link.webReference?.url(in: project) else { return nil }
            return (url, url + "_tn-preview")
        case .sheet:
            guard let path, let href = link.worksheetLink?.destination(from: path) else { return nil }
            return (href, "/api/preview" + (href == "/" ? "" : href) + "?fill=1")
        case .url:
            guard let path, let href = link.worksheetLink?.destination(from: path) else { return nil }
            return (href, "/api/link-preview?url=" + encodeQuery(link.target))
        }
    }
    func render(_ drawing: IdeaDrawing) -> String {
        let node = drawing.node
        let destination = node.link.flatMap(target)
        let graphic: String
        if let file = node.file {
            graphic = fileBox(node, file: file, base: assetBase ?? noteBase ?? "", interactive: noteBase != nil, exported: assetBase != nil,
                              text: node.isTextFile ? fileText(node) : nil, graphics: graphics, siteHost: siteHost)
        } else if node.type == "chart" {
            graphic = chartBox(node, source: chartSources[node.id], base: assetBase ?? noteBase ?? "", interactive: noteBase != nil, graphics: graphics)
        } else {
            graphic = nodeSVG(drawing, siteHost: siteHost, graphics: graphics, interactive: noteBase != nil, preview: node.fillsWithPreview ? destination?.preview : nil)
        }
        let classes = nodeClasses(node, hasChildren: containers.contains(node.id))
        guard noteBase != nil else { return "<g class=\"\(classes)\">\(graphic)</g>" }
        let tag = destination == nil ? "g" : "a"
        var linked = destination.map { " data-link=\"true\" href=\"\(escaped($0.href))\"" } ?? ""
        if node.link?.kind == .web {
            linked += " data-web-presentation=\"true\" target=\"_blank\" rel=\"noopener noreferrer\""
        } else if node.link?.worksheetLink?.isExternal(siteHost: siteHost) == true {
            linked += " target=\"_blank\" rel=\"noopener noreferrer\""
        }
        let geometry = "data-x=\"\(node.position.x)\" data-y=\"\(node.position.y)\" data-width=\"\(node.width)\" data-height=\"\(node.height)\" data-shape=\"\(node.shape.rawValue)\" data-parent=\"\(node.parent ?? "")\""
        return "<\(tag) id=\"object-\(node.id)\" class=\"\(classes)\" data-node=\"\(node.id)\" data-type=\"\(node.type)\" \(geometry)\(linked) aria-label=\"\(escaped(node.name))\">\(graphic)</\(tag)>"
    }
    let wiresByLayer = Dictionary(grouping: edges, by: \.layer)
    var scene: [String] = []
    for (index, drawing) in ordered.enumerated() {
        scene.append(contentsOf: wiresByLayer[index, default: []].map(\.markup))
        scene.append(render(drawing))
    }
    scene.append(contentsOf: wiresByLayer[ordered.count, default: []].map(\.markup))
    if bounds.minX > bounds.maxX { bounds = (-360, -240, 360, 240) }
    // Legalább 720 × 480-as kép, a tartalom közepére igazítva.
    let centerX = (bounds.minX + bounds.maxX) / 2, centerY = (bounds.minY + bounds.maxY) / 2
    let spanX = max(720, bounds.maxX - bounds.minX), spanY = max(480, bounds.maxY - bounds.minY)
    let originX = centerX - spanX / 2, originY = centerY - spanY / 2
    let width = number(spanX)
    let height = number(spanY)
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
        "<rect x=\"\(number(originX))\" y=\"\(number(originY))\" width=\"\(width)\" height=\"\(height)\" fill=\"\(fill)\"/>"
    }
    let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" class="canvas passive-canvas" role="\(noteBase == nil ? "img" : "group")" aria-label="\(escaped(board.title))" width="\(width)" height="\(height)" viewBox="\(number(originX)) \(number(originY)) \(width) \(height)">
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

package func worksheetMarkdown(_ worksheet: Worksheet) -> String {
    func inline(_ text: String) -> String {
        let syntax = "\\`*_{}[]<>()#+-.!|"
        return text.map { syntax.contains($0) ? "\\" + String($0) : String($0) }.joined()
    }
    var sections = ["# \(inline(worksheet.title))\n"]
    if let text = worksheet.text, !text.isEmpty { sections.append(text) }
    for node in worksheet.nodes where !node.isJunction {
        if node.file != nil {
            sections.append("## \(inline(node.name))\n")
            if !node.text.isEmpty { sections.append(node.text) }
        } else if !node.text.isEmpty {
            sections.append(node.text)
        }
    }
    if !worksheet.edges.isEmpty {
        sections.append("## Kapcsolatok\n")
        let names = Dictionary(uniqueKeysWithValues: worksheet.nodes.map { ($0.id, inline($0.name)) })
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
