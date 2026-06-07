import Algorithms
import Foundation
import Observation
import RepoBarCore

// MARK: - AppState container

@MainActor
@Observable
final class AppState {
    var session = Session()
    let auth = OAuthCoordinator()
    let patAuth = PATAuthenticator()
    let legacyGitHub: GitHubClient
    var github: GitHubClient
    let accountManager = AccountManager()
    let refreshScheduler = RefreshScheduler()
    let settingsStore = SettingsStore()
    let gitHubPullRequestNotificationRunner = GitHubPullRequestNotificationRunner()
    let localRepoManager = LocalRepoManager()
    let menuRefreshInterval: TimeInterval = 30
    var refreshTask: Task<Void, Never>?
    var localProjectsTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    var menuRefreshTask: Task<Void, Never>?
    private var gitHubReferenceMonitor: GitHubReferenceMonitor?
    private var gitHubReferenceResolutionID = UUID()
    var refreshTaskToken = UUID()
    let hydrateConcurrencyLimit = 4
    var prefetchTask: Task<Void, Never>?
    private let tokenRefreshInterval: TimeInterval = 300
    let menuRefreshDebounceInterval: TimeInterval = 1
    var lastMenuRefreshRequest: Date?

    // Default GitHub App values for convenience login from the main window.
    let defaultClientID = RepoBarAuthDefaults.clientID
    let defaultClientSecret = RepoBarAuthDefaults.clientSecret
    let defaultLoopbackPort = RepoBarAuthDefaults.loopbackPort
    let defaultGitHubHost = RepoBarAuthDefaults.githubHost
    let defaultAPIHost = RepoBarAuthDefaults.apiHost

