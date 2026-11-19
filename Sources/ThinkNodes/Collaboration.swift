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
    let checkpointRevision: Int?
    let participants: [Participant]
}

/// Selection, revision checks and writes share one critical section.
final class Collaboration: @unchecked Sendable {
    private struct Peer {
        let name: String?
        let role: Role?
        let color: String
        var editing = false
        var socket: WebSocket?
        var node: String?
        var seen = ContinuousClock.now
        var waiter: EventLoopPromise<Void>?
    }

    private struct Room {
        var checkpoint: Worksheet?
        var revision = 0
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
                peer.socket?.close(promise: nil)
                peer.waiter?.succeed(())
                peers.removeValue(forKey: id)
            }
            if !peers.values.contains(where: \.editing) { checkpoint = nil }
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
                  since: String?, loop: any EventLoop, editing: Bool = false,
                  revision: Int? = nil, checkpointRevision: Int? = nil) throws -> (LiveState, EventLoopFuture<Void>?) {
        try lock.withLock {
            expireInactiveRooms()
            var board = try store.load(path, user: user)
            var room = rooms[path.url] ?? Room()
            room.expire()
            room.revision = board.revision
            if let existing = room.peers[client], existing.name != user?.name { throw Abort(.forbidden) }
            if action == "snapshot" && room.peers[client] == nil { throw Abort(.gone) }
            if action == "leave" {
                let leaving = room.peers.removeValue(forKey: client)
                leaving?.socket?.close(promise: nil)
                leaving?.waiter?.succeed(())
                if !room.peers.values.contains(where: \.editing) { room.checkpoint = nil }
                room.changed()
            } else {
                if action == "checkpoint" || action == "resign" {
                    guard let user, board.canEdit(user), room.peers[client]?.editing == true,
                          var checkpoint = room.checkpoint else { throw Abort(.forbidden) }
                    guard revision == board.revision, checkpointRevision == checkpoint.revision else {
                        throw Abort(.preconditionFailed, reason: "A munkalap vagy a visszaállítási pont megváltozott. Ellenőrizd, majd próbáld újra.")
                    }
                    if action == "resign" {
                        checkpoint.revision = board.revision
                        checkpoint.owner = board.owner
                        checkpoint.editors = board.editors
                        checkpoint.isPublic = board.isPublic
                        board = try store.update(path, worksheet: checkpoint, user: user, restoring: true)
                        room.revision = board.revision
                        for id in Array(room.peers.keys) { room.peers[id]?.node = nil }
                    }
                    room.checkpoint = board
                    room.changed()
                }
                if room.peers[client] == nil {
                    room.peers[client] = Peer(name: user?.name, role: user?.role, color: room.color(for: user?.name))
                    room.changed()
                }
                if editing && action == "poll" {
                    guard board.canEdit(user) else { throw Abort(.forbidden) }
                    room.peers[client]?.editing = true
                    if room.checkpoint == nil { room.checkpoint = board; room.changed() }
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
            let state = LiveState(version: room.version, revision: board.revision, checkpointRevision: room.checkpoint?.revision, participants: room.peers.map {
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
                room.revision = saved.revision
                let ids = Set(saved.nodes.map(\.id))
                for (id, peer) in room.peers {
                    let allowed = peer.role == .admin || (peer.name != nil &&
                        (peer.name == saved.owner || (saved.editors ?? []).contains(peer.name ?? "")))
                    if !allowed && saved.isPublic == false {
                        peer.socket?.close(promise: nil)
                        peer.waiter?.succeed(())
                        room.peers.removeValue(forKey: id)
                        continue
                    }
                    if let node = peer.node, !ids.contains(node) { room.peers[id]?.node = nil }
                    if !allowed {
                        room.peers[id]?.editing = false
                        room.peers[id]?.node = nil
                    }
                }
                if !room.peers.values.contains(where: \.editing) { room.checkpoint = nil }
                room.changed()
                rooms[path.url] = room
            }
            return saved
        }
    }

    // The first socket frame carries the private capability established by the
    // authenticated presence request. Preview frames never enter the worksheet store.
    func attach(_ socket: WebSocket, path: WorksheetPath, client: String) {
        let attached = lock.withLock {
            guard let peer = rooms[path.url]?.peers[client], peer.seen.duration(to: .now) < .seconds(45) else { return false }
            peer.socket?.close(promise: nil)
            rooms[path.url]?.peers[client]?.socket = socket
            return true
        }
        guard attached else { socket.close(promise: nil); return }
        socket.onText { [weak self] socket, text in
            struct Motion: Decodable {
                let node: String
                let revision: Int
                let delta: Point?
            }
            guard text.utf8.count < 512, let frame = try? JSONDecoder().decode(Motion.self, from: Data(text.utf8)),
                  frame.delta.map({ abs($0.x) <= 200_000 && abs($0.y) <= 200_000 }) ?? true else { return }
            self?.lock.withLock {
                guard let room = self?.rooms[path.url], room.revision == frame.revision,
                      let sender = room.peers[client], sender.socket === socket, sender.node == frame.node,
                      sender.seen.duration(to: .now) < .seconds(45) else { return }
                for (id, peer) in room.peers where id != client && peer.seen.duration(to: .now) < .seconds(45) {
                    peer.socket?.send(text)
                }
            }
        }
        socket.onClose.whenComplete { [weak self, weak socket] _ in
            self?.lock.withLock {
                if self?.rooms[path.url]?.peers[client]?.socket === socket {
                    self?.rooms[path.url]?.peers[client]?.socket = nil
                    if let room = self?.rooms[path.url], let node = room.peers[client]?.node {
                        let clear = "{\"node\":\"\(node)\",\"revision\":\(room.revision)}"
                        for peer in room.peers.values { peer.socket?.send(clear) }
                    }
                }
            }
        }
    }

    func archive(_ path: WorksheetPath, expected: Int) throws {
        try lock.withLock {
            try store.archive(path, expected: expected)
            rooms.removeValue(forKey: path.url)?.peers.values.forEach {
                $0.socket?.close(promise: nil)
                $0.waiter?.succeed(())
            }
        }
    }
}
