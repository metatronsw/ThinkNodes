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

@Test func transparentBoxSurfacesExportWithTheirContent() throws {
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
    // A megszűnt elmosott ("blurred") mód régi munkalapból kitöltött háttérként töltődik be.
    let old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(transparent)) as! [String: Any]
    var nodes = old["nodes"] as! [[String: Any]]
    nodes[0]["backgroundMode"] = "blurred"
    var legacy = old
    legacy["nodes"] = nodes
    var solid = try JSONDecoder().decode(Worksheet.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(solid.nodes[0].backgroundMode == nil)
    let svg = boardSVG(solid)
    #expect(!svg.contains("box-background-blur") && !svg.contains("feGaussianBlur"))
    #expect(svg.components(separatedBy: "node-surface").count == 2)
    solid.nodes[0].backgroundMode = .empty
    let outline = boardSVG(solid)
    #expect(outline.contains(##"class="node-surface" fill="none" stroke="\##(solid.nodes[0].fill)""##))
    // Vászonszín: közönséges dobozon is a munkalap háttérszíne a felület.
    var tinted = Worksheet(title: "Vászonszín", nodes: [Idea(id: "box", text: "Doboz", position: position, backgroundMode: .canvas)])
    tinted.background = "#123456"
    #expect(boardSVG(tinted).contains(##"class="node-surface" fill="#123456""##))
}

/// A vászonszín a paletta 0. színe: a régi "canvas" háttérmód betöltéskor 0. színű kitöltés lesz, és a 0. színű,
/// kitöltött doboz felülete a munkalap háttere (editor.js canvasSurface).
@Test func paletteColorZeroIsTheCanvasSurface() throws {
    let legacy = #"{"schemaVersion":3,"title":"Vászon","nodes":[{"id":"box","type":"box","text":"Doboz","position":{"x":0,"y":0},"fill":5,"backgroundMode":"canvas"}],"edges":[]}"#
    let board = try JSONDecoder().decode(Worksheet.self, from: Data(legacy.utf8))
    #expect(board.nodes[0].backgroundMode == nil)
    #expect(board.nodes[0].fill == "@0")
    let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(board)) as! [String: Any]
    #expect((saved["nodes"] as! [[String: Any]])[0]["fill"] as? Int == 0)
    var themed = board
    themed.appearance = Appearance()
    themed.background = "#123456"
    #expect(boardSVG(themed).contains(##"class="node-surface" fill="#123456""##))
    // Textúrás vásznon (Liquid Glass) a felület a vászon háttere a textúrával együtt: a doboz helyéhez igazított minta.
    var liquid = themed
    liquid.appearance = Appearance(theme: 4, palette: 1)
    let glass = boardSVG(liquid)
    #expect(glass.contains(##"<clipPath id="canvas-clip-box">"##))
    #expect(glass.contains(##"<use href="#canvas-art" transform="translate(-0.000 -0.000)"/>"##) || glass.contains(##"<use href="#canvas-art" transform="translate(0.000 0.000)"/>"##))
    #expect(glass.contains(##"class="node-surface" fill="none""##))
    #expect(glass.contains(##"<g id="canvas-art"><rect"##) && glass.contains("fx-aurora"))
    // Közvetlen (#hex) szín: változatlanul megmarad és úgy rajzolódik.
    themed.nodes[0].fill = "#a1b2c3"
    #expect(boardSVG(themed).contains(##"fill="#a1b2c3""##))
}

/// A .md fájldoboz: a sima sortörés egy új sor (nem kettő), a blokkok között annyi üres sor, ahány a forrásban.
@Test func markdownExactLinesKeepTheSourceSpacing() {
    let html = markdownHTML("# Cím\nelső\nmásodik\n\nharmadik\n\n\n- a\n- b", exactLines: true)
    #expect(!html.contains("data-sourcepos"))
    #expect(html.contains("első<br />\nmásodik"))
    #expect(html.contains(#"<p data-gap="1">harmadik"#))
    #expect(html.contains(#"<ul data-gap="2">"#))
    #expect(!html.contains(#"<li data-gap"#))
    #expect(!html.contains(#"<p data-gap="1">első"#))
    #expect(markdownHTML("a\nb") == markdownHTML("a\nb", exactLines: false))
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
    // Közönséges dobozra a kapcsoló nem hat.
    var box = Idea(id: "box", text: "Doboz", position: Point(x: 0, y: 0))
    box.frame = false
    #expect(!boardSVG(Worksheet(title: "Keret", nodes: [box])).contains(#"stroke="none" stroke-width="1.6""#))
}

