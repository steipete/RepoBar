import Foundation
import Observation
import RepoBarCore

@MainActor
@Observable
final class AppState {
    var session = Session()
    let auth: OAuthCoordinator
    let patAuth: PATAuthenticator
    let legacyGitHub: GitHubClient
    var github: GitHubClient
    let accountManager: AccountManager
    let refreshScheduler = RefreshScheduler()
    let settingsStore: SettingsStore
    let gitHubPullRequestNotificationRunner = GitHubPullRequestNotificationRunner()
    let gitHubReleaseNotificationRunner = GitHubReleaseNotificationRunner()
    let localRepoManager = LocalRepoManager()
    let menuRefreshInterval: TimeInterval = 30
    var refreshTask: Task<Void, Never>?
    var localProjectsTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    var menuRefreshTask: Task<Void, Never>?
    var gitHubReferenceMonitor: GitHubReferenceMonitor?
    var gitHubReferenceResolutionID = UUID()
    private var lifecycleID = UUID()
    var refreshTaskToken = UUID()
    let hydrateConcurrencyLimit = 4
    var prefetchTask: Task<Void, Never>?
    private let tokenRefreshInterval: TimeInterval = 300
    let menuRefreshDebounceInterval: TimeInterval = 1
    var lastMenuRefreshRequest: Date?
    private(set) var isStarted = false

    // Default GitHub App values for convenience login from the main window.
    let defaultClientID = RepoBarAuthDefaults.clientID
    let defaultClientSecret = RepoBarAuthDefaults.clientSecret
    let defaultLoopbackPort = RepoBarAuthDefaults.loopbackPort
    let defaultGitHubHost = RepoBarAuthDefaults.githubHost
    let defaultAPIHost = RepoBarAuthDefaults.apiHost

    init(
        settingsStore: SettingsStore = SettingsStore(),
        accountManager: AccountManager? = nil,
        auth: OAuthCoordinator = OAuthCoordinator(),
        patAuth: PATAuthenticator = PATAuthenticator()
    ) {
        let legacyGitHub = GitHubClient()
        self.legacyGitHub = legacyGitHub
        self.github = legacyGitHub
        self.auth = auth
        self.patAuth = patAuth
        self.settingsStore = settingsStore
        self.accountManager = accountManager ?? AccountManager()
        self.session.settings = self.settingsStore.load()
        self.reloadRateLimitCacheSummary()
        RepoBarLogging.bootstrapIfNeeded()
        RepoBarLogging.configure(
            verbosity: self.session.settings.loggingVerbosity,
            fileLoggingEnabled: self.session.settings.fileLoggingEnabled
        )
        let storedOAuthTokens = self.auth.loadTokens()
        let storedPAT = self.patAuth.loadPAT()
        self.session.hasStoredTokens = (storedOAuthTokens != nil) || (storedPAT != nil)
        let inferredAuthMethod: AuthMethod = storedPAT != nil ? .pat : .oauth
        if self.session.settings.authMethod != inferredAuthMethod {
            self.session.settings.authMethod = inferredAuthMethod
            self.settingsStore.save(self.session.settings)
        }
    }

    func start() {
        guard self.isStarted == false else { return }

        self.isStarted = true
        let lifecycleID = UUID()
        self.lifecycleID = lifecycleID
        let tokenStore = TokenStore.shared
        self.startupTask = Task { [weak self] in
            await self?.performStartup(tokenStore: tokenStore, lifecycleID: lifecycleID)
        }
    }

    func shutdown() {
        guard self.isStarted else { return }

        self.isStarted = false
        self.lifecycleID = UUID()
        self.startupTask?.cancel()
        self.startupTask = nil
        self.tokenRefreshTask?.cancel()
        self.tokenRefreshTask = nil
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.localProjectsTask?.cancel()
        self.localProjectsTask = nil
        self.menuRefreshTask?.cancel()
        self.menuRefreshTask = nil
        self.prefetchTask?.cancel()
        self.prefetchTask = nil
        self.refreshTaskToken = UUID()
        self.refreshScheduler.stop()
        self.gitHubReferenceMonitor?.stop()
        self.gitHubReferenceMonitor = nil
    }

