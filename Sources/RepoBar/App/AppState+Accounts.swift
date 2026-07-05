import Foundation
import RepoBarCore

extension AppState {
    /// Bootstraps the account manager and runs one-shot legacy migration on first launch.
    ///
    /// Migration steps:
    /// 1. If `settings.accounts` is already populated, just hand them to the manager.
    /// 2. Otherwise probe legacy single-account credentials (OAuth, then PAT) and
    ///    derive a single `Account` from `GET /user`. Move tokens under the new
    ///    account-scoped Keychain keys and persist `settings.accounts`.
    /// 3. Mark the discovered account active so all existing single-account
    ///    code paths keep working through `session.activeAccountID`.
    func bootstrapAccounts() async {
        let manager = self.accountManager
        if self.session.settings.accounts.isEmpty {
            if let migrated = await self.migrateLegacyAccountIfNeeded() {
                self.session.settings.accounts = [migrated]
                self.session.settings.activeAccountID = migrated.id
                self.persistSettings()
            }
        }
        await manager.bootstrap(from: self.session.settings)
        await self.syncPrimaryGitHubClientToActiveAccount()
        self.session.activeAccountID = manager.activeAccountID
        if let active = manager.activeAccount(), manager.hasStoredCredentials(accountID: active.id) {
            self.session.account = .loggedIn(UserIdentity(username: active.username, host: active.host))
            self.session.hasStoredTokens = true
        } else {
            self.session.account = .loggedOut
            self.session.hasStoredTokens = false
        }
        self.session.accountSessions = self.session.settings.accounts.map { account in
            AccountSession(account: account)
        }
    }

    /// Attempts to discover an existing single-account login and convert it into a
    /// multi-account `Account` record. Returns `nil` when no credentials exist.
    private func migrateLegacyAccountIfNeeded() async -> Account? {
        let tokenStore = TokenStore.shared
        let oauthTokens = try? tokenStore.load()
        let legacyPAT = try? tokenStore.loadPAT()
        let legacyCreds = try? tokenStore.loadClientCredentials()
        guard oauthTokens != nil || legacyPAT != nil else { return nil }

        let host = self.session.settings.enterpriseHost ?? self.session.settings.githubHost
        let preferredMethod: AuthMethod = if oauthTokens != nil, legacyPAT != nil {
            self.session.settings.authMethod
        } else {
            oauthTokens != nil ? .oauth : .pat
        }

        // Use a one-off probe client to call /user with whichever credentials exist.
        let identity = await self.probeLegacyIdentity(
            host: host,
            oauthTokens: preferredMethod == .oauth ? oauthTokens : nil,
            pat: preferredMethod == .pat ? legacyPAT : nil
        )

        guard let username = identity?.username ?? self.fallbackUsernameFromSettings() else {
            return nil
        }

        let account = Account(
            username: username,
            host: host,
            authMethod: preferredMethod,
            loopbackPort: self.session.settings.loopbackPort,
            clientID: legacyCreds?.clientID
        )

        if preferredMethod == .oauth, let oauthTokens {
            try? tokenStore.save(tokens: oauthTokens, accountID: account.id)
        }
        if preferredMethod == .oauth, let legacyCreds {
            try? tokenStore.save(clientCredentials: legacyCreds, accountID: account.id)
        }
        if preferredMethod == .pat, let legacyPAT {
            try? tokenStore.savePAT(legacyPAT, accountID: account.id)
        }
        // Keep legacy fixed keys until the primary refresh path is fully
        // account-scoped; current app startup still uses them for login state.

        return account
    }

    private func probeLegacyIdentity(
        host: URL,
        oauthTokens: OAuthTokens?,
        pat: String?
    ) async -> UserIdentity? {
        let apiHost = Account.deriveAPIHost(for: host)
        let probe = GitHubClient()
        await probe.setAPIHost(apiHost)
        await probe.setTokenProvider { @Sendable in
            if let oauthTokens {
                return oauthTokens
            }
            if let pat {
                return OAuthTokens(accessToken: pat, refreshToken: "", expiresAt: nil)
            }
            return nil
        }
        return try? await probe.currentUser()
    }

    func currentUserFromLegacyCredentials(host: URL) async -> UserIdentity? {
        await self.probeLegacyIdentity(
            host: host,
            oauthTokens: try? TokenStore.shared.load(),
            pat: try? TokenStore.shared.loadPAT()
        )
    }

    private func fallbackUsernameFromSettings() -> String? {
        if case let .loggedIn(identity) = self.session.account, identity.username.isEmpty == false {
            return identity.username
        }
        return nil
    }

