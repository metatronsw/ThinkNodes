import Foundation
import Testing
import VaporTesting
@testable import ThinkCore
@testable import ThinkNodes

// SVG-renderelés: dobozok, vonalak, animációk, feliratok.

@Test func autoSizeSurvivesRoundTripAndFitsSVGText() throws {
    let idea = Idea(id: "fit", text: "# Cím\n\nTörzs", position: Point(x: 0, y: 0),
                    width: 240, height: 100, shape: .rectangle, backgroundMode: .free, fitText: true)
    let board = Worksheet(title: "AutoSize", nodes: [idea])
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(board))
    #expect(saved.nodes[0].fitText == true)
    #expect(saved.nodes[0].backgroundMode == .free)
    #expect(saved.nodes[0].fontSize == 16)
    let svg = boardSVG(saved)
    #expect(!svg.contains("rx=\"0\""))
    #expect(!svg.contains("node-surface"))
    #expect(boardSVG(saved, noteBase: "/sheet").contains("rx=\"0\" fill=\"none\" pointer-events=\"fill\""))
    #expect(svg.contains("font-weight=\"700\">Cím</tspan>"))
    #expect(svg.contains("font-weight=\"400\">Törzs</tspan>"))
}

@Test func transparentAndBlurredBoxSurfacesExportWithTheirContent() throws {
    let position = Point(x: 0, y: 0)
    let note = Idea(id: "note", type: "text", file: CanvasFile(asset: "file-note", filename: "jegyzet.txt"),
                    position: position, backgroundMode: .free)
    let asset = UUID().uuidString.lowercased() + ".png"
    let image = Idea(id: "image", type: "image", file: CanvasFile(asset: asset, alphaEnabled: false),
                     position: position, backgroundMode: .free)
    let transparent = Worksheet(title: "Átlátszó", nodes: [note, image])
    try transparent.validate()
    let exported = boardSVG(transparent, fileText: { $0.id == "note" ? "Tartalom" : nil })
    #expect(exported.contains("Tartalom") && exported.contains("<img"))
    #expect(!exported.contains("node-surface") && !exported.contains("pointer-events=\"fill\""))
    #expect(!exported.contains("background-color:") && !exported.contains("box-background-blur"))
    var blurred = transparent
    blurred.nodes[0].backgroundMode = .blurred
    blurred = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(blurred))
    #expect(blurred.nodes[0].backgroundMode == .blurred)
    let svg = boardSVG(blurred)
    #expect(svg.contains(#"opacity=".98" filter="url(#box-background-blur)""#))
    #expect(svg.contains(#"<feGaussianBlur stdDeviation="2"/>"#))
    #expect(svg.components(separatedBy: "node-surface").count == 2)
    blurred.nodes[0].backgroundMode = .empty
    let outline = boardSVG(blurred)
    #expect(outline.contains(##"class="node-surface" fill="none" stroke="\##(blurred.nodes[0].fill)""##))
    #expect(!outline.contains("box-background-blur"))
}

@Test func textFileBoxFrameCanBeSwitchedOffInEveryBackgroundMode() throws {
    var note = Idea(id: "note", type: "text", file: CanvasFile(asset: "file-note", filename: "jegyzet.txt"), position: Point(x: 0, y: 0))
    #expect(!boardSVG(Worksheet(title: "Keret", nodes: [note])).contains(#"class="node-surface" fill="\#(note.fill)" stroke="none""#))
    note.frame = false
    var board = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(Worksheet(title: "Keret", nodes: [note])))
    try board.validate()
    #expect(board.nodes[0].frame == false)
    #expect(boardSVG(board).contains(#"class="node-surface" fill="\#(note.fill)" stroke="none""#))
    board.nodes[0].backgroundMode = .translucent
    let translucent = boardSVG(board)
    #expect(translucent.contains(#"stroke="none" stroke-width="1.6" fill-opacity=".75""#))
    board.nodes[0].backgroundMode = .blurred
    #expect(boardSVG(board).contains(#"class="node-frame" fill="none" stroke="none""#))
    // Közönséges dobozra a kapcsoló nem hat.
    var box = Idea(id: "box", text: "Doboz", position: Point(x: 0, y: 0))
    box.frame = false
    #expect(!boardSVG(Worksheet(title: "Keret", nodes: [box])).contains(#"stroke="none" stroke-width="1.6""#))
}

