import Foundation
@testable import RepoBar
@testable import RepoBarCore
import Testing

@MainActor
struct MultiAccountRepositoryRefreshTests {
    @Test
    func `consolidation off refreshes active account only`() async throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        let aliceTransport = AccountRepositoryTransport(repositories: [.init(id: 1, owner: "alice", name: "one")])
        let bobTransport = AccountRepositoryTransport(repositories: [.init(id: 2, owner: "bob", name: "two")])
        let environment = try await Self.environment(
            accounts: [alice, bob],
            activeAccountID: alice.id,
            consolidateAccounts: false,
            selectedAccountIDs: [alice.id, bob.id],
            transports: [alice.id: aliceTransport, bob.id: bobTransport]
        )
        defer { environment.cleanup() }

        _ = await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 100))

        #expect(await aliceTransport.requestCount == 1)
        #expect(await bobTransport.requestCount == 0)
        #expect(environment.app.session.accountSessions.map(\.id) == [alice.id])
        #expect(environment.app.session.repositories.map(\.fullName) == ["alice/one"])
    }

    @Test
    func `consolidation on isolates same host accounts and preserves overlapping repositories`() async throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        let shared = AccountRepositoryFixture(id: 42, owner: "example", name: "shared")
        let aliceTransport = AccountRepositoryTransport(repositories: [shared])
        let bobTransport = AccountRepositoryTransport(repositories: [shared])
        let environment = try await Self.environment(
            accounts: [alice, bob],
            activeAccountID: alice.id,
            consolidateAccounts: true,
            selectedAccountIDs: [alice.id, bob.id],
            transports: [alice.id: aliceTransport, bob.id: bobTransport]
        )
        defer { environment.cleanup() }

        _ = await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 200))

        #expect(await aliceTransport.requestCount == 1)
        #expect(await bobTransport.requestCount == 1)
        #expect(await aliceTransport.requestedPaths == ["/user/repos"])
        #expect(await bobTransport.requestedPaths == ["/user/repos"])
        #expect(environment.app.session.accountSessions.map(\.id) == [alice.id, bob.id])
        #expect(environment.app.session.aggregatedRepositories.count == 2)
        #expect(Set(environment.app.session.aggregatedRepositories.map(\.id)).count == 2)
        #expect(environment.app.session.repositories.count == 1)
    }

    @Test
    func `consolidation on refreshes only included credentialed current accounts`() async throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        let credentialless = try Self.account("credentialless")
        let removed = try Self.account("removed")
        let aliceTransport = AccountRepositoryTransport(repositories: [.init(id: 1, owner: "alice", name: "one")])
        let bobTransport = AccountRepositoryTransport(repositories: [.init(id: 2, owner: "bob", name: "two")])
        let credentiallessTransport = AccountRepositoryTransport(
            repositories: [.init(id: 3, owner: "credentialless", name: "three")]
        )
        let removedTransport = AccountRepositoryTransport(repositories: [.init(id: 4, owner: "removed", name: "four")])
        let environment = try await Self.environment(
            accounts: [alice, bob, credentialless, removed],
            activeAccountID: alice.id,
            consolidateAccounts: true,
            selectedAccountIDs: [alice.id, credentialless.id, removed.id, "github.com#unknown"],
            credentialedAccountIDs: [alice.id, bob.id, removed.id],
            transports: [
                alice.id: aliceTransport,
                bob.id: bobTransport,
                credentialless.id: credentiallessTransport,
                removed.id: removedTransport
            ]
        )
        defer { environment.cleanup() }
        await environment.app.accountManager.remove(accountID: removed.id)

        _ = await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 300))

        #expect(await aliceTransport.requestCount == 1)
        #expect(await bobTransport.requestCount == 0)
        #expect(await credentiallessTransport.requestCount == 0)
        #expect(await removedTransport.requestCount == 0)
        #expect(environment.app.session.accountSessions.map(\.id) == [alice.id])
        #expect(environment.app.session.aggregatedRepositories.map(\.accountID) == [alice.id])
    }

    @Test
    func `partial failure retains last good account state while healthy account advances`() async throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        let aliceTransport = AccountRepositoryTransport(repositories: [.init(id: 1, owner: "alice", name: "old")])
        let bobTransport = AccountRepositoryTransport(repositories: [.init(id: 2, owner: "bob", name: "old")])
        let environment = try await Self.environment(
            accounts: [alice, bob],
            activeAccountID: alice.id,
            consolidateAccounts: true,
            selectedAccountIDs: [alice.id, bob.id],
            transports: [alice.id: aliceTransport, bob.id: bobTransport]
        )
        defer { environment.cleanup() }
        let firstDate = Date(timeIntervalSince1970: 400)
        _ = await environment.app.refreshAccountRepositorySnapshots(now: firstDate)

        await aliceTransport.setFailure(statusCode: 500)
        await bobTransport.setRepositories([.init(id: 3, owner: "bob", name: "new")])
        _ = await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 500))

        let aliceSession = try #require(environment.app.session.accountSessions.first(where: { $0.id == alice.id }))
        let bobSession = try #require(environment.app.session.accountSessions.first(where: { $0.id == bob.id }))
        #expect(aliceSession.repositories.map(\.fullName) == ["alice/old"])
        #expect(aliceSession.lastSuccessfulRefreshAt == firstDate)
        #expect(aliceSession.isStale)
        #expect(aliceSession.lastError != nil)
        #expect(bobSession.repositories.map(\.fullName) == ["bob/new"])
        #expect(bobSession.lastSuccessfulRefreshAt == Date(timeIntervalSince1970: 500))
        #expect(bobSession.isStale == false)
        #expect(environment.app.session.aggregatedRepositories.count == 2)
    }

    @Test
    func `older generation cannot overwrite a newer refresh`() async throws {
        let alice = try Self.account("alice")
        let transport = AccountRepositoryTransport(repositories: [])
        let loader = SequencedAccountRepositoryLoader(
            responses: [
                .init(delay: .milliseconds(200), repository: Self.repository(id: "old", owner: "alice", name: "old")),
                .init(delay: .zero, repository: Self.repository(id: "new", owner: "alice", name: "new"))
            ]
        )
        let environment = try await Self.environment(
            accounts: [alice],
            activeAccountID: alice.id,
            consolidateAccounts: false,
            selectedAccountIDs: [alice.id],
            transports: [alice.id: transport],
            loader: loader
        )
        defer { environment.cleanup() }

        let first = Task { @MainActor in
            await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 600))
        }
        while await loader.snapshotRequestCount == 0 {
            await Task.yield()
        }
        let second = await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 700))
        let firstOutcome = await first.value

        #expect(second.published)
        #expect(firstOutcome.published == false)
        #expect(environment.app.session.repositories.map(\.fullName) == ["alice/new"])
    }

    @Test
    func `cancelled refresh cannot overwrite last good state`() async throws {
        let alice = try Self.account("alice")
        let transport = AccountRepositoryTransport(repositories: [])
        let loader = SequencedAccountRepositoryLoader(
            responses: [
                .init(delay: .zero, repository: Self.repository(id: "good", owner: "alice", name: "good")),
                .init(delay: .seconds(1), repository: Self.repository(id: "late", owner: "alice", name: "late"))
            ]
        )
        let environment = try await Self.environment(
            accounts: [alice],
            activeAccountID: alice.id,
            consolidateAccounts: false,
            selectedAccountIDs: [alice.id],
            transports: [alice.id: transport],
            loader: loader
        )
        defer { environment.cleanup() }
        _ = await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 710))

        let cancelled = Task { @MainActor in
            await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 720))
        }
        while await loader.snapshotRequestCount < 2 {
            await Task.yield()
        }
        cancelled.cancel()
        let outcome = await cancelled.value

        #expect(outcome.published == false)
        #expect(environment.app.session.repositories.map(\.fullName) == ["alice/good"])
    }

    @Test
    func `hydrated snapshot cannot cross an active account switch`() async throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        let aliceTransport = AccountRepositoryTransport(repositories: [.init(id: 1, owner: "alice", name: "one")])
        let bobTransport = AccountRepositoryTransport(repositories: [.init(id: 2, owner: "bob", name: "two")])
        let environment = try await Self.environment(
            accounts: [alice, bob],
            activeAccountID: alice.id,
            consolidateAccounts: true,
            selectedAccountIDs: [alice.id, bob.id],
            transports: [alice.id: aliceTransport, bob.id: bobTransport]
        )
        defer { environment.cleanup() }
        let outcome = await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 730))
        let aliceHydrated = Self.repository(id: "alice-hydrated", owner: "alice", name: "hydrated")
        let bobBefore = try #require(
            environment.app.session.accountSessions.first(where: { $0.id == bob.id })?.repositories
        )

        environment.app.session.activeAccountID = bob.id
        let published = environment.app.publishHydratedActiveRepositorySnapshot(
            accessibleRepositories: [aliceHydrated],
            repositories: [aliceHydrated],
            accountID: alice.id,
            generation: outcome.generation,
            now: Date(timeIntervalSince1970: 740)
        )

        #expect(published == false)
        #expect(environment.app.session.accountSessions.first(where: { $0.id == bob.id })?.repositories == bobBefore)
    }

    @Test
    func `non active authentication failure remains account local`() async throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        let aliceTransport = AccountRepositoryTransport(repositories: [.init(id: 1, owner: "alice", name: "one")])
        let bobTransport = AccountRepositoryTransport(repositories: [.init(id: 2, owner: "bob", name: "two")])
        let environment = try await Self.environment(
            accounts: [alice, bob],
            activeAccountID: alice.id,
            consolidateAccounts: true,
            selectedAccountIDs: [alice.id, bob.id],
            transports: [alice.id: aliceTransport, bob.id: bobTransport]
        )
        defer { environment.cleanup() }
        await bobTransport.setFailure(statusCode: 401)

        _ = await environment.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 750))

        let aliceSession = try #require(environment.app.session.accountSessions.first(where: { $0.id == alice.id }))
        let bobSession = try #require(environment.app.session.accountSessions.first(where: { $0.id == bob.id }))
        #expect(aliceSession.state.isLoggedIn)
        #expect(bobSession.state == .loggedOut)
        #expect(try environment.tokenStore.loadPAT(accountID: alice.id) != nil)
        #expect(try environment.tokenStore.loadPAT(accountID: bob.id) != nil)
    }

    @Test
    func `consolidated active failure remains visible after full refresh`() async throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        let aliceTransport = AccountRepositoryTransport(repositories: [])
        let bobTransport = AccountRepositoryTransport(repositories: [.init(id: 2, owner: "bob", name: "two")])
        let environment = try await Self.environment(
            accounts: [alice, bob],
            activeAccountID: alice.id,
            consolidateAccounts: true,
            selectedAccountIDs: [alice.id, bob.id],
            transports: [alice.id: aliceTransport, bob.id: bobTransport]
        )
        defer { environment.cleanup() }
        await aliceTransport.setFailure(statusCode: 500)

        await environment.app.refresh()

        let aliceSession = try #require(environment.app.session.accountSessions.first(where: { $0.id == alice.id }))
        let bobSession = try #require(environment.app.session.accountSessions.first(where: { $0.id == bob.id }))
        #expect(aliceSession.isStale)
        #expect(aliceSession.lastError != nil)
        #expect(environment.app.session.lastError == aliceSession.lastError)
        #expect(bobSession.repositories.map(\.fullName) == ["bob/two"])
    }

    @Test
    func `account caches hydrate independently before failed live requests`() async throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        let aliceTransport = AccountRepositoryTransport(repositories: [.init(id: 1, owner: "alice", name: "cached")])
        let bobTransport = AccountRepositoryTransport(repositories: [.init(id: 2, owner: "bob", name: "cached")])
        let first = try await Self.environment(
            accounts: [alice, bob],
            activeAccountID: alice.id,
            consolidateAccounts: true,
            selectedAccountIDs: [alice.id, bob.id],
            transports: [alice.id: aliceTransport, bob.id: bobTransport]
        )
        _ = await first.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 800))
        #expect(first.caches[alice.id]?.count() == 1)
        #expect(first.caches[bob.id]?.count() == 1)
        let firstAliceClient = try #require(first.app.accountManager.client(for: alice.id))
        let firstBobClient = try #require(first.app.accountManager.client(for: bob.id))
        #expect(try await firstAliceClient.cachedRepositoryList(limit: nil).map(\.fullName) == ["alice/cached"])
        #expect(try await firstBobClient.cachedRepositoryList(limit: nil).map(\.fullName) == ["bob/cached"])

        await aliceTransport.setFailure(statusCode: 503)
        await bobTransport.setFailure(statusCode: 503)
        let second = try await Self.environment(
            accounts: [alice, bob],
            activeAccountID: alice.id,
            consolidateAccounts: true,
            selectedAccountIDs: [alice.id, bob.id],
            transports: [alice.id: aliceTransport, bob.id: bobTransport],
            cacheDirectories: first.cacheDirectories,
            tokenStore: first.tokenStore
        )
        defer {
            second.cleanup(removeCaches: false)
            first.cleanup()
        }

        _ = await second.app.refreshAccountRepositorySnapshots(now: Date(timeIntervalSince1970: 900))

        let sessions = Dictionary(uniqueKeysWithValues: second.app.session.accountSessions.map { ($0.id, $0) })
        #expect(sessions[alice.id]?.repositories.map(\.fullName) == ["alice/cached"])
        #expect(sessions[bob.id]?.repositories.map(\.fullName) == ["bob/cached"])
        #expect(sessions[alice.id]?.isStale == true)
        #expect(sessions[bob.id]?.isStale == true)
        #expect(second.app.session.aggregatedRepositories.count == 2)
    }

    private static func account(_ username: String) throws -> Account {
        try Account(
            username: username,
            host: #require(URL(string: "https://github.com")),
            authMethod: .pat
        )
    }

    private static func environment(
        accounts: [Account],
        activeAccountID: String,
        consolidateAccounts: Bool,
        selectedAccountIDs: Set<String>,
        credentialedAccountIDs: Set<String>? = nil,
        transports: [String: AccountRepositoryTransport],
        loader: any AccountRepositorySnapshotLoading = AccountRepositorySnapshotLoader(),
        cacheDirectories: [String: URL]? = nil,
        tokenStore: TokenStore? = nil
    ) async throws -> AccountRefreshTestEnvironment {
        let store = tokenStore ?? TokenStore(service: "com.steipete.repobar.multi-account-refresh.\(UUID().uuidString)")
        let credentialed = credentialedAccountIDs ?? Set(accounts.map(\.id))
        for account in accounts where credentialed.contains(account.id) {
            try store.savePAT("token-\(account.username)", accountID: account.id)
        }

        var directories = cacheDirectories ?? [:]
        var clients: [String: GitHubClient] = [:]
        var caches: [String: HTTPResponseDiskCache] = [:]
        for account in accounts {
            let directory: URL
            if let existing = directories[account.id] {
                directory = existing
            } else {
                directory = FileManager.default.temporaryDirectory
                    .appending(path: "repobar-account-refresh-\(UUID().uuidString)", directoryHint: .isDirectory)
                directories[account.id] = directory
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let cache = try HTTPResponseDiskCache(path: directory.appending(path: "cache.sqlite").path)
            caches[account.id] = cache
            let transport = try #require(transports[account.id])
            let dataLoader = HTTPDataLoader { request in
                try await transport.data(for: request)
            }
            clients[account.id] = GitHubClient(
                accountID: account.id,
                archiveSettingsProvider: { GitHubArchiveSettings() },
                dataLoader: dataLoader,
                responseDiskCache: cache,
                etagCache: ETagCache(persistentStore: cache)
            )
        }

        var settings = UserSettings()
        settings.accounts = accounts
        settings.activeAccountID = activeAccountID
        settings.consolidateAccounts = consolidateAccounts
        settings.accountSelection = .only(selectedAccountIDs)
        let defaultsName = "com.steipete.repobar.multi-account-refresh.defaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let manager = AccountManager(
            tokenStore: store,
            clientFactory: { account in
                clients[account.id]!
            }
        )
        let app = AppState(
            settingsStore: SettingsStore(defaults: defaults),
            accountManager: manager,
            accountRepositorySnapshotLoader: loader
        )
        app.session.settings = settings
        await app.bootstrapAccounts()
        return AccountRefreshTestEnvironment(
            app: app,
            tokenStore: store,
            accounts: accounts,
            cacheDirectories: directories,
            caches: caches,
            defaultsName: defaultsName
        )
    }

    private static func repository(id: String, owner: String, name: String) -> Repository {
        Repository(
            id: id,
            name: name,
            owner: owner,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            forks: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
    }
}

