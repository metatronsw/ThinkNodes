import Foundation

// Szabadkézi (filc) rajz és papírfelületek a téma `graphics.sketch` és `graphics.paper` beállításához.
// A Public/sketch.js párja: ugyanaz az algoritmus és ugyanaz az álvéletlen-sorozat, így az SVG-export és a szerkesztő
// rajza egyezik (Tests/Fixtures/sketch.json). A kattintható terület és a szöveg helye a szabályos alak marad.

/// Az azonosító 32 bites hash-e (FNV-1a; sketch.js sketchSeed).
func sketchSeed(_ text: String) -> UInt32 {
    var hash: UInt32 = 2166136261
    for byte in text.utf8 { hash ^= UInt32(byte); hash = hash &* 16777619 }
    return hash
}

/// Mulberry32 álvéletlen-generátor (sketch.js generator).
struct SketchRandom {
    var state: UInt32
    mutating func next() -> Double {
        state &+= 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296
    }
}

/// Egy tizedesre kerekítve, a JavaScript `Math.round` és számkiírás szerint ("-0" helyett "0", egész szám tizedes nélkül).
private func sketchNumber(_ value: Double) -> String {
    let rounded = (value * 10 + 0.5).rounded(.down) / 10
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
}
private func sketchPair(_ x: Double, _ y: Double) -> String { sketchNumber(x) + " " + sketchNumber(y) }

enum SketchOutline: Equatable {
    case points([(x: Double, y: Double)])
    case ellipse(Double, Double)
    static func == (a: SketchOutline, b: SketchOutline) -> Bool {
        switch (a, b) {
        case let (.ellipse(x1, y1), .ellipse(x2, y2)): x1 == x2 && y1 == y2
        case let (.points(p), .points(q)): p.count == q.count && zip(p, q).allSatisfy { $0.x == $1.x && $0.y == $1.y }
        default: false
        }
    }
}

/// A lekerekített doboz szabadkézi változata enyhén letört sarkú (sketch.js sketchOutline).
func sketchOutline(_ shape: Shape, width: Double, height: Double, vertices: [(x: Double, y: Double)]?) -> SketchOutline {
    let x = width / 2, y = height / 2
    if shape == .ellipse { return .ellipse(x, y) }
    if let vertices, !vertices.isEmpty { return .points(vertices) }
    let cut = shape == .rounded ? min(x, y, 9) : 0
    return .points(cut > 0 ? [(-x+cut,-y), (x-cut,-y), (x,-y+cut), (x,y-cut), (x-cut,y), (-x+cut,y), (-x,y-cut), (-x,-y+cut)]
        : [(-x,-y), (x,-y), (x,y), (-x,y)])
}

struct SketchPen {
    var random: SketchRandom

    private struct Side { var a: (Double, Double); var b: (Double, Double); var c1: (Double, Double); var c2: (Double, Double) }