/// A vonal vastagsága a méretből (1–3) és a téma szorzójából jön; a pontozott és a lüktető (vastag, animált) vonal sem
/// lehet 32-nél vastagabb (geometry.js edgePaint, maximumLineWidth).
@Test func maximumWireThicknessIncludesDottedAndAnimatedStrokes() throws {
    var edge = Connection(id: "wide", sourcePoint: Point(x: 0, y: 0), target: ConnectionTarget(point: Point(x: 200, y: 0)),
                          appearance: .dotted, animated: true, size: 3)
    try Worksheet(title: "Vonal", edges: [edge]).validate()
    // Erős témaszorzóval a vastagság eléri a felső korlátot (10,5 × 2 × 2 = 42 → 32), a pontozott sem nő tovább.
    let strong: [String: LineScale] = ["straight": .uniform(2)]
    edge.appearance = .thick
    edge.width = edge.scaledWidth(strong)
    #expect(edge.lineWidth == 32 && edge.pulseWidth == 32)
    edge.appearance = .dotted
    edge.width = edge.scaledWidth(strong)
    #expect(edge.width == 21 && edge.lineWidth == 32)
    // Téma nélkül: vastag, 3-as méret = 21, lüktetés 1,45-szörösre.
    edge.width = nil
    edge.appearance = .thick
    #expect(boardSVG(Worksheet(title: "Vonal", edges: [edge])).contains(#"values="21.000;30.450;21.000""#))
    edge.size = 4
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
                          type: .arc, size: 3, startArrow: false, endArrow: true)
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
    // 3-as méret (10,5): a vékony végtől (a vastagság negyede) a nyílig fokozatosan vastagodik; a nyílhegy ehhez méretezett.
    #expect(try widths(render()) == [3, 7, 11])
    #expect(render().contains("scale(30.500)"))
    edge.startArrow = true
    #expect(try widths(render()) == [11, 3, 11])
    edge.endArrow = false
    #expect(try widths(render()) == [11, 7, 3])
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
    // Sima vonal: egy kis pötty fut végig az útvonalon; két nyílnál oda-vissza (a gradiens animáció megszűnt).
    #expect(!render().contains("wire-gradient"))
    #expect(render().contains(#"<circle class="wire-dot" r="3.000""#))
    #expect(render().contains(#"keyPoints="0;1;0" keyTimes="0;0.5;1" repeatCount="indefinite""#))
    #expect(render().contains(#"dur="3.000s""#))
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
    edge.size = 2
    #expect(render().contains(#"font-size="17.000" font-weight="400""#))
    edge.size = nil
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

/// A vonalak kirajzolt útvonala a szerveren pontosan egyezzen a szerkesztőével: oda-vissza kötések eltolása a
/// vonalvastagság szerint, és a vonal vége a nyílhegy talpánál. Közös esetek: Tests/Fixtures/wires.json
/// (kliensoldali párja: Tests/Editor/wires.mjs, Public/geometry.js edgeGeometry / wireHeads / pairShift).
@Test func wirePathsMatchSharedFixtures() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/wires.json")
    enum Token: Decodable, Equatable {
        case command(String), number(Double)
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Double.self) { self = .number(number) } else { self = .command(try value.decode(String.self)) }
        }
    }
    struct Path: Decodable { let id: String; let path: [Token] }
    struct Case: Decodable { let name: String; let nodes: [Idea]; let edges: [Connection]; let paths: [Path] }
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: fixture))
    #expect(cases.count >= 12)
    let line = try NSRegularExpression(pattern: #"<path class="wire-line"[^>]* d="([^"]*)""#)
    let piece = try NSRegularExpression(pattern: #"[A-Za-z]|-?[0-9]+(?:\.[0-9]+)?"#)
    for item in cases {
        let svg = boardSVG(Worksheet(title: "Vonalak", nodes: item.nodes, edges: item.edges))
        let drawn = line.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)).map { String(svg[Range($0.range(at: 1), in: svg)!]) }
        #expect(drawn.count == item.paths.count, "Vonalak száma eltér: \(item.name)")
        for (d, expected) in zip(drawn, item.paths) {
            let tokens = piece.matches(in: d, range: NSRange(d.startIndex..., in: d)).map { match -> Token in
                let text = String(d[Range(match.range, in: d)!])
                return Double(text).map(Token.number) ?? .command(text)
            }
            let same = tokens.count == expected.path.count && zip(tokens, expected.path).allSatisfy { actual, wanted in
                switch (actual, wanted) {
                case let (.number(a), .number(b)): abs(a - b) < 0.002
                default: actual == wanted
                }
            }
            #expect(same, "Eltérés: \(item.name) / \(expected.id): \(d)")
        }
    }
}

