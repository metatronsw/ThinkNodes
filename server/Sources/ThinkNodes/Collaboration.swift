import Foundation
import ThinkCore
import Vapor

struct Participant: Content {
    /// A résztvevő nyilvános azonosítója (a kurzorüzenetek `cursor` mezője is ez): a pingelő neve ez alapján villan fel.
    let id: String
    let name: String
    let color: String
    let node: String?
    let edge: String?
    var avatar: Int?
    let mine: Bool
    let viewing: Bool
    /// Nem nézi a lapot (másik ablak vagy fül van előtérben): a jelenlévők között szürkén látszik, a kurzora nem.
    let away: Bool
    /// Tétlen foglalás: legalább `idleHold` ideje fogja a dobozt, és azóta nem csinált semmit (egér, billentyű, görgetés,
    /// mentés); a dobozt más átveheti (kijelöléskor).
    var idle: Bool = false
    /// Csak a saját sorban, egyszer: a dobozt más vette át tőled (tétlenség miatt).
    var lost: LostHold? = nil
}

/// A tétlenség miatt átvett doboz és az átvevő neve.
struct LostHold: Content {
    let node: String
    let by: String
}

/// Folyamatban lévő előadás (prezentáció mód) a szobában: ki adja elő, milyen módban („invite”: a követők leválhatnak;
/// „forced”: kötelező követés) és a legutóbbi keret (munkalap-koordinátában: x, y, szélesség, magasság).
struct PresentationState: Content {
    let presenter: String
    let name: String
    let color: String
    let avatar: Int?
    let mode: String
    let rect: [Double]?
}

struct LiveState: Content {
    let version: String
    let revision: Int
    let checkpointRevision: Int?
    let checkpointChanged: Bool
    let participants: [Participant]
    var presentation: PresentationState? = nil
}

/// Selection, revision checks and writes share one critical section.
final class Collaboration: @unchecked Sendable {
    private struct Cursor: Codable {
        let cursor: String
        let color: String
        /// A kurzor mellé írt név, illetve rajzolt avatar (a néző választja ki, melyik látszódjon).
        let name: String
        let avatar: Int
        var point: Point?

        var message: String {
            String(decoding: try! JSONEncoder().encode(self), as: UTF8.self)
        }
    }

    /// Egy résztvevő cellakijelölése a fogott táblázat- vagy CSV-dobozban (csak a kijelölés és az, hogy szerkeszt-e;
    /// a gépelt szöveg nem megy át). Rövid életű, a munkalapba nem kerül.
    private struct CellMark: Codable {
        struct Range: Codable {
            let r0: Int, c0: Int, r1: Int, c1: Int, r: Int, c: Int
            let editing: Bool
            var isValid: Bool {
                [r0, r1, r].allSatisfy { (0..<1000).contains($0) } && [c0, c1, c].allSatisfy { (0..<100).contains($0) }
            }
        }
        let cells: String
        let node: String
        let color: String
        var range: Range?

        var message: String {
            String(decoding: try! JSONEncoder().encode(self), as: UTF8.self)
        }
    }

    private struct Peer {
        let cursorID = UUID().uuidString
        var cursor: Cursor?
        var cells: CellMark?

        let name: String?
        let role: Role?
        var color: String
        var avatar: Int?
        var away = false
        var editing = false
        var viewing = false
        var socket: WebSocket?
        var node: String?
        var edge: String?
        let joined = ContinuousClock.now
        var seen = ContinuousClock.now
        var waiter: EventLoopPromise<Void>?
        /// Utolsó tevékenység (egér, billentyű, görgetés, kijelölés, mentés; a hosszú lekérdezés nem az).
        var active = ContinuousClock.now
        /// Mióta fogja a mostani dobozt.
        var heldSince = ContinuousClock.now
        /// A WebSocket bezárult (és még nem csatlakozott újra): ennyi idő után a résztvevő kiesik (`disconnectGrace`).
        var disconnected: ContinuousClock.Instant?
        /// A tétlenség jelzése (a változáskor a szoba verziója nő, a többiek azonnal látják).
        var idle = false
        var lost: LostHold?

        func isIdle(_ hold: Duration) -> Bool {
            node != nil && !viewing && heldSince.duration(to: .now) >= hold && active.duration(to: .now) >= hold
        }
    }

