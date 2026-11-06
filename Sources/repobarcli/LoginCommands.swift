import Commander
import Foundation
import RepoBarCore

@MainActor
struct LoginCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "login"

    @Option(name: .customLong("host"), help: "GitHub host URL (GitHub.com or Enterprise base URL)")
    var host: String?

    @Option(name: .customLong("client-id"), help: "GitHub App OAuth client ID")
    var clientID: String?

    @Option(name: .customLong("client-secret"), help: "GitHub App OAuth client secret")
    var clientSecret: String?

    @Option(name: .customLong("loopback-port"), help: "Loopback port for OAuth callback")
    var loopbackPort: Int?

    @Option(name: .customLong("label"), help: "Friendly display name for the new account")
    var label: String?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Sign in via browser-based OAuth"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.host = try values.decodeOption("host")
        self.clientID = try values.decodeOption("clientID")
        self.clientSecret = try values.decodeOption("clientSecret")
        self.loopbackPort = try values.decodeOption("loopbackPort")
        self.label = try values.decodeOption("label")
    }

    mutating func run() async throws {
        if let loopbackPort, loopbackPort <= 0 || loopbackPort >= 65536 {
            throw ValidationError("--loopback-port must be between 1 and 65535")
        }

        let store = cliSettingsStore()
        var settings = store.load()
        let rawHost: URL = if let host {
            try parseHost(host)
        } else {
            settings.enterpriseHost ?? settings.githubHost
        }
        let normalizedHost = try OAuthLoginFlow.normalizeHost(rawHost)
        let resolvedClientID = self.clientID ?? RepoBarAuthDefaults.clientID
        let resolvedClientSecret = self.clientSecret ?? RepoBarAuthDefaults.clientSecret
        let resolvedLoopbackPort = self.loopbackPort ?? settings.loopbackPort

        let flow = OAuthLoginFlow(tokenStore: .shared) { url in
            try openURL(url)
        }
        let tokens = try await flow.login(
            clientID: resolvedClientID,
            clientSecret: resolvedClientSecret,
            host: normalizedHost,
            loopbackPort: resolvedLoopbackPort,
            devicePrompt: { code, url in
                print("Enter \(code) at \(url.absoluteString)")
            }
        )

        // Identify the signed-in user so we can persist an account record.
        let apiHost = Account.deriveAPIHost(for: normalizedHost)
        let probeClient = GitHubClient()
        await probeClient.setAPIHost(apiHost)
        let capturedToken = tokens.accessToken
        await probeClient.setTokenProvider { @Sendable in
            OAuthTokens(accessToken: capturedToken, refreshToken: "", expiresAt: nil)
        }
        let identity = try await probeClient.currentUser()

        let account = Account(
            username: identity.username,
            host: normalizedHost,
            authMethod: .oauth,
            loopbackPort: resolvedLoopbackPort,
            clientID: resolvedClientID,
            displayName: self.label
        )

        // Persist tokens + client credentials under the account-scoped keys so
        // multi-account refresh continues to work after the legacy "default"
        // entries are cleared on a future migration.
        try TokenStore.shared.save(tokens: tokens, accountID: account.id)
        try TokenStore.shared.save(
            clientCredentials: OAuthClientCredentials(
                clientID: resolvedClientID,
                clientSecret: resolvedClientSecret
            ),
            accountID: account.id
        )

        settings.loopbackPort = resolvedLoopbackPort
        settings.githubHost = RepoBarAuthDefaults.githubHost
        if normalizedHost.host?.lowercased() == "github.com" {
            settings.enterpriseHost = nil
        } else {
            settings.enterpriseHost = normalizedHost
        }
        if let index = settings.accounts.firstIndex(where: { $0.id == account.id }) {
            settings.accounts[index] = account
        } else {
            settings.accounts.append(account)
        }
        settings.activeAccountID = account.id
        store.save(settings)

        print("Login succeeded; tokens stored for \(account.id).")
    }
}