@MainActor
private struct AccountRefreshTestEnvironment {
    let app: AppState
    let tokenStore: TokenStore
    let accounts: [Account]
    let cacheDirectories: [String: URL]
    let caches: [String: HTTPResponseDiskCache]
    let defaultsName: String

    func cleanup(removeCaches: Bool = true) {
        for account in self.accounts {
            self.tokenStore.clear(accountID: account.id)
        }
        UserDefaults.standard.removePersistentDomain(forName: self.defaultsName)
        if removeCaches {
            for directory in self.cacheDirectories.values {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
}

private struct AccountRepositoryFixture {
    let id: Int
    let owner: String
    let name: String
}

private actor AccountRepositoryTransport {
    private var repositories: [AccountRepositoryFixture]
    private var statusCode = 200
    private(set) var requests: [URLRequest] = []

    init(repositories: [AccountRepositoryFixture]) {
        self.repositories = repositories
    }

    var requestCount: Int {
        self.requests.count
    }

    var requestedPaths: [String] {
        self.requests.compactMap(\.url?.path)
    }

    func setRepositories(_ repositories: [AccountRepositoryFixture]) {
        self.repositories = repositories
        self.statusCode = 200
    }

    func setFailure(statusCode: Int) {
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        self.requests.append(request)
        let data: Data
        if self.statusCode == 200 {
            let objects: [[String: Any]] = self.repositories.map { repo in
                [
                    "id": repo.id,
                    "name": repo.name,
                    "full_name": "\(repo.owner)/\(repo.name)",
                    "description": NSNull(),
                    "language": NSNull(),
                    "topics": [],
                    "fork": false,
                    "archived": false,
                    "has_discussions": true,
                    "open_issues_count": 0,
                    "stargazers_count": 0,
                    "forks_count": 0,
                    "pushed_at": NSNull(),
                    "permissions": ["pull": true],
                    "owner": ["login": repo.owner]
                ]
            }
            data = try JSONSerialization.data(withJSONObject: objects)
        } else {
            data = Data(#"{"message":"injected failure"}"#.utf8)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: self.statusCode,
            httpVersion: nil,
            headerFields: self.statusCode == 200 ? ["ETag": "\"refresh-test\""] : nil
        )!
        return (data, response)
    }
}

private actor SequencedAccountRepositoryLoader: AccountRepositorySnapshotLoading {
    struct Response {
        let delay: Duration
        let repository: Repository
    }

    private var responses: [Response]
    private(set) var snapshotRequestCount = 0

    init(responses: [Response]) {
        self.responses = responses
    }

    func cachedSnapshot(for _: AccountRepositorySnapshotRequest) async throws -> AccountRepositorySnapshot? {
        nil
    }

    func snapshot(for request: AccountRepositorySnapshotRequest) async throws -> AccountRepositorySnapshot {
        self.snapshotRequestCount += 1
        let response = self.responses.removeFirst()
        try await Task.sleep(for: response.delay)
        return AccountRepositorySnapshot(
            account: request.account,
            accessibleRepositories: [response.repository],
            repositories: [response.repository],
            capturedAt: request.now,
            diagnostics: .empty,
            cacheSummary: nil
        )
    }
}