@Test func maximumWireThicknessIncludesDottedAndAnimatedStrokes() throws {
    var edge = Connection(id: "wide", sourcePoint: Point(x: 0, y: 0), target: ConnectionTarget(point: Point(x: 200, y: 0)),
                          appearance: .dotted, animated: true, width: 32)
    try Worksheet(title: "Vonal", edges: [edge]).validate()
    #expect(edge.lineWidth == 32)
    edge.appearance = .thick
    #expect(edge.lineWidth == 32 && edge.pulseWidth == 32)
    #expect(boardSVG(Worksheet(title: "Vonal", edges: [edge])).contains(#"values="32.000;32.000;32.000""#))
    edge.width = 33
    #expect(throws: Abort.self) { try Worksheet(title: "Vonal", edges: [edge]).validate() }
}

@Test func svgShortensBoxLabelsWithoutClipping() throws {
    var node = Idea(id: "box", text: "# Hosszú cím\n\n**Nagy szöveg**", position: Point(x: 0, y: 0),
                    width: 64, height: 40, shape: .ellipse, fontSize: 80)
    let bounded = boardSVG(Worksheet(title: "Doboz", nodes: [node]))
    #expect(!bounded.contains("<clipPath"))
    #expect(!bounded.contains("clip-path="))
    // Ha egy sor sem fér el a dobozban, nem rajzolunk sort vagy pontokat az eredeti betűmérettel.
    #expect(!bounded.contains("…") && bounded.contains(#"<text class="node-text""#))
    node.backgroundMode = .free
    let board = Worksheet(title: "Doboz", nodes: [node])
    try board.validate()
    let free = boardSVG(board)
    #expect(!free.contains("<clipPath"))
    #expect(!free.contains("textLength"))
    #expect(!free.contains("…"))
    #expect(!free.contains("node-surface"))
}

@Test func containerStylesAndJunctionsSurviveRoundTrip() throws {
    let origin = Point(x: 0, y: 0)
    var container = Idea(id: "group", text: "Konténer", position: origin, link: NodeLink(kind: .sheet, target: "aloldal"), container: true, locked: true)
    let child = Idea(id: "child", text: "Ötlet\n\n**törzs** *kiemelés*", hideText: false, position: origin, width: 300, height: 120, textColor: "#663300",
                     fontSize: 17, italic: true, underline: true, alignment: .left, parent: "group")
    let junction = Idea(id: "joint", type: "junction", text: "Kapocs", position: Point(x: 200, y: 80), width: 34, height: 34,
                        shape: .ellipse, angle: 30)
    let line = Connection(id: "line", source: child.id, target: ConnectionTarget(node: junction.id))
    let second = Connection(id: "other-line", source: junction.id, target: ConnectionTarget(point: origin), endArrow: false)
    var board = Worksheet(title: "Ábra", gridSpacing: 32,
                          nodes: [child, junction, container], edges: [line, second])
    try board.validate()
    var largeTitle = board
    largeTitle.nodes[0].fontSize = 10000
    try largeTitle.validate()
    var legacy = board
    var duplicate = line
    duplicate.id = "parallel"
    legacy.edges.append(duplicate)
    #expect(throws: Abort.self) { try legacy.validate() }
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(board))
    try saved.validate()
    #expect(saved.nodes.first?.parent == container.id)
    #expect(saved.nodes.first?.fontSize == 17)
    #expect(saved.nodes[1].angle == 30)
    #expect(saved.nodes.last?.locked == true)
    #expect(saved.nodes.last?.link == NodeLink(kind: .sheet, target: "aloldal"))
    let svg = boardSVG(saved)
    #expect(!svg.contains("worksheet-grid"))
    #expect(!svg.contains("<pattern"))
    #expect(svg.contains("text-anchor=\"start\""))
    #expect(!svg.contains("text-decoration=\"underline\" font-size"), "a Dőlt/Aláhúzott gombok megszűntek")
    #expect(!svg.contains("font-style=\"normal\""), "a Dőlt gomb nem írja felül a markdown dőlt szöveget")
    #expect(svg.contains("r=\"17.000\" fill=\"#dce9ff\""))
    #expect(svg.contains("rotate(30.000)") && svg.contains(">Kapocs</text>"))
    #expect(svg.contains("stroke-width=\"6.4\" data-locked-outline=\"\""))
    #expect(svg.contains("font-size=\"13\" fill=\"#182335\">aloldal</text>"))
    #expect(svg.contains("has-children") && svg.contains("node is-junction"))
    board.nodes[1].text = ""
    try board.validate()
    let groupStart = try #require(svg.range(of: "aria-label=\"Konténer\" transform="))
    let edgeStart = try #require(svg.range(of: "marker-end=\"url(#arrow-line)"))
    let childStart = try #require(svg.range(of: "aria-label=\"Ötlet\" transform="))
    // Minden vonal minden doboz fölött van (a konténer és a tartalma fölött is).
    #expect(groupStart.lowerBound < edgeStart.lowerBound && childStart.lowerBound < edgeStart.lowerBound)
    let plain = boardSVG(board)
    #expect(!plain.contains("worksheet-grid"))
    #expect(!plain.contains("stroke=\"none\"/>"))
    board.edges = [line]
    #expect(throws: Abort.self) { try board.validate() }
    board.edges = []
    board.nodes = [container]
    container.parent = container.id
    board.nodes[0] = container
    #expect(throws: Abort.self) { try board.validate() }
    board.nodes[0].parent = "missing"
    #expect(throws: Abort.self) { try board.validate() }
    var fileLink = Worksheet(title: "Link", nodes: [Idea(id: "doc", type: "document", file: CanvasFile(asset: "file-doc", filename: "a.pdf"),
                                                     position: origin, link: NodeLink(kind: .url, target: "https://example.org"))])
    #expect(throws: Abort.self) { try fileLink.validate() }
    fileLink.nodes[0].link = nil
    try fileLink.validate()
}

