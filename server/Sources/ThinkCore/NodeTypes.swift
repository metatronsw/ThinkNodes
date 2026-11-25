import Foundation
import Vapor

/// Vászonobjektum-típusok regisztere: `Public/node-types.json` (docs/node-types.md).
/// Az alkategória (`base`) örökli az alaptípus képességeit; a `traits` felülírja, az `addTraits` bővíti.
package struct NodeTypeDefinition: Codable, Sendable {
    var label: String?
    var base: String?
    package var file: String?
    var extensions: [String]?
    var traits: [String]?
    var addTraits: [String]?
}

package enum NodeTypes {
    private struct Registry: Codable { var types: [String: NodeTypeDefinition] }

    static let definitions: [String: NodeTypeDefinition] = {
        let url = URL(fileURLWithPath: DirectoryConfiguration.detect().publicDirectory).appendingPathComponent("node-types.json")
        do { return try JSONDecoder().decode(Registry.self, from: Data(contentsOf: url)).types }
        catch {
            print("ThinkNodes: invalid node type registry: \(error)")
            return fallback
        }
    }()

    /// Tartalék, ha a regiszter nem olvasható (pl. hibás telepítés); a JSON-nal egyezik.
    private static let fallback: [String: NodeTypeDefinition] = [
        "box": .init(traits: ["text", "shape", "motion", "surface", "elevation", "size", "children", "link"]),
        "preview": .init(label: "Előnézet", base: "box", traits: ["comment", "surface", "elevation", "size", "link"]),
        "text": .init(file: "text", traits: ["file", "fileText", "comment", "surface", "elevation", "size"]),
        "code": .init(base: "text", extensions: ["json", "js", "mjs", "swift", "css"]),
        "csv": .init(base: "text", extensions: ["csv", "tsv"]),
        "table": .init(label: "Táblázat", base: "text", extensions: ["tntable"],
                       traits: ["file", "table", "comment", "surface", "elevation", "size"]),
        "image": .init(file: "media", extensions: ["png", "jpg", "jpeg", "gif", "webp", "svg"],
                       traits: ["file", "comment", "alpha", "surface", "elevation", "size", "link"]),
        "audio": .init(file: "media", extensions: ["mp3", "wav", "ogg", "flac", "m4a", "aac"],
                       traits: ["file", "comment", "player", "surface", "elevation", "size"]),
        "document": .init(file: "binary", extensions: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "zip"], traits: ["file", "comment", "surface", "elevation", "size"]),
        "chart": .init(label: "Grafikon", traits: ["chart", "comment", "surface", "elevation", "size"]),
        "junction": .init(traits: ["label", "diameter", "color"]),
    ]

    static func isKnown(_ type: String) -> Bool { definitions[type] != nil }

    /// Az öröklési lánc gyökere: `code` → `text`.
    static func root(_ type: String) -> String {
        var current = type, seen = Set<String>()
        while let base = definitions[current]?.base, seen.insert(current).inserted { current = base }
        return current
    }

    static func traits(_ type: String) -> Set<String> {
        guard let definition = definitions[type] else { return [] }
        var result = definition.base.map(traits) ?? []
        if let own = definition.traits { result = Set(own) }
        result.formUnion(definition.addTraits ?? [])
        return result
    }

    static func has(_ type: String, _ trait: String) -> Bool { traits(type).contains(trait) }

    /// Fájlt tárol-e a típus (és milyen módon: `text`, `media`, `binary`).
    static func fileKind(_ type: String) -> String? {
        var current: String? = type, seen = Set<String>()
        while let id = current, seen.insert(id).inserted {
            if let file = definitions[id]?.file { return file }
            current = definitions[id]?.base
        }
        return nil
    }

    /// Importált fájl típusa: médiánál kiterjesztés, egyébként tartalom alapján (UTF-8, NUL bájt nélkül → szöveg).
    static func classify(filename: String, bytes: Data) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        for media in ["image", "audio", "document"] where definitions[media]?.extensions?.contains(ext) == true {
            return media
        }
        guard isPlainText(bytes) else { return "document" }
        for (id, definition) in definitions.sorted(by: { $0.key < $1.key })
        where root(id) == "text" && id != "text" && definition.extensions?.contains(ext) == true {
            return id
        }
        return "text"
    }

    /// Szöveg: érvényes UTF-8, és a tabulátoron, soremelésen, lapdobáson kívül nincs benne vezérlőkarakter.
    static func isPlainText(_ bytes: Data) -> Bool {
        !bytes.contains { ($0 < 0x20 && ![9, 10, 12, 13].contains($0)) || $0 == 0x7f } && String(data: bytes, encoding: .utf8) != nil
    }
}