@MainActor
struct LogoutCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "logout"

    @Option(name: .customLong("account"), help: "Account ID or username@host (defaults to active account)")
    var account: String?

    @Flag(names: [.customLong("all")], help: "Log out of every configured account")
    var all: Bool = false

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Clear stored credentials"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.account = try values.decodeOption("account")
        self.all = values.flag("all")
    }

    mutating func run() async throws {
        let store = cliSettingsStore()
        var settings = store.load()

        if self.all {
            TokenStore.shared.clearAllCredentials()
            let scopedAccountIDs = Set(settings.accounts.map(\.id))
                .union((try? TokenStore.shared.allAccountIDs()) ?? [])
            for accountID in scopedAccountIDs {
                TokenStore.shared.clear(accountID: accountID)
            }
            settings.accounts = []
            settings.activeAccountID = nil
            store.save(settings)
            print("Logged out of all accounts.")
            return
        }

        if settings.accounts.isEmpty {
            TokenStore.shared.clear()
            print("Logged out.")
            return
        }

        let resolved = try AccountResolver.resolve(self.account, settings: settings)
        TokenStore.shared.clear(accountID: resolved.id)
        settings.accounts.removeAll(where: { $0.id == resolved.id })
        if settings.activeAccountID == resolved.id {
            settings.activeAccountID = settings.accounts.first?.id
        }
        mirrorResolvedActiveAccount(settings: &settings)
        store.save(settings)
        print("Logged out of \(resolved.id).")
    }
}

@MainActor
struct ImportGHTokenCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "import-gh-token"

    @Option(name: .customLong("host"), help: "GitHub host (https://github.com or your GHE base URL)")
    var host: String?

    @Option(name: .customLong("label"), help: "Friendly display name for the imported account")
    var label: String?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Import token from GitHub CLI (gh) for SSO-enabled orgs"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.host = try values.decodeOption("host")
        self.label = try values.decodeOption("label")
    }

    mutating func run() async throws {
        let store = cliSettingsStore()
        var settings = store.load()
        let rawHost: URL = if let host {
            try parseHost(host)
        } else {
            settings.enterpriseHost ?? settings.githubHost
        }
        let normalizedHost = try OAuthLoginFlow.normalizeHost(rawHost)
        guard let ghHostname = normalizedHost.host, ghHostname.isEmpty == false else {
            throw ValidationError("Invalid host: \(rawHost.absoluteString)")
        }

        // Get token from gh CLI
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token", "--hostname", ghHostname]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ValidationError("Failed to run 'gh auth token'. Is GitHub CLI installed?")
        }

        guard process.terminationStatus == 0 else {
            throw ValidationError("'gh auth token' failed. Please run 'gh auth login' first.")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let tokenString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tokenString.isEmpty
        else {
            throw ValidationError("No token returned from gh CLI. Please run 'gh auth login' first.")
        }

        // gh tokens don't expire, so leave expiry unset and skip refresh.
        let tokens = OAuthTokens(
            accessToken: tokenString,
            refreshToken: "",
            expiresAt: nil
        )

        // Probe the API so we can persist a stable account record.
        let apiHost = Account.deriveAPIHost(for: normalizedHost)
        let probeClient = GitHubClient()
        await probeClient.setAPIHost(apiHost)
        await probeClient.setTokenProvider { @Sendable in
            OAuthTokens(accessToken: tokenString, refreshToken: "", expiresAt: nil)
        }
        let identity = try await probeClient.currentUser()
        let account = Account(
            username: identity.username,
            host: normalizedHost,
            authMethod: .pat,
            displayName: self.label
        )

        // Legacy single-account fast path keeps working.
        try TokenStore.shared.save(tokens: tokens)
        // Account-scoped storage for multi-account flows.
        try TokenStore.shared.save(tokens: tokens, accountID: account.id)
        try TokenStore.shared.savePAT(tokenString, accountID: account.id)

        settings.githubHost = RepoBarAuthDefaults.githubHost
        if normalizedHost.host?.lowercased() == "github.com" {
            settings.enterpriseHost = nil
        } else {
            settings.enterpriseHost = normalizedHost
        }
        if let index = settings.accounts.firstIndex(where: { $0.id == account.id }) {
            settings.accounts[index] = account
        } else {
            settings.accounts.append(account)
        }
        settings.activeAccountID = account.id
        store.save(settings)

        print("Successfully imported gh CLI token for \(account.id).")
        print("Token expires: unknown")
        print("\nNote: Re-run this command if your gh token changes or if you re-authenticate with 'gh auth login'.")
    }
}
