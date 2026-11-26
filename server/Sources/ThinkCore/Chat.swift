import Foundation
import Vapor

/// Csevegés munkalaponként. Az üzenetek a munkalap mappájában, a `.chat.jsonl` fájlban vannak (soronként egy JSON),
/// így a munkalappal együtt mozognak (átnevezés, áthelyezés, lomtár). A munkalap fájljától és verzióitól független,
/// ezért nem ütközik a mentésekkel. Csak bejelentkezett felhasználó olvashatja és írhatja, aki a lapot is láthatja.
package struct ChatMessage: Content, Sendable, Equatable {
    package let id: String
    package let author: String
    package let time: Date
    package let text: String
    /// Az író színe és avatarja olvasáskor kerül bele (a beállításokból), nem tárolódik.
    package var color: String?
    package var avatar: Int?

    private enum CodingKeys: String, CodingKey { case id, author, time, text, color, avatar }
}

/// Egy üzenet legfeljebb ennyi karakter; a lekérdezés a legutóbbi ennyi üzenetet adja.
package let chatMessageLimit = 2000
package let chatHistoryLimit = 200

extension WorksheetStore {
    private func chatURL(_ path: WorksheetPath) throws -> URL {
        let url = try folder(path).appendingPathComponent(".chat.jsonl")
        try rejectLink(url)
        return url
    }

    private func authorizeChat(_ path: WorksheetPath, user: User?, unlocks: Set<String>) throws {
        guard user != nil else { throw Abort(.unauthorized, reason: "A csevegéshez jelentkezz be.") }
        if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
        _ = try worksheetURL(path)
        try authorize(accessLocked(context(path), user: user, unlocks: unlocks), user: user)
    }

    private func decorated(_ message: ChatMessage, settings: SiteSettings) -> ChatMessage {
        var message = message
        message.color = settings.color(for: message.author)
        message.avatar = settings.preferences?[message.author]?.avatar ?? 1
        return message
    }

    private func readChat(_ url: URL) throws -> [ChatMessage] {
        guard files.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").compactMap {
            try? decoder.decode(ChatMessage.self, from: Data($0.utf8))
        }
    }

    /// A legutóbbi `chatHistoryLimit` üzenet, időrendben.
    package func chat(_ path: WorksheetPath, user: User?, unlocks: Set<String> = []) throws -> [ChatMessage] {
        try lock.withLock {
            try authorizeChat(path, user: user, unlocks: unlocks)
            let settings = try readSettings()
            return try readChat(chatURL(path)).suffix(chatHistoryLimit).map { decorated($0, settings: settings) }
        }
    }

    package func postChat(_ path: WorksheetPath, text raw: String, user: User?, unlocks: Set<String> = []) throws -> ChatMessage {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Abort(.badRequest, reason: "Üres üzenet.") }
        guard text.count <= chatMessageLimit else { throw Abort(.payloadTooLarge, reason: "Az üzenet legfeljebb \(chatMessageLimit) karakter lehet.") }
        return try lock.withLock {
            try authorizeChat(path, user: user, unlocks: unlocks)
            let message = ChatMessage(id: UUID().uuidString.lowercased(), author: user!.name, time: Date(), text: text)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(message)
            line.append(0x0a)
            let url = try chatURL(path)
            if files.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url, options: .atomic)
            }
            return decorated(message, settings: try readSettings())
        }
    }

    /// Üzenet törlése: a szerzője vagy admin törölheti.
    package func deleteChat(_ path: WorksheetPath, id: String, user: User?, unlocks: Set<String> = []) throws {
        try lock.withLock {
            try authorizeChat(path, user: user, unlocks: unlocks)
            let url = try chatURL(path)
            var messages = try readChat(url)
            guard let index = messages.firstIndex(where: { $0.id == id }) else { throw Abort(.notFound) }
            guard messages[index].author == user?.name || user?.role == .admin else { throw Abort(.forbidden) }
            messages.remove(at: index)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let body = try messages.map { String(decoding: try encoder.encode($0), as: UTF8.self) + "\n" }.joined()
            try Data(body.utf8).write(to: url, options: .atomic)
        }
    }
}
