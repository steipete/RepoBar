import Foundation
import OSLog
import RepoBarCore

/// Owns per-account `GitHubClient` instances and their auth state.
///
/// Bootstrapped from `UserSettings.accounts`. Each account gets its own
/// `GitHubClient` with an `apiHost` and a token provider closure that reads
/// from the account-scoped `TokenStore` APIs (Phase 1).
@MainActor
final class AccountManager {
    private(set) var accounts: [Account] = []
    private(set) var activeAccountID: String?
    private var clients: [String: GitHubClient] = [:]
    private let tokenStore: TokenStore
    private let oauthRefresher: OAuthTokenRefresher
    private let signposter = OSSignposter(subsystem: "com.steipete.repobar", category: "account-manager")

    init(
        tokenStore: TokenStore = .shared,
        oauthRefresher: OAuthTokenRefresher? = nil
    ) {
        self.tokenStore = tokenStore
        self.oauthRefresher = oauthRefresher ?? OAuthTokenRefresher(tokenStore: tokenStore)
    }

    // MARK: - Bootstrap

    /// Bootstraps the manager from persisted settings.
    /// Creates per-account `GitHubClient` instances and wires their token providers.
    func bootstrap(from settings: UserSettings) async {
        self.accounts = settings.accounts
        self.activeAccountID = settings.resolvedActiveAccount()?.id ?? settings.accounts.first?.id
        self.clients.removeAll(keepingCapacity: true)
        for account in self.accounts {
            await self.makeClient(for: account)
        }
    }

    /// Looks up the per-account `GitHubClient`. Returns `nil` when the account is unknown.
    func client(for accountID: String) -> GitHubClient? {
        self.clients[accountID]
    }

    /// The `GitHubClient` for the currently active account, if any.
    func activeClient() -> GitHubClient? {
        guard let activeAccountID else { return nil }

        return self.clients[activeAccountID]
    }

    func activeAccount() -> Account? {
        guard let activeAccountID else { return nil }

        return self.accounts.first(where: { $0.id == activeAccountID })
    }

    func hasStoredCredentials(accountID: String) -> Bool {
        guard let account = self.accounts.first(where: { $0.id == accountID }) else { return false }

        switch account.authMethod {
        case .oauth:
            return (try? self.tokenStore.loadTokens(accountID: accountID)) != nil
        case .pat:
            return (try? self.tokenStore.loadPAT(accountID: accountID)) != nil
        }
    }

    /// Sets the active account by ID. Returns whether the change took effect.
    @discardableResult
    func setActive(accountID: String?) -> Bool {
        if let accountID, self.accounts.contains(where: { $0.id == accountID }) {
            guard self.activeAccountID != accountID else { return false }

            self.activeAccountID = accountID
            return true
        }
        if accountID == nil, self.activeAccountID != nil {
            self.activeAccountID = nil
            return true
        }
        return false
    }

    // MARK: - Add / Remove

    /// Adds a new account, replacing any existing record with the same ID.
    /// Creates and caches a `GitHubClient` and marks it active when no other
    /// account is active yet.
    func add(_ account: Account) async {
        if let index = self.accounts.firstIndex(where: { $0.id == account.id }) {
            self.accounts[index] = account
        } else {
            self.accounts.append(account)
        }
        await self.makeClient(for: account)
        if self.activeAccountID == nil {
            self.activeAccountID = account.id
        }
    }

    /// Removes an account, its cached client, and all account-scoped tokens.
    func remove(accountID: String) async {
        self.tokenStore.clear(accountID: accountID)
        self.clients.removeValue(forKey: accountID)
        self.accounts.removeAll(where: { $0.id == accountID })
        if self.activeAccountID == accountID {
            self.activeAccountID = self.accounts.first?.id
        }
    }

    // MARK: - Account-scoped login helpers

    /// Persists OAuth tokens for `account` under its account-scoped keys.
    func storeOAuthTokens(_ tokens: OAuthTokens, for account: Account) throws {
        try self.tokenStore.save(tokens: tokens, accountID: account.id)
    }

    /// Persists OAuth client credentials for `account`.
    func storeClientCredentials(
        _ credentials: OAuthClientCredentials,
        for account: Account
    ) throws {
        try self.tokenStore.save(clientCredentials: credentials, accountID: account.id)
    }

    /// Persists a PAT for `account`.
    func storePAT(_ pat: String, for account: Account) throws {
        try self.tokenStore.savePAT(pat, accountID: account.id)
    }

    // MARK: - Token refresh

    /// Refreshes the OAuth token for `accountID` if needed.
    func refreshIfNeeded(accountID: String, force: Bool = false) async throws -> OAuthTokens? {
        guard let account = self.accounts.first(where: { $0.id == accountID }) else { return nil }

        switch account.authMethod {
        case .pat:
            // PATs do not refresh.
            if let pat = try self.tokenStore.loadPAT(accountID: accountID) {
                return OAuthTokens(accessToken: pat, refreshToken: "", expiresAt: nil)
            }
            return nil
        case .oauth:
            return try await self.refreshOAuth(account: account, force: force)
        }
    }

    /// Refreshes all OAuth accounts that have stored tokens.
    func refreshAllIfNeeded(force: Bool = false) async {
        for account in self.accounts where account.authMethod == .oauth {
            _ = try? await self.refreshOAuth(account: account, force: force)
        }
    }

    // MARK: - Account-scoped token provider

    /// Returns the current access token for `accountID`, preferring OAuth and
    /// falling back to PAT storage. Triggers a refresh if needed.
    func currentAccessToken(accountID: String) async throws -> String? {
        guard let account = self.accounts.first(where: { $0.id == accountID }) else { return nil }

        if account.authMethod == .pat {
            if let pat = try self.tokenStore.loadPAT(accountID: accountID) {
                return pat
            }
            return nil
        }
        return try await self.refreshOAuth(account: account, force: false)?.accessToken
    }

    // MARK: - Private

    private func makeClient(for account: Account) async {
        let client = GitHubClient(accountID: account.id)
        await client.setAPIHost(account.apiHost)
        let accountID = account.id
        let store = self.tokenStore
        let refresher = self.oauthRefresher
        await client.setTokenProvider { @Sendable [weak self] in
            if let self {
                guard let token = try await self.currentAccessToken(accountID: accountID) else { return nil }

                return OAuthTokens(accessToken: token, refreshToken: "", expiresAt: nil)
            }

            // A client can outlive the manager; preserve its account-scoped credential behavior.
            if account.authMethod == .pat, let pat = try store.loadPAT(accountID: accountID) {
                return OAuthTokens(accessToken: pat, refreshToken: "", expiresAt: nil)
            }
            if account.authMethod == .oauth {
                return try await refresher.refreshIfNeeded(host: account.host, accountID: accountID)
            }
            return nil
        }
        self.clients[account.id] = client
    }

    private func refreshOAuth(account: Account, force: Bool) async throws -> OAuthTokens? {
        let signpost = self.signposter.beginInterval("refreshOAuth")
        defer { self.signposter.endInterval("refreshOAuth", signpost) }

        return try await self.oauthRefresher.refreshIfNeeded(
            host: account.host,
            force: force,
            accountID: account.id
        )
    }
}
