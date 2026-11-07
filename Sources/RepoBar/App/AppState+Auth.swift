import Foundation
import RepoBarCore

extension AppState {
    /// Starts the OAuth flow using the default GitHub App credentials, invoked from the logged-out prompt.
    func quickLogin() async {
        if case let .openAccountSettings(account) = QuickLoginDecision.resolve(
            accounts: self.session.settings.accounts,
            host: self.defaultGitHubHost
        ) {
            self.session.settingsSelectedTab = .accounts
            self.session.lastError = String(
                format: AppLocalizer().string("%@ @ %@ uses a personal access token. Update it in Accounts settings."),
                account.username,
                account.host.host ?? account.host.absoluteString
            )
            SettingsOpener.shared.open()
            return
        }
        self.session.account = .loggingIn
        self.session.settings.loopbackPort = self.defaultLoopbackPort
        self.session.settings.githubHost = self.defaultGitHubHost
        self.session.settings.enterpriseHost = nil
        self.session.settings.authMethod = .oauth
        self.persistSettings()

        do {
            try await self.auth.login(
                clientID: self.defaultClientID,
                clientSecret: self.defaultClientSecret,
                host: self.defaultGitHubHost,
                loopbackPort: self.defaultLoopbackPort
            )
            self.session.hasStoredTokens = true
            if let user = await self.currentUserFromLegacyCredentials(host: self.defaultGitHubHost) {
                self.session.account = .loggedIn(user)
                self.session.lastError = nil
                await self.recordAccountForLogin(user: user, host: self.defaultGitHubHost, method: .oauth)
            } else {
                self.session.account = .loggedIn(UserIdentity(username: "", host: self.defaultGitHubHost))
            }
            await self.refresh()
        } catch {
            self.session.account = .loggedOut
            self.session.lastError = error.userFacingMessage
        }
    }

    /// Authenticates with a Personal Access Token.
    func loginWithPAT(_ pat: String, host: URL) async {
        self.session.account = .loggingIn
        self.session.lastError = nil
        self.session.settings.githubHost = host
        if host.host?.lowercased() == "github.com" {
            self.session.settings.enterpriseHost = nil
        } else {
            self.session.settings.enterpriseHost = host
        }

        do {
            let user = try await self.patAuth.authenticate(pat: pat, host: host)
            self.session.settings.authMethod = .pat
            self.session.hasStoredTokens = true
            self.session.account = .loggedIn(user)
            self.session.lastError = nil
            self.persistSettings()
            await self.recordAccountForLogin(user: user, host: host, method: .pat, persistPAT: pat)
            await self.refresh()
        } catch {
            self.session.account = .loggedOut
            self.session.settings.authMethod = .oauth
            self.persistSettings()
            self.session.lastError = error.localizedDescription
        }
    }

    /// Logs out the current user, clearing tokens based on the current auth method.
    func logoutCurrentMethod() async {
        if let accountID = self.session.settings.resolvedActiveAccount()?.id {
            await self.removeAccount(accountID)
            if self.session.settings.accounts.isEmpty {
                self.session.account = .loggedOut
                self.session.hasStoredTokens = false
            }
            return
        }

        await self.auth.logout()
        await self.patAuth.logout()
        self.session.account = .loggedOut
        self.session.hasStoredTokens = false
        self.session.settings.authMethod = .oauth
        self.persistSettings()
    }
}