    private struct Presentation {
        let client: String
        let mode: String
        var rect: [Double]?

        func message(from peer: Peer) -> String? {
            guard let rect else { return nil }
            struct Frame: Encodable { let present: String; let rect: [Double] }
            return (try? JSONEncoder().encode(Frame(present: peer.cursorID, rect: rect))).map { String(decoding: $0, as: UTF8.self) }
        }
    }

    private struct Room {
        var presentation: Presentation?
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

        /// `hold`: a tétlen foglalás ideje; `grace`: a szakadt kapcsolat türelmi ideje.
        mutating func expire(hold: Duration = .seconds(60), grace: Duration = .seconds(10)) {
            // Kiesik: 45 mp-e nem jelentkezett, vagy a WebSocketje bezárult, `grace` ideje nem csatlakozott újra, és
            // azóta lekérdezés sem jött tőle (hirtelen bezárt böngésző, megszakadt hálózat).
            let expired = peers.filter { _, peer in
                peer.seen.duration(to: .now) > .seconds(45)
                    || (peer.socket == nil && peer.disconnected.map { $0.duration(to: .now) >= grace } == true && peer.seen.duration(to: .now) >= grace)
            }
            for (id, peer) in expired {
                hideCursor(peer)
                peer.socket?.close(promise: nil)
                peer.waiter?.succeed(())
                peers.removeValue(forKey: id)
            }
            if !peers.values.contains(where: \.editing) { checkpoint = nil }
            if let presenter = presentation?.client, peers[presenter] == nil { presentation = nil }
            var idleChanged = false
            for (id, peer) in peers where peer.isIdle(hold) != peer.idle {
                peers[id]?.idle = peer.isIdle(hold)
                idleChanged = true
            }
            if !expired.isEmpty || idleChanged { changed() }
        }

        /// Fiók nélküli résztvevő színe: a palettának a szobában még nem használt színe (a fiókok színe a beállításokból jön).
        func guestColor() -> String {
            let used = Set(peers.values.map(\.color))
            return userPalette.first(where: { !used.contains($0) }) ?? userPalette[peers.count % userPalette.count]
        }
    }

    let pages = PageUpdates()
    /// Ennyi ideje fogott és ennyi ideje tétlen résztvevő dobozát más átveheti (a tesztek rövidebbre állítják).
    var idleHold: Duration = .seconds(60)
    /// A bezárult WebSocket után ennyi idővel esik ki a résztvevő, ha nem csatlakozott újra és nem kérdezett le.
    var disconnectGrace: Duration = .seconds(10)
    private let store: WorksheetStore
    private let lock = NSLock()
    private var rooms: [String: Room] = [:]

    private var lastSweep = ContinuousClock.now

    private func expireInactiveRooms() {
        guard lastSweep.duration(to: .now) > .seconds(45) else { return }
        lastSweep = .now
        for key in Array(rooms.keys) {
            rooms[key]?.expire(hold: idleHold, grace: disconnectGrace)
            if rooms[key]?.peers.isEmpty == true { rooms.removeValue(forKey: key) }
        }
    }

    init(store: WorksheetStore) {
        self.store = store
    }

