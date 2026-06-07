import Commander
import Foundation
import RepoBarCore

@MainActor
struct RepoBarRoot: ParsableCommand {
    nonisolated static let commandName = "repobar"

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "RepoBar CLI",
            subcommands: [
                ReposCommand.self,
                RepoCommand.self,
                IssuesCommand.self,
                PullsCommand.self,
                ReleasesCommand.self,
                CICommand.self,
                DiscussionsCommand.self,
                TagsCommand.self,
                BranchesCommand.self,
                ContributorsCommand.self,
                CommitsCommand.self,
                ActivityCommand.self,
                LocalProjectsCommand.self,
                LocalSyncCommand.self,
                LocalRebaseCommand.self,
                LocalResetCommand.self,
                LocalBranchesCommand.self,
                WorktreesCommand.self,
                OpenFinderCommand.self,
                OpenTerminalCommand.self,
                CheckoutCommand.self,
                RefreshCommand.self,
                ContributionsCommand.self,
                ChangelogCommand.self,
                MarkdownCommand.self,
                PinCommand.self,
                UnpinCommand.self,
                HideCommand.self,
                ShowCommand.self,
                ArchivesListCommand.self,
                ArchivesStatusCommand.self,
                ArchivesValidateCommand.self,
                ArchivesUpdateCommand.self,
                ArchivesAddCommand.self,
                ArchivesRemoveCommand.self,
                ArchivesEnableCommand.self,
                ArchivesDisableCommand.self,
                RateLimitsCommand.self,
                ReferenceTranslateCommand.self,
                CacheStatusCommand.self,
                CacheClearCommand.self,
                SettingsShowCommand.self,
                SettingsSetCommand.self,
                LoginCommand.self,
                LogoutCommand.self,
                ImportGHTokenCommand.self,
                StatusCommand.self,
                AccountsListCommand.self,
                AccountsUseCommand.self,
                AccountsRemoveCommand.self
            ],
            defaultSubcommand: ReposCommand.self
        )
    }
}

