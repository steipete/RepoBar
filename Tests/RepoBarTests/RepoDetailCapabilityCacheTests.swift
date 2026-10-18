import Foundation
@testable import RepoBarCore
import Testing

struct RepoDetailCapabilityCacheTests {
    @Test
    func `discussions capability respects TTL`() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appending(path: "repobar-capability-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: baseURL)
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("json"))
        }

        let diskStore = RepoDetailCacheStore(fileManager: .default, baseURL: baseURL)
        let store = RepoDetailStore(diskStore: diskStore)
        let apiHost = try #require(URL(string: "https://api.github.com"))
        let now = Date(timeIntervalSinceReferenceDate: 123_456)

        _ = await store.updateDiscussionsEnabled(
            apiHost: apiHost,
            owner: "steipete",
            name: "RepoBar",
            enabled: false,
            checkedAt: now
        )

        let cached = await store.discussionsEnabled(
            apiHost: apiHost,
            owner: "steipete",
            name: "RepoBar",
            now: now,
            ttl: 60
        )
        #expect(cached == false)

        let stale = await store.discussionsEnabled(
            apiHost: apiHost,
            owner: "steipete",
            name: "RepoBar",
            now: now.addingTimeInterval(61),
            ttl: 60
        )
        #expect(stale == nil)
    }

    @Test
    func `discussions capability persists across stores`() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appending(path: "repobar-capability-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: baseURL)
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("json"))
        }

        let diskStore = RepoDetailCacheStore(fileManager: .default, baseURL: baseURL)
        let apiHost = try #require(URL(string: "https://api.github.com"))
        let now = Date(timeIntervalSinceReferenceDate: 222_222)

        let writer = RepoDetailStore(diskStore: diskStore)
        _ = await writer.updateDiscussionsEnabled(
            apiHost: apiHost,
            owner: "steipete",
            name: "RepoBar",
            enabled: true,
            checkedAt: now
        )

        await writer.flush()

        let reader = RepoDetailStore(diskStore: RepoDetailCacheStore(baseURL: baseURL))
        let cached = await reader.discussionsEnabled(
            apiHost: apiHost,
            owner: "steipete",
            name: "RepoBar",
            now: now,
            ttl: 3600
        )
        #expect(cached == true)
    }
}