    func presence(_ path: WorksheetPath, user: User?, client: String, action: String, node: String?, edge: String? = nil,
                  since: String?, loop: any EventLoop, editing: Bool = false,
                  revision: Int? = nil, checkpointRevision: Int? = nil, unlocks: Set<String> = [], point: Point? = nil,
                  away: Bool? = nil, mode: String? = nil) throws -> (LiveState, EventLoopFuture<Void>?) {
        try lock.withLock {
            expireInactiveRooms()
            var board = try store.load(path, user: user, unlocks: unlocks)
            let access = try store.access(path, sheet: board, user: user, unlocks: unlocks)
            var room = rooms[path.url] ?? Room()
            room.expire(hold: idleHold, grace: disconnectGrace)
            room.revision = board.revision
            if let existing = room.peers[client], existing.name != user?.name { throw Abort(.forbidden) }
            if action == "snapshot" && room.peers[client] == nil { throw Abort(.gone) }
            if action == "leave" {
                let leaving = room.peers.removeValue(forKey: client)
                room.hideCursor(leaving)
                leaving?.socket?.close(promise: nil)
                leaving?.waiter?.succeed(())
                if !room.peers.values.contains(where: \.editing) { room.checkpoint = nil }
                if room.presentation?.client == client { room.presentation = nil }
                room.changed()
            } else {
                if action == "checkpoint" || action == "resign" {
                    guard access.editable, room.peers[client]?.editing == true,
                          var checkpoint = room.checkpoint else { throw Abort(.forbidden) }
                    guard revision == board.revision, checkpointRevision == checkpoint.revision else {
                        throw Abort(.preconditionFailed, reason: "A munkalap vagy a visszaállítási pont megváltozott. Ellenőrizd, majd próbáld újra.")
                    }
                    if action == "resign" {
                        checkpoint.revision = board.revision
                        board = try store.update(path, worksheet: checkpoint, user: user, restoring: true, unlocks: unlocks)
                        room.revision = board.revision
                        pages.publish(.content, at: path)
                        for id in Array(room.peers.keys) {
                            room.peers[id]?.node = nil
                            room.peers[id]?.edge = nil
                        }
                    }
                    room.checkpoint = board
                    room.changed()
                }
                if room.peers[client] == nil {
                    room.peers[client] = Peer(name: user?.name, role: user?.role, color: user == nil && !access.editable ? "" : user?.color ?? room.guestColor())
                    room.changed()
                }
                if let color = user?.color, room.peers[client]?.color != color {
                    room.peers[client]?.color = color
                    room.changed()
                }
                // A „status” kérés és minden hosszú lekérdezés hozza, hogy a résztvevő nézi-e a lapot.
                if let away {
                    if room.peers[client]?.away != away {
                        room.peers[client]?.away = away
                        if away {
                            room.hideCursor(room.peers[client])
                            room.peers[client]?.cursor = nil
                        }
                        room.changed()
                    }
                }
                if room.peers[client]?.avatar != user?.avatar {
                    room.peers[client]?.avatar = user?.avatar
                    room.changed()
                }
                if editing && action == "poll" {
                    guard access.editable else { throw Abort(.forbidden) }
                    room.peers[client]?.editing = true
                    if room.checkpoint == nil { room.checkpoint = board; room.changed() }
                }
                room.peers[client]?.seen = .now
                if ["select", "ping", "present", "unpresent", "checkpoint", "resign"].contains(action) { room.peers[client]?.active = .now }
                if action == "ping" {
                    guard user != nil || access.editable, let peer = room.peers[client], peer.seen.duration(to: .now) < .seconds(45),
                          node.map({ id in board.nodes.contains { $0.id == id } }) ?? (point?.isValid == true) else { throw Abort(.forbidden) }
                    struct Ping: Encodable {
                        let ping = true
                        let revision: Int
                        let node: String?
                        let point: Point?
                        /// A pinget küldő színe, neve és avatarja (a ping és a képernyőn kívüli ping nyila ezzel rajzolódik).
                        let color: String
                        let name: String
                        let avatar: Int?
                        /// A küldő azonosítója (`Participant.id`).
                        let peer: String
                    }
                    let data = try JSONEncoder().encode(Ping(revision: board.revision, node: node, point: point, color: peer.color,
                                                             name: peer.name ?? "Vendég", avatar: peer.avatar ?? (peer.name == nil ? nil : 1),
                                                             peer: peer.cursorID))
                    for (id, receiver) in room.peers where id != client {
                        receiver.socket?.send(String(decoding: data, as: UTF8.self))
                    }
                }
                // Előadás indítása / befejezése. Egyszerre egy előadó lehet; a futó előadást csak admin veheti át.
                if action == "present" {
                    guard let user, let mode, ["invite", "forced"].contains(mode) else { throw Abort(.forbidden) }
                    if let current = room.presentation, current.client != client, let presenter = room.peers[current.client],
                       user.role != .admin {
                        throw Abort(.locked, reason: "\(presenter.name ?? "Vendég") már előad.")
                    }
                    room.presentation = Presentation(client: client, mode: mode, rect: room.presentation?.client == client ? room.presentation?.rect : nil)
                    room.changed()
                }
                if action == "unpresent" {
                    if let current = room.presentation, current.client == client || user?.role == .admin {
                        room.presentation = nil
                        room.changed()
                    }
                }
                if action == "select" || action == "view-select" {
                    let viewing = action == "view-select"
                    guard viewing ? user != nil : access.editable else { throw Abort(.forbidden) }
                    if let node {
                        guard board.nodes.contains(where: { $0.id == node }) else { throw Abort(.notFound) }
                        if !viewing, let owner = room.peers.first(where: { $0.key != client && !$0.value.viewing && $0.value.node == node }) {
                            // Tétlen foglalás (legalább `idleHold` ideje fogja, és azóta nem csinált semmit): átvehető;
                            // a régi gazdája a következő lekérdezésben értesül (`lost`).
                            guard owner.value.isIdle(idleHold) else {
                                throw Abort(.locked, reason: "\(owner.value.name ?? "Vendég") már kijelölte ezt a dobozt.")
                            }
                            room.peers[owner.key]?.node = nil
                            room.peers[owner.key]?.edge = nil
                            room.peers[owner.key]?.idle = false
                            room.peers[owner.key]?.lost = LostHold(node: node, by: user?.name ?? "Vendég")
                            room.changed()
                        }
                    }
                    if let edge {
                        guard node == nil, board.edges.contains(where: { $0.id == edge }) else { throw Abort(.notFound) }
                    }
                    if room.peers[client]?.node != node || room.peers[client]?.edge != edge || room.peers[client]?.viewing != viewing {
                        if room.peers[client]?.node != node { room.peers[client]?.heldSince = .now }
                        room.peers[client]?.viewing = viewing
                        room.peers[client]?.edge = edge
                        room.peers[client]?.node = node
                        room.peers[client]?.idle = false
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
            var state = LiveState(version: room.version, revision: board.revision, checkpointRevision: room.checkpoint?.revision, checkpointChanged: changed, participants: room.peers.sorted { a, b in
                let adminA = a.value.role == .admin
                let adminB = b.value.role == .admin
                if adminA != adminB { return adminA }
                return a.value.joined == b.value.joined ? a.key < b.key : a.value.joined < b.value.joined
            }.map {
                Participant(id: $0.value.cursorID, name: $0.value.name ?? "Vendég", color: $0.value.color, node: $0.value.node, edge: $0.value.edge, avatar: $0.value.avatar ?? ($0.value.name == nil ? nil : 1), mine: $0.key == client, viewing: $0.value.viewing, away: $0.value.away,
                            idle: $0.value.idle, lost: $0.key == client ? $0.value.lost : nil)
            })
            // Az átvételről szóló értesítés egyszer megy ki.
            if room.peers[client]?.lost != nil { room.peers[client]?.lost = nil }
            if let presentation = room.presentation, let presenter = room.peers[presentation.client] {
                state.presentation = PresentationState(presenter: presenter.cursorID, name: presenter.name ?? "Vendég", color: presenter.color,
                                                       avatar: presenter.avatar ?? (presenter.name == nil ? nil : 1), mode: presentation.mode,
                                                       rect: presentation.rect)
            }
            rooms[path.url] = room.peers.isEmpty ? nil : room
            return (state, wait)
        }
    }

    /// `ownSelections`: a mentő felhasználó saját (másik ablakban lévő) kijelölése nem zárja a dobozt – a külön ablakos
    /// szövegszerkesztő így akkor is menthet, ha a lap szerkesztőjében ugyanő éppen kijelölve tartja a dobozt.
    func update(_ path: WorksheetPath, sheet: Worksheet, user: User?, client: String?, unlocks: Set<String> = [], restoring: Bool = false,
                ownSelections: Bool = false) throws -> Worksheet {
        try lock.withLock {
            rooms[path.url]?.expire(hold: idleHold, grace: disconnectGrace)
            let saved = try store.update(path, worksheet: sheet, user: user, restoring: restoring, unlocks: unlocks) { current in
                // Visszaállításkor a más által kijelölt dobozok nem akadályoznak; a kijelölések alább megszűnnek.
                if restoring { return }
                if let client {
                    guard let peer = rooms[path.url]?.peers[client], peer.name == user?.name else {
                        throw Abort(.conflict, reason: "Kapcsolódj újra a munkalaphoz.")
                    }
                    rooms[path.url]?.peers[client]?.active = .now
                }
                guard let room = rooms[path.url] else { return }
                let locked = Set(room.peers.filter { $0.key != client && !$0.value.viewing && !(ownSelections && $0.value.name == user?.name) }
                    .values.compactMap(\.node))
                guard !locked.isEmpty else { return }
                let submitted = Dictionary(sheet.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for node in current.nodes where locked.contains(node.id) && submitted[node.id] != node {
                    // Removing the last cable also removes its orphaned connection point.
                    if node.isJunction && submitted[node.id] == nil { continue }
                    throw Abort(.locked, reason: "A dobozt egy másik felhasználó jelölte ki.")
                }
            }
            if var room = rooms[path.url] {
                room.revision = saved.revision
                let ids = Set(saved.nodes.map(\.id))
                let edges = Set(saved.edges.map(\.id))
                for (id, peer) in room.peers {
                    if let node = peer.node, restoring || !ids.contains(node) { room.peers[id]?.node = nil }
                    if let edge = peer.edge, restoring || !edges.contains(edge) { room.peers[id]?.edge = nil }
                }
                if !room.peers.values.contains(where: \.editing) { room.checkpoint = nil }
                room.changed()
                rooms[path.url] = room
            }
            pages.publish(.content, at: path)
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
            rooms[path.url]?.peers[client]?.disconnected = nil
            for (id, other) in rooms[path.url]?.peers ?? [:] where id != client {
                if let cursor = other.cursor { socket.send(cursor.message) }
                if let cells = other.cells, other.node == cells.node { socket.send(cells.message) }
            }
            if let room = rooms[path.url], let presentation = room.presentation, presentation.client != client,
               let presenter = room.peers[presentation.client], let message = presentation.message(from: presenter) {
                socket.send(message)
            }
            return true
        }
        guard attached else { socket.close(promise: nil); return }
        socket.onText { [weak self] socket, text in
            guard text.utf8.count < 512 else { return }
            // Tevékenység (egér, billentyű, görgetés a lapon; a kliens legfeljebb 10 mp-enként küldi): a tétlen foglalás
            // ebből számol.
            struct Active: Decodable { let active: Bool }
            if let frame = try? JSONDecoder().decode(Active.self, from: Data(text.utf8)), frame.active {
                self?.noteActivity(path, client: client, socket: socket)
                return
            }
            struct Pointer: Decodable { let mouse: Bool; let point: Point? }
            if let pointer = try? JSONDecoder().decode(Pointer.self, from: Data(text.utf8)) {
                guard pointer.mouse, pointer.point?.isValid != false else { return }
                self?.lock.withLock {
                    guard let room = self?.rooms[path.url], let peer = room.peers[client], let name = peer.name,
                          peer.socket === socket, peer.seen.duration(to: .now) < .seconds(45),
                          !peer.away || pointer.point == nil else { return }
                    let cursor = Cursor(cursor: peer.cursorID, color: peer.color, name: name, avatar: peer.avatar ?? 1, point: pointer.point)
                    self?.rooms[path.url]?.peers[client]?.cursor = pointer.point == nil ? nil : cursor
                    if pointer.point != nil { self?.rooms[path.url]?.peers[client]?.active = .now }
                    let message = cursor.message
                    for (id, other) in room.peers where id != client { other.socket?.send(message) }
                }
                return
            }
            // Rajzeszközök (lézer pointer, filctoll, Public/laser.js): a vonás pontjai (x, y párok, munkalap-koordinátában) a
            // küldő színével mennek a többieknek. `kind`: "marker" (filc) vagy hiányzik (lézer); `clear`: a filcvonás új rajzot
            // kezd, a küldő előző filcrajza törlődik. Nem tárolódik; a nem aktív (más ablakot néző) résztvevőé nem megy tovább.
            struct Laser: Decodable { let laser: Bool; let stroke: Int; let points: [Double]; let end: Bool?; let kind: String?; let clear: Bool? }
            if let frame = try? JSONDecoder().decode(Laser.self, from: Data(text.utf8)) {
                guard frame.laser, frame.points.count <= 64, frame.points.count % 2 == 0, frame.kind == nil || frame.kind == "marker",
                      frame.points.allSatisfy({ $0.isFinite && abs($0) <= 100_000 }) else { return }
                self?.lock.withLock {
                    guard let room = self?.rooms[path.url], let sender = room.peers[client], sender.name != nil,
                          sender.socket === socket, !sender.away, sender.seen.duration(to: .now) < .seconds(45) else { return }
                    struct Relay: Encodable { let laser: String; let color: String; let stroke: Int; let points: [Double]; let end: Bool?
                                              let kind: String?; let clear: Bool? }
                    guard let data = try? JSONEncoder().encode(Relay(laser: sender.cursorID, color: sender.color, stroke: frame.stroke,
                                                                     points: frame.points, end: frame.end, kind: frame.kind,
                                                                     clear: frame.clear)) else { return }
                    let message = String(decoding: data, as: UTF8.self)
                    self?.rooms[path.url]?.peers[client]?.active = .now
                    for (id, other) in room.peers where id != client { other.socket?.send(message) }
                }
                return
            }
            // Előadás kerete: csak az előadótól; eltárolódik (a később belépők is megkapják) és megy a többieknek.
            struct Present: Decodable { let present: Bool; let rect: [Double] }
            if let frame = try? JSONDecoder().decode(Present.self, from: Data(text.utf8)) {
                guard frame.present, frame.rect.count == 4, frame.rect.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
                      frame.rect[2] > 0, frame.rect[3] > 0 else { return }
                self?.lock.withLock {
                    guard let room = self?.rooms[path.url], let sender = room.peers[client], sender.socket === socket,
                          room.presentation?.client == client, sender.seen.duration(to: .now) < .seconds(45) else { return }
                    self?.rooms[path.url]?.presentation?.rect = frame.rect
                    guard let message = self?.rooms[path.url]?.presentation?.message(from: sender) else { return }
                    for (id, other) in room.peers where id != client { other.socket?.send(message) }
                }
                return
            }
            struct Cells: Decodable { let cells: Bool; let node: String; let range: CellMark.Range? }
            if let frame = try? JSONDecoder().decode(Cells.self, from: Data(text.utf8)) {
                guard frame.cells, frame.range?.isValid != false else { return }
                self?.lock.withLock {
                    guard let room = self?.rooms[path.url], let sender = room.peers[client], sender.socket === socket,
                          !sender.viewing, frame.range == nil || sender.node == frame.node,
                          sender.seen.duration(to: .now) < .seconds(45) else { return }
                    let mark = CellMark(cells: sender.cursorID, node: frame.node, color: sender.color, range: frame.range)
                    self?.rooms[path.url]?.peers[client]?.cells = frame.range == nil ? nil : mark
                    self?.rooms[path.url]?.peers[client]?.active = .now
                    let message = mark.message
                    for (id, other) in room.peers where id != client { other.socket?.send(message) }
                }
                return
            }
            // Görgetés élő követése: aki a dobozt fogja, annak a görgetési helyzete megy a többieknek (a mentés külön, a
            // munkalappal történik). Nem tárolódik.
            struct Scroll: Codable { let scroll: Bool; let node: String; let x: Double; let y: Double }
            if let frame = try? JSONDecoder().decode(Scroll.self, from: Data(text.utf8)) {
                guard frame.scroll, frame.x.isFinite, frame.y.isFinite, (0...100_000).contains(frame.x), (0...100_000).contains(frame.y) else { return }
                self?.lock.withLock {
                    guard let room = self?.rooms[path.url], let sender = room.peers[client], sender.socket === socket,
                          !sender.viewing, sender.node == frame.node, sender.seen.duration(to: .now) < .seconds(45) else { return }
                    self?.rooms[path.url]?.peers[client]?.active = .now
                    for (id, other) in room.peers where id != client { other.socket?.send(text) }
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
                self?.rooms[path.url]?.peers[client]?.active = .now
                for (id, peer) in room.peers where id != client && peer.seen.duration(to: .now) < .seconds(45) {
                    peer.socket?.send(String(decoding: data, as: UTF8.self))
                }
            }
        }
        let loop = socket.eventLoop
        socket.onClose.whenComplete { [weak self, weak socket] _ in
            self?.lock.withLock {
                if self?.rooms[path.url]?.peers[client]?.socket === socket {
                    self?.rooms[path.url]?.hideCursor(self?.rooms[path.url]?.peers[client])
                    self?.rooms[path.url]?.peers[client]?.cursor = nil
                    if var cells = self?.rooms[path.url]?.peers[client]?.cells {
                        cells.range = nil
                        let message = cells.message
                        for peer in (self?.rooms[path.url]?.peers ?? [:]).values { peer.socket?.send(message) }
                        self?.rooms[path.url]?.peers[client]?.cells = nil
                    }
                    self?.rooms[path.url]?.peers[client]?.socket = nil
                    self?.rooms[path.url]?.peers[client]?.disconnected = .now
                    if let room = self?.rooms[path.url], let node = room.peers[client]?.node {
                        let clear = "{\"node\":\"\(node)\",\"revision\":\(room.revision)}"
                        for peer in room.peers.values { peer.socket?.send(clear) }
                    }
                }
            }
            // Ha nem csatlakozik újra és nem is kérdez le, a türelmi idő után kiesik, és a foglalása felszabadul
            // (a többiek hosszú lekérdezése ezzel azonnal visszatér).
            guard let self else { return }
            self.scheduleSweep(path, on: loop, after: self.disconnectGrace)
        }
    }

    /// A szoba lejárt résztvevőinek eltávolítása `after` idő múlva, majd `disconnectGrace`-enként, amíg van szakadt kapcsolatú
    /// résztvevő (a lekérdezés a türelmi időn belül is jöhetett, ilyenkor később esik ki).
    private func scheduleSweep(_ path: WorksheetPath, on loop: any EventLoop, after delay: Duration) {
        let nanoseconds = Int64(delay.components.seconds) * 1_000_000_000 + Int64(delay.components.attoseconds / 1_000_000_000)
        loop.scheduleTask(in: .nanoseconds(max(1, nanoseconds))) { [weak self] in
            guard let self else { return }
            let pending = self.lock.withLock { () -> Bool in
                self.rooms[path.url]?.expire(hold: self.idleHold, grace: self.disconnectGrace)
                if self.rooms[path.url]?.peers.isEmpty == true { self.rooms.removeValue(forKey: path.url) }
                return self.rooms[path.url]?.peers.values.contains { $0.socket == nil && $0.disconnected != nil } == true
            }
            if pending { self.scheduleSweep(path, on: loop, after: self.disconnectGrace) }
        }
    }

    /// Tevékenység a WebSocketen (és a tesztekben közvetlenül): a résztvevő nem tétlen.
    func noteActivity(_ path: WorksheetPath, client: String, socket: WebSocket? = nil) {
        lock.withLock {
            guard let peer = rooms[path.url]?.peers[client], socket == nil || peer.socket === socket else { return }
            rooms[path.url]?.peers[client]?.active = .now
            if peer.idle {
                rooms[path.url]?.peers[client]?.idle = false
                rooms[path.url]?.changed()
            }
        }
    }

    /// A WebSocket bezárulásának jelzése (a tesztekben közvetlenül; élesben az onClose).
    func markDisconnected(_ path: WorksheetPath, client: String) {
        lock.withLock {
            rooms[path.url]?.peers[client]?.socket = nil
            rooms[path.url]?.peers[client]?.disconnected = .now
        }
    }

    /// Csevegés: az új vagy törölt üzenet azonnal megy a szoba bejelentkezett résztvevőinek (a vendég nem kapja).
    func broadcastChat(_ path: WorksheetPath, message: String) {
        lock.withLock {
            for peer in (rooms[path.url]?.peers ?? [:]).values where peer.name != nil { peer.socket?.send(message) }
        }
    }

    func accountChanged() {
        lock.withLock {
            for key in Array(rooms.keys) { rooms[key]?.changed() }
            pages.publishAccountChange()
        }
    }

    func manage(_ path: WorksheetPath, operation: DocumentAction, user: User, unlocks: Set<String>) throws -> WorksheetPath? {
        // A jelszó hash-e a zárakon kívül készül, különben a bcrypt idejére minden kérés megállna.
        let passwordHash = try WorksheetStore.passwordHash(for: operation)
        return try lock.withLock {
            let result = try store.manage(path, operation: operation, user: user, unlocks: unlocks, passwordHash: passwordHash)
            invalidate(path)
            pages.publish(.structure, at: path)
            if let result, result.url != path.url { pages.publish(.structure, at: result) }
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
            pages.publish(.structure, at: path)
        }
    }
}
