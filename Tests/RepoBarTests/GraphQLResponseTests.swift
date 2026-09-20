import Foundation
@testable import RepoBarCore
import Testing

struct GraphQLResponseTests {
    @Test(arguments: [
        #"{"errors":[{"message":"Something went wrong while executing your query"}]}"#,
        #"{"data":null,"errors":[{"message":"Something went wrong while executing your query"}]}"#,
        #"{"data":{"repository":null},"errors":[{"message":"Something went wrong while executing your query"}]}"#
    ])
    func `error envelope preserves git hub message`(body: String) throws {
        #expect(throws: GraphQLResponseError.self) {
            try GraphQLClient.decodeRepoSummary(from: Data(body.utf8), owner: "owner", name: "repo")
        }
        do {
            try GraphQLResponseValidator.validate(Data(body.utf8))
        } catch {
            #expect(error.localizedDescription == "GitHub GraphQL: Something went wrong while executing your query")
        }
    }

    @Test
    func `missing data is not A decoding error`() {
        #expect(throws: GraphQLResponseError.self) {
            try GraphQLClient.decodeRepoSummary(from: Data("{}".utf8), owner: "owner", name: "repo")
        }
    }

    @Test(arguments: [false, true])
    func `failed responses are not cached`(contributions: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GraphQLResponseTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Cache.sqlite").path
        let cache = try GraphQLResponseDiskCache(path: path)
        let transport = GraphQLTestTransport(bodies: [
            #"{"errors":[{"message":"Temporary query failure"}]}"#,
            contributions ? #"{"data":{"user":null}}"# : Self.summary
        ])
        let client = GraphQLClient(responseCache: cache, dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        await client.setTokenProvider { "test-token" }
        do {
            if contributions {
                _ = try await client.userContributionHeatmap(login: "owner")
            } else {
                _ = try await client.repoSummary(owner: "owner", name: "repo")
            }
            Issue.record("Expected the GraphQL error")
        } catch let error as GraphQLResponseError {
            #expect(error.message.contains("Temporary query failure"))
        }
        if contributions {
            _ = try await client.userContributionHeatmap(login: "owner")
        } else {
            #expect(try await client.repoSummary(owner: "owner", name: "repo").openIssues == 4)
        }
        #expect(await transport.requests.count == 2)
    }

    @Test
    func `invalid legacy cache is bypassed`() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GraphQLResponseTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Cache.sqlite").path
        let cache = try GraphQLResponseDiskCache(path: path)
        let transport = GraphQLTestTransport(bodies: [Self.summary, Self.summary])
        let client = GraphQLClient(responseCache: cache, dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        await client.setTokenProvider { "test-token" }
        _ = try await client.repoSummary(owner: "owner", name: "repo")
        let request = try #require(await transport.requests.first)
        let endpoint = try #require(request.url)
        let body = try #require(request.httpBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        let key = "\(endpoint.absoluteString)\tRepoSummary\t\(bodyString)"
        let legacyCache = try GraphQLResponseDiskCache(path: path)
        legacyCache.save(key: key, endpoint: endpoint, operation: "RepoSummary", body: body, responseBody: Data("{}".utf8))

        #expect(try await client.repoSummary(owner: "owner", name: "repo").openIssues == 4)
        #expect(await transport.requests.count == 2)
        _ = try await client.repoSummary(owner: "owner", name: "repo")
        #expect(await transport.requests.count == 2)
    }

    private static let summary = #"{"data":{"repository":{"latestRelease":null,"issues":{"totalCount":4},"pullRequests":{"totalCount":2}}}}"#

    @Test
    func `restart retains quota while repository data stays cached`() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GraphQLQuotaTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Cache.sqlite").path
        let reset = Date().addingTimeInterval(3600)
        let transport = GraphQLTestTransport(bodies: [Self.summary], headers: [
            "X-RateLimit-Resource": "graphql", "X-RateLimit-Limit": "5000",
            "X-RateLimit-Remaining": "842", "X-RateLimit-Used": "4158",
            "X-RateLimit-Reset": String(Int(reset.timeIntervalSince1970))
        ])
        let loader = HTTPDataLoader { try await transport.data(for: $0) }
        let first = try GraphQLClient(responseCache: GraphQLResponseDiskCache(path: path), dataLoader: loader)
        await first.setTokenProvider { "test-token" }
        _ = try await first.repoSummary(owner: "owner", name: "repo")
        let original = try #require(await first.rateLimitSnapshot())

        let restarted = try GraphQLClient(responseCache: GraphQLResponseDiskCache(path: path), dataLoader: loader)
        await restarted.setTokenProvider { "test-token" }
        #expect(try await restarted.repoSummary(owner: "owner", name: "repo").openIssues == 4)
        let restored = try #require(await restarted.rateLimitSnapshot())
        #expect(restored.remaining == 842)
        #expect(restored.fetchedAt == original.fetchedAt)
        #expect(restored.reset == original.reset)
        #expect(await transport.requests.count == 1)

        try await restarted.setEndpoint(apiHost: #require(URL(string: "https://github.example/api/v3")))
        #expect(await restarted.rateLimitSnapshot() == nil)
        try await restarted.setEndpoint(apiHost: #require(URL(string: "https://api.github.com")))
        #expect(await restarted.rateLimitSnapshot()?.remaining == 842)

        let otherAccount = try GraphQLClient(responseCache: GraphQLResponseDiskCache(path: folder.appending(path: "Other.sqlite").path))
        #expect(await otherAccount.rateLimitSnapshot() == nil)
    }

    @Test
    func `persisted quota expires and clears with account cache`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GraphQLQuotaTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Cache.sqlite").path
        let cache = try GraphQLResponseDiskCache(path: path)
        let endpoint = try #require(URL(string: "https://api.github.com/graphql"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(60)
        cache.saveRateLimitSnapshot(
            RateLimitSnapshot(resource: "graphql", limit: 5000, remaining: 842, used: 4158, reset: reset, fetchedAt: now),
            endpoint: endpoint
        )
        #expect(cache.rateLimitSnapshot(endpoint: endpoint, now: now)?.remaining == 842)
        #expect(cache.rateLimitSnapshot(endpoint: endpoint, now: reset) == nil)
        try HTTPResponseDiskCache(path: path).clear()
        #expect(cache.rateLimitSnapshot(endpoint: endpoint, now: now) == nil)
    }

    @Test(arguments: [false, true])
    func `legacy cached data attempts one quota refresh and retains offline fallback`(offline: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GraphQLQuotaTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Cache.sqlite").path
        let legacyTransport = GraphQLTestTransport(bodies: [Self.summary])
        let legacy = try GraphQLClient(responseCache: GraphQLResponseDiskCache(path: path), dataLoader: HTTPDataLoader { try await legacyTransport.data(for: $0) })
        await legacy.setTokenProvider { "test-token" }
        _ = try await legacy.repoSummary(owner: "owner", name: "repo")

        let liveTransport = GraphQLTestTransport(bodies: offline ? [] : [Self.summary], headers: [
            "X-RateLimit-Resource": "graphql", "X-RateLimit-Limit": "5000",
            "X-RateLimit-Remaining": "842", "X-RateLimit-Reset": String(Int(Date().addingTimeInterval(3600).timeIntervalSince1970))
        ])
        let upgraded = try GraphQLClient(responseCache: GraphQLResponseDiskCache(path: path), dataLoader: HTTPDataLoader { try await liveTransport.data(for: $0) })
        await upgraded.setTokenProvider { "test-token" }
        _ = try await upgraded.repoSummary(owner: "owner", name: "repo")
        _ = try await upgraded.repoSummary(owner: "owner", name: "repo")
        #expect(await liveTransport.requests.count == 1)
        #expect(await liveTransport.requests.first?.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(await upgraded.rateLimitSnapshot()?.remaining == (offline ? nil : 842))
    }

    @Test
    func `restart preserves an observed exhausted GraphQL window`() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GraphQLQuotaTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = try GraphQLResponseDiskCache(path: folder.appending(path: "Cache.sqlite").path)
        try cache.saveRateLimitSnapshot(
            RateLimitSnapshot(resource: "graphql", limit: 5000, remaining: 0, used: 5000, reset: Date().addingTimeInterval(3600), fetchedAt: Date()),
            endpoint: #require(URL(string: "https://api.github.com/graphql"))
        )
        let transport = GraphQLTestTransport(bodies: [Self.summary])
        let restarted = GraphQLClient(responseCache: cache, dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        await restarted.setTokenProvider { "test-token" }
        await #expect(throws: GitHubAPIError.self) {
            _ = try await restarted.repoSummary(owner: "owner", name: "uncached")
        }
        #expect(await transport.requests.isEmpty)
    }
}

private actor GraphQLTestTransport {
    private var bodies: [String]
    private let headers: [String: String]
    private(set) var requests: [URLRequest] = []

    init(bodies: [String], headers: [String: String] = [:]) {
        self.bodies = bodies
        self.headers = headers
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        self.requests.append(request)
        guard self.bodies.isEmpty == false else { throw URLError(.badServerResponse) }

        let body = self.bodies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: self.headers)!)
    }
}