    private func performStartup(tokenStore: TokenStore, lifecycleID: UUID) async {
        guard self.isCurrentLifecycle(lifecycleID) else { return }

        await self.github.setTokenProvider { @Sendable [weak self] () async throws -> OAuthTokens? in
            guard let self else { return nil }

            let accountID = await MainActor.run { self.session.settings.resolvedActiveAccount()?.id }
            if let accountID {
                if let token = try? await self.accountManager.currentAccessToken(accountID: accountID) {
                    return OAuthTokens(accessToken: token, refreshToken: "", expiresAt: nil)
                }
                return nil
            }

            let authMethod = await MainActor.run { self.session.settings.authMethod }
            if authMethod == .pat, let pat = try? tokenStore.loadPAT() {
                return OAuthTokens(accessToken: pat, refreshToken: "", expiresAt: nil)
            }
            return try? await self.auth.refreshIfNeeded()
        }
        guard self.isCurrentLifecycle(lifecycleID) else { return }

        await self.bootstrapAccounts()
        guard self.isCurrentLifecycle(lifecycleID) else { return }

        self.startTokenRefreshLoop(lifecycleID: lifecycleID)
        self.refreshScheduler.configure(interval: self.session.settings.refreshInterval.seconds) { [weak self] in
            self?.requestRefresh()
        }
        await DiagnosticsLogger.shared.setEnabled(self.session.settings.diagnosticsEnabled)
        self.updateGitHubReferenceMonitor()
        try? await Task.sleep(for: .milliseconds(250))
        guard self.isCurrentLifecycle(lifecycleID) else { return }

        await self.refreshRateLimitDisplayState()
        if self.lifecycleID == lifecycleID {
            self.startupTask = nil
        }
    }

    private func startTokenRefreshLoop(lifecycleID: UUID) {
        self.tokenRefreshTask?.cancel()
        self.tokenRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.refreshStoredTokens(lifecycleID: lifecycleID) else { return }

                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }

    func refreshStoredTokensNow() async {
        // The legacy item mirrors the account refresh token. GitHub retires
        // that token on first use, so a second refresh of the same value fails.
        if self.hasOAuthAccountRecord() {
            await self.accountManager.refreshAllIfNeeded()
            return
        }
        if self.session.settings.authMethod == .oauth, self.auth.loadTokens() != nil {
            _ = try? await self.auth.refreshIfNeeded()
        }
    }

    private func hasOAuthAccountRecord() -> Bool {
        if self.accountManager.accounts.contains(where: { $0.authMethod == .oauth }) {
            return true
        }
        return self.session.settings.accounts.contains(where: { $0.authMethod == .oauth })
    }

    private func refreshStoredTokens(lifecycleID: UUID) async -> TimeInterval? {
        guard self.isCurrentLifecycle(lifecycleID) else { return nil }

        await self.refreshStoredTokensNow()
        return self.isCurrentLifecycle(lifecycleID) ? self.tokenRefreshInterval : nil
    }

    private func isCurrentLifecycle(_ lifecycleID: UUID) -> Bool {
        self.isStarted && self.lifecycleID == lifecycleID && Task.isCancelled == false
    }

    struct GlobalActivityResult {
        let events: [ActivityEvent]
        let commits: [RepoCommitSummary]
        let error: String?
        let commitError: String?
    }

    func diagnostics() async -> DiagnosticsSummary {
        await self.refreshRateLimitDisplayState()
        return self.session.rateLimitDiagnostics
    }

    func refreshRateLimitDisplayState() async {
        _ = try? await self.github.refreshRateLimitResources()
        let diagnostics = await self.github.diagnostics()
        let cacheSummary = try? RepoBarPersistentCache.summary(limit: 100)
        self.session.rateLimitReset = await self.github.rateLimitReset()
        self.session.rateLimitDiagnostics = diagnostics
        self.session.rateLimitCacheSummary = cacheSummary
        NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
    }

    func reloadRateLimitCacheSummary(limit: Int = 100) {
        self.session.rateLimitCacheSummary = try? RepoBarPersistentCache.summary(limit: limit)
    }

    func clearCaches() async {
        await self.github.clearCache()
        ContributionCacheStore.clear()
    }

    func persistSettings() {
        self.settingsStore.save(self.session.settings)
    }

    func openAIAPIKeySource() -> OpenAIAPIKeySource {
        OpenAIAPIKeyStore().resolve().source
    }

    func saveOpenAIAPIKey(_ key: String) throws {
        try OpenAIAPIKeyStore().save(key)
    }

    func clearOpenAIAPIKey() {
        OpenAIAPIKeyStore().clearStoredKey()
    }
}

extension AppState {}