@MainActor
struct ReposCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "repos"

    @Option(name: .customLong("limit"), help: "Max repositories to fetch (default: all accessible)")
    var limit: Int?

    @Option(name: .customLong("age"), help: "Max age in days for repo activity (default: 365)")
    var age: Int = RepositoryQueryDefaults.defaultAgeDays

    @Flag(names: [.customLong("release")], help: "Include latest release tag and date")
    var includeRelease: Bool = false

    @Flag(names: [.customLong("event")], help: "Show activity event column (hidden by default)")
    var includeEvent: Bool = false

    @Flag(names: [.customLong("forks"), .customLong("include-forks")], help: "Include forked repositories (hidden by default)")
    var includeForks: Bool = false

    @Flag(names: [.customLong("archived"), .customLong("include-archived")], help: "Include archived repositories (hidden by default)")
    var includeArchived: Bool = false

    @Option(name: .customLong("scope"), help: "Repository scope (values: all, pinned, hidden)")
    var scope: RepoScopeSelection?

    @Option(name: .customLong("filter"), help: "Filter repositories (values: all, work, issues, prs)")
    var filter: RepoFilterSelection?

    @Flag(names: [.customLong("pinned-only")], help: "Only list pinned repositories from settings")
    var pinnedOnly: Bool = false

    @Option(name: .customLong("only-with"), help: "Only show repos that have issues and/or PRs (values: work, issues, prs)")
    var onlyWith: OnlyWithSelection?

    @Option(name: .customLong("owner"), help: "Only show repositories owned by this login (repeatable, comma-separated)")
    var owner: String?

    @Flag(names: [.customLong("mine")], help: "Only show repositories owned by the authenticated user")
    var mine: Bool = false

    @Option(name: .customLong("sort"), help: "Sort by activity, issues, prs, stars, repo, or event")
    var sort: RepositorySortKey = .activity

    @OptionGroup
    var output: OutputOptions

    private var ownerFilter: RepoOwnerFilter?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "List repositories by activity, issues, PRs, and stars"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        self.limit = try values.decodeOption("limit")
        self.age = try values.decodeOption("age") ?? 365
        self.sort = try values.decodeOption("sort") ?? .activity
        self.includeRelease = values.flag("includeRelease")
        self.includeEvent = values.flag("includeEvent")
        self.includeForks = values.flag("includeForks")
        self.includeArchived = values.flag("includeArchived")
        self.scope = try values.decodeOption("scope")
        self.filter = try values.decodeOption("filter")
        self.pinnedOnly = values.flag("pinnedOnly")
        self.onlyWith = try values.decodeOption("onlyWith")
        let rawOwners = values.optionValues("owner")
        self.ownerFilter = RepoOwnerFilter.parse(rawOwners)
        self.mine = values.flag("mine")
        if self.ownerFilter == nil, rawOwners.isEmpty == false {
            throw ValidationError("--owner must include at least one login")
        }
    }

    mutating func run() async throws {
        if let limit, limit <= 0 {
            throw ValidationError("--limit must be greater than 0")
        }
        if self.age <= 0 {
            throw ValidationError("--age must be greater than 0")
        }
        if self.pinnedOnly, let scope, scope != .pinned {
            throw ValidationError("--pinned-only cannot be combined with --scope \(scope.rawValue)")
        }
        if self.filter != nil, self.onlyWith != nil {
            throw ValidationError("--filter cannot be combined with --only-with")
        }

        if self.output.jsonOutput == false, self.output.useColor {
            print("RepoBar CLI")
        }

        let context = try await makeAuthenticatedClient()
        let settings = context.settings
        let client = context.client

        var ownerFilter = self.ownerFilter
        if self.mine {
            let identity = try await client.currentUser()
            ownerFilter = (ownerFilter ?? RepoOwnerFilter(owners: []))
                .inserting(owner: identity.username)
        }

        let now = Date()
        let baseHost = context.host
        let effectiveScope = self.scope ?? (self.pinnedOnly ? .pinned : .all)
        let effectiveOnlyWith = self.filter?.onlyWith ?? self.onlyWith?.filter ?? .none
        let hidden = Set(settings.repoList.hiddenRepositories)
        let pinned = settings.repoList.pinnedRepositories.filter { !hidden.contains($0) }
        let ageCutoff = RepositoryQueryDefaults.ageCutoff(
            now: now,
            scope: effectiveScope.repositoryScope,
            ageDays: self.age
        )
        let query = RepositoryQuery(
            scope: effectiveScope.repositoryScope,
            onlyWith: effectiveOnlyWith,
            includeForks: self.includeForks,
            includeArchived: self.includeArchived,
            sortKey: self.sort,
            limit: self.limit,
            ageCutoff: ageCutoff,
            pinned: pinned,
            hidden: hidden,
            pinPriority: false
        )

        switch effectiveScope {
        case .pinned:
            guard pinned.isEmpty == false else {
                if self.output.jsonOutput {
                    try renderJSON([], baseHost: baseHost)
                } else {
                    print("No pinned repositories to show.")
                }
                return
            }

            let repos = try await self.fetchNamedRepositories(pinned, client: client)
            let ownerFiltered = ownerFilter?.applying(to: repos) ?? repos
            let filtered = RepositoryPipeline.apply(ownerFiltered, query: query)
            try await self.renderResults(
                repos: filtered,
                baseHost: baseHost,
                now: now,
                client: client
            )
            return
        case .hidden:
            let hiddenList = settings.repoList.hiddenRepositories
            guard hiddenList.isEmpty == false else {
                if self.output.jsonOutput {
                    try renderJSON([], baseHost: baseHost)
                } else {
                    print("No hidden repositories to show.")
                }
                return
            }

            let repos = try await self.fetchNamedRepositories(hiddenList, client: client)
            let ownerFiltered = ownerFilter?.applying(to: repos) ?? repos
            let filtered = RepositoryPipeline.apply(ownerFiltered, query: query)
            try await self.renderResults(
                repos: filtered,
                baseHost: baseHost,
                now: now,
                client: client
            )
            return
        case .all:
            break
        }

        let fetchLimit = Self.activityFetchLimit(requestedLimit: limit, ownerFilter: ownerFilter)
        let repos = try await client.activityRepositories(limit: fetchLimit)
        let ownerFiltered = ownerFilter?.applying(to: repos) ?? repos
        let filteredRepos = RepositoryPipeline.apply(ownerFiltered, query: query)
        try await self.renderResults(
            repos: filteredRepos,
            baseHost: baseHost,
            now: now,
            client: client
        )
    }

    private func renderResults(
        repos: [Repository],
        baseHost: URL,
        now: Date,
        client: GitHubClient
    ) async throws {
        var output = repos
        if self.includeRelease {
            output = try await self.attachLatestReleases(to: output, client: client)
        }
        let rows = prepareRows(repos: output, now: now)

        if self.output.jsonOutput {
            try renderJSON(rows, baseHost: baseHost)
        } else {
            let context = RepoTableContext(
                useColor: self.output.useColor,
                includeURL: self.output.plain == false,
                includeRelease: self.includeRelease,
                includeEvent: self.includeEvent,
                baseHost: baseHost,
                now: now
            )
            renderTable(rows, context: context)
        }
    }

    private func attachLatestReleases(to repos: [Repository], client: GitHubClient) async throws -> [Repository] {
        try await withThrowingTaskGroup(of: (Int, Repository).self) { group in
            for (index, repo) in repos.enumerated() {
                group.addTask {
                    var updated = repo
                    do {
                        updated.latestRelease = try await client.latestRelease(owner: repo.owner, name: repo.name)
                    } catch {
                        if updated.error == nil {
                            updated.error = "Release: \(error.userFacingMessage)"
                        }
                        if let gh = error as? GitHubAPIError {
                            updated.rateLimitedUntil = maxDate(updated.rateLimitedUntil, gh.rateLimitedUntil ?? gh.retryAfter)
                        }
                    }
                    return (index, updated)
                }
            }

            var results: [Repository?] = Array(repeating: nil, count: repos.count)
            for try await (index, repo) in group {
                results[index] = repo
            }
            return results.compactMap(\.self)
        }
    }

    private struct RepoLookup {
        let index: Int
        let repo: RepoIdentifier
    }

    private func fetchNamedRepositories(_ names: [String], client: GitHubClient) async throws -> [Repository] {
        let targets: [RepoLookup] = names.enumerated().compactMap { index, name in
            guard let repo = try? parseRepoName(name) else { return nil }

            return RepoLookup(index: index, repo: repo)
        }
        return try await withThrowingTaskGroup(of: (Int, Repository).self) { group in
            for target in targets {
                group.addTask {
                    let repo = try await client.fullRepository(owner: target.repo.owner, name: target.repo.name)
                    return (target.index, repo.withOrder(target.index))
                }
            }

            var results: [Repository?] = Array(repeating: nil, count: names.count)
            for try await (index, repo) in group {
                results[index] = repo
            }
            return results.compactMap(\.self)
        }
    }

    nonisolated static func activityFetchLimit(requestedLimit: Int?, ownerFilter: RepoOwnerFilter?) -> Int? {
        ownerFilter == nil ? requestedLimit : nil
    }
}