@Test func elevatedBoxesKeepTheirShadowAndStayOutsideContainers() throws {
    let position = Point(x: 0, y: 0)
    let group = Idea(id: "group", text: "Kiemelt konténer", position: position, container: true, elevated: true)
    let child = Idea(id: "child", text: "Tartalom", position: position, parent: group.id)
    let ordinary = Idea(id: "ordinary", text: "Másik doboz", position: position)
    let file = Idea(id: "file", type: "text", file: CanvasFile(asset: "file-kiemelt", filename: "kiemelt.txt"), position: position, elevated: true)
    var sheet = Worksheet(title: "Kiemelés", nodes: [group, child, ordinary, file])
    sheet = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(sheet))
    try sheet.validate()
    #expect(sheet.nodes[0].elevated == true && sheet.nodes[2].elevated == nil)
    let svg = boardSVG(sheet, noteBase: "/sheet")
    #expect(!svg.contains("elevated-clip"))
    #expect(!svg.contains("feDropShadow"))
    #expect(svg.components(separatedBy: "node-shadow").count == 3)
    let ordinaryLayer = try #require(svg.range(of: #"data-node="ordinary""#))
    let raisedLayer = try #require(svg.range(of: #"data-node="group""#))
    let childLayer = try #require(svg.range(of: #"data-node="child""#))
    #expect(ordinaryLayer.lowerBound < raisedLayer.lowerBound && raisedLayer.lowerBound < childLayer.lowerBound)
    sheet.nodes[1].elevated = true
    #expect(throws: Abort.self) { try sheet.validate() }
}

@Test func codeBlockWhitespace() throws {
    let block = try #require(canvasMarkdown("```\n  a  b\n\n c\n```").first)
    let rows = wrapMarkdown(block.runs, columns: 40, preformatted: true)
    #expect(rows.map { $0.pieces.map(\.text).joined() } == ["  a  b", "", " c"])
}

@Test func bodyJustificationSurvivesRoundTrip() throws {
    let node = Idea(id: "box", text: "# Cím\n\nEz egy rövid példa több szövegsorral.",
                    position: Point(x: 0, y: 0), width: 130, height: 180, justified: true)
    let board = Worksheet(title: "Munkalap", text: "Bevezetés", textJustified: true, nodes: [node])
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(board))
    #expect(saved.textJustified == true)
    #expect(saved.nodes[0].justified == true)
    let svg = boardSVG(saved)
    // A tördelt sorok célszélességet kapnak; a szóközöket a böngésző tágítja (Public/justify.js), nem betűritkítás.
    #expect(svg.contains("data-justify=") && !svg.contains("lengthAdjust=\"spacing\""))
}

