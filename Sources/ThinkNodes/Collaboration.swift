import Foundation
import Vapor

struct Participant: Content {
    let name: String
    let color: String
    let node: String?
    let mine: Bool
}

struct LiveState: Content {
    let version: String
    let revision: Int
    let participants: [Participant]
}

/// Selection, revision checks and writes share one critical section.
final class Collaboration: @unchecked Sendable {
    private struct Peer {
        let name: String?
        let role: Role?
        let color: String
        var node: String?
        var seen = ContinuousClock.now
        var waiter: EventLoopPromise<Void>?
    }

    private struct Room {
        var version = UUID().uuidString
        var peers: [String: Peer] = [:]

        mutating func changed() {
            version = UUID().uuidString
            for id in Array(peers.keys) {
                peers[id]?.waiter?.succeed(())
                peers[id]?.waiter = nil
            }
        }

        mutating func expire() {
            let expired = peers.filter { $0.value.seen.duration(to: .now) > .seconds(45) }
            for (id, peer) in expired {
                peer.waiter?.succeed(())
                peers.removeValue(forKey: id)
            }
            if !expired.isEmpty { changed() }
        }

        func color(for name: String?) -> String {
            if let peer = peers.values.first(where: { $0.name == name }) { return peer.color }
            let used = Set(peers.values.map(\.color))
            let palette = ["#365bd6", "#bd4359", "#078469", "#9452ba", "#b35a14", "#167eae", "#a23878"]
            if let color = palette.first(where: { !used.contains($0) }) { return color }
            var color: String
            repeat { color = String(format: "#%06x", Int.random(in: 0x303030...0xb0b0b0)) } while used.contains(color)
            return color
        }
    }

    private let store: WorksheetStore
    private let lock = NSLock()
    private var rooms: [String: Room] = [:]

    private var lastSweep = ContinuousClock.now

    private func expireInactiveRooms() {
        guard lastSweep.duration(to: .now) > .seconds(45) else { return }
        lastSweep = .now
        for key in Array(rooms.keys) {
            rooms[key]?.expire()
            if rooms[key]?.peers.isEmpty == true { rooms.removeValue(forKey: key) }
        }
    }

    init(store: WorksheetStore) { self.store = store }

    func presence(_ path: WorksheetPath, user: User?, client: String, action: String, node: String?,
                  since: String?, loop: any EventLoop) throws -> (LiveState, EventLoopFuture<Void>?) {
        try lock.withLock {
            expireInactiveRooms()
            let board = try store.load(path, user: user)
            var room = rooms[path.url] ?? Room()
            room.expire()
            if let existing = room.peers[client], existing.name != user?.name { throw Abort(.forbidden) }
            if action == "snapshot" && room.peers[client] == nil { throw Abort(.gone) }
            if action == "leave" {
                room.peers.removeValue(forKey: client)?.waiter?.succeed(())
                room.changed()
            } else {
                if room.peers[client] == nil {
                    room.peers[client] = Peer(name: user?.name, role: user?.role, color: room.color(for: user?.name))
                    room.changed()
                }
                room.peers[client]?.seen = .now
                if action == "select" {
                    guard board.canEdit(user) else { throw Abort(.forbidden) }
                    if let node {
                        guard board.nodes.contains(where: { $0.id == node }) else { throw Abort(.notFound) }
                        if let owner = room.peers.first(where: { $0.key != client && $0.value.node == node }) {
                            throw Abort(.locked, reason: "\(owner.value.name ?? "Vendég") már kijelölte ezt a dobozt.")
                        }
                    }
                    if room.peers[client]?.node != node {
                        room.peers[client]?.node = node
                        room.changed()
                    }
                }
            }
            var wait: EventLoopFuture<Void>?
            if action == "poll", since == room.version {
                let promise = loop.makePromise(of: Void.self)
                room.peers[client]?.waiter?.succeed(())
                room.peers[client]?.waiter = promise
                let timeout = loop.scheduleTask(in: .seconds(12)) { promise.succeed(()) }
                promise.futureResult.whenComplete { _ in timeout.cancel() }
                wait = promise.futureResult
            }
            let state = LiveState(version: room.version, revision: board.revision, participants: room.peers.map {
                Participant(name: $0.value.name ?? "Vendég", color: $0.value.color, node: $0.value.node, mine: $0.key == client)
            }.sorted { $0.name < $1.name })
            rooms[path.url] = room.peers.isEmpty ? nil : room
            return (state, wait)
        }
    }

    func update(_ path: WorksheetPath, sheet: Worksheet, user: User, client: String?) throws -> Worksheet {
        try lock.withLock {
            rooms[path.url]?.expire()
            let saved = try store.update(path, worksheet: sheet, user: user) { current in
                if let client, rooms[path.url]?.peers[client]?.name != user.name {
                    throw Abort(.conflict, reason: "Kapcsolódj újra a munkalaphoz.")
                }
                guard let room = rooms[path.url] else { return }
                let locked = Set(room.peers.filter { $0.key != client }.values.compactMap(\.node))
                guard !locked.isEmpty else { return }
                let submitted = Dictionary(sheet.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for node in current.nodes where locked.contains(node.id) && submitted[node.id] != node {
                    // Removing the last cable also removes its orphaned connection point.
                    if node.kind == .connectionPoint && submitted[node.id] == nil { continue }
                    throw Abort(.locked, reason: "A dobozt egy másik felhasználó jelölte ki.")
                }
            }
            if var room = rooms[path.url] {
                let ids = Set(saved.nodes.map(\.id))
                for (id, peer) in room.peers {
                    if let node = peer.node, !ids.contains(node) { room.peers[id]?.node = nil }
                    if peer.node != nil, peer.role != .admin, let name = peer.name,
                       name != saved.owner, saved.editors?.contains(name) != true { room.peers[id]?.node = nil }
                }
                room.changed()
                rooms[path.url] = room
            }
            return saved
        }
    }

    func archive(_ path: WorksheetPath, expected: Int) throws {
        try lock.withLock {
            try store.archive(path, expected: expected)
            rooms.removeValue(forKey: path.url)?.peers.values.forEach { $0.waiter?.succeed(()) }
        }
    }
}
