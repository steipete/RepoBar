import AppKit
@testable import RepoBar
@testable import RepoBarCore
import Testing

struct RecentListMenuTests {
    @MainActor
    @Test
    func `recent list cache evicts least recently used entry`() {
        let cache = RecentListCache<Int>(maxEntries: 2)
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let one = AccountScopedCacheKey(accountID: "account", key: "one")
        let two = AccountScopedCacheKey(accountID: "account", key: "two")
        let three = AccountScopedCacheKey(accountID: "account", key: "three")

        cache.store([1], for: one, fetchedAt: now)
        cache.store([2], for: two, fetchedAt: now)
        #expect(cache.stale(for: one) == [1])
        cache.store([3], for: three, fetchedAt: now)

        #expect(cache.count() == 2)
        #expect(cache.stale(for: one) == [1])
        #expect(cache.stale(for: two) == nil)
        #expect(cache.stale(for: three) == [3])
    }

    @MainActor
    @Test
    func `recent list menus survive main menu open`() {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let mainMenu = NSMenu()
        let submenu = NSMenu()

        manager.setMainMenuForTesting(mainMenu)
        manager.registerRecentListMenu(
            submenu,
            context: RepoRecentMenuContext(accountID: "account", fullName: "owner/repo", kind: .issues)
        )

        manager.menuWillOpen(mainMenu)

        #expect(manager.isRecentListMenu(submenu))
    }

    @MainActor
    @Test
    func `recent list menus survive filter rebuild`() async throws {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let mainMenu = NSMenu()
        let submenu = NSMenu()

        manager.setMainMenuForTesting(mainMenu)
        manager.registerRecentListMenu(
            submenu,
            context: RepoRecentMenuContext(accountID: "account", fullName: "owner/repo", kind: .issues)
        )

        manager.menuFiltersChanged()
        try await Task.sleep(for: .milliseconds(50))

        #expect(manager.isRecentListMenu(submenu))
    }

