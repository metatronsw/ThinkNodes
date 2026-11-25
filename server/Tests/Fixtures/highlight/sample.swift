/// Swift: megjegyzés (egymásba ágyazott `/* */` is), szöveg (`\(…)` beágyazással, többsoros `"""`, nyers `#"…"#`),
/// szám, kulcsszó, attribútum (`@MainActor`), fordítási utasítás (`#if`), nagybetűs név (típus), függvényhívás,
/// pont utáni tag, írásjelek.
struct SwiftLanguage: CodeLanguage {
    let extensions = ["swift"]

    private static let keywords: Set<String> = [
        "Any", "Self", "any", "as", "associatedtype", "async", "await", "borrowing", "break", "case", "catch", "class", "consuming",
        "continue", "convenience", "default", "defer", "deinit", "didSet", "do", "else", "enum", "extension", "fallthrough", "false",
        "fileprivate", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "mutating", "nil",
        "nonisolated", "nonmutating", "override", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "some",
        "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "unowned", "var", "weak",
        "where", "while", "willSet",
    ]
    /// Csak bizonyos helyzetben kulcsszavak; névként is gyakoriak (`prefix(3)`, `set = …`), ezért ha hívás, értékadás
    /// vagy tagelérés követi őket, nem kapnak kulcsszó-színt.
    private static let contextual: Set<String> = [
        "actor", "dynamic", "final", "get", "indirect", "infix", "isolated", "lazy", "macro", "open", "operator", "optional",
        "package", "postfix", "precedencegroup", "prefix", "required", "set",
    ]
    /// Egymásba ágyazott szövegbeágyazások legnagyobb mélysége: a rekurzió korlátja.
    private static let maximumDepth = 24

    func scan(_ scanner: inout CodeScanner) {
        code(&scanner, depth: 0)
    }