    private mutating func side(_ start: (x: Double, y: Double), _ end: (x: Double, y: Double), rough: Double, over: Double) -> Side {
        let dx = end.x - start.x, dy = end.y - start.y, length = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy)
        let ux = dx / length, uy = dy / length, nx = -uy, ny = ux
        let bow = rough * min(3.2, 0.6 + length / 90)
        let before = over > 0 ? (0.4 + random.next() * 0.8) * over : 0
        let after = over > 0 ? (0.4 + random.next() * 0.8) * over : 0
        let ax = start.x - ux * before + (random.next() - 0.5) * 2 * rough * 0.6
        let ay = start.y - uy * before + (random.next() - 0.5) * 2 * rough * 0.6
        let bx = end.x + ux * after + (random.next() - 0.5) * 2 * rough * 0.6
        let by = end.y + uy * after + (random.next() - 0.5) * 2 * rough * 0.6
        let k1 = (random.next() - 0.5) * 2 * bow, k2 = (random.next() - 0.5) * 2 * bow
        return Side(a: (ax, ay), b: (bx, by), c1: (start.x + dx / 3 + nx * k1, start.y + dy / 3 + ny * k1),
                    c2: (start.x + dx * 2 / 3 + nx * k2, start.y + dy * 2 / 3 + ny * k2))
    }

    /// Ellipszis (sketch.js loop): a körvonal (`open`) egyetlen, a bal oldalon induló, ott pontosan össze nem érő vonal.
    private mutating func loop(_ rx: Double, _ ry: Double, rough: Double, open: Bool) -> String {
        let steps = max(12, min(28, Int(((rx + ry) / 14 + 0.5).rounded(.down))))
        var start = random.next() * Double.pi * 2, sweep = Double.pi * 2, drift = 0.0
        if open {
            start = Double.pi + (start / (Double.pi * 2) - 0.5) * 0.5
            sweep += (random.next() - 0.35) * 0.3
            let size = rough * (1.2 + random.next() * 1.8)
            drift = random.next() < 0.5 ? -size : size
        }
        var points: [(Double, Double)] = []
        for i in 0...steps {
            let angle = start + sweep * Double(i) / Double(steps)
            let wobble = (random.next() - 0.5) * 2 * rough + drift * Double(i) / Double(steps)
            points.append((cos(angle) * (rx + wobble), sin(angle) * (ry + wobble)))
        }
        var d = "M" + sketchPair(points[0].0, points[0].1)
        for i in 1..<(points.count - 1) {
            let p = points[i], q = points[i + 1]
            d += " Q" + sketchPair(p.0, p.1) + " " + sketchPair((p.0 + q.0) / 2, (p.1 + q.1) / 2)
        }
        return d + " L" + sketchPair(points[points.count - 1].0, points[points.count - 1].1)
    }

    /// Sarkos alak körvonala egyetlen folytonos vonalként (sketch.js line).
    private mutating func line(_ points: [(x: Double, y: Double)], rough: Double) -> String {
        func jitter() -> Double { (random.next() - 0.5) * 2 * rough * 0.6 }
        var x = points[0].x + jitter()
        var y = points[0].y + jitter()
        var d = "M" + sketchPair(x, y)
        for i in points.indices {
            let last = i == points.count - 1
            let over = last ? rough * (2 + random.next() * 3) : 0
            let aside = last ? rough * (random.next() - 0.2) * 2 : 0
            let target = points[(i + 1) % points.count]
            let dx = target.x - x, dy = target.y - y, length = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy)
            let nx = -dy / length, ny = dx / length
            let ex = target.x + dx / length * over + nx * aside + jitter()
            let ey = target.y + dy / length * over + ny * aside + jitter()
            let bow = rough * min(3.2, 0.6 + length / 90)
            let k1 = (random.next() - 0.5) * 2 * bow, k2 = (random.next() - 0.5) * 2 * bow
            d += " C" + sketchPair(x + dx / 3 + nx * k1, y + dy / 3 + ny * k1) + " " + sketchPair(x + dx * 2 / 3 + nx * k2, y + dy * 2 / 3 + ny * k2) + " " + sketchPair(ex, ey)
            x = ex; y = ey
        }
        return d
    }

    /// A kitöltés zárt alakja és a `passes` darab körvonal-útvonal (sketch.js sketchPaths).
    static func paths(seed: UInt32, outline: SketchOutline, rough: Double, passes: Int) -> (fill: String, strokes: [String]) {
        var pen = SketchPen(random: SketchRandom(state: seed))
        switch outline {
        case let .ellipse(rx, ry):
            let fill = pen.loop(rx, ry, rough: rough * 0.5, open: false) + "Z"
            return (fill, (0..<passes).map { _ in pen.loop(rx, ry, rough: rough, open: true) })
        case let .points(points):
            func curve(_ side: Side) -> String {
                " C" + sketchPair(side.c1.0, side.c1.1) + " " + sketchPair(side.c2.0, side.c2.1) + " " + sketchPair(side.b.0, side.b.1)
            }
            let edges = points.indices.map { pen.side(points[$0], points[($0 + 1) % points.count], rough: rough * 0.5, over: 0) }
            let fill = "M" + sketchPair(edges[0].a.0, edges[0].a.1) + edges.map(curve).joined() + "Z"
            let strokes = (0..<passes).map { _ in pen.line(points, rough: rough) }
            return (fill, strokes)
        }
    }
}

/// A vonal második húzásának eltolása (sketch.js sketchShift).
func sketchShift(_ seed: UInt32, rough: Double) -> (Double, Double) {
    var random = SketchRandom(state: seed ^ 0x9E3779B9)
    let x = (random.next() - 0.5) * 2.4 * rough, y = (random.next() - 0.5) * 2.4 * rough
    return ((x * 10 + 0.5).rounded(.down) / 10, (y * 10 + 0.5).rounded(.down) / 10)
}
func sketchShiftText(_ seed: UInt32, rough: Double) -> String {
    let (x, y) = sketchShift(seed, rough: rough)
    return sketchNumber(x) + " " + sketchNumber(y)
}

/// A cetli színe: a szín fehérrel félig keverve (sketch.js stickyColor).
func stickyColor(_ hex: String) -> String {
    guard hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return hex }
    return "#" + [16, 8, 0].map { shift in
        let channel = Double((value >> shift) & 255) * 0.5 + 255 * 0.5
        return String(format: "%02x", Int((channel + 0.5).rounded(.down)))
    }.joined()
}

/// Papírfajta: táblázat és CSV → cetli, szövegfájl (.md, .txt) → füzetlap (editor.js paperKind). A kódfájl nem papír:
/// a téma szokásos (szabadkézi) dobozán áll, sorvonalak nélkül.
func paperKind(_ node: Idea, _ graphics: VisualTheme.Graphics?) -> String? {
    guard let paper = graphics?.paper, node.file != nil, ![.empty, .free].contains(node.resolvedBackgroundMode) else { return nil }
    if node.type == "table" || node.type == "csv" { return paper.grid == "sticky" ? "sticky" : nil }
    return node.type == "text" && paper.text == "notebook" ? "notebook" : nil
}