@Test func connectionTypesAndAppearances() throws {
    let from = Point(x: -100, y: 0)
    let to = Point(x: 100, y: 0)
    var edge = Connection(id: "wire", sourcePoint: from, target: ConnectionTarget(point: to), endArrow: false)
    func render() -> String { boardSVG(Worksheet(title: "Vonalak", edges: [edge])) }

    edge.type = .sCurve
    #expect(render().contains("M -100.000 0.000 L 100.000 0.000"))
    edge.target.point?.y = 60
    edge.appearance = .dotted
    let curve = render()
    #expect(curve.contains("C 0.000 0.000 0.000 60.000"))
    #expect(curve.contains("stroke-linecap=\"round\" stroke-dasharray=\"0 16.000\""))

    edge.type = .lightning
    edge.target.point = to
    edge.appearance = .thick
    let zigzag = render()
    #expect(zigzag.contains("L -71.429 -16.000 -42.857 16.000 -14.286 -16.000 14.286 16.000 42.857 -16.000 71.429 16.000 100.000 0.000"))
    #expect(zigzag.contains("stroke-width=\"4.000\""))
    #expect(edge.type.label == "Zigzag")
    edge.type = .arc
    #expect(render().contains("Q 0.000 -56.000"))
    edge.type = .rope
    #expect(render().contains("Q 0.000 170.000"))

    let previous = #"{"id":"wire","srcPt":{"x":0,"y":0},"target":{"point":{"x":50,"y":20}},"style":"rope"}"#
    let decoded = try JSONDecoder().decode(Connection.self, from: Data(previous.utf8))
    #expect(decoded.type == .rope && decoded.appearance == .plain && !decoded.hasEndArrow)
    let saved = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
    #expect(!saved.contains("\"style\""))
}

@Test func arcWidthFollowsArrowDirectionsInSVG() throws {
    var edge = Connection(id: "arc", sourcePoint: Point(x: 0, y: 0),
                          target: ConnectionTarget(point: Point(x: 200, y: 0)),
                          type: .arc, width: 8, startArrow: false, endArrow: true)
    func render() -> String { boardSVG(Worksheet(title: "Íves vonal", edges: [edge])) }
    func widths(_ svg: String) throws -> [Int] {
        let suffix = try #require(svg.components(separatedBy: "data-wire-taper=\"\" d=\"M ").dropFirst().first)
        let drawing = try #require(suffix.components(separatedBy: " Z\"").first)
        let points = drawing.components(separatedBy: " L ").map { pair in pair.split(separator: " ").compactMap { Double($0) } }
        try #require(points.count == 66 && points.allSatisfy { $0.count == 2 })
        return [0, 16, 32].map { i in
            Int(hypot(points[i][0] - points[65 - i][0], points[i][1] - points[65 - i][1]).rounded())
        }
    }
    #expect(try widths(render()) == [2, 5, 8])
    #expect(render().contains("scale(25.500)"))
    edge.startArrow = true
    #expect(try widths(render()) == [8, 2, 8])
    edge.endArrow = false
    #expect(try widths(render()) == [8, 5, 2])
    edge.startArrow = false
    #expect(!render().contains("data-wire-taper"))
}