    /// Kód olvasása a végéig, illetve `depth > 0` esetén a `\(` beágyazást záró `)` jelig (a jelet nem lépi át).
    private func code(_ scanner: inout CodeScanner, depth: Int) {
        var parentheses = 0
        while !scanner.atEnd {
            let byte = scanner.current, start = scanner.position
            switch byte {
            case _ where byte.isSpace:
                scanner.position += 1
            case UInt8(ascii: "/") where scanner.peek() == UInt8(ascii: "/"):
                scanner.scanLineComment()
            case UInt8(ascii: "/") where scanner.peek() == UInt8(ascii: "*"):
                blockComment(&scanner)
            case UInt8(ascii: "\""):
                string(&scanner, hashes: 0, depth: depth)
            case UInt8(ascii: "#"):
                var hashes = 0
                while scanner.peek(hashes) == UInt8(ascii: "#") { hashes += 1 }
                if scanner.peek(hashes) == UInt8(ascii: "\"") {
                    string(&scanner, hashes: hashes, depth: depth)
                } else if scanner.peek().isLetter {
                    scanner.position += 1
                    scanner.skipWhile { $0.isWord }
                    scanner.mark(.keyword, from: start)
                } else {
                    scanner.position += 1
                    scanner.mark(.punctuation, from: start)
                }
            case UInt8(ascii: "@") where scanner.peek().isLetter || scanner.peek() == UInt8(ascii: "_"):
                scanner.position += 1
                scanner.skipWhile { $0.isWord }
                scanner.mark(.keyword, from: start)
            case _ where byte.isDigit:
                number(&scanner)
            case UInt8(ascii: "`"):
                // `class` – kulcsszó névként: színezetlen.
                scanner.position += 1
                scanner.skipWhile { $0.isWord }
                if scanner.current == UInt8(ascii: "`") { scanner.position += 1 }
            case _ where byte.isLetter || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "$") || byte >= 0x80:
                scanner.skipWhile { $0.isWord || $0 == UInt8(ascii: "$") }
                let word = String(decoding: scanner.bytes[start..<scanner.position], as: UTF8.self)
                let member = start > 0 && scanner.bytes[start - 1] == UInt8(ascii: ".") && !(start > 1 && scanner.bytes[start - 2] == UInt8(ascii: "."))
                let next = scanner.nextSignificant
                if !member, Self.keywords.contains(word) {
                    scanner.mark(.keyword, from: start)
                } else if !member, Self.contextual.contains(word), !Self.followsName(next) {
                    scanner.mark(.keyword, from: start)
                } else if byte >= 65 && byte <= 90 {
                    scanner.mark(.type, from: start)
                } else if next == UInt8(ascii: "(") && scanner.current == next {
                    scanner.mark(.function, from: start)
                } else if member {
                    scanner.mark(.name, from: start)
                }
            default:
                if byte == UInt8(ascii: "(") { parentheses += 1 }
                if byte == UInt8(ascii: ")") {
                    if depth > 0 && parentheses == 0 { return }
                    parentheses -= 1
                }
                scanner.position += 1
                scanner.mark(.punctuation, from: start)
            }
        }
    }

    /// Ami egy név (és nem kulcsszó) után áll: hívás, értékadás, tagelérés, felsorolás vége.
    private static func followsName(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "(") || byte == UInt8(ascii: "=") || byte == UInt8(ascii: ".") || byte == UInt8(ascii: ",")
            || byte == UInt8(ascii: ")") || byte == UInt8(ascii: ":") || byte == UInt8(ascii: "]") || byte == 0
    }

    /// `/* … */`, egymásba ágyazva is; lezáratlanul a végéig tart.
    private func blockComment(_ scanner: inout CodeScanner) {
        let start = scanner.position
        var depth = 0
        while !scanner.atEnd {
            if scanner.starts(with: "/*") { depth += 1; scanner.position += 2 }
            else if scanner.starts(with: "*/") {
                depth -= 1
                scanner.position += 2
                if depth == 0 { break }
            } else { scanner.position += 1 }
        }
        scanner.position = min(scanner.position, scanner.end)
        scanner.mark(.comment, from: start)
    }

    /// Szám: tizedes (1_000.5), kitevő (1e-5), hexadecimális (0xFF), bináris, oktális.
    private func number(_ scanner: inout CodeScanner) {
        let start = scanner.position
        let prefixed = scanner.current == UInt8(ascii: "0") && scanner.peek().isLetter
        while !scanner.atEnd {
            let byte = scanner.current
            if byte.isWord || (byte == UInt8(ascii: ".") && scanner.peek().isDigit) { scanner.position += 1 }
            else if !prefixed, byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-"), scanner.peek(-1) | 0x20 == UInt8(ascii: "e"), scanner.peek().isDigit { scanner.position += 1 }
            else { break }
        }
        scanner.mark(.number, from: start)
    }

    /// Szöveg `hashes` darab `#` jellel (nyers szöveg) és egy vagy három idézőjellel. A beágyazás (`\(…)`, nyers
    /// szövegben `\#(…)`) belseje kódként színeződik. Az egysoros szöveg lezáratlanul a sor végéig tart.
    private func string(_ scanner: inout CodeScanner, hashes: Int, depth: Int) {
        var start = scanner.position
        scanner.position += hashes
        let multiline = scanner.starts(with: "\"\"\"")
        scanner.position += multiline ? 3 : 1
        func hashesFollow(_ offset: Int) -> Bool {
            for index in 0..<hashes where scanner.peek(offset + index) != UInt8(ascii: "#") { return false }
            return true
        }
        while !scanner.atEnd {
            let byte = scanner.current
            if byte == UInt8(ascii: "\n") && !multiline { break }
            if byte == UInt8(ascii: "\\") && hashesFollow(1) {
                if scanner.peek(1 + hashes) == UInt8(ascii: "("), depth < Self.maximumDepth {
                    scanner.mark(.string, from: start)
                    let open = scanner.position
                    scanner.position += 2 + hashes
                    scanner.mark(.punctuation, from: open)
                    code(&scanner, depth: depth + 1)
                    if scanner.current == UInt8(ascii: ")") {
                        let close = scanner.position
                        scanner.position += 1
                        scanner.mark(.punctuation, from: close)
                    }
                    start = scanner.position
                    continue
                }
                // Védett karakter (\" \\ \n …): a következő bájt nem zárhatja a szöveget.
                let next = scanner.peek(1 + hashes)
                scanner.position = min(scanner.position + 1 + hashes + (next == UInt8(ascii: "\n") ? 0 : 1), scanner.end)
                continue
            }
            if byte == UInt8(ascii: "\""), !multiline || scanner.starts(with: "\"\"\""), hashesFollow(multiline ? 3 : 1) {
                scanner.position += (multiline ? 3 : 1) + hashes
                break
            }
            scanner.position += 1
        }
        scanner.mark(.string, from: start)
    }
}
import Foundation
import Vapor

// Color references travel as integers. Old documents may still contain literal colors.
@propertyWrapper package struct StoredPaint: Codable, Equatable, Sendable {
    package var wrappedValue: String
    package init(wrappedValue: String) { self.wrappedValue = wrappedValue }
    package init(from decoder: Decoder) throws {
        let field = try decoder.singleValueContainer()
        if let id = try? field.decode(Int.self), (0..<64).contains(id) { wrappedValue = "@\(id)" }
        else { wrappedValue = try field.decode(String.self) }
    }
    package func encode(to encoder: Encoder) throws {
        var field = encoder.singleValueContainer()
        if let id = paintID(wrappedValue) { try field.encode(id) }
        else { try field.encode(wrappedValue) }
    }
}