/// A konténer szövegének körbefuttatása a szerveren pontosan egyezzen a szerkesztőével: közös esetek a
/// Tests/Fixtures/text-flow.json fájlban (kliensoldali párja: Tests/Editor/text-flow.mjs, Public/geometry.js labelLayout).
@Test func textFlowMatchesSharedFixtures() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/text-flow.json")
    struct Line: Decodable { let text: String; let x: Double; let y: Double; let anchor: String }
    struct Case: Decodable { let name: String; let nodes: [Idea]; let lines: [Line] }
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: fixture))
    #expect(cases.count >= 10)
    let row = try NSRegularExpression(pattern: #"<tspan text-anchor="(start|middle|end)"(?: data-justify="[^"]*")? x="([-0-9.]+)" y="([-0-9.]+)"[^>]*>([^<]*)</tspan>"#)
    for item in cases {
        let svg = boardSVG(Worksheet(title: "Körbefuttatás", nodes: item.nodes))
        let found = row.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)).map { match in
            (1...4).map { String(svg[Range(match.range(at: $0), in: svg)!]) }
        }
        #expect(found.count == item.lines.count, "Sorok száma eltér: \(item.name)")
        for (actual, expected) in zip(found, item.lines) {
            let x = try #require(Double(actual[1])), y = try #require(Double(actual[2]))
            #expect(actual[0] == expected.anchor && actual[3] == expected.text && abs(x - expected.x) < 0.002 && abs(y - expected.y) < 0.002,
                    "Eltérés: \(item.name) – „\(expected.text)” (\(expected.x), \(expected.y)) helyett „\(actual[3])” (\(x), \(y))")
        }
    }
}

