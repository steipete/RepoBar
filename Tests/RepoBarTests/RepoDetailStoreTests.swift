import Foundation
@testable import RepoBarCore
import Synchronization
import Testing

struct RepoDetailStoreTests {
    @Test
    func `cache policy marks fresh and stale`() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let cache = RepoDetailCache(
            openPulls: 1,
            openPullsFetchedAt: now.addingTimeInterval(-7200),
            ciFetchedAt: now.addingTimeInterval(-600)
        )
        let policy = RepoDetailCachePolicy(
            openPullsTTL: 3600,
            ciTTL: 3600,
            activityTTL: 3600,
            trafficTTL: 3600,
            heatmapTTL: 3600,
            releaseTTL: 3600
        )

        let state = policy.state(for: cache, now: now)
        #expect(state.openPulls == .stale)
        #expect(state.ci == .fresh)
        #expect(state.activity == .missing)
    }

    @Test
    func `default heatmap policy keeps stats stale ok for a day`() {
        #expect(RepoDetailCacheConstants.heatmapTTL == 24 * 60 * 60)
    }

    @Test
    func `store uses memory after disk removal`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        await store.save(RepoDetailCache(openPulls: 5), apiHost: fixture.host, owner: "me", name: "Repo")
        await store.flush()
        try FileManager.default.removeItem(at: fixture.snapshot)

        let loaded = await store.load(apiHost: fixture.host, owner: "me", name: "Repo")
        #expect(loaded.openPulls == 5)
    }

    @Test
    func `save then load preserves repositories hosts and timestamps`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let enterprise = try #require(URL(string: "https://github.example.com/api/v3"))
        let now = Date(timeIntervalSinceReferenceDate: 123_456)
        await store.save(RepoDetailCache(openPulls: 9, openPullsFetchedAt: now), apiHost: fixture.host, owner: "me", name: "Repo")
        await store.save(RepoDetailCache(openPulls: 4), apiHost: enterprise, owner: "me", name: "Repo")
        await store.save(RepoDetailCache(openPulls: 2), apiHost: fixture.host, owner: "other", name: "Repo")
        await store.flush()

        let reloaded = fixture.store()
        let cache = await reloaded.load(apiHost: fixture.host, owner: "me", name: "Repo")
        #expect(cache.openPulls == 9)
        #expect(cache.openPullsFetchedAt == now)
        #expect(await reloaded.load(apiHost: enterprise, owner: "me", name: "Repo").openPulls == 4)
        #expect(await reloaded.load(apiHost: fixture.host, owner: "other", name: "Repo").openPulls == 2)

        // Updating one entry after relaunch must retain the rest of the snapshot.
        await reloaded.save(RepoDetailCache(openPulls: 10), apiHost: fixture.host, owner: "me", name: "Repo")
        await reloaded.flush()
        let third = fixture.store()
        #expect(await third.load(apiHost: enterprise, owner: "me", name: "Repo").openPulls == 4)
    }

    @Test
    func `hundreds of saves coalesce into one snapshot write`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        for index in 0 ..< 597 {
            await store.save(RepoDetailCache(openPulls: index), apiHost: fixture.host, owner: "me", name: "Repo\(index)")
        }
        #expect(fixture.writeCount == 0)
        #expect(await store.load(apiHost: fixture.host, owner: "me", name: "Repo596").openPulls == 596)
        await store.flush()
        #expect(fixture.writeCount == 1)
        await store.flush()
        #expect(fixture.writeCount == 1)
        let snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.snapshot)) as? [String: Any]
        #expect(snapshot?.count == 597)
    }

    @Test(.timeLimit(.minutes(1)))
    func `dirty cache flushes automatically`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let writes = AsyncStream<Void>.makeStream()
        let disk = RepoDetailCacheStore(baseURL: fixture.legacy) { data, url in
            try data.write(to: url, options: .atomic)
            writes.continuation.yield(())
        }
        let store = RepoDetailStore(diskStore: disk, flushDelay: .milliseconds(10))
        await store.save(RepoDetailCache(openPulls: 1), apiHost: fixture.host, owner: "me", name: "Repo")
        var iterator = writes.stream.makeAsyncIterator()
        _ = await iterator.next()
        writes.continuation.finish()
        let reloaded = fixture.store()
        #expect(await reloaded.load(apiHost: fixture.host, owner: "me", name: "Repo").openPulls == 1)
    }

    @Test
    func `unchanged bytes skip writes including after relaunch`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let cache = RepoDetailCache(openPulls: 9, openPullsFetchedAt: Date(timeIntervalSinceReferenceDate: 123))
        await store.save(cache, apiHost: fixture.host, owner: "me", name: "Repo")
        await store.flush()
        await store.save(cache, apiHost: fixture.host, owner: "me", name: "Repo")
        await store.flush()
        let reloaded = fixture.store()
        await reloaded.save(cache, apiHost: fixture.host, owner: "me", name: "Repo")
        await reloaded.flush()
        #expect(fixture.writeCount == 1)

        // Fetched-at timestamps still persist even when the displayed value is unchanged.
        let refreshed = RepoDetailCache(openPulls: 9, openPullsFetchedAt: Date(timeIntervalSinceReferenceDate: 456))
        await reloaded.save(refreshed, apiHost: fixture.host, owner: "me", name: "Repo")
        await reloaded.flush()
        #expect(fixture.writeCount == 2)
    }

    @Test
    func `legacy directory is discarded without importing or deleting snapshot`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        await store.save(RepoDetailCache(openPulls: 9), apiHost: fixture.host, owner: "me", name: "Repo")
        await store.flush()
        let legacyFile = fixture.legacy.appending(path: "api.github.com/me/Old.json")
        try FileManager.default.createDirectory(at: legacyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"openPulls\":99}".utf8).write(to: legacyFile)

        let reloaded = fixture.store()
        #expect(await reloaded.load(apiHost: fixture.host, owner: "me", name: "Repo").openPulls == 9)
        #expect(await reloaded.load(apiHost: fixture.host, owner: "me", name: "Old").openPulls == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.legacy.path))
        #expect(FileManager.default.fileExists(atPath: fixture.snapshot.path))
    }

    @Test
    func `clear drops memory disk and pending saves`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        await store.save(RepoDetailCache(openPulls: 2), apiHost: fixture.host, owner: "me", name: "Repo")
        await store.flush()
        await store.save(RepoDetailCache(openPulls: 3), apiHost: fixture.host, owner: "me", name: "Repo")
        await store.clear()
        await store.flush()
        #expect(await store.load(apiHost: fixture.host, owner: "me", name: "Repo").openPulls == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshot.path))
        #expect(fixture.writeCount == 1)
        let reloaded = fixture.store()
        #expect(await reloaded.load(apiHost: fixture.host, owner: "me", name: "Repo").openPulls == nil)

        await store.save(RepoDetailCache(openPulls: 2), apiHost: fixture.host, owner: "me", name: "Repo")
        await store.flush()
        #expect(fixture.writeCount == 2)
        #expect(FileManager.default.fileExists(atPath: fixture.snapshot.path))
    }

    @Test
    func `hostless URL uses github fallback key`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        await store.save(RepoDetailCache(openPulls: 1), apiHost: URL(fileURLWithPath: "/tmp"), owner: "me", name: "Repo")
        #expect(await store.load(apiHost: fixture.host, owner: "me", name: "Repo").openPulls == 1)
        await store.flush()
    }

    @Test
    func `failed write retains dirty memory for retry`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.remove() }
        let fail = Mutex(true)
        let disk = RepoDetailCacheStore(baseURL: fixture.legacy) { data, url in
            if fail.withLock({ $0 }) {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: url, options: .atomic)
        }
        let store = RepoDetailStore(diskStore: disk, flushDelay: .seconds(3600))
        await store.save(RepoDetailCache(openPulls: 7), apiHost: fixture.host, owner: "me", name: "Repo")
        await store.flush()
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshot.path))
        #expect(await store.load(apiHost: fixture.host, owner: "me", name: "Repo").openPulls == 7)
        fail.withLock { $0 = false }
        await store.flush()
        let reloaded = fixture.store()
        #expect(await reloaded.load(apiHost: fixture.host, owner: "me", name: "Repo").openPulls == 7)
    }
}

private final class CacheFixture: Sendable {
    let root: URL
    let legacy: URL
    let snapshot: URL
    let host = URL(string: "https://api.github.com")!
    private let writes = Mutex(0)

    var writeCount: Int {
        self.writes.withLock { $0 }
    }

    init() throws {
        self.root = FileManager.default.temporaryDirectory.appending(path: "repobar-cache-\(UUID().uuidString)")
        self.legacy = self.root.appending(path: "RepoDetailCache")
        self.snapshot = self.legacy.appendingPathExtension("json")
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func store() -> RepoDetailStore {
        let disk = RepoDetailCacheStore(baseURL: self.legacy) { [self] data, url in
            try data.write(to: url, options: .atomic)
            self.writes.withLock { $0 += 1 }
        }
        return RepoDetailStore(diskStore: disk, flushDelay: .seconds(3600))
    }

    func remove() {
        try? FileManager.default.removeItem(at: self.root)
    }
}
