import Foundation
import Vapor

extension Worksheet {
    /// Read stored and imported documents. Live editor requests use the current schema directly.
    static func decodeFile(_ data: Data) throws -> Worksheet {
        struct Version: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        guard try decoder.decode(Version.self, from: data).schemaVersion == 2 else {
            return try decoder.decode(Worksheet.self, from: data)
        }
        guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = document["nodes"] as? [[String: Any]] else { throw Abort(.unprocessableEntity) }
        document["nodes"] = try nodes.map(convertLegacyNode)
        document["schemaVersion"] = currentSchema
        return try decoder.decode(Worksheet.self, from: JSONSerialization.data(withJSONObject: document))
    }

    private static func convertLegacyNode(_ old: [String: Any]) throws -> [String: Any] {
        var node = old
        let title = old["title"] as? String ?? ""
        let body = old["text"] as? String ?? ""
        let kind = old["kind"] as? String
        var type = kind == "connectionPoint" ? "junction" : "box"
        if kind == "container" { node["container"] = true }
        node.removeValue(forKey: "link")
        if let link = old["link"] as? String, !link.isEmpty {
            guard let target = WorksheetLink(link) else { throw Abort(.unprocessableEntity) }
            let linkKind: String = if case .website = target { "url" } else { "sheet" }
            node["link"] = ["kind": linkKind, "target": link]
        }
        if var file = old["file"] as? [String: Any] {
            let filename = file["filename"] as? String ?? title
            switch file["type"] as? String {
            case "web":
                guard let target = file["webPath"] as? String else { throw Abort(.unprocessableEntity) }
                node["link"] = ["kind": "web", "target": target]
                node.removeValue(forKey: "file")
            case "image": type = "image"
            case "mp3": type = "audio"
            case "attachment": type = "document"
            case "txt", "md", "json":
                if file["asset"] != nil || file["filename"] != nil || filename.hasSuffix("." + (file["type"] as? String ?? "")) {
                    type = file["type"] as? String == "json" ? "code" : "text"
                    if file["asset"] == nil { file["asset"] = filename }
                    node["file"] = file
                } else { node.removeValue(forKey: "file") }
            default: throw Abort(.unprocessableEntity)
            }
        }
        node["type"] = type
        node["text"] = type == "junction" ? title : [title, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
        if type != "box" && type != "junction", let file = node["file"] as? [String: Any], file["filename"] as? String == title {
            node["text"] = body
        }
        if node["backgroundMode"] == nil {
            if old["backgroundEnabled"] as? Bool == false { node["backgroundMode"] = "free" }
        }
        if let style = old["textStyle"] as? [String: Any] {
            for (source, destination) in [("size","fontSz"), ("color","textCol"), ("align","align"), ("vAlign","vAlign"),
                                          ("bold","bold"), ("italic","italic"), ("underline","underline"), ("justified","justified")] {
                if let value = style[source] { node[destination] = value }
            }
        }
        return node
    }
}
