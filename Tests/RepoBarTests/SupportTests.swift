import Foundation
@testable import RepoBar
@testable import RepoBarCore
import Testing

@MainActor
struct RefreshAndBackoffTests {
    @Test
    func `pasteboard polling backs off when unchanged and resets after activity`() {
        var cadence = PasteboardPollCadence()
        #expect(cadence.nextInterval == .seconds(1))
        #expect(cadence.nextLeeway == .milliseconds(500))

        for _ in 0 ..< 4 {
            cadence.record(didChange: false)
        }
        #expect(cadence.nextInterval == .seconds(1))

        cadence.record(didChange: false)
        #expect(cadence.nextInterval == .seconds(5))
        #expect(cadence.nextLeeway == .seconds(2))

        cadence.record(didChange: true)
        #expect(cadence.nextInterval == .seconds(1))
        #expect(cadence.nextLeeway == .milliseconds(500))
    }

    @Test
    func `force refresh triggers tick`() {
        let scheduler = RefreshScheduler()
        var fired = false
        scheduler.configure(interval: 60, fireImmediately: false) {
            fired = true
        }

        scheduler.forceRefresh()
        #expect(fired)
    }

    @Test
    func `scheduler stop invalidates timer and releases tick`() {
        let scheduler = RefreshScheduler()
        var fireCount = 0
        scheduler.configure(interval: 60, fireImmediately: false) {
            fireCount += 1
        }
        #expect(scheduler.isRunning)

        scheduler.stop()
        scheduler.forceRefresh()

        #expect(scheduler.isRunning == false)
        #expect(fireCount == 0)
    }

    @Test
    func `app state runtime lifecycle is explicit and idempotent`() async {
        weak var releasedState: AppState?
        do {
            let appState = AppState()
            releasedState = appState
            #expect(appState.isStarted == false)

            appState.start()
            appState.start()
            #expect(appState.isStarted)

            appState.shutdown()
            appState.shutdown()
            #expect(appState.isStarted == false)
            #expect(appState.refreshScheduler.isRunning == false)

            appState.start()
            #expect(appState.isStarted)
            appState.shutdown()
        }

        await Task.yield()
        #expect(releasedState == nil)
    }

    @Test
    func `backoff tracks cooldown`() async throws {
        let tracker = BackoffTracker()
        let url = try #require(URL(string: "https://example.com/path"))
        let initial = await tracker.isCoolingDown(url: url)
        #expect(initial == false)

        let until = Date().addingTimeInterval(30)
        await tracker.setCooldown(url: url, until: until)

        let cooling = await tracker.isCoolingDown(url: url)
        #expect(cooling)
        let reported = await tracker.cooldown(for: url)
        #expect(reported != nil)
        if let reported {
            #expect(abs(reported.timeIntervalSince1970 - until.timeIntervalSince1970) < 0.5)
        }
    }

    @Test
    func `maps certificate errors`() {
        let error = URLError(.serverCertificateUntrusted)
        #expect(error.userFacingMessage == "Enterprise host certificate is not trusted.")
    }

    @Test
    func `maps cannot parse response`() {
        let error = URLError(.cannotParseResponse)
        #expect(error.userFacingMessage == "GitHub returned an unexpected response.")
    }

    @Test
    func `authentication failure detection`() {
        let unauthorized: Error = GitHubAPIError.badStatus(code: 401, message: nil)
        #expect(unauthorized.isAuthenticationFailure)

        let refreshFailure: Error = GitHubAPIError.badStatus(
            code: 400,
            message: "Authentication refresh failed (HTTP 400). Please sign in again."
        )
        #expect(refreshFailure.isAuthenticationFailure)

        let urlAuth: Error = URLError(.userAuthenticationRequired)
        #expect(urlAuth.isAuthenticationFailure)
    }

    @Test
    func `all repository issue search only surfaces total failure`() {
        #expect(AppState.shouldSurfaceIssueSearchFailure(searchedRepositories: 3, failedSearches: 3, matchCount: 0))
        #expect(!AppState.shouldSurfaceIssueSearchFailure(searchedRepositories: 3, failedSearches: 1, matchCount: 0))
        #expect(!AppState.shouldSurfaceIssueSearchFailure(searchedRepositories: 3, failedSearches: 3, matchCount: 1))
    }