    /// Records a freshly authenticated identity as an `Account` and registers it
    /// with `AccountManager` so the account list reflects the new login.
    ///
    /// For OAuth logins the legacy fixed Keychain keys are also copied under
    /// the account-scoped keys so the per-account refresher can take over.
    func recordAccountForLogin(
        user: UserIdentity,
        host: URL,
        method: AuthMethod,
        persistPAT pat: String? = nil
    ) async {
        guard user.username.isEmpty == false else { return }

        let account = Account(
            username: user.username,
            host: host,
            authMethod: method,
            loopbackPort: self.session.settings.loopbackPort,
            clientID: (try? TokenStore.shared.loadClientCredentials())?.clientID
        )

        TokenStore.shared.clear(accountID: account.id)
        switch method {
        case .oauth:
            if let tokens = try? TokenStore.shared.load() {
                try? TokenStore.shared.save(tokens: tokens, accountID: account.id)
            }
            if let creds = try? TokenStore.shared.loadClientCredentials() {
                try? TokenStore.shared.save(clientCredentials: creds, accountID: account.id)
            }
        case .pat:
            let token = pat ?? (try? TokenStore.shared.loadPAT())
            if let token {
                try? TokenStore.shared.savePAT(token, accountID: account.id)
            }
        }

        await self.accountManager.add(account)
        _ = self.accountManager.setActive(accountID: account.id)
        if let index = self.session.settings.accounts.firstIndex(where: { $0.id == account.id }) {
            self.session.settings.accounts[index] = account
        } else {
            self.session.settings.accounts.append(account)
        }
        self.session.settings.activeAccountID = account.id
        self.mirrorActiveAccountIntoSettings(account)
        self.mirrorActiveAccountCredentialsToLegacy(account)
        self.session.activeAccountID = self.accountManager.activeAccountID
        await self.syncPrimaryGitHubClientToActiveAccount()
        self.session.accountSessions = self.session.settings.accounts.map { existing in
            if let current = self.session.accountSessions.first(where: { $0.id == existing.id }) {
                return current
            }
            return AccountSession(account: existing)
        }
        self.persistSettings()
    }

    /// Switches the active account by ID. No-op when the ID is unknown.
    func switchActiveAccount(to accountID: String) async {
        guard self.accountManager.setActive(accountID: accountID) else { return }

        self.session.activeAccountID = accountID
        self.session.settings.activeAccountID = accountID
        if let active = self.accountManager.activeAccount() {
            self.mirrorActiveAccountIntoSettings(active)
            self.mirrorActiveAccountCredentialsToLegacy(active)
        }
        self.persistSettings()
        await self.syncPrimaryGitHubClientToActiveAccount()
        await self.refreshSessionIdentityFromActiveClient()
        // Trigger a refresh so the menu reflects the new active account.
        self.requestRefresh(cancelInFlight: true)
    }

    /// Removes an account, clears its tokens, and updates the active selection.
    func removeAccount(_ accountID: String) async {
        await self.accountManager.remove(accountID: accountID)
        self.session.settings.accounts.removeAll(where: { $0.id == accountID })
        self.session.accountSessions.removeAll(where: { $0.id == accountID })
        if self.session.settings.activeAccountID == accountID {
            self.session.settings.activeAccountID = self.session.settings.accounts.first?.id
            self.session.activeAccountID = self.session.settings.activeAccountID
        }
        if let active = self.accountManager.activeAccount() {
            self.mirrorActiveAccountIntoSettings(active)
            self.mirrorActiveAccountCredentialsToLegacy(active)
        } else {
            TokenStore.shared.clear()
        }
        await self.syncPrimaryGitHubClientToActiveAccount()
        await self.refreshSessionIdentityFromActiveClient()
        // Drop any per-account pinned/hidden lists for the removed account.
        var lists = self.session.settings.accountRepoLists
        lists.pinnedByAccount.removeValue(forKey: accountID)
        lists.hiddenByAccount.removeValue(forKey: accountID)
        self.session.settings.accountRepoLists = lists
        self.persistSettings()
        self.requestRefresh(cancelInFlight: true)
    }

    private func syncPrimaryGitHubClientToActiveAccount() async {
        if let active = self.accountManager.activeAccount() {
            if let client = self.accountManager.activeClient() {
                self.github = client
                await self.github.setAPIHost(active.apiHost)
                return
            }
        }
        self.github = self.legacyGitHub
        await self.github.setAPIHost(self.defaultAPIHost)
    }

    private func refreshSessionIdentityFromActiveClient() async {
        if self.session.settings.resolvedActiveAccount() == nil {
            self.session.account = .loggedOut
            return
        }
        if let user = try? await self.github.currentUser() {
            self.session.account = .loggedIn(user)
        }
    }

    private func mirrorActiveAccountIntoSettings(_ account: Account) {
        self.session.settings.githubHost = account.host
        self.session.settings.enterpriseHost = account.host.host?.lowercased() == "github.com" ? nil : account.host
        self.session.settings.authMethod = account.authMethod
        self.session.settings.loopbackPort = account.loopbackPort
    }

    private func mirrorActiveAccountCredentialsToLegacy(_ account: Account) {
        _ = TokenStore.shared.mirrorAccountCredentialsToLegacy(
            accountID: account.id,
            authMethod: account.authMethod
        )
    }
}
