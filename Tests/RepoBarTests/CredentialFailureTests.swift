import Foundation
@testable import RepoBar
@testable import RepoBarCore
import Testing

@MainActor
struct CredentialFailureTests {
    @Test(arguments: [AuthMethod.pat, .oauth])
    func `account credential state distinguishes failed reads`(method: AuthMethod) async throws {
        let fixture = try CredentialFixture(method: method)
        defer { fixture.cleanUp() }
        let manager = AccountManager(tokenStore: fixture.tokens)
        await manager.bootstrap(from: fixture.settings.load())
        #expect(manager.credentialState(accountID: fixture.account.id) == .missing)
        if method == .pat {
            try fixture.tokens.savePAT("test-pat", accountID: fixture.account.id)
        } else {
            try fixture.tokens.save(tokens: OAuthTokens(accessToken: "test", refreshToken: "", expiresAt: nil), accountID: fixture.account.id)
        }
        #expect(manager.credentialState(accountID: fixture.account.id) == .present)
        try fixture.makeUnreadable(key: "\(fixture.account.id):\(method == .pat ? "pat" : "default")")
        #expect(manager.credentialState(accountID: fixture.account.id) == .unavailable)
        await #expect(throws: (any Error).self) {
            _ = try await manager.currentAccessToken(accountID: fixture.account.id)
        }
    }

    @Test
    func `bootstrap preserves PAT settings when credentials are unavailable`() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.cleanUp() }
        try fixture.makeUnreadable(key: "\(fixture.account.id):pat")
        let saved = fixture.settings.load()
        let app = fixture.makeApp()
        app.session.hasStoredTokens = true
        await app.bootstrapAccounts()
        #expect(app.session.account == .credentialsUnavailable(fixture.identity))
        #expect(app.session.hasStoredTokens)
        #expect(app.session.settings == saved)
        #expect(fixture.settings.load() == saved)
    }

    @Test
    func `legacy failed reads preserve auth method and unavailable bootstrap`() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.cleanUp() }
        var settings = fixture.settings.load()
        settings.accounts = []
        settings.activeAccountID = nil
        fixture.settings.save(settings)
        try fixture.makeUnreadable(key: "pat")
        let app = fixture.makeApp()
        #expect(app.session.settings.authMethod == .pat)
        #expect(fixture.settings.load() == settings)
        await app.bootstrapAccounts()
        #expect(app.session.account == .credentialsUnavailable(nil))
        #expect(app.authenticationMaterialState() == .unavailable)
        #expect(fixture.settings.load() == settings)
    }

    @Test
    func `launch repairs auth method from the active PAT account`() throws {
        let fixture = try CredentialFixture()
        defer { fixture.cleanUp() }
        // A failed quick sign-in used to persist OAuth while the active account stayed PAT.
        var stale = fixture.settings.load()
        stale.authMethod = .oauth
        fixture.settings.save(stale)
        let app = fixture.makeApp()
        #expect(app.session.settings.authMethod == .pat)
        #expect(fixture.settings.load().authMethod == .pat)
    }

    @Test
    func `legacy credential state requires definitive reads`() throws {
        let fixture = try CredentialFixture()
        defer { fixture.cleanUp() }
        let manager = AccountManager(tokenStore: fixture.tokens)
        #expect(manager.legacyCredentialState() == .missing)
        try fixture.tokens.savePAT("test")
        #expect(manager.legacyCredentialState() == .present)
        try fixture.makeUnreadable(key: "default")
        #expect(manager.legacyCredentialState() == .unavailable)
    }

    @Test
    func `unavailable refresh preserves loaded GitHub state without requesting tokens`() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.cleanUp() }
        try fixture.makeUnreadable(key: "\(fixture.account.id):pat")
        let app = fixture.makeApp()
        await app.bootstrapAccounts()
        await app.github.setTokenProvider {
            Issue.record("Unavailable refresh attempted a GitHub request")
            throw URLError(.notConnectedToInternet)
        }
        let repo = Repository(
            id: "test",
            name: "repo",
            owner: "test",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 1,
            openPulls: 2,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        let snapshot = MenuSnapshot(repositories: [repo], capturedAt: .distantPast)
        app.session.repositories = [repo]
        app.session.accessibleRepositories = [repo]
        app.session.menuSnapshot = snapshot
        app.session.menuDisplayIndex = ["test/repo": RepositoryDisplayModel(repo: repo)]
        app.session.hasLoadedRepositories = true
        app.session.hasStoredTokens = true
        app.session.menuRepoSelection = .all
        let heatmapRange = HeatmapRange(start: .distantPast, end: .distantFuture)
        app.session.heatmapRange = heatmapRange
        let activity = ActivityEvent(title: "Saved activity", actor: "test", date: .distantPast, url: fixture.account.host)
        let commit = RepoCommitSummary(
            sha: "test",
            message: "Saved commit",
            url: fixture.account.host,
            authoredAt: .distantPast,
            authorName: nil,
            authorLogin: nil,
            authorAvatarURL: nil
        )
        app.session.globalActivityEvents = [activity]
        app.session.globalCommitEvents = [commit]
        app.session.contributionHeatmap = [HeatmapCell(date: .distantPast, count: 5)]
        app.session.contributionUser = "test"
        app.session.globalActivityError = "saved activity"
        app.session.globalCommitError = "saved commits"
        await app.refresh()
        #expect(app.session.account == .credentialsUnavailable(fixture.identity))
        #expect(app.session.repositories.map(\.id) == [repo.id])
        #expect(app.session.accessibleRepositories.map(\.id) == [repo.id])
        #expect(app.session.menuSnapshot?.capturedAt == snapshot.capturedAt)
        #expect(app.session.menuDisplayIndex["test/repo"]?.source.id == repo.id)
        #expect(app.session.hasLoadedRepositories)
        #expect(app.session.hasStoredTokens)
        #expect(app.session.menuRepoSelection == .all)
        #expect(app.session.heatmapRange == heatmapRange)
        #expect(app.session.contributionUser == "test")
        #expect(app.session.contributionHeatmap.map(\.count) == [5])
        #expect(app.session.globalActivityEvents == [activity])
        #expect(app.session.globalCommitEvents == [commit])
        #expect(app.session.globalActivityError == "saved activity")
        #expect(app.session.globalCommitError == "saved commits")
        #expect(app.session.localProjectsScanInProgress == false)
    }

    @Test
    func `refresh restores active identity once credentials become readable`() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.cleanUp() }
        let key = "\(fixture.account.id):pat"
        try fixture.makeUnreadable(key: key)
        let app = fixture.makeApp()
        await app.bootstrapAccounts()
        app.session.menuRepoSelection = .all
        await app.refresh()
        #expect(app.session.account == .credentialsUnavailable(fixture.identity))
        #expect(app.session.menuRepoSelection == .all)
        try FileManager.default.removeItem(at: fixture.tokenURL(key: key))
        try fixture.tokens.savePAT("recovered", accountID: fixture.account.id)
        await app.github.setTokenProvider {
            // Identity recovery must not depend on /user being reachable.
            throw URLError(.notConnectedToInternet)
        }
        await app.refresh()
        #expect(app.session.account == .loggedIn(fixture.identity))
        #expect(app.session.menuRepoSelection == .all)
    }

    @Test
    func `oauth coordinator retries a failed initial load`() throws {
        let fixture = try CredentialFixture()
        defer { fixture.cleanUp() }
        try fixture.makeUnreadable(key: "default")
        let coordinator = OAuthCoordinator(tokenStore: fixture.tokens)
        #expect(coordinator.loadTokens() == nil)
        try FileManager.default.removeItem(at: fixture.tokenURL(key: "default"))
        try fixture.tokens.save(tokens: OAuthTokens(accessToken: "recovered", refreshToken: "", expiresAt: nil))
        #expect(coordinator.loadTokens()?.accessToken == "recovered")
    }
}