    @Test
    func `all repository issue search fanout is capped to recent readable repos`() {
        let base = Date(timeIntervalSinceReferenceDate: 1000)
        var repos = (0 ..< 20).map { index in
            Self.makeIssueNavigatorRepo(
                name: "repo\(index)",
                pushedAt: base.addingTimeInterval(TimeInterval(index))
            )
        }
        repos.append(Self.makeIssueNavigatorRepo(name: "archived", isArchived: true, pushedAt: base.addingTimeInterval(100)))
        repos.append(Self.makeIssueNavigatorRepo(name: "private", viewerCanRead: false, pushedAt: base.addingTimeInterval(101)))

        let selected = AppState.issueNavigatorSearchRepositories(from: repos)

        #expect(selected.count == AppLimits.IssueNavigator.maxRepositorySearchFanout)
        #expect(selected.first?.fullName == "owner/repo19")
        #expect(selected.last?.fullName == "owner/repo8")
        #expect(selected.contains { $0.name == "archived" } == false)
        #expect(selected.contains { $0.name == "private" } == false)
    }

    @Test
    func `navigator result sorting uses updated time before created time`() throws {
        let base = Date(timeIntervalSinceReferenceDate: 1000)
        let recentlyCreated = try Self.makeGitHubReferenceMatch(
            number: 1,
            createdAt: base.addingTimeInterval(300),
            updatedAt: base.addingTimeInterval(10)
        )
        let recentlyUpdated = try Self.makeGitHubReferenceMatch(
            number: 2,
            createdAt: base.addingTimeInterval(1),
            updatedAt: base.addingTimeInterval(200)
        )

        let sorted = AppState.dedupedGitHubReferenceMatches([recentlyCreated, recentlyUpdated])

        #expect(sorted.map(\.title) == ["Match 2", "Match 1"])
    }

    @Test
    func `recent repository candidates respect issue and pull request filters before capping`() {
        let base = Date(timeIntervalSinceReferenceDate: 1000)
        var repos = (0 ..< AppLimits.IssueNavigator.recentRepositoryLimit).map { index in
            Self.makeIssueNavigatorRepo(
                name: "pr\(index)",
                openPulls: 1,
                pushedAt: base.addingTimeInterval(TimeInterval(100 + index))
            )
        }
        repos.append(Self.makeIssueNavigatorRepo(name: "issue", openIssues: 1, pushedAt: base))

        let issueRepos = AppState.issueNavigatorRecentRepositories(
            from: repos,
            includeIssues: true,
            includePullRequests: false
        )
        let pullRepos = AppState.issueNavigatorRecentRepositories(
            from: repos,
            includeIssues: false,
            includePullRequests: true
        )

        #expect(issueRepos.map(\.fullName) == ["owner/issue"])
        #expect(pullRepos.count == AppLimits.IssueNavigator.recentRepositoryLimit)
        #expect(pullRepos.allSatisfy { $0.openPulls > 0 })
    }

    @Test
    func `all repository issue search waits for repository inventory`() async throws {
        let appState = AppState()

        do {
            _ = try await appState.searchIssueReferences(
                matching: "review",
                repositoryFullName: nil,
                includeIssues: true,
                includePullRequests: true
            )
            Issue.record("Expected repository inventory loading error")
        } catch {
            #expect(error.userFacingMessage == "Repository list is still loading. Try again in a moment.")
        }
    }

    @Test
    func `all repository issue search does not fall back to public github when inventory is empty`() async throws {
        let appState = AppState()
        appState.session.hasLoadedRepositories = true

        let matches = try await appState.searchIssueReferences(
            matching: "review",
            repositoryFullName: nil,
            includeIssues: true,
            includePullRequests: true
        )

        #expect(matches.isEmpty)
    }

    @Test
    func `loopback parses code and state`() {
        let request = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1:53682\r\n\r\n"
        let parsed = LoopbackServer.parse(request: request)
        #expect(parsed?.code == "abc")
        #expect(parsed?.state == "xyz")
    }

    private static func makeIssueNavigatorRepo(
        name: String,
        isArchived: Bool = false,
        viewerCanRead: Bool = true,
        openIssues: Int = 0,
        openPulls: Int = 0,
        pushedAt: Date
    ) -> Repository {
        Repository(
            id: "owner/\(name)",
            name: name,
            owner: "owner",
            isArchived: isArchived,
            viewerCanRead: viewerCanRead,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: openIssues,
            openPulls: openPulls,
            pushedAt: pushedAt,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }

    private static func makeGitHubReferenceMatch(
        number: Int,
        createdAt: Date,
        updatedAt: Date
    ) throws -> GitHubReferenceMatch {
        let url = try #require(URL(string: "https://github.com/owner/repo/issues/\(number)"))
        return GitHubReferenceMatch(
            query: .repositoryIssueNumber(repositoryFullName: "owner/repo", number: number),
            title: "Match \(number)",
            url: url,
            repositoryFullName: "owner/repo",
            kind: .issue,
            state: .open,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
