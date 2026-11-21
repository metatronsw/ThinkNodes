import Foundation
import Vapor

struct Participant: Content {
    let name: String
    let color: String
    let node: String?
    let edge: String?
    let mine: Bool
    let viewing: Bool
}

struct LiveState: Content {
    let version: String
    let revision: Int
    let checkpointRevision: Int?
    let checkpointChanged: Bool
    let participants: [Participant]
}

/// Selection, revision checks and writes share one critical section.
final class Collaboration: @unchecked Sendable {
    private struct Cursor: Codable {
        let cursor: String
        let color: String
        var point: Point?

        var message: String {
            String(decoding: try! JSONEncoder().encode(self), as: UTF8.self)
        }
    }

    private struct Peer {
        let cursorID = UUID().uuidString
        var cursor: Cursor?

        let name: String?
        let role: Role?
        let color: String
        var editing = false
        var viewing = false
        var socket: WebSocket?
        var node: String?
        var edge: String?
        let joined = ContinuousClock.now
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

        func hideCursor(_ peer: Peer?) {
            guard var cursor = peer?.cursor else { return }
            cursor.point = nil
            let message = cursor.message
            for recipient in peers.values { recipient.socket?.send(message) }
        }

        mutating func expire() {
            let expired = peers.filter { $0.value.seen.duration(to: .now) > .seconds(45) }
            for (id, peer) in expired {
                hideCursor(peer)
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

    init(store: WorksheetStore) {
        self.store = store
    }

    func presence(_ path: WorksheetPath, user: User?, client: String, action: String, node: String?, edge: String? = nil,
                  since: String?, loop: any EventLoop, editing: Bool = false,
                  revision: Int? = nil, checkpointRevision: Int? = nil, unlocks: Set<String> = [], point: Point? = nil) throws -> (LiveState, EventLoopFuture<Void>?) {
        try lock.withLock {
            expireInactiveRooms()
            var board = try store.load(path, user: user, unlocks: unlocks)
            let access = try store.access(path, sheet: board, user: user, unlocks: unlocks)
            var room = rooms[path.url] ?? Room()
            room.expire()
            room.revision = board.revision
            if let existing = room.peers[client], existing.name != user?.name { throw Abort(.forbidden) }
            if action == "snapshot" && room.peers[client] == nil { throw Abort(.gone) }
            if action == "leave" {
                let leaving = room.peers.removeValue(forKey: client)
                room.hideCursor(leaving)
                leaving?.socket?.close(promise: nil)
                leaving?.waiter?.succeed(())
                if !room.peers.values.contains(where: \.editing) { room.checkpoint = nil }
                room.changed()
            } else {
                if action == "checkpoint" || action == "resign" {
                    guard let user, access.editable, room.peers[client]?.editing == true,
                          var checkpoint = room.checkpoint else { throw Abort(.forbidden) }
                    guard revision == board.revision, checkpointRevision == checkpoint.revision else {
                        throw Abort(.preconditionFailed, reason: "A munkalap vagy a visszaállítási pont megváltozott. Ellenőrizd, majd próbáld újra.")
                    }
                    if action == "resign" {
                        checkpoint.revision = board.revision
                        board = try store.update(path, worksheet: checkpoint, user: user, restoring: true, unlocks: unlocks)
                        room.revision = board.revision
                        for id in Array(room.peers.keys) {
                            room.peers[id]?.node = nil
                            room.peers[id]?.edge = nil
                        }
                    }
                    room.checkpoint = board
                    room.changed()
                }
                if room.peers[client] == nil {
                    room.peers[client] = Peer(name: user?.name, role: user?.role, color: user == nil ? "" : room.color(for: user?.name))
                    room.changed()
                }
                if editing && action == "poll" {
                    guard access.editable else { throw Abort(.forbidden) }
                    room.peers[client]?.editing = true
                    if room.checkpoint == nil { room.checkpoint = board; room.changed() }
                }
                room.peers[client]?.seen = .now
                if action == "ping" {
                    guard user != nil, let peer = room.peers[client], peer.seen.duration(to: .now) < .seconds(45),
                          node.map({ id in board.nodes.contains { $0.id == id } }) ?? (point?.isValid == true) else { throw Abort(.forbidden) }
                    struct Ping: Encodable {
                        let ping = true
                        let revision: Int
                        let node: String?
                        let point: Point?
                    }
                    let data = try JSONEncoder().encode(Ping(revision: board.revision, node: node, point: point))
                    for (id, receiver) in room.peers where id != client {
                        receiver.socket?.send(String(decoding: data, as: UTF8.self))
                    }
                }
                if action == "select" || action == "view-select" {
                    let viewing = action == "view-select"
                    guard viewing ? user != nil : access.editable else { throw Abort(.forbidden) }
                    if let node {
                        guard board.nodes.contains(where: { $0.id == node }) else { throw Abort(.notFound) }
                        if !viewing, let owner = room.peers.first(where: { $0.key != client && !$0.value.viewing && $0.value.node == node }) {
                            throw Abort(.locked, reason: "\(owner.value.name ?? "Vendég") már kijelölte ezt a dobozt.")
                        }
                    }
                    if let edge {
                        guard node == nil, board.edges.contains(where: { $0.id == edge }) else { throw Abort(.notFound) }
                    }
                    if room.peers[client]?.node != node || room.peers[client]?.edge != edge || room.peers[client]?.viewing != viewing {
                        room.peers[client]?.viewing = viewing
                        room.peers[client]?.edge = edge
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
            var comparable = board
            comparable.revision = room.checkpoint?.revision ?? board.revision
            comparable.resetRevision = room.checkpoint?.resetRevision
            comparable.schemaVersion = room.checkpoint?.schemaVersion ?? board.schemaVersion
            let changed = room.checkpoint.map { $0 != comparable } ?? false
            let state = LiveState(version: room.version, revision: board.revision, checkpointRevision: room.checkpoint?.revision, checkpointChanged: changed, participants: room.peers.sorted { a, b in
                let adminA = a.value.role == .admin
                let adminB = b.value.role == .admin
                if adminA != adminB { return adminA }
                return a.value.joined == b.value.joined ? a.key < b.key : a.value.joined < b.value.joined
            }.map {
                Participant(name: $0.value.name ?? "Vendég", color: $0.value.color, node: $0.value.node, edge: $0.value.edge, mine: $0.key == client, viewing: $0.value.viewing)
            })
            rooms[path.url] = room.peers.isEmpty ? nil : room
            return (state, wait)
        }
    }

    func update(_ path: WorksheetPath, sheet: Worksheet, user: User, client: String?, unlocks: Set<String> = []) throws -> Worksheet {
        try lock.withLock {
            rooms[path.url]?.expire()
            let saved = try store.update(path, worksheet: sheet, user: user, unlocks: unlocks) { current in
                if let client, rooms[path.url]?.peers[client]?.name != user.name {
                    throw Abort(.conflict, reason: "Kapcsolódj újra a munkalaphoz.")
                }
                guard let room = rooms[path.url] else { return }
                let locked = Set(room.peers.filter { $0.key != client && !$0.value.viewing }.values.compactMap(\.node))
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
                let edges = Set(saved.edges.map(\.id))
                for (id, peer) in room.peers {
                    if let node = peer.node, !ids.contains(node) { room.peers[id]?.node = nil }
                    if let edge = peer.edge, !edges.contains(edge) { room.peers[id]?.edge = nil }
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
            for (id, other) in rooms[path.url]?.peers ?? [:] where id != client {
                if let cursor = other.cursor { socket.send(cursor.message) }
            }
            return true
        }
        guard attached else { socket.close(promise: nil); return }
        socket.onText { [weak self] socket, text in
            guard text.utf8.count < 512 else { return }
            struct Pointer: Decodable { let mouse: Bool; let point: Point? }
            if let pointer = try? JSONDecoder().decode(Pointer.self, from: Data(text.utf8)) {
                guard pointer.mouse, pointer.point?.isValid != false else { return }
                self?.lock.withLock {
                    guard let room = self?.rooms[path.url], let peer = room.peers[client],
                          peer.name != nil, peer.socket === socket, peer.seen.duration(to: .now) < .seconds(45) else { return }
                    let cursor = Cursor(cursor: peer.cursorID, color: peer.color, point: pointer.point)
                    self?.rooms[path.url]?.peers[client]?.cursor = pointer.point == nil ? nil : cursor
                    let message = cursor.message
                    for (id, other) in room.peers where id != client { other.socket?.send(message) }
                }
                return
            }
            struct Motion: Codable {
                let node: String
                let revision: Int
                let delta: Point?
            }
            guard text.utf8.count < 512, let frame = try? JSONDecoder().decode(Motion.self, from: Data(text.utf8)),
                  frame.delta.map({ abs($0.x) <= 200_000 && abs($0.y) <= 200_000 }) ?? true else { return }
            self?.lock.withLock {
                guard let room = self?.rooms[path.url], room.revision == frame.revision,
                      let sender = room.peers[client], sender.socket === socket, !sender.viewing, sender.node == frame.node,
                      sender.seen.duration(to: .now) < .seconds(45) else { return }
                guard let data = try? JSONEncoder().encode(frame) else { return }
                for (id, peer) in room.peers where id != client && peer.seen.duration(to: .now) < .seconds(45) {
                    peer.socket?.send(String(decoding: data, as: UTF8.self))
                }
            }
        }
        socket.onClose.whenComplete { [weak self, weak socket] _ in
            self?.lock.withLock {
                if self?.rooms[path.url]?.peers[client]?.socket === socket {
                    self?.rooms[path.url]?.hideCursor(self?.rooms[path.url]?.peers[client])
                    self?.rooms[path.url]?.peers[client]?.cursor = nil
                    self?.rooms[path.url]?.peers[client]?.socket = nil
                    if let room = self?.rooms[path.url], let node = room.peers[client]?.node {
                        let clear = "{\"node\":\"\(node)\",\"revision\":\(room.revision)}"
                        for peer in room.peers.values { peer.socket?.send(clear) }
                    }
                }
            }
        }
    }

    func manage(_ path: WorksheetPath, operation: DocumentAction, user: User, unlocks: Set<String>) throws -> WorksheetPath? {
        try lock.withLock {
            let result = try store.manage(path, operation: operation, user: user, unlocks: unlocks)
            invalidate(path)
            return result
        }
    }

    private func invalidate(_ path: WorksheetPath) {
        for key in rooms.keys.filter({ $0 == path.url || $0.hasPrefix(path.url + "/") }) {
            rooms.removeValue(forKey: key)?.peers.values.forEach {
                $0.socket?.close(promise: nil)
                $0.waiter?.succeed(())
            }
        }
    }

    func archive(_ path: WorksheetPath, expected: Int) throws {
        try lock.withLock {
            try store.archive(path, expected: expected)
            invalidate(path)
        }
    }
}