    init() {
        let legacyGitHub = GitHubClient()
        self.legacyGitHub = legacyGitHub
        self.github = legacyGitHub
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
        // Capture tokenStore separately for Sendable compliance
        let tokenStore = TokenStore.shared
        Task {
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
                if authMethod == .pat {
                    if let pat = try? tokenStore.loadPAT() {
                        return OAuthTokens(accessToken: pat, refreshToken: "", expiresAt: nil)
                    }
                }
                return try? await self.auth.refreshIfNeeded()
            }
        }
        self.tokenRefreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                if self.session.settings.authMethod == .oauth, self.auth.loadTokens() != nil {
                    _ = try? await self.auth.refreshIfNeeded()
                }
                // Fan out to every account-scoped OAuth refresher. PAT-only
                // accounts are no-ops and OAuth accounts refresh independently.
                await self.accountManager.refreshAllIfNeeded()
                try? await Task.sleep(for: .seconds(self.tokenRefreshInterval))
            }
        }
        // Bootstrap account manager before the first scheduled refresh so
        // account-scoped credentials are available to the token provider.
        Task { [weak self] in
            guard let self else { return }

            await self.bootstrapAccounts()
            self.refreshScheduler.configure(interval: self.session.settings.refreshInterval.seconds) { [weak self] in
                self?.requestRefresh()
            }
        }
        Task { await DiagnosticsLogger.shared.setEnabled(self.session.settings.diagnosticsEnabled) }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await self?.refreshRateLimitDisplayState()
        }
        self.updateGitHubReferenceMonitor()
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

    func updateGitHubReferenceMonitor() {
        guard self.session.settings.gitHubReferenceMonitor.enabled else {
            Task { await DiagnosticsLogger.shared.message("GitHub reference monitor disabled") }
            self.gitHubReferenceMonitor?.stop()
            self.gitHubReferenceMonitor = nil
            self.setGitHubReferenceMatch(nil)
            return
        }

        if self.gitHubReferenceMonitor == nil {
            Task { await DiagnosticsLogger.shared.message("GitHub reference monitor created") }
            self.gitHubReferenceMonitor = GitHubReferenceMonitor(
                onPasteboardWithoutReference: { [weak self] in
                    await self?.clearGitHubReference()
                },
                onReferences: { [weak self] queries, text in
                    await self?.resolveGitHubReferences(queries, sourceText: text)
                }
            )
        }
        Task { await DiagnosticsLogger.shared.message("GitHub reference monitor started mode=clipboard-only") }
        self.gitHubReferenceMonitor?.start()
    }

    private func clearGitHubReference() async {
        guard self.session.settings.gitHubReferenceMonitor.enabled else { return }

        self.gitHubReferenceResolutionID = UUID()
        self.setGitHubReferenceMatches([])
    }

    private func resolveGitHubReferences(_ queries: [GitHubReferenceQuery], sourceText: String) async {
        guard self.session.settings.gitHubReferenceMonitor.enabled else { return }

        let resolutionID = UUID()
        self.gitHubReferenceResolutionID = resolutionID
        let scopedQueries = await self.queries(queries, applyingLocalRepositoryContextFrom: sourceText)
        guard self.gitHubReferenceResolutionID == resolutionID else { return }

        let provisionalMatches = self.provisionalReferenceMatches(from: sourceText)
        let matches = await self.referenceMatches(
            for: scopedQueries,
            resolutionID: resolutionID,
            provisionalMatches: provisionalMatches
        ) { matches in
            self.setGitHubReferenceMatches(matches)
        }
        guard self.gitHubReferenceResolutionID == resolutionID else { return }

        self.setGitHubReferenceMatches(matches)
    }

    func resolveGitHubReferenceQueries(_ queries: [GitHubReferenceQuery], sourceText: String) async -> [GitHubReferenceMatch] {
        let scopedQueries = await self.queries(queries, applyingLocalRepositoryContextFrom: sourceText)
        return await self.referenceMatches(for: scopedQueries, resolutionID: nil)
    }

    func searchIssueReferences(
        matching text: String,
        repositoryFullName: String?,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int = AppLimits.IssueNavigator.searchLimit
    ) async throws -> [GitHubReferenceMatch] {
        if let repositoryFullName {
            return try await self.github.searchIssueReferences(
                matching: text,
                repositoryFullName: repositoryFullName,
                includeIssues: includeIssues,
                includePullRequests: includePullRequests,
                limit: limit
            )
        }

        let repositories = Self.issueNavigatorSearchRepositories(from: self.githubReferenceCandidateRepositories())
        guard repositories.isEmpty == false else {
            if self.session.hasLoadedRepositories {
                return []
            }

            throw IssueNavigatorSearchError.repositoryInventoryLoading
        }

        let github = self.github
        let perRepositoryLimit = AppLimits.IssueNavigator.perRepositorySearchLimit
        var matches: [GitHubReferenceMatch] = []
        var firstError: Error?
        var failedSearches = 0

        for chunk in repositories.chunks(ofCount: AppLimits.IssueNavigator.repositorySearchConcurrencyLimit) {
            await withTaskGroup(of: Result<[GitHubReferenceMatch], Error>.self) { group in
                for repo in chunk {
                    group.addTask {
                        do {
                            let matches = try await github.searchIssueReferences(
                                matching: text,
                                repositoryFullName: repo.fullName,
                                includeIssues: includeIssues,
                                includePullRequests: includePullRequests,
                                limit: perRepositoryLimit
                            )
                            return .success(matches)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                for await result in group {
                    switch result {
                    case let .success(found):
                        matches.append(contentsOf: found)
                    case let .failure(error):
                        failedSearches += 1
                        firstError = firstError ?? error
                    }
                }
            }
        }

        if Self.shouldSurfaceIssueSearchFailure(
            searchedRepositories: repositories.count,
            failedSearches: failedSearches,
            matchCount: matches.count
        ), let firstError {
            throw firstError
        }

        return Array(Self.dedupedGitHubReferenceMatches(matches).prefix(limit))
    }

    static func shouldSurfaceIssueSearchFailure(
        searchedRepositories: Int,
        failedSearches: Int,
        matchCount: Int
    ) -> Bool {
        matchCount == 0 && searchedRepositories > 0 && failedSearches >= searchedRepositories
    }

    static func issueNavigatorSearchRepositories(from repositories: [Repository]) -> [Repository] {
        let sorted = repositories
            .filter { $0.viewerCanRead && !$0.isArchived }
            .sorted {
                let lhsDate = $0.latestActivity?.date ?? $0.pushedAt ?? .distantPast
                let rhsDate = $1.latestActivity?.date ?? $1.pushedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }

        return Array(sorted.prefix(AppLimits.IssueNavigator.maxRepositorySearchFanout))
    }

    func recentIssueReferences(
        repositoryFullName: String?,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int = AppLimits.IssueNavigator.searchLimit
    ) async throws -> [GitHubReferenceMatch] {
        if let repositoryFullName {
            let matches = try await self.recentRepositoryIssueReferences(
                repositoryFullName: repositoryFullName,
                includeIssues: includeIssues,
                includePullRequests: includePullRequests,
                limit: limit
            )
            return Array(Self.dedupedGitHubReferenceMatches(matches).prefix(limit))
        }

        async let allResult = Self.capture {
            try await self.github.recentIssueReferences(
                filter: "all",
                includeIssues: includeIssues,
                includePullRequests: includePullRequests,
                limit: limit
            )
        }
        async let subscribedResult = Self.capture {
            try await self.github.recentIssueReferences(
                filter: "subscribed",
                includeIssues: includeIssues,
                includePullRequests: includePullRequests,
                limit: limit
            )
        }
        async let repositoryMatches = self.recentAccessibleRepositoryIssueReferences(
            includeIssues: includeIssues,
            includePullRequests: includePullRequests
        )

        let (all, subscribed, accessible) = await (allResult, subscribedResult, repositoryMatches)
        var matches = accessible
        var firstError: Error?
        switch all {
        case let .success(found):
            matches.append(contentsOf: found)
        case let .failure(error):
            firstError = firstError ?? error
        }
        switch subscribed {
        case let .success(found):
            matches.append(contentsOf: found)
        case let .failure(error):
            firstError = firstError ?? error
        }

        if matches.isEmpty, let firstError {
            throw firstError
        }

        return Array(Self.dedupedGitHubReferenceMatches(matches).prefix(limit))
    }

    func gitHubReferenceRepositories() -> [Repository] {
        self.githubReferenceCandidateRepositories()
    }

    private nonisolated static func capture<T>(_ operation: @escaping @Sendable () async throws -> T) async -> Result<T, Error> {
        do {
            return try await .success(operation())
        } catch {
            return .failure(error)
        }
    }

    nonisolated static func dedupedGitHubReferenceMatches(_ matches: [GitHubReferenceMatch]) -> [GitHubReferenceMatch] {
        var seen: Set<URL> = []
        return matches
            .filter { seen.insert($0.url).inserted }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
    }

    static func issueNavigatorRecentRepositories(
        from repositories: [Repository],
        includeIssues: Bool,
        includePullRequests: Bool
    ) -> [Repository] {
        let sorted = repositories
            .filter { repo in
                guard repo.viewerCanRead, !repo.isArchived else { return false }

                return (includeIssues && repo.openIssues > 0) || (includePullRequests && repo.openPulls > 0)
            }
            .sorted {
                let lhs = $0.latestActivity?.date ?? $0.pushedAt ?? .distantPast
                let rhs = $1.latestActivity?.date ?? $1.pushedAt ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                return $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }

        return Array(sorted.prefix(AppLimits.IssueNavigator.recentRepositoryLimit))
    }

    private func recentAccessibleRepositoryIssueReferences(
        includeIssues: Bool,
        includePullRequests: Bool
    ) async -> [GitHubReferenceMatch] {
        let repositories = Self.issueNavigatorRecentRepositories(
            from: self.githubReferenceCandidateRepositories(),
            includeIssues: includeIssues,
            includePullRequests: includePullRequests
        )

        var matches: [GitHubReferenceMatch] = []
        let github = self.github

        for chunk in repositories.chunks(ofCount: AppLimits.IssueNavigator.repositorySearchConcurrencyLimit) {
            await withTaskGroup(of: [GitHubReferenceMatch].self) { group in
                for repo in chunk {
                    group.addTask {
                        do {
                            return try await Self.recentRepositoryIssueReferences(
                                github: github,
                                repositoryFullName: repo.fullName,
                                includeIssues: includeIssues,
                                includePullRequests: includePullRequests,
                                limit: AppLimits.IssueNavigator.perRepositoryRecentLimit
                            )
                        } catch {
                            return []
                        }
                    }
                }

                for await found in group {
                    matches.append(contentsOf: found)
                }
            }
        }

        return matches
    }

    private func recentRepositoryIssueReferences(
        repositoryFullName: String,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int
    ) async throws -> [GitHubReferenceMatch] {
        try await Self.recentRepositoryIssueReferences(
            github: self.github,
            repositoryFullName: repositoryFullName,
            includeIssues: includeIssues,
            includePullRequests: includePullRequests,
            limit: limit
        )
    }

    private nonisolated static func recentRepositoryIssueReferences(
        github: GitHubClient,
        repositoryFullName: String,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int
    ) async throws -> [GitHubReferenceMatch] {
        guard let parts = repositoryParts(from: repositoryFullName) else { return [] }

        async let issuesItems: [RepoIssueSummary] = includeIssues
            ? github.recentIssues(owner: parts.owner, name: parts.name, limit: limit)
            : []
        async let pullsItems: [RepoPullRequestSummary] = includePullRequests
            ? github.recentPullRequests(owner: parts.owner, name: parts.name, limit: limit)
            : []

        let (issues, pulls) = try await (issuesItems, pullsItems)
        var matches: [GitHubReferenceMatch] = []
        matches.append(contentsOf: issues.map {
            GitHubReferenceMatch(
                query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: $0.number),
                title: $0.title,
                url: $0.url,
                repositoryFullName: repositoryFullName,
                kind: .issue,
                state: .open,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                authorLogin: $0.authorLogin
            )
        })
        matches.append(contentsOf: pulls.map {
            GitHubReferenceMatch(
                query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: $0.number),
                title: $0.title,
                url: $0.url,
                repositoryFullName: repositoryFullName,
                kind: .pullRequest,
                state: .open,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                bodyPreview: $0.bodyPreview,
                authorLogin: $0.authorLogin
            )
        })

        return Self.dedupedGitHubReferenceMatches(matches)
    }

    private nonisolated static func repositoryParts(from fullName: String) -> (owner: String, name: String)? {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].isEmpty == false, parts[1].isEmpty == false else { return nil }

        return (parts[0], parts[1])
    }

    private func referenceMatches(
        for queries: [GitHubReferenceQuery],
        resolutionID: UUID?,
        provisionalMatches: [GitHubReferenceQuery: GitHubReferenceMatch] = [:],
        onProgress: (([GitHubReferenceMatch]) -> Void)? = nil
    ) async -> [GitHubReferenceMatch] {
        let limitedQueries = Array(queries.prefix(AppLimits.GitHubReferenceMonitor.queryLimit))
        let repositories = self.githubReferenceCandidateRepositories()
        let github = self.github
        var matchesByIndex: [Int: GitHubReferenceMatch] = [:]

        let indexedQueries = Array(limitedQueries.enumerated())
        for (index, query) in indexedQueries {
            if let provisionalMatch = provisionalMatches[query] {
                matchesByIndex[index] = provisionalMatch
            }
        }
        if matchesByIndex.isEmpty == false {
            onProgress?(Self.orderedReferenceMatches(matchesByIndex))
        }

        for chunk in indexedQueries.chunks(ofCount: AppLimits.GitHubReferenceMonitor.resolutionConcurrencyLimit) {
            await withTaskGroup(of: (Int, GitHubReferenceMatch?).self) { group in
                for (index, query) in chunk {
                    group.addTask {
                        let match = await Self.resolveGitHubReferenceMatch(
                            query: query,
                            repositories: repositories,
                            github: github
                        )
                        return (index, match)
                    }
                }

                for await (index, match) in group {
                    if let resolutionID, self.gitHubReferenceResolutionID != resolutionID {
                        group.cancelAll()
                        return
                    }
                    if let match {
                        matchesByIndex[index] = match
                    } else if let provisionalMatch = matchesByIndex[index], provisionalMatch.isResolved == false {
                        matchesByIndex[index] = GitHubReferenceMatch.unresolved(from: provisionalMatch)
                    } else {
                        continue
                    }
                    onProgress?(Self.orderedReferenceMatches(matchesByIndex))
                }
            }

            if let resolutionID, self.gitHubReferenceResolutionID != resolutionID {
                return []
            }
        }

        return Self.orderedReferenceMatches(matchesByIndex)
    }

    private nonisolated static func orderedReferenceMatches(_ matchesByIndex: [Int: GitHubReferenceMatch]) -> [GitHubReferenceMatch] {
        var seen: Set<URL> = []
        return matchesByIndex.keys.sorted().compactMap { matchesByIndex[$0] }.filter {
            seen.insert($0.url).inserted
        }
    }

    private nonisolated func provisionalReferenceMatches(from sourceText: String) -> [GitHubReferenceQuery: GitHubReferenceMatch] {
        let now = Date()
        var matches: [GitHubReferenceQuery: GitHubReferenceMatch] = [:]
        for reference in GitHubReferenceTranslator.urlReferences(in: sourceText) {
            guard let match = GitHubReferenceMatch.provisional(
                query: reference.query,
                url: reference.url,
                kind: reference.kind,
                now: now
            ) else { continue }

            matches[reference.query] = match
        }
        return matches
    }

    private func queries(
        _ queries: [GitHubReferenceQuery],
        applyingLocalRepositoryContextFrom text: String
    ) async -> [GitHubReferenceQuery] {
        guard queries.contains(where: { $0.repositoryFullName == nil }) else { return queries }

        let repositoryFullName = await GitHubReferenceLocalContext.repositoryFullName(
            in: text,
            localRepoIndex: self.session.localRepoIndex
        )
        guard let repositoryFullName else {
            return await GitHubReferenceLocalContext.queries(
                queries,
                applyingLocalRepositoryContextFrom: self.session.localRepoIndex
            )
        }

        return GitHubReferenceTranslator.queries(
            from: text,
            minimumBareDigits: AppLimits.GitHubReferenceMonitor.minimumBareDigits,
            repositoryContextOverride: repositoryFullName
        )
    }

    private nonisolated static func resolveGitHubReferenceMatch(
        query: GitHubReferenceQuery,
        repositories: [Repository],
        github: GitHubClient
    ) async -> GitHubReferenceMatch? {
        let candidateRepositories = if let repositoryFullName = query.repositoryFullName {
            repositories.filter { $0.fullName.caseInsensitiveCompare(repositoryFullName) == .orderedSame }
        } else if let repositoryName = query.repositoryName {
            repositories.filter { $0.name.caseInsensitiveCompare(repositoryName) == .orderedSame }
        } else {
            repositories
        }
        guard candidateRepositories.isEmpty == false else {
            return await github.liveReferenceMatch(query: query)
        }

        let cachedMatches = await github.cachedReferenceMatches(
            query: query,
            repositories: candidateRepositories,
            limit: AppLimits.GitHubReferenceMonitor.cacheLookupLimit
        )
        if let match = GitHubReferenceMatch.newestCreated(in: cachedMatches) {
            return match
        }

        let liveMatch = await github.liveReferenceMatch(
            query: query,
            repositories: Array(candidateRepositories.prefix(AppLimits.GitHubReferenceMonitor.liveLookupLimit))
        )
        if let liveMatch {
            return liveMatch
        }

        guard query.repositoryFullName == nil else { return nil }

        return await github.liveReferenceMatch(query: query)
    }

    private func githubReferenceCandidateRepositories() -> [Repository] {
        let sources = [
            self.session.accessibleRepositories,
            self.session.repositories,
            self.session.menuSnapshot?.repositories ?? []
        ]
        let repositories = sources.first(where: { $0.isEmpty == false }) ?? []
        var seen: Set<String> = []
        return repositories.filter { repo in
            guard repo.viewerCanRead else { return false }

            return seen.insert(repo.fullName.lowercased()).inserted
        }
    }

    private func setGitHubReferenceMatch(_ match: GitHubReferenceMatch?) {
        self.setGitHubReferenceMatches(match.map { [$0] } ?? [])
    }

    private func setGitHubReferenceMatches(_ matches: [GitHubReferenceMatch]) {
        let primaryMatch = GitHubReferenceMatch.newestCreated(in: matches)
        guard self.session.gitHubReferenceMatches != matches || self.session.gitHubReferenceMatch != primaryMatch else { return }

        self.session.gitHubReferenceMatches = matches
        self.session.gitHubReferenceMatch = primaryMatch
        NotificationCenter.default.post(name: .gitHubReferenceMatchDidChange, object: nil)
    }
}

private enum IssueNavigatorSearchError: LocalizedError {
    case repositoryInventoryLoading

    var errorDescription: String? {
        switch self {
        case .repositoryInventoryLoading:
            "Repository list is still loading. Try again in a moment."
        }
    }
}