private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case (nil, nil):
        nil
    case (nil, let rhs?):
        rhs
    case (let lhs?, nil):
        lhs
    case let (lhs?, rhs?):
        max(lhs, rhs)
    }
}

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
            loopbackPort: resolvedLoopbackPort
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

@MainActor
struct StatusCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "status"

    @OptionGroup
    var output: OutputOptions

    @Option(name: .customLong("account"), help: "Account ID or username@host (defaults to active account)")
    var account: String?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Show login state"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        self.account = try values.decodeOption("account")
    }

    mutating func run() async throws {
        let settings = cliSettingsStore().load()
        // When the user explicitly targets an account, read account-scoped tokens.
        if self.account != nil || settings.accounts.isEmpty == false {
            let resolved: Account
            do {
                resolved = try AccountResolver.resolve(self.account, settings: settings)
            } catch {
                if self.account == nil {
                    // No account configured at all - fall through to legacy path.
                    try await self.runLegacy()
                    return
                }
                throw error
            }
            let tokens = try? TokenStore.shared.loadTokens(accountID: resolved.id)
            let pat = try? TokenStore.shared.loadPAT(accountID: resolved.id)
            let now = Date()
            let expiresAt = tokens?.expiresAt
            let expired = expiresAt.map { $0 <= now }
            let expiresIn = expiresAt.map { RelativeFormatter.string(from: $0, relativeTo: now) }
            let authenticated = tokens != nil || pat != nil
            if self.output.jsonOutput {
                let output = StatusOutput(
                    authenticated: authenticated,
                    host: resolved.host.absoluteString,
                    expiresAt: expiresAt,
                    expiresIn: expiresIn,
                    expired: expired
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(output)
                if let json = String(data: data, encoding: .utf8) { print(json) }
            } else if authenticated == false {
                print("Logged out (\(resolved.id)).")
            } else {
                print("Logged in as \(resolved.id).")
                print("Host: \(resolved.host.absoluteString)")
                if let expiresAt {
                    let state = expired == true ? "expired" : "expires"
                    let label = expiresIn ?? expiresAt.formatted()
                    print("\(state.capitalized): \(label)")
                } else {
                    print("Expires: unknown")
                }
            }
            return
        }
        try await self.runLegacy()
    }

    private func runLegacy() async throws {
        let tokens = try TokenStore.shared.load()
        guard let tokens else {
            if self.output.jsonOutput {
                let output = StatusOutput(
                    authenticated: false,
                    host: nil,
                    expiresAt: nil,
                    expiresIn: nil,
                    expired: nil
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(output)
                if let json = String(data: data, encoding: .utf8) { print(json) }
            } else {
                print("Logged out.")
            }
            return
        }

        let settings = cliSettingsStore().load()
        let host = (settings.enterpriseHost ?? settings.githubHost).absoluteString
        let now = Date()
        let expiresAt = tokens.expiresAt
        let expired = expiresAt.map { $0 <= now }
        let expiresIn = expiresAt.map { RelativeFormatter.string(from: $0, relativeTo: now) }

        if self.output.jsonOutput {
            let output = StatusOutput(
                authenticated: true,
                host: host,
                expiresAt: expiresAt,
                expiresIn: expiresIn,
                expired: expired
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(output)
            if let json = String(data: data, encoding: .utf8) { print(json) }
        } else {
            print("Logged in.")
            print("Host: \(host)")
            if let expiresAt {
                let state = expired == true ? "expired" : "expires"
                let label = expiresIn ?? expiresAt.formatted()
                print("\(state.capitalized): \(label)")
            } else {
                print("Expires: unknown")
            }
        }
    }
}
