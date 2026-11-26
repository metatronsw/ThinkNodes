import Foundation
import Vapor

/// Projektnapló: projektenként egy közös lap, a bejegyzések idő szerint. Írni és jelölni minden szerkesztő tud (aki a
/// projektet szerkesztheti és be van jelentkezve, vendég szerepkör nélkül); olvasni bárki, aki a projektet látja.
/// Tárolás: a projekt mappájában `.naplo.json`. Bejegyzésenkénti műveletek (hozzáadás, szöveg, jelző), így ketten
/// egyszerre is dolgozhatnak rajta ütközés nélkül.
package struct LogEntry: Content, Sendable, Equatable {
    package let id: String
    package let author: String
    package let created: Date
    package var text: String
    package var important = false
    package var done = false
    package var inactive = false
    package var editedBy: String?
    package var edited: Date?
    /// Az író színe és avatarja olvasáskor kerül bele, nem tárolódik.
    package var color: String?
    package var avatar: Int?
}

package struct ProjectLog: Content, Sendable {
    package var entries: [LogEntry]
    /// Írhat-e a kérő (a felület ehhez igazodik; a szerver minden műveletnél újra ellenőrzi).
    package var writable: Bool
}

package let logEntryLimit = 5000

extension WorksheetStore {
    private func logContext(_ project: String, user: User?, unlocks: Set<String>) throws -> (url: URL, writable: Bool) {
        if try readSettings().requireLogin && user == nil { throw Abort(.unauthorized) }
        let path = try WorksheetPath([project])
        let ctx = try context(path)
        let access = accessLocked(ctx, user: user, unlocks: unlocks)
        try authorize(access, user: user)
        let url = ctx.project.appendingPathComponent(".naplo.json")
        try rejectLink(url)
        return (url, access.editable && user != nil && user?.role != .guest)
    }

    private func readLog(_ url: URL) throws -> [LogEntry] {
        guard files.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([LogEntry].self, from: Data(contentsOf: url))
    }

    private func writeLog(_ entries: [LogEntry], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stored = entries.map { entry -> LogEntry in var entry = entry; entry.color = nil; entry.avatar = nil; return entry }
        try encoder.encode(stored).write(to: url, options: .atomic)
    }

    private func decoratedLog(_ entries: [LogEntry], settings: SiteSettings) -> [LogEntry] {
        entries.map { entry in
            var entry = entry
            entry.color = settings.color(for: entry.author)
            entry.avatar = settings.preferences?[entry.author]?.avatar ?? 1
            return entry
        }
    }

    package func projectLog(_ project: String, user: User?, unlocks: Set<String> = []) throws -> ProjectLog {
        try lock.withLock {
            let (url, writable) = try logContext(project, user: user, unlocks: unlocks)
            return ProjectLog(entries: decoratedLog(try readLog(url), settings: try readSettings()), writable: writable)
        }
    }

    /// Bejegyzés-műveletek: `add` (szöveg, fontos), `text` (szöveg módosítása), `flag` (important / done / inactive).
    package func changeLog(_ project: String, action: String, id: String?, text: String?, flag: String?, value: Bool?,
                           user: User?, unlocks: Set<String> = []) throws -> ProjectLog {
        try lock.withLock {
            let (url, writable) = try logContext(project, user: user, unlocks: unlocks)
            guard writable, let user else { throw Abort(.forbidden, reason: "A naplóba csak a projekt szerkesztői írhatnak.") }
            var entries = try readLog(url)
            func cleaned(_ raw: String?) throws -> String {
                let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw Abort(.badRequest, reason: "Üres bejegyzés.") }
                guard text.count <= logEntryLimit else { throw Abort(.payloadTooLarge, reason: "A bejegyzés legfeljebb \(logEntryLimit) karakter lehet.") }
                return text
            }
            switch action {
            case "add":
                var entry = LogEntry(id: UUID().uuidString.lowercased(), author: user.name, created: Date(), text: try cleaned(text))
                entry.important = value == true
                entries.append(entry)
            case "text", "flag":
                guard let index = entries.firstIndex(where: { $0.id == id }) else { throw Abort(.notFound) }
                if action == "text" {
                    entries[index].text = try cleaned(text)
                } else {
                    guard let value else { throw Abort(.badRequest) }
                    switch flag {
                    case "important": entries[index].important = value
                    case "done": entries[index].done = value
                    case "inactive": entries[index].inactive = value
                    default: throw Abort(.badRequest)
                    }
                }
                entries[index].editedBy = user.name
                entries[index].edited = Date()
            default:
                throw Abort(.badRequest)
            }
            try writeLog(entries, to: url)
            return ProjectLog(entries: decoratedLog(entries, settings: try readSettings()), writable: writable)
        }
    }
}