@Test func formerAutoLayoutKeyLoadsAsTextFlow() throws {
    // A 2026-11-25-i első változat `autoLayout` néven írta a szövegkörbefuttatás kapcsolóját.
    let data = Data(#"{"id":"group","type":"box","text":"Konténer","pos":{"x":0,"y":0},"w":300,"h":200,"container":true,"autoLayout":false}"#.utf8)
    let box = try JSONDecoder().decode(Idea.self, from: data)
    #expect(box.textFlow == false)
    let saved = String(decoding: try JSONEncoder().encode(box), as: UTF8.self)
    #expect(saved.contains("\"textFlow\":false") && !saved.contains("autoLayout"))
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

/// Színezett kódfájl: az önálló SVG-be (letöltés, előnézeti kép) a színszabályok beágyazódnak; a megtekintő oldalon
/// (ott az app.css adja) és színezhető kódfájl nélkül nincs beágyazott stílus.
@Test func standaloneSVGEmbedsCodeColours() throws {
    let position = Point(x: 0, y: 0)
    let code = Idea(id: "code", type: "code", file: CanvasFile(asset: "file-code", filename: "adat.json"), position: position)
    let sheet = Worksheet(title: "Kód", nodes: [code])
    try sheet.validate()
    let text: (Idea) -> String? = { _ in "{\"a\": true}" }
    let exported = boardSVG(sheet, fileText: text)
    #expect(exported.contains("<span class=\"hl-k\">true</span>"))
    #expect(exported.contains("<style>.node-code {") && exported.contains(".hl-k { color: color-mix(in oklab, currentColor 35%, #d6336c); }"))
    let viewed = boardSVG(sheet, noteBase: "/sheet", fileText: text)
    #expect(viewed.contains("<span class=\"hl-k\">true</span>") && !viewed.contains("<style>"))
    var plain = sheet
    plain.nodes[0].file?.filename = "adat.py"
    #expect(!boardSVG(plain, fileText: text).contains("<style>"))
}

/// „Tartalom a dobozhoz” táblázat: saját, SVG-vel skálázott foreignObject (torzítás nélkül), a jegyzet üres; a beállítás
/// mentés után is megmarad.
@Test func contentFitTableIsScaledAsAWhole() throws {
    let text = #"{"cells":{},"format":"thinknodes-table","grid":true,"id":"tbl-fit","size":{"cols":5,"rows":20},"styles":[{}],"version":1}"#
    var node = Idea(id: "tb", type: "table", file: CanvasFile(asset: "file-tb", filename: "t.tntable"), position: Point(x: 0, y: 0))
    node.width = 420
    node.height = 260
    node.contentFit = true
    let saved = try JSONDecoder().decode(Worksheet.self, from: JSONEncoder().encode(Worksheet(title: "Táblázat", nodes: [node])))
    #expect(saved.nodes[0].contentFit == true)
    let svg = boardSVG(saved, fileText: { _ in text })
    // 20 sor × 24 px + 1 = 481 magas; (260 - 36) / 481 = 0,4657 (a szélesség: 370 / 401 = 0,92 – a kisebb számít).
    #expect(svg.contains(#"<g class="table-fit" transform="translate(-190.000 -112.000) scale(0.466)">"#))
    #expect(svg.contains(#"class="table-fit-note" style="width:401.000px;height:481.000px""#))
    #expect(svg.contains(#"<div class="node-note" data-font-size="16.000"></div>"#))
    // A táblázat HTML-je az SVG-ben (XML) is érvényes: a <col> önlezáró (különben az előnézeti kép betölthetetlen).
    #expect(svg.contains(#"<col style="width:80px"/>"#) && !svg.contains(#"<col style="width:80px">"#))
    node.contentFit = nil
    #expect(!boardSVG(Worksheet(title: "Táblázat", nodes: [node]), fileText: { _ in text }).contains("table-fit"))
}

/// „Tartalom a dobozhoz” CSV: a szerkesztő táblázatdokumentuma (editor.js csvDocument, Rendering.swift csvGridDocument)
/// skálázva. A sorok a szerkesztőével egyeznek (table-csv.js parseCSVRows: a záró üres sor is sor), az oszlopszélesség a
/// leghosszabb mező 13 px-es szélessége + 20 (48 és 420 között).
@Test func contentFitCSVUsesTheEditorTable() throws {
    #expect(csvEditorRows("név,érték\nalma,1\nkörte,22\n\n", separator: ",") == [["név", "érték"], ["alma", "1"], ["körte", "22"], [""]])
    #expect(csvEditorRows("a,\"b,\"\"c\"\"\"\r\n1,2", separator: ",") == [["a", "b,\"c\""], ["1", "2"]])
    #expect(csvEditorRows("\"\",x\n", separator: ",") == [["", "x"]])
    #expect(csvEditorRows("a;b\r\n\r\n", separator: ";") == [["a", "b"], [""]])
    let text = "név,érték\nalma,1\nkörte,22\n\n"
    var node = Idea(id: "cv", type: "csv", file: CanvasFile(asset: "file-cv", filename: "adat.csv"), position: Point(x: 0, y: 0))
    node.width = 300
    node.height = 200
    node.contentFit = true
    let svg = boardSVG(Worksheet(title: "CSV", nodes: [node]), fileText: { _ in text })
    // 4 sor × 24 + 1 = 97 magas; 2 × 51 + 1 = 103 széles; (200 - 36) / 97 = 1,691 (a szélesség: 250 / 103 = 2,43).
    #expect(svg.contains(#"class="table-fit-note" style="width:103.000px;height:97.000px""#))
    #expect(svg.contains(#"scale(1.691)"#) && svg.contains("tn-table") && !svg.contains("node-csv"))
    node.contentFit = nil
    let plain = boardSVG(Worksheet(title: "CSV", nodes: [node]), fileText: { _ in text })
    #expect(!plain.contains("table-fit") && plain.contains("node-csv"))
}

/// Az önálló SVG (letöltés, előnézeti kép) szigorú XML: ha bármelyik doboz HTML-je nem XHTML (pl. lezáratlan <col>),
/// a böngésző az előnézetet képként nem tölti be, és a főoldali kártyák háttere üres marad. Minden doboztípus egy lapon.
@Test func standaloneSVGIsWellFormedXMLForEveryBoxType() throws {
    let at = Point(x: 0, y: 0)
    var nodes = [
        Idea(id: "box", text: "# Cím\n\n- egy\n- kettő\n\n---\n\nsor  \ntörés & <jel>", position: at),
        Idea(id: "md", type: "text", file: CanvasFile(asset: "file-md", filename: "j.md"), position: Point(x: 300, y: 0)),
        Idea(id: "txt", type: "text", file: CanvasFile(asset: "file-txt", filename: "j.txt"), position: Point(x: 600, y: 0)),
        Idea(id: "code", type: "code", file: CanvasFile(asset: "file-js", filename: "a.js"), position: Point(x: 900, y: 0)),
        Idea(id: "csv", type: "csv", file: CanvasFile(asset: "file-csv", filename: "a.csv"), position: Point(x: 0, y: 300)),
        Idea(id: "table", type: "table", file: CanvasFile(asset: "file-tb", filename: "t.tntable"), position: Point(x: 300, y: 300)),
        Idea(id: "fit", type: "table", file: CanvasFile(asset: "file-tb2", filename: "u.tntable"), position: Point(x: 600, y: 300)),
        Idea(id: "image", type: "image", file: CanvasFile(asset: "kep.png", filename: "kep.png"), position: Point(x: 900, y: 300)),
        Idea(id: "audio", type: "audio", file: CanvasFile(asset: "hang.mp3", filename: "hang.mp3"), position: Point(x: 0, y: 600)),
        Idea(id: "doc", type: "document", file: CanvasFile(asset: "leiras.pdf", filename: "leiras.pdf"), position: Point(x: 300, y: 600)),
    ]
    nodes[6].contentFit = true
    nodes[0].text += "\n\n[link](https://example.com)"
    let table = #"{"cells":{"A1":{"v":"<b>&</b>"},"B2":{"v":1500}},"format":"thinknodes-table","grid":true,"id":"tbl-xml","size":{"cols":3,"rows":4},"styles":[{}],"version":1}"#
    let texts = ["md": "# Cím\nsor<br>\n\n- a\n- b\n\n---\n\n&nbsp; <i>x</i>", "txt": "a < b & c", "code": "if (a < b) { x = \"&\"; }",
                 "csv": "a,b\n1,<2>\n&,x", "table": table, "fit": table]
    let svg = boardSVG(Worksheet(title: "XML & <próba>", nodes: nodes), fileText: { texts[$0.id] })
    let parser = XMLParser(data: Data(svg.utf8))
    let parsed = parser.parse()
    #expect(parsed, "Az önálló SVG nem érvényes XML: \(parser.parserError.map(String.init(describing:)) ?? "?") (sor \(parser.lineNumber))")
}

/// A projektkártya háttere (PreviewRaster): fix 640 × 360-as, elmosott .webp az előnézeti SVG-ből. Csak ha a gépen van
/// `rsvg-convert` és `cwebp` (különben a szerver az SVG-előnézetet adja).
@Test(.enabled(if: PreviewRaster.available)) func previewRasterIsAFixedSizeWebP() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("raster-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("lap.svg"), target = folder.appendingPathComponent("lap.webp")
    // Szándékosan más arányú (magas) rajz: a kép kitölti a 16:9-et, levágva.
    try Data(boardSVG(Worksheet(title: "Raszter", nodes: [Idea(id: "a", text: "Doboz", position: Point(x: 0, y: 0)),
        Idea(id: "b", text: "Másik", position: Point(x: 0, y: 900))])).utf8).write(to: source)
    #expect(PreviewRaster.render(source: source, to: target))
    let data = try Data(contentsOf: target)
    #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF" && String(decoding: data[8..<12], as: UTF8.self) == "WEBP")
    #expect(data.count < 60_000)
    // A WebP mérete a fejlécből (VP8X: 24 bites szélesség-1 / magasság-1; VP8L: 14 bites mezők; VP8: 14 bites mezők).
    let chunk = String(decoding: data[12..<16], as: UTF8.self)
    func le(_ at: Int, _ count: Int) -> Int { (0..<count).reduce(0) { $0 | Int(data[at + $1]) << (8 * $1) } }
    let size: (Int, Int) = switch chunk {
    case "VP8X": (le(24, 3) + 1, le(27, 3) + 1)
    case "VP8L": { let bits = le(21, 4); return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1) }()
    default: (le(26, 2) & 0x3FFF, le(28, 2) & 0x3FFF)
    }
    #expect(size.0 == PreviewRaster.width && size.1 == PreviewRaster.height)
    // Egyetlen statikus képkocka: nincs animációs blokk (ANIM / ANMF), és a VP8X animáció-jelzője (0x02) sincs beállítva.
    #expect(data.range(of: Data("ANIM".utf8)) == nil && data.range(of: Data("ANMF".utf8)) == nil)
    if chunk == "VP8X" { #expect(data[20] & 0x02 == 0) }
    // A rajz teljesen fedi a képet (az elmosás pereme a képen kívül): nincs átlátszósági réteg.
    #expect(data.range(of: Data("ALPH".utf8)) == nil)
    if chunk == "VP8X" { #expect(data[20] & 0x10 == 0) }
}
