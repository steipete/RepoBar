import Foundation
@testable import RepoBarCore
import Testing

struct RepoDetailCacheStoreTests {
    @Test
    func `save and load round trip`() throws {
        let baseURL = FileManager.default.temporaryDirectory.appending(path: "repobar-cache-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: baseURL)
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("json"))
        }

        var store = RepoDetailCacheStore(fileManager: .default, baseURL: baseURL)
        let now = Date(timeIntervalSinceReferenceDate: 123_456)

        let cache = try RepoDetailCache(
            openPulls: 7,
            openPullsFetchedAt: now,
            ciDetails: CIStatusDetails(status: .passing, runCount: 42),
            ciFetchedAt: now,
            latestActivity: ActivityEvent(
                title: "Merged PR",
                actor: "alice",
                date: now,
                url: #require(URL(string: "https://example.com/pr/1"))
            ),
            activityEvents: [
                ActivityEvent(
                    title: "Merged PR",
                    actor: "alice",
                    date: now,
                    url: #require(URL(string: "https://example.com/pr/1"))
                ),
                ActivityEvent(
                    title: "Opened issue",
                    actor: "bob",
                    date: now.addingTimeInterval(-600),
                    url: #require(URL(string: "https://example.com/issue/2"))
                )
            ],
            activityFetchedAt: now,
            traffic: TrafficStats(uniqueVisitors: 9, uniqueCloners: 2),
            trafficFetchedAt: now,
            heatmap: [HeatmapCell(date: now, count: 3)],
            heatmapFetchedAt: now,
            latestRelease: Release(name: "v1.0.0", tag: "v1.0.0", publishedAt: now, url: #require(URL(string: "https://example.com/release"))),
            releaseFetchedAt: now,
            discussionsEnabled: true,
            discussionsCheckedAt: now
        )

        let saved = store.save(["api.github.com::steipete/RepoBar": cache])
        #expect(saved)
        let loaded = store.load()["api.github.com::steipete/RepoBar"]

        let result = try #require(loaded)
        #expect(result.openPulls == 7)
        #expect(result.ciDetails?.status == .passing)
        #expect(result.latestActivity?.actor == "alice")
        #expect(result.activityEvents?.count == 2)
        #expect(result.traffic?.uniqueVisitors == 9)
        #expect(result.heatmap?.count == 1)
        #expect(result.latestRelease?.tag == "v1.0.0")
        #expect(result.discussionsEnabled == true)
    }

    @Test
    func `load corrupt cache removes file`() throws {
        let baseURL = FileManager.default.temporaryDirectory.appending(path: "repobar-cache-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: baseURL)
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("json"))
        }

        var store = RepoDetailCacheStore(fileManager: .default, baseURL: baseURL)

        let cacheFile = baseURL.appendingPathExtension("json")

        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cacheFile, options: .atomic)

        #expect(store.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: cacheFile.path()) == false)
    }

    @Test
    func `clear removes snapshot`() {
        let baseURL = FileManager.default.temporaryDirectory.appending(path: "repobar-cache-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: baseURL)
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("json"))
        }

        var store = RepoDetailCacheStore(fileManager: .default, baseURL: baseURL)

        let saved = store.save(["api.github.com::steipete/RepoBar": RepoDetailCache()])
        #expect(saved)
        #expect(FileManager.default.fileExists(atPath: baseURL.appendingPathExtension("json").path()))

        store.clear()
        #expect(FileManager.default.fileExists(atPath: baseURL.appendingPathExtension("json").path()) == false)
    }
}