    @MainActor
    @Test
    func `recent list failures show user facing reason`() {
        let error = GitHubAPIError.badStatus(code: 403, message: "Requires repository issues access.")

        #expect(
            RecentListMenuCoordinator.failureMessage(for: error) ==
                "Failed: Requires repository issues access."
        )
    }

    @MainActor
    @Test
    func `recent list timeouts include configured seconds`() {
        #expect(RecentListMenuCoordinator.timeoutMessage(timeout: 12) == "Timed out after 12s")
    }

    @MainActor
    @Test
    func `recent list rate limit message is visible`() {
        let reset = Date(timeIntervalSinceNow: 120)
        let error = GitHubAPIError.rateLimited(until: reset, message: "GitHub rate limit hit.")

        #expect(RecentListMenuCoordinator.rateLimitMessage(for: error)?.contains("GitHub rate limited; resets") == true)
        #expect(RecentListMenuCoordinator.rateLimitMessage(for: URLError(.timedOut)) == nil)
    }

    @MainActor
    @Test
    func `identical repository requests use account scoped clients caches and inflight tasks`() async throws {
        let requestLog = RecentRequestLog()
        let aliceClient = await Self.makeRecentListClient(
            accountID: "alice",
            branchName: "alice-branch",
            requestLog: requestLog
        )
        let bobClient = await Self.makeRecentListClient(
            accountID: "bob",
            branchName: "bob-branch",
            requestLog: requestLog
        )
        let clients = ["alice": aliceClient, "bob": bobClient]
        let service = RecentMenuService(
            clientResolver: { accountID in
                guard let client = clients[accountID] else {
                    throw AccountManagerError.unknownAccount(accountID)
                }

                return client
            },
            activeAccountID: { "alice" }
        )
        let alice = try service.cacheContext(accountID: "alice", fullName: "owner/repo")
        let bob = try service.cacheContext(accountID: "bob", fullName: "owner/repo")

        let aliceTask = Task { @MainActor in
            try await service.load(accountID: "alice", fullName: "owner/repo", kind: .branches)
        }
        let bobTask = Task { @MainActor in
            try await service.load(accountID: "bob", fullName: "owner/repo", kind: .branches)
        }
        let loaded = try await (aliceTask.value, bobTask.value)

        guard case let .branches(aliceBranches) = loaded.0,
              case let .branches(bobBranches) = loaded.1
        else {
            Issue.record("Expected branch results")
            return
        }

        #expect(alice.key != bob.key)
        #expect(aliceBranches.map(\.name) == ["alice-branch"])
        #expect(bobBranches.map(\.name) == ["bob-branch"])
        #expect(await requestLog.count(for: "alice") == 1)
        #expect(await requestLog.count(for: "bob") == 1)

        service.removeCachedState(accountID: "alice")
        let descriptor = try #require(service.descriptor(for: .branches))
        #expect(descriptor.stale(alice.key) == nil)
        #expect(descriptor.stale(bob.key)?.count == 1)
    }

    @MainActor
    @Test
    func `multi reference menu offers issue navigator action at end`() throws {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let menu = NSMenu()
        let matches = try [
            Self.makeReference(number: 1),
            Self.makeReference(number: 2)
        ]

        manager.populateGitHubReferenceMenuForTesting(menu, matches: matches)

        let titles = menu.items.map(\.title)
        #expect(Array(titles.suffix(2)) == ["", "Open 2 refs in Issue Navigator…"])
        #expect(menu.items.last?.target is GitHubReferenceStatusCoordinator)
    }

    @MainActor
    @Test
    func `multi reference status item uses click action instead of attached menu`() throws {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let matches = try [
            Self.makeReference(number: 1),
            Self.makeReference(number: 2)
        ]

        appState.session.gitHubReferenceMatches = matches
        appState.session.gitHubReferenceMatch = matches.first
        manager.syncGitHubReferenceStatusItemForTesting()

        let item = try #require(manager.gitHubReferenceStatusItemForTesting())
        let button = try #require(item.button)
        #expect(item.menu == nil)
        #expect(button.target is GitHubReferenceStatusCoordinator)
        #expect(button.action == #selector(GitHubReferenceStatusCoordinator.statusItemClicked(_:)))
    }

    private static func makeReference(number: Int) throws -> GitHubReferenceMatch {
        let url = try #require(URL(string: "https://github.com/owner/repo/issues/\(number)"))
        return GitHubReferenceMatch(
            query: .repositoryIssueNumber(repositoryFullName: "owner/repo", number: number),
            title: "Issue \(number)",
            url: url,
            repositoryFullName: "owner/repo",
            kind: .issue,
            state: .open,
            createdAt: Date(timeIntervalSinceReferenceDate: TimeInterval(number)),
            updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(number))
        )
    }

    private static func makeRecentListClient(
        accountID: String,
        branchName: String,
        requestLog: RecentRequestLog
    ) async -> GitHubClient {
        let dataLoader = HTTPDataLoader { request in
            await requestLog.record(accountID)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = Data(
                """
                [{"name":"\(branchName)","commit":{"sha":"\(accountID)-sha"},"protected":false}]
                """.utf8
            )
            return (body, response)
        }
        let client = GitHubClient(
            accountID: accountID,
            archiveSettingsProvider: { GitHubArchiveSettings() },
            dataLoader: dataLoader,
            responseDiskCache: nil
        )
        await client.setTokenProvider {
            OAuthTokens(accessToken: "\(accountID)-token", refreshToken: "", expiresAt: nil)
        }
        return client
    }
}

private actor RecentRequestLog {
    private var counts: [String: Int] = [:]

    func record(_ accountID: String) {
        self.counts[accountID, default: 0] += 1
    }

    func count(for accountID: String) -> Int {
        self.counts[accountID, default: 0]
    }
}