@MainActor
final class CredentialFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "repobar-credentials-\(UUID().uuidString)"
    let defaults: UserDefaults
    let tokens: TokenStore
    let settings: SettingsStore
    let account: Account

    var identity: UserIdentity {
        UserIdentity(username: self.account.username, host: self.account.host)
    }

    init(method: AuthMethod = .pat) throws {
        self.defaults = try #require(UserDefaults(suiteName: self.suite))
        self.tokens = TokenStore(service: "credential-tests", storage: .file(self.directory))
        self.settings = SettingsStore(defaults: self.defaults)
        self.account = Account(username: "alice", host: URL(string: "https://github.com")!, authMethod: method)
        var settings = UserSettings()
        settings.localProjects.rootPath = nil
        settings.localProjects.rootBookmarkData = nil
        settings.authMethod = method
        settings.accounts = [self.account]
        settings.activeAccountID = self.account.id
        self.settings.save(settings)
    }

    func tokenURL(key: String) -> URL {
        let serviceName = "credential-tests".utf8.map { String(format: "%02x", $0) }.joined()
        let accountName = key.utf8.map { String(format: "%02x", $0) }.joined()
        return self.directory.appendingPathComponent("v2-\(serviceName)-v2-\(accountName).json")
    }

    func makeUnreadable(key: String) throws {
        let url = self.tokenURL(key: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func makeApp() -> AppState {
        AppState(settingsStore: self.settings, accountManager: AccountManager(tokenStore: self.tokens))
    }

    func cleanUp() {
        self.defaults.removePersistentDomain(forName: self.suite)
        try? FileManager.default.removeItem(at: self.directory)
    }
}
