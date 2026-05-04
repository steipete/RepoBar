import Foundation
@testable import RepoBarCore
import Testing

struct GitHubRequestRunnerTests {
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
    func `cooldown message names endpoint`() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/owner/repo/stats/commit_activity"))
        let backoff = BackoffTracker()
        let retryAfter = Date().addingTimeInterval(30)
        await backoff.setCooldown(url: url, until: retryAfter)
        let runner = GitHubRequestRunner(backoff: backoff)

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
}