@Test func animatedConnectionsRoundTripAndRenderSVG() throws {
    var edge = Connection(id: "animated", sourcePoint: Point(x: 0, y: 0),
                          target: ConnectionTarget(point: Point(x: 100, y: 0)),
                          animated: true, startArrow: true, endArrow: true)
    edge = try JSONDecoder().decode(Connection.self, from: JSONEncoder().encode(edge))
    #expect(edge.animated == true)
    func render() -> String { boardSVG(Worksheet(title: "Animáció", edges: [edge])) }
    #expect(render().contains("stroke=\"url(#wire-gradient-animated)\""))
    #expect(render().contains("dur=\"12s\" repeatCount=\"indefinite\""))
    #expect(render().contains("<stop offset=\".25\" stop-color=\"currentColor\"/>"))
    #expect(render().contains("<stop offset=\".5\" stop-color=\"currentColor\" stop-opacity=\".5\"/>"))
    #expect(render().contains("<stop offset=\".75\" stop-color=\"currentColor\"/>"))
    edge.appearance = .thick
    #expect(render().contains("attributeName=\"stroke-width\" values=\"4.000;5.800;4.000\""))
    #expect(render().contains("type=\"scale\" additive=\"sum\""))
    edge.label = "Inline"
    let above = render()
    #expect(!above.contains("clip-path="))
    #expect(above.contains(#"font-size="26.000" font-weight="700""#))
    edge.labelInLine = true
    edge = try JSONDecoder().decode(Connection.self, from: JSONEncoder().encode(edge))
    #expect(edge.labelInLine == true)
    let labeled = render()
    // A vonalba nem férő felirat a vonal fölé kerül, nem nyomódik össze és nem vágódik le.
    #expect(!labeled.contains("wire-gap-animated") && !labeled.contains("textLength"))
    #expect(labeled.contains(#"data-arrow-end="target""#))
    edge.appearance = .dashed
    #expect(render().contains(##"clip-path="url(#wire-gap-animated)""##))
    #expect(render().contains(#"font-size="14.000" font-weight="400""#))
    edge.width = 5
    #expect(render().contains(#"font-size="17.000" font-weight="400""#))
    edge.width = nil
    edge.labelInLine = nil
    #expect(!render().contains("clip-path="))
    #expect(render().contains("attributeName=\"stroke-dashoffset\" values=\"0;-12.000;0\""))
    edge.appearance = .dotted
    edge.endArrow = false
    #expect(render().contains("attributeName=\"stroke-dashoffset\" values=\"0;16.000\""))
    edge.animated = false
    #expect(!render().contains("<animate"))
}

@Test func boxAnimationsRoundTripAndRenderSVG() throws {
    var box = Idea(id: "box", text: "Doboz", position: Point(x: 0, y: 0))
    for (mode, track): (BoxAnimation, String) in [
        (.pulse, "type=\"scale\""), (.blink, "attributeName=\"opacity\""),
        (.rock, "type=\"rotate\""), (.hop, "type=\"translate\""),
    ] {
        box.animation = mode
        let saved = try JSONDecoder().decode(Idea.self, from: JSONEncoder().encode(box))
        #expect(saved.animation == mode)
        let svg = boardSVG(Worksheet(title: "Animáció", nodes: [saved]))
        #expect(svg.contains("data-box-animation=\"\(mode.rawValue)\""))
        #expect(svg.contains(track))
        #expect(svg.contains("repeatCount=\"indefinite\""))
    }
    box.animation = BoxAnimation.none
    #expect(!boardSVG(Worksheet(title: "Animáció", nodes: [box])).contains("data-box-animation"))
}

@Test func wiresRenderAboveEveryBoxExceptElevatedOnes() throws {
    let container = Idea(id: "container", text: "Konténer", position: Point(x: 0, y: 0),
                         width: 600, height: 320, container: true)
    let source = Idea(id: "source", text: "Kezdőpont", position: Point(x: -120, y: 0), parent: container.id)
    let target = Idea(id: "target", text: "Végpont", position: Point(x: 120, y: 0), animation: .pulse, parent: container.id)
    let edge = Connection(id: "wire", source: source.id, target: ConnectionTarget(node: target.id))
    let raised = Idea(id: "raised", text: "Kiemelt", position: Point(x: 0, y: 200), elevated: true)
    let svg = boardSVG(Worksheet(title: "Rétegek", nodes: [raised, source, target, container], edges: [edge]), noteBase: "/retegek")
    let containerOffset = try #require(svg.range(of: "id=\"object-container\"")).lowerBound
    let wireOffset = try #require(svg.range(of: "class=\"wire\"")).lowerBound
    let sourceOffset = try #require(svg.range(of: "id=\"object-source\"")).lowerBound
    let targetOffset = try #require(svg.range(of: "id=\"object-target\"")).lowerBound
    let raisedOffset = try #require(svg.range(of: "id=\"object-raised\"")).lowerBound
    // A vonal minden doboz fölött van, a Kiemelt objektum alatt.
    #expect(containerOffset < wireOffset && sourceOffset < wireOffset && targetOffset < wireOffset)
    #expect(wireOffset < raisedOffset)
}

