import Foundation
@testable import RepoBarCore
import Testing

struct GitHubRequestRunnerTests {
    @Test
    func `injected transport reuses cached body for not modified response`() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/repo/releases"))
        let transport = StubHTTPTransport(responses: [
            Self.response(url: url, status: 200, headers: ["ETag": "\"release-v1\""], body: "cached-body"),
            Self.response(url: url, status: 304, body: "")
        ])
        let runner = GitHubRequestRunner(
            etagCache: ETagCache(),
            dataLoader: HTTPDataLoader { request in
                try await transport.data(for: request)
            }
        )

        let first = try await runner.get(url: url, token: "token")
        let second = try await runner.get(url: url, token: "token")
        let requests = await transport.requests

        #expect(String(data: first.0, encoding: .utf8) == "cached-body")
        #expect(String(data: second.0, encoding: .utf8) == "cached-body")
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"release-v1\"")
    }

    @Test
    func `injected transport records stats cooldown`() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/repo/stats/commit_activity"))
        let transport = StubHTTPTransport(responses: [
            Self.response(url: url, status: 202, headers: ["Retry-After": "120"], body: "")
        ])
        let runner = GitHubRequestRunner(
            etagCache: ETagCache(),
            dataLoader: HTTPDataLoader { request in
                try await transport.data(for: request)
            }
        )

        do {
            _ = try await runner.get(url: url, token: "token")
            Issue.record("Expected service unavailable error")
        } catch let error as GitHubAPIError {
            guard case let .serviceUnavailable(retryAfter, message) = error else {
                Issue.record("Expected serviceUnavailable, got \(error)")
                return
            }

            #expect(retryAfter != nil)
            #expect(message.contains("generating repository stats"))
        }

        let diagnostics = await runner.diagnosticsSnapshot()
        #expect(diagnostics.endpointCooldowns.first?.endpoint == "commit activity")
    }

    @Test
    func `injected transport distinguishes permission failure from rate limit`() async throws {
        let permissionURL = try #require(URL(string: "https://api.github.com/repos/owner/repo/traffic/views"))
        let limitedURL = try #require(URL(string: "https://api.github.com/repos/owner/repo/issues"))
        let reset = Int(Date().addingTimeInterval(300).timeIntervalSince1970)
        let transport = StubHTTPTransport(responses: [
            Self.response(
                url: permissionURL,
                status: 403,
                headers: ["X-RateLimit-Remaining": "42"],
                body: #"{"message":"Resource not accessible"}"#
            ),
            Self.response(
                url: limitedURL,
                status: 403,
                headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(reset)"],
                body: #"{"message":"API rate limit exceeded"}"#
            )
        ])
        let runner = GitHubRequestRunner(
            etagCache: ETagCache(),
            dataLoader: HTTPDataLoader { request in
                try await transport.data(for: request)
            }
        )

        do {
            _ = try await runner.get(url: permissionURL, token: "token")
            Issue.record("Expected permission failure")
        } catch let GitHubAPIError.badStatus(code, message) {
            #expect(code == 403)
            #expect(message?.contains("Resource not accessible") == true)
        }

        do {
            _ = try await runner.get(url: limitedURL, token: "token")
            Issue.record("Expected rate limit failure")
        } catch let GitHubAPIError.rateLimited(_, message) {
            #expect(message.contains("rate limit"))
        }
    }

    @Test
    func `etag requests bypass URLSession local cache`() throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/repo/releases"))

        let request = GitHubRequestRunner.makeRequest(url: url, token: "token", useETag: true)
        let uncachedRequest = GitHubRequestRunner.makeRequest(url: url, token: "token", useETag: false)

        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(uncachedRequest.cachePolicy == .useProtocolCachePolicy)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test
    func `etag body cache stores only successful responses`() {
        #expect(GitHubRequestRunner.shouldCacheETagResponse(statusCode: 200))
        #expect(GitHubRequestRunner.shouldCacheETagResponse(statusCode: 304) == false)
        #expect(GitHubRequestRunner.shouldCacheETagResponse(statusCode: 404) == false)
    }

    @Test
    func `cooldown message names endpoint`() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/repo/stats/commit_activity"))
        let backoff = BackoffTracker()
        let retryAfter = Date().addingTimeInterval(30)
        await backoff.setCooldown(url: url, until: retryAfter)
        let runner = GitHubRequestRunner(etagCache: ETagCache(), backoff: backoff)

        do {
            _ = try await runner.get(url: url, token: "token")
            Issue.record("Expected cooldown error")
        } catch let error as GitHubAPIError {
            #expect(error.displayMessage.hasPrefix("GitHub endpoint cooldown (commit activity); retry in "))
            #expect(error.displayMessage.contains("until in") == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `cooldown message identifies actions endpoint`() throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/repo/actions/runs?per_page=20"))
        let retryAfter = Date(timeIntervalSinceReferenceDate: 60)
        let now = Date(timeIntervalSinceReferenceDate: 30)

        let message = GitHubRequestRunner.cooldownMessage(for: url, until: retryAfter, now: now)

        #expect(message == "GitHub endpoint cooldown (Actions runs); retry in 30 sec.")
    }

    @Test
    func `bad status message includes GitHub response detail`() {
        let data = Data("""
        {
          "message": "Validation Failed",
          "errors": [
            { "resource": "Search", "field": "q", "code": "invalid", "message": "Search query is too broad." }
          ]
        }
        """.utf8)

        let message = GitHubRequestRunner.statusMessage(for: 422, data: data)

        #expect(message == "GitHub returned 422: Validation Failed: Search query is too broad.")
    }

    @Test
    func `bad status message keeps fallback for non github body`() {
        let data = Data("nope".utf8)

        let message = GitHubRequestRunner.statusMessage(for: 422, data: data)

        #expect(message == "GitHub returned 422: client error.")
    }

    @Test
    func `diagnostics expose endpoint cooldowns`() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/repo/stats/commit_activity"))
        let backoff = BackoffTracker()
        let retryAfter = Date().addingTimeInterval(30)
        await backoff.setCooldown(url: url, until: retryAfter)
        let runner = GitHubRequestRunner(backoff: backoff)

        let diagnostics = await runner.diagnosticsSnapshot()

        #expect(diagnostics.backoffEntries == 1)
        #expect(diagnostics.endpointCooldowns.count == 1)
        #expect(diagnostics.endpointCooldowns.first?.endpoint == "commit activity")
        #expect(diagnostics.endpointCooldowns.first?.repository == "owner/repo")
    }

    @Test
    func `log path redacts query values`() throws {
        let url = try #require(URL(string: "https://api.github.com/search/issues?q=repo:owner/private+secret&per_page=50"))

        let path = GitHubRequestRunner.logPath(for: url)

        #expect(path == "/search/issues?q=<redacted>&per_page=<redacted>")
        #expect(path.contains("owner/private") == false)
        #expect(path.contains("secret") == false)
    }

    @Test(arguments: [403, 429])
    func `secondary limits honor Retry After despite remaining primary quota`(status: Int) async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/repo/issues"))
        let transport = StubHTTPTransport(responses: [Self.response(
            url: url, status: status,
            headers: ["X-RateLimit-Remaining": "42", "X-RateLimit-Reset": "\(Int(Date().addingTimeInterval(3600).timeIntervalSince1970))", "Retry-After": "120"],
            body: #"{"message":"You have exceeded a secondary rate limit."}"#
        )])
        let runner = GitHubRequestRunner(etagCache: ETagCache(), dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        for _ in 0 ..< 2 {
            do {
                _ = try await runner.get(url: url, token: "token")
                Issue.record("Expected secondary rate limit")
            } catch let GitHubAPIError.rateLimited(until, _) {
                let until = try #require(until)
                #expect((100 ... 130).contains(until.timeIntervalSinceNow))
            }
        }
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: [200, 429])
    func `GraphQL secondary limits stop repeat requests`(status: Int) async throws {
        let url = try #require(URL(string: "https://api.github.com/graphql"))
        let transport = StubHTTPTransport(responses: [Self.response(
            url: url, status: status,
            headers: ["X-RateLimit-Remaining": "42", "X-RateLimit-Reset": "\(Int(Date().addingTimeInterval(3600).timeIntervalSince1970))", "Retry-After": "120"],
            body: #"{"errors":[{"type":"RATE_LIMITED","message":"You have exceeded a secondary rate limit."}]}"#
        )])
        let client = GraphQLClient(responseCache: nil, dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        await client.setTokenProvider { "token" }
        for _ in 0 ..< 2 {
            do {
                _ = try await client.repoSummary(owner: "owner", name: "repo")
                Issue.record("Expected GraphQL rate limit")
            } catch let GitHubAPIError.rateLimited(until, _) {
                let until = try #require(until)
                #expect((100 ... 130).contains(until.timeIntervalSinceNow))
            }
        }
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `permission errors without quota headers do not throttle later requests`() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/repo/issues"))
        let transport = StubHTTPTransport(responses: [
            Self.response(url: url, status: 403, body: #"{"message":"Resource not accessible"}"#),
            Self.response(url: url, status: 200, body: "allowed")
        ])
        let runner = GitHubRequestRunner(etagCache: ETagCache(), dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        do {
            _ = try await runner.get(url: url, token: "token")
            Issue.record("Expected permission failure")
        } catch let GitHubAPIError.badStatus(code, _) {
            #expect(code == 403)
        }
        let result = try await runner.get(url: url, token: "token")
        #expect(String(bytes: result.0, encoding: .utf8) == "allowed")
        #expect(await transport.requests.count == 2)
    }

    @Test
    func `redirected stats cooldown uses the requested URL`() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/old/stats/commit_activity"))
        let redirected = try #require(URL(string: "https://api.github.com/repos/owner/new/stats/commit_activity"))
        let transport = StubHTTPTransport(responses: [Self.response(url: redirected, status: 202, headers: ["Retry-After": "120"], body: "")])
        let runner = GitHubRequestRunner(etagCache: ETagCache(), dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        for _ in 0 ..< 2 {
            do {
                _ = try await runner.get(url: url, token: "token")
                Issue.record("Expected stats cooldown")
            } catch let GitHubAPIError.serviceUnavailable(until, _) {
                #expect(until != nil)
            }
        }
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `queued search requests recheck the rate budget before admission`() async throws {
        let url = try #require(URL(string: "https://api.github.com/search/issues?q=repo:owner/repo"))
        let response = Self.response(url: url, status: 429, headers: ["X-RateLimit-Remaining": "42", "Retry-After": "120"], body: #"{"message":"Secondary rate limit"}"#)
        let transport = StubHTTPTransport(responses: Array(repeating: response, count: 12))
        let runner = GitHubRequestRunner(etagCache: ETagCache(), dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        let limited = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 12 {
                group.addTask {
                    do {
                        _ = try await runner.get(url: url, token: "token")
                        return false
                    } catch GitHubAPIError.rateLimited {
                        return true
                    } catch {
                        return false
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(limited.count == 12 && limited.allSatisfy(\.self))
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `successful GraphQL response exhausts budget without discarding its data`() async throws {
        let url = try #require(URL(string: "https://api.github.com/graphql"))
        let transport = StubHTTPTransport(responses: [Self.response(
            url: url, status: 200,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(Int(Date().addingTimeInterval(120).timeIntervalSince1970))"],
            body: #"{"data":{"repository":{"issues":{"totalCount":1},"pullRequests":{"totalCount":2},"latestRelease":null}}}"#
        )])
        let client = GraphQLClient(responseCache: nil, dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        await client.setTokenProvider { "token" }
        let summary = try await client.repoSummary(owner: "owner", name: "repo")
        #expect(summary.openIssues == 1 && summary.openPulls == 2)
        do {
            _ = try await client.repoSummary(owner: "owner", name: "repo")
            Issue.record("Expected exhausted quota")
        } catch GitHubAPIError.rateLimited {}
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `successful final REST request stops queued work at exhausted quota`() async throws {
        let url = try #require(URL(string: "https://api.github.com/search/issues?q=repo:owner/repo"))
        let response = Self.response(
            url: url, status: 200,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(Int(Date().addingTimeInterval(120).timeIntervalSince1970))"],
            body: "allowed"
        )
        let transport = StubHTTPTransport(responses: Array(repeating: response, count: 12))
        let runner = GitHubRequestRunner(etagCache: ETagCache(), dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        let successes = await withTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 12 {
                group.addTask {
                    do {
                        _ = try await runner.get(url: url, token: "token")
                        return 1
                    } catch GitHubAPIError.rateLimited {
                        return 0
                    } catch {
                        Issue.record(error)
                        return 0
                    }
                }
            }
            return await group.reduce(0, +)
        }
        #expect(successes == 1)
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `search quota does not replace or block core`() async throws {
        let coreURL = try #require(URL(string: "https://api.github.com/user"))
        let searchURL = try #require(URL(string: "https://api.github.com/search/repositories?q=swift"))
        let reset = Int(Date().addingTimeInterval(60).timeIntervalSince1970)
        let transport = StubHTTPTransport(responses: [
            Self.response(url: coreURL, status: 200, headers: ["X-RateLimit-Resource": "core", "X-RateLimit-Remaining": "4900"], body: "{}"),
            Self.response(url: searchURL, status: 403, headers: ["X-RateLimit-Resource": "search", "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(reset)"], body: "{}"),
            Self.response(url: coreURL, status: 200, headers: ["X-RateLimit-Resource": "core", "X-RateLimit-Remaining": "4899"], body: "{}")
        ])
        let runner = GitHubRequestRunner(etagCache: ETagCache(), dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        _ = try await runner.get(url: coreURL, token: "test-token")
        do {
            _ = try await runner.get(url: searchURL, token: "test-token")
            Issue.record("Expected search rate limit")
        } catch GitHubAPIError.rateLimited {}
        let diagnostics = await runner.diagnosticsSnapshot()
        #expect(diagnostics.restRateLimit?.remaining == 4900)
        #expect(diagnostics.rateLimitReset == nil)
        _ = try await runner.get(url: coreURL, token: "test-token")
        #expect(await runner.diagnosticsSnapshot().restRateLimit?.remaining == 4899)
    }

    @Test
    func `rate limit endpoint remains available when core is exhausted`() async throws {
        let url = try #require(URL(string: "https://api.github.com/rate_limit"))
        let cache = ETagCache()
        await cache.setRateLimitReset(date: Date().addingTimeInterval(300))
        let transport = StubHTTPTransport(responses: [Self.response(url: url, status: 200, body: "{}")])
        let runner = GitHubRequestRunner(etagCache: cache, dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        _ = try await runner.get(url: url, token: "test-token", useETag: false)
        #expect(await transport.requests.count == 1)
        #expect(await transport.requests.first?.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test
    func `quota endpoint headers and body cannot overwrite real usage`() async throws {
        let userURL = try #require(URL(string: "https://api.github.com/user"))
        let quotaURL = try #require(URL(string: "https://api.github.com/rate_limit"))
        let now = Date()
        let reset = now.addingTimeInterval(600)
        let transport = StubHTTPTransport(responses: [
            Self.response(url: userURL, status: 200, headers: [
                "X-RateLimit-Resource": "core", "X-RateLimit-Limit": "5000",
                "X-RateLimit-Remaining": "2120", "X-RateLimit-Used": "2880",
                "X-RateLimit-Reset": "\(Int(reset.timeIntervalSince1970))"
            ], body: "{}"),
            Self.response(url: quotaURL, status: 200, headers: [
                "X-RateLimit-Resource": "core", "X-RateLimit-Limit": "5000",
                "X-RateLimit-Remaining": "5000", "X-RateLimit-Used": "0",
                "X-RateLimit-Reset": "\(Int(now.addingTimeInterval(3600).timeIntervalSince1970))"
            ], body: "{}")
        ])
        let runner = GitHubRequestRunner(etagCache: ETagCache(), dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        _ = try await runner.get(url: userURL, token: "test-token")
        let original = await runner.diagnosticsSnapshot().restRateLimit
        _ = try await runner.get(url: quotaURL, token: "test-token", useETag: false)
        for offset in [10.0, 20.0] {
            let sampled = now.addingTimeInterval(offset)
            await runner.recordRateLimitResources(RateLimitResourcesSnapshot(fetchedAt: sampled, resources: [
                "core": RateLimitSnapshot(resource: "core", limit: 5000, remaining: 5000, used: 0, reset: sampled.addingTimeInterval(3600), fetchedAt: sampled)
            ]))
            let diagnostics = await runner.diagnosticsSnapshot()
            #expect(diagnostics.restRateLimit?.remaining == 2120)
            #expect(diagnostics.restRateLimit?.fetchedAt == original?.fetchedAt)
            #expect(diagnostics.rateLimitResources?["core"]?.remaining == 2120)
            #expect(diagnostics.rateLimitResources?["core"]?.reset == original?.reset)
        }
    }

    @Test
    func `user events cannot hide a constrained repository core window`() async throws {
        let repoURL = try #require(URL(string: "https://api.github.com/repos/owner/repo"))
        let eventsURL = try #require(URL(string: "https://api.github.com/users/owner/events"))
        let now = Date()
        let transport = StubHTTPTransport(responses: [
            Self.response(url: repoURL, status: 200, headers: [
                "X-RateLimit-Resource": "core", "X-RateLimit-Limit": "5000",
                "X-RateLimit-Remaining": "599", "X-RateLimit-Reset": "\(Int(now.addingTimeInterval(600).timeIntervalSince1970))"
            ], body: "{}"),
            Self.response(url: eventsURL, status: 200, headers: [
                "X-RateLimit-Resource": "core", "X-RateLimit-Limit": "5000",
                "X-RateLimit-Remaining": "4959", "X-RateLimit-Reset": "\(Int(now.addingTimeInterval(3600).timeIntervalSince1970))"
            ], body: "{}")
        ])
        let runner = GitHubRequestRunner(etagCache: ETagCache(), dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        _ = try await runner.get(url: repoURL, token: "test-token")
        _ = try await runner.get(url: eventsURL, token: "test-token")
        #expect(await runner.diagnosticsSnapshot().restRateLimit?.remaining == 599)
        let reported = RateLimitSnapshot(resource: "core", limit: 5000, remaining: 5000, used: 0, reset: now.addingTimeInterval(3600), fetchedAt: Date())
        await runner.recordRateLimitResources(RateLimitResourcesSnapshot(fetchedAt: Date(), resources: ["core": reported]))
        #expect(await runner.diagnosticsSnapshot().rateLimitResources?["core"]?.remaining == 599)
        await runner.clear()
        #expect(await runner.diagnosticsSnapshot().restRateLimit == nil)
    }

    private static func response(
        url: URL,
        status: Int,
        headers: [String: String] = [:],
        body: String
    ) -> StubHTTPTransport.Response {
        StubHTTPTransport.Response(
            data: Data(body.utf8),
            response: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        )
    }
}

private actor StubHTTPTransport {
    struct Response {
        let data: Data
        let response: HTTPURLResponse
    }

    private var pendingResponses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.pendingResponses = responses
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        self.requests.append(request)
        guard self.pendingResponses.isEmpty == false else {
            throw URLError(.badServerResponse)
        }

        let response = self.pendingResponses.removeFirst()
        return (response.data, response.response)
    }
}
