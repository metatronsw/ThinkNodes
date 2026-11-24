import Foundation
import Vapor

package final class PageUpdates: @unchecked Sendable {
    package init() {}

    package enum Scope: Hashable {
        case index, admin, viewer(String), editor(String)
    }

    package enum Change {
        case content, attachments, structure
    }

    package struct Subscription {
        let id: UUID
        package let version: UUID
    }

    private struct Feed {
        package let scope: Scope
        package var version = UUID()
        var waiters: [UUID: EventLoopPromise<Void>] = [:]
    }

    private let lock = NSLock()
    private var ids: [Scope: UUID] = [:]
    private var feeds: [UUID: Feed] = [:]

    package func subscribe(_ scope: Scope) -> Subscription {
        lock.withLock {
            let id = ids[scope] ?? UUID()
            if feeds[id] == nil {
                ids[scope] = id
                feeds[id] = Feed(scope: scope)
            }
            return Subscription(id: id, version: feeds[id]!.version)
        }
    }

    package func wait(_ id: UUID, since: UUID, on loop: any EventLoop) async throws -> UUID {
        let version = try await lock.withLock {
            guard let feed = feeds[id] else { throw Abort(.gone) }
            guard feed.version == since else { return loop.makeSucceededFuture(feed.version) }
            let request = UUID()
            let promise = loop.makePromise(of: Void.self)
            feeds[id]?.waiters[request] = promise
            let timeout = loop.scheduleTask(in: .seconds(20)) { [weak self] in
                self?.finishWait(id, request: request)
            }
            return promise.futureResult.flatMapThrowing { [self] in
                timeout.cancel()
                return try lock.withLock {
                    guard let version = feeds[id]?.version else { throw Abort(.gone) }
                    return version
                }
            }
        }.get()
        return version
    }

    private func finishWait(_ id: UUID, request: UUID) {
        let waiter = lock.withLock { feeds[id]?.waiters.removeValue(forKey: request) }
        waiter?.succeed(())
    }

    package func publish(_ change: Change, at path: WorksheetPath) {
        let parent = path.url.split(separator: "/").dropLast().joined(separator: "/")
        wake { scope in
            switch scope {
            case .index: change == .structure || path.parts.count == 1
            case .admin: false
            case .viewer(let url):
                url == path.url || url == parent || (change == .structure && url.hasPrefix(path.url + "/"))
            case .editor(let url):
                change != .content && (url == path.url || (change == .structure && url.hasPrefix(path.url + "/")))
            }
        }
    }

    package func publishAccountChange() {
        wake { _ in true }
    }

    private func wake(_ matches: (Scope) -> Bool) {
        let waiters = lock.withLock {
            let version = UUID()
            return feeds.keys.filter { matches(feeds[$0]!.scope) }.flatMap { id -> [EventLoopPromise<Void>] in
                feeds[id]?.version = version
                let pending = feeds[id]?.waiters.values.map { $0 } ?? []
                feeds[id]?.waiters.removeAll()
                return pending
            }
        }
        for waiter in waiters { waiter.succeed(()) }
    }
}
