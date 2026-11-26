import Foundation
import Vapor

/// Tartós munkamenetek: az adatmappa `.sessions.json` fájljában (0600), hogy a szerver újraindulása se léptesse ki a
/// felhasználókat, és a CSRF-token se változzon. A memóriában tartott munkamenetekkel minden újraindítás után új token
/// (és tesztmódban új „TesterN” név) járt, ezért a nyitott szerkesztő és megtekintő teljesen újratöltötte magát.
/// A Vapor minden válasznál meghívja az `updateSession`-t: a fájl csak tényleges változáskor íródik, összevonva (legfeljebb
/// másodpercenként egyszer). A 30 napja nem használt munkamenetek törlődnek.
final class FileSessions: SessionDriver, @unchecked Sendable {
    private struct Entry: Codable {
        var data: [String: String]
        var seen: Date
    }
    static let lifetime: TimeInterval = 60 * 60 * 24 * 30
    private static let touchInterval: TimeInterval = 60 * 60
    private let url: URL
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var flushScheduled = false

    init(directory: URL) {
        url = directory.appendingPathComponent(".sessions.json")
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            let limit = Date().addingTimeInterval(-Self.lifetime)
            entries = stored.filter { $0.value.seen > limit }
        }
    }

    func createSession(_ data: SessionData, for request: Request) -> EventLoopFuture<SessionID> {
        let id = SessionID(string: [UInt8].random(count: 32).base64String())
        lock.withLock {
            entries[id.string] = Entry(data: data.snapshot, seen: Date())
            scheduleFlush()
        }
        return request.eventLoop.makeSucceededFuture(id)
    }

    func readSession(_ sessionID: SessionID, for request: Request) -> EventLoopFuture<SessionData?> {
        let data: [String: String]? = lock.withLock {
            guard var entry = entries[sessionID.string] else { return nil }
            if entry.seen.timeIntervalSinceNow < -Self.lifetime {
                entries[sessionID.string] = nil
                scheduleFlush()
                return nil
            }
            // A használat ideje óránként egyszer frissül (a lejárathoz), nem minden kérésnél.
            if entry.seen.timeIntervalSinceNow < -Self.touchInterval {
                entry.seen = Date()
                entries[sessionID.string] = entry
                scheduleFlush()
            }
            return entry.data
        }
        return request.eventLoop.makeSucceededFuture(data.map(SessionData.init(initialData:)))
    }

    func updateSession(_ sessionID: SessionID, to data: SessionData, for request: Request) -> EventLoopFuture<SessionID> {
        lock.withLock {
            let snapshot = data.snapshot
            if entries[sessionID.string]?.data != snapshot {
                entries[sessionID.string] = Entry(data: snapshot, seen: Date())
                scheduleFlush()
            }
        }
        return request.eventLoop.makeSucceededFuture(sessionID)
    }

    func deleteSession(_ sessionID: SessionID, for request: Request) -> EventLoopFuture<Void> {
        lock.withLock {
            if entries.removeValue(forKey: sessionID.string) != nil { scheduleFlush() }
        }
        return request.eventLoop.makeSucceededFuture(())
    }

    /// A zár alatt hívandó: egy másodpercen belüli változások egyetlen írásba olvadnak.
    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [self] in flush() }
    }

    func flush() {
        let snapshot: [String: Entry] = lock.withLock {
            flushScheduled = false
            let limit = Date().addingTimeInterval(-Self.lifetime)
            entries = entries.filter { $0.value.seen > limit }
            return entries
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Írási hiba esetén a munkamenetek a memóriában tovább élnek; a következő változás újra megpróbálja.
        }
    }
}