@Test func wiresBetweenBoxesInDifferentContainersRenderAboveBothContainers() throws {
    let first = Idea(id: "first", text: "Első", position: Point(x: 0, y: 0), width: 300, height: 300, container: true)
    let second = Idea(id: "second", text: "Második", position: Point(x: 500, y: 0), width: 300, height: 300, container: true)
    let a = Idea(id: "a", text: "A", position: Point(x: 0, y: 0), width: 100, height: 60, parent: first.id)
    let b = Idea(id: "b", text: "B", position: Point(x: 500, y: 0), width: 100, height: 60, parent: second.id)
    let edge = Connection(id: "wire", source: a.id, target: ConnectionTarget(node: b.id))
    let svg = boardSVG(Worksheet(title: "Két konténer", nodes: [a, b, first, second], edges: [edge]), noteBase: "/ket-kontener")
    let offset = { (id: String) in try #require(svg.range(of: "id=\"object-\(id)\"")).lowerBound }
    let wire = try #require(svg.range(of: "class=\"wire\"")).lowerBound
    #expect(try offset("first") < wire)
    #expect(try offset("second") < wire)
}

@Test func boxesAboveAContainerAlsoCoverItsContents() throws {
    let container = Idea(id: "container", text: "Konténer", position: Point(x: 0, y: 0),
                         width: 300, height: 300, container: true)
    let child = Idea(id: "child", text: "Tartalom", position: Point(x: 0, y: 0), width: 100, height: 60, parent: container.id)
    let cover = Idea(id: "cover", text: "Rálógó doboz", position: Point(x: 150, y: 0), width: 500, height: 400)
    let svg = boardSVG(Worksheet(title: "Kitakarás", nodes: [cover, child, container]), noteBase: "/kitakaras")
    let offset = { (id: String) in try #require(svg.range(of: "id=\"object-\(id)\"")).lowerBound }
    #expect(try offset("container") < offset("child"))
    #expect(try offset("child") < offset("cover"))
}

@Test(arguments: [
    (Shape.triangle, 3, "30.000"),
    (.pentagon, 5, "55.587"),
    (.hexagon, 6, "60.000"),
    (.parallelogram, 4, "46.500"),
])
func polygonBoxesRoundTrip(shape: Shape, corners: Int, borderX: String) throws {
    let box = Idea(id: "box", text: "Doboz", position: Point(x: 0, y: 0), width: 120, height: 80, shape: shape)
    let edge = Connection(id: "wire", source: box.id, target: ConnectionTarget(point: Point(x: 200, y: 0)), endArrow: false)
    let sheet = Worksheet(title: "Sokszögek", nodes: [box], edges: [edge])
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(sheet))
    #expect(saved.nodes.first?.shape == shape)
    let svg = boardSVG(saved, noteBase: "/polygons")
    let polygon = try #require(svg.components(separatedBy: "<polygon points=\"").dropFirst().first)
    #expect(polygon.prefix(while: { $0 != "\"" }).split(separator: " ").count == corners)
    #expect(svg.contains("data-shape=\"\(shape.rawValue)\""))
    #expect(svg.contains("M \(borderX) 0.000 L 200.000 0.000"))
}

@Test func experimentalAnchorsLoadAsAutomaticConnections() throws {
    let box = Idea(id: "box", text: "Doboz", position: Point(x: 0, y: 0), width: 120, height: 80, shape: .rectangle)
    var second = box
    second.id = "second"
    second.position = Point(x: 200, y: 60)
    let data = Data(#"{"id":"wire","source":"box","sourceAnchor":"n","target":{"node":"second","anchor":"sw"}}"#.utf8)
    let edge = try JSONDecoder().decode(Connection.self, from: data)
    let sheet = Worksheet(title: "Pontok", nodes: [box, second], edges: [edge])
    try sheet.validate()
    // A vonal a nyílhegy talpáig tart (13,5 képponttal a végpont előtt).
    #expect(boardSVG(sheet).contains("M 60.000 18.000 L 127.069 38.121"))
    let encoded = String(decoding: try JSONEncoder().encode(edge), as: UTF8.self)
    #expect(!encoded.lowercased().contains("anchor"))
}

/// BUGS.md: kikapcsolt előnézetnél (`staticPreview`) a linkes doboz szövege csak a dobozban látszik, alatta nem ismétlődik.
@Test func staticPreviewLinkBoxShowsTextOnlyOnce() {
    var withPreview = Idea(id: "kartya", type: "preview", text: "Egyszer látszik", position: Point(x: 0, y: 0),
                           link: NodeLink(kind: .url, target: "https://example.com"))
    #expect(boardSVG(Worksheet(title: "Link", nodes: [withPreview])).contains("node-below"))
    withPreview.staticPreview = true
    let svg = boardSVG(Worksheet(title: "Link", nodes: [withPreview]))
    #expect(!svg.contains("node-below"))
    #expect(svg.contains("Egyszer látszik"))
}

@Test func chartIsAStandaloneObjectFedByTheConnectedTable() throws {
    var table = Idea(id: "adat", type: "csv", file: CanvasFile(asset: "adat.csv", filename: "adat.csv"), position: Point(x: 0, y: 0))
    table.width = 300; table.height = 200
    var chart = Idea(id: "rajz", type: "chart", position: Point(x: 500, y: 0))
    chart.width = 380; chart.height = 260
    chart.chart = ChartSettings(kind: "line", labels: 0, values: [1, 2], header: nil)
    let note = Idea(id: "doboz", text: "Megjegyzés", position: Point(x: 500, y: 400))
    let link = Connection(id: "adatvonal", source: "adat", target: ConnectionTarget(node: "rajz", point: nil))
    let arrow = Connection(id: "nyil", source: "doboz", target: ConnectionTarget(node: "rajz", point: nil))
    var sheet = Worksheet(title: "Grafikon", nodes: [table, chart, note], edges: [link, arrow])
    try sheet.validate()
    sheet = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(sheet))
    #expect(sheet.nodes[1].chart == chart.chart && sheet.nodes[1].file == nil)

    // Megtekintő: a grafikon helyőrzője a bekötött táblázat fájljára mutat; a táblázat táblázat marad.
    let text: (Idea) -> String? = { _ in "Hónap;Bevétel\nJan;1\n" }
    let viewer = boardSVG(sheet, noteBase: "/projekt/lap", fileText: text)
    #expect(viewer.contains("&quot;kind&quot;:&quot;line&quot;") && viewer.contains("data-chart-type=\"csv\""))
    #expect(viewer.contains("data-chart-source=\"/api/attachment/projekt/lap?inline=1&amp;name=adat") && viewer.contains("node-csv"))
    // Adatvonal: nyíl nélkül, mindkét végén félkorong; a másik dobozból jövő vonal közönséges nyíl marad.
    #expect(viewer.components(separatedBy: "data-plug").count == 3)
    #expect(!viewer.contains("id=\"arrow-adatvonal\"") && viewer.contains("id=\"arrow-nyil\""))
    // Az adatvonal a két doboz egymás felé eső oldalának közepéhez csatlakozik, és minden objektum mögött van.
    #expect(viewer.contains("translate(150.000 0.000)") && viewer.contains("translate(310.000 0.000)"))
    let plug = try #require(viewer.range(of: "data-plug")), firstBox = try #require(viewer.range(of: "class=\"node-surface\""))
    #expect(plug.lowerBound < firstBox.lowerBound)
    // A táblázat sarka 5 px-es, a grafikoné a szokásos.
    #expect(viewer.contains(#"width="300.000" height="200.000" rx="5""#) && viewer.contains(#"width="380.000" height="260.000" rx="12""#))

    // Bekötött táblázat nélkül (a táblázat törlése után) a grafikon megmarad, üresen.
    var alone = sheet
    alone.nodes.removeFirst()
    alone.edges.removeFirst()
    try alone.validate()
    let empty = boardSVG(alone, noteBase: "/projekt/lap", fileText: text)
    #expect(empty.contains("Nincs bekötött táblázat") && !empty.contains("data-chart-source") && !empty.contains("data-plug"))
    // Szkript nélküli kimenet (SVG-export, előnézeti kép): a grafikon doboza üres.
    #expect(!boardSVG(sheet, fileText: text).contains("node-chart\""))

    // Érvénytelen beállítás; grafikon-beállítás más típuson; fájl a grafikonon: a lap nem menthető.
    for wrong in [ChartSettings(kind: "radar"), ChartSettings(kind: "pie", labels: -2), ChartSettings(kind: "line", values: Array(0..<9))] {
        var bad = sheet
        bad.nodes[1].chart = wrong
        #expect(throws: (any Error).self) { try bad.validate() }
    }
    var bad = sheet
    bad.nodes[0].chart = chart.chart
    #expect(throws: (any Error).self) { try bad.validate() }
    bad = sheet
    bad.nodes[1].file = CanvasFile(asset: "adat.csv", filename: "adat.csv")
    #expect(throws: (any Error).self) { try bad.validate() }
}