func paintID(_ value: String) -> Int? {
    guard value.first == "@", let id = Int(value.dropFirst()), (0..<64).contains(id) else { return nil }
    return id
}

@propertyWrapper package struct OptionalPaint: Codable, Equatable, Sendable {
    package var wrappedValue: String?
    package init(wrappedValue: String?) { self.wrappedValue = wrappedValue }
    package init(from decoder: Decoder) throws { wrappedValue = try StoredPaint(from: decoder).wrappedValue }
    package func encode(to encoder: Encoder) throws {
        if let wrappedValue { try StoredPaint(wrappedValue: wrappedValue).encode(to: encoder) }
        else { var field = encoder.singleValueContainer(); try field.encodeNil() }
    }
}
extension KeyedDecodingContainer {
    func decode(_ type: OptionalPaint.Type, forKey key: Key) throws -> OptionalPaint {
        try decodeIfPresent(type, forKey: key) ?? OptionalPaint(wrappedValue: nil)
    }
}
extension KeyedEncodingContainer {
    package mutating func encode(_ paint: OptionalPaint, forKey key: Key) throws {
        if let value = paint.wrappedValue { try encode(StoredPaint(wrappedValue: value), forKey: key) }
    }
}

package struct Appearance: Codable, Equatable, Sendable {
    package var theme = 1
    var palette = 1
}
package struct VisualTheme: Content, Equatable {
    package struct Color: Codable, Equatable, Sendable { var id: Int; var name: String; var light: String?; var dark: String? }
    package struct Palette: Codable, Equatable, Sendable { var id: Int; var name: String; var colors: [Color] }
    package struct Graphics: Codable, Equatable, Sendable {
        var glow: Double?
        package var selection: Int?
        // Clockwise convex contour in units of half the box dimensions.
        var contour: [Point]?
        var linePoints: [Point]?
        var box: Shape?
        var boxChamfer: Double?
        var validGeometry: Bool {
            if let linePoints, linePoints.isEmpty || linePoints.count > 12 ||
                !linePoints.allSatisfy({ (0...1).contains($0.x) && (-1...1).contains($0.y) }) { return false }
            guard let contour else { return true }
            guard [.diamond,.triangle,.pentagon,.hexagon,.parallelogram].contains(box),
                  (3...32).contains(contour.count),
                  contour.allSatisfy({ abs($0.x) <= 1 && abs($0.y) <= 1 }) else { return false }
            for i in contour.indices {
                let a = contour[i], b = contour[(i+1) % contour.count]
                guard a.x*b.y-a.y*b.x > 0.0001 else { return false }
                for p in contour where (b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x) < -0.0001 { return false }
            }
            return true
        }
        var line: ConnectionType?
        var lineArc: Double?
        var roundedWires: Bool?
        var junction: Shape?
        var grid: String?
        var glass: Bool?
        var junctionSize: Double?
        var motionSpeed: Double?
        /// Három betűtípus (CSS font-family): alap, valamint két jól eltérő választható.
        var fonts: [String]?
    }
    package var version: Int
    package var id: Int
    package var name: String
    var modes: [String]
    var palettes: [Palette]
    package var graphics: Graphics?
    // Lépésenkénti guard: az egyetlen hosszú `&&`-lánc típusellenőrzése ~2 s fordítási időt vitt el.
    var valid: Bool {
        guard version == 1, !name.isEmpty, !modes.isEmpty, !palettes.isEmpty else { return false }
        let modeSet = Set<String>(modes)
        guard modeSet.count == modes.count, modeSet.isSubset(of: ["light", "dark"]) else { return false }
        let paletteIDs = Set<Int>(palettes.map(\.id))
        guard paletteIDs.count == palettes.count, palettes.allSatisfy(Self.validPalette) else { return false }
        guard let graphics else { return true }
        return Self.validGraphics(graphics)
    }

    private static func validPalette(_ palette: Palette) -> Bool {
        let ids = Set<Int>(palette.colors.map(\.id))
        guard (16...64).contains(palette.colors.count), ids.count == palette.colors.count else { return false }
        guard Set<Int>(0..<16).isSubset(of: ids), ids.isSubset(of: Set<Int>(0..<64)) else { return false }
        return palette.colors.allSatisfy(validColor)
    }

    private static func validColor(_ color: Color) -> Bool {
        let variants: [String] = [color.light, color.dark].compactMap { $0 }
        guard !color.name.isEmpty, !variants.isEmpty else { return false }
        return variants.allSatisfy { (value: String) -> Bool in
            value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
        }
    }

    private static func validGraphics(_ graphics: Graphics) -> Bool {
        guard graphics.validGeometry else { return false }
        let boxChamfer: Double = graphics.boxChamfer ?? 0
        let glow: Double = graphics.glow ?? 3
        let selection: Int = graphics.selection ?? 4
        let junctionSize: Double = graphics.junctionSize ?? 12
        let lineArc: Double = graphics.lineArc ?? 0
        let motionSpeed: Double = graphics.motionSpeed ?? 1
        guard (0.0...24.0).contains(boxChamfer), (0.0...24.0).contains(glow), (0..<8).contains(selection),
              (4.0...128.0).contains(junctionSize), (0.0...0.25).contains(lineArc), (0.1...5.0).contains(motionSpeed)
        else { return false }
        let grids: [String] = ["dots", "lines", "drafting"]
        guard grids.contains(graphics.grid ?? "dots") else { return false }
        let junctions: [Shape] = [.rectangle, .ellipse, .diamond]
        guard junctions.contains(graphics.junction ?? .ellipse) else { return false }
        guard let fonts = graphics.fonts else { return true }
        return fonts.count == 3 && fonts.allSatisfy(validFont)
    }

    private static func validFont(_ font: String) -> Bool {
        let forbidden: Set<Character> = ["<", ">", "\"", ";", "{", "}"]
        return !font.isEmpty && font.count <= 200 && !font.contains(where: forbidden.contains)
    }
}

extension VisualTheme.Graphics {
    static let defaultFonts = ["system-ui, sans-serif", "Georgia, 'Times New Roman', serif", "'Chalkboard SE', 'Comic Sans MS', cursive"]
    /// A doboz betűtípusa a téma három betűtípusa közül (1-től számozva).
    func fontFamily(_ index: Int?) -> String {
        let list = fonts ?? Self.defaultFonts
        return list[min(max((index ?? 1) - 1, 0), list.count - 1)]
    }
}

package enum Themes {
    // Theme files are reloaded on startup; previews from a previous catalog must be redrawn.
    static let loadedAt = Date()
    package static let catalog: [VisualTheme] = {
        let dir = URL(fileURLWithPath: DirectoryConfiguration.detect().publicDirectory).appendingPathComponent("themes")
        var result = [VisualTheme]()
        for url in ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) where url.pathExtension == "json" {
            do {
                let theme = try JSONDecoder().decode(VisualTheme.self, from: Data(contentsOf: url))
                guard theme.valid, !result.contains(where: { $0.id == theme.id }) else { throw Abort(.unprocessableEntity) }
                result.append(theme)
            } catch { print("ThinkNodes: invalid theme \(url.lastPathComponent): \(error)") }
        }
        return result.sorted { $0.id < $1.id }
    }()
}

extension VisualTheme {
    fileprivate func paintResolver(paletteID: Int, mode: String?) -> ((String?, Int) -> String)? {
        guard let palette = palettes.first(where: { $0.id == paletteID }) else { return nil }
        let dark = (mode.flatMap { modes.contains($0) ? $0 : nil } ?? modes[0]) == "dark"
        let colors = Dictionary(uniqueKeysWithValues: palette.colors.map { ($0.id, $0) })
        return { value, role in
            if let value, value.hasPrefix("#") { return value }
            let color = value.flatMap(paintID).flatMap { colors[$0] } ?? colors[role]!
            return (dark ? color.dark ?? color.light : color.light ?? color.dark)!
        }
    }
}

extension Worksheet {
    package func resolvedBackground(mode: String?) -> String {
        let appearance = self.appearance ?? Appearance()
        return Themes.catalog.first(where: { $0.id == appearance.theme })?
            .paintResolver(paletteID: appearance.palette, mode: mode)?(background, 0) ?? backgroundColor
    }

    package func painted(mode: String?, catalog: [VisualTheme] = Themes.catalog) -> Worksheet {
        let appearance = self.appearance ?? Appearance()
        guard let theme = catalog.first(where: { $0.id == appearance.theme }),
              let resolve = theme.paintResolver(paletteID: appearance.palette, mode: mode) else { return self }
        var sheet = self
        sheet.background = resolve(background, 0)
        for i in sheet.nodes.indices {
            let node = nodes[i]
            if node.isJunction { sheet.nodes[i].shape = theme.graphics?.junction ?? .ellipse }
            else if node.shape == .rounded { sheet.nodes[i].shape = theme.graphics?.box ?? .rounded }
            sheet.nodes[i].fill = resolve(node.fill, 2)
            sheet.nodes[i].textColor = resolve(node.textColor, 1)
            if let color = node.file?.alphaBackground { sheet.nodes[i].file?.alphaBackground = resolve(color, 2) }
        }
        for i in sheet.edges.indices {
            sheet.edges[i].color = resolve(edges[i].color, 3)
            if edges[i].type == .straight { sheet.edges[i].type = theme.graphics?.line ?? .straight }
        }
        return sheet
    }
}
