import Foundation

/// Lightweight GitHub client using REST plus a minimal GraphQL enrichment step.
public actor GitHubClient {
    private static let repositoryHydrationConcurrencyLimit = 8
    private static let activityFetchConcurrencyLimit = 6

    public var apiHost: URL = .init(string: "https://api.github.com")!
    private let tokenStore = TokenStore.shared
    private var tokenProvider: (@Sendable () async throws -> OAuthTokens?)?
    private let graphQL: GraphQLClient
    private let diag = DiagnosticsLogger.shared
    private let requestRunner: GitHubRequestRunner
    private let responseDiskCache: HTTPResponseDiskCache?
    private let archiveSettingsProvider: @Sendable () -> GitHubArchiveSettings
    private lazy var restAPI = GitHubRestAPI(
        apiHost: { [weak self] in await self?.apiHost ?? URL(string: "https://api.github.com")! },
        tokenProvider: { [weak self] in
            guard let self else { throw URLError(.userAuthenticationRequired) }

            return try await self.validAccessToken()
        },
        requestRunner: requestRunner,
        diag: diag,
        responseDiskCache: responseDiskCache
    )
    private lazy var repoDetailCoordinator = RepoDetailCoordinator(
        restAPI: restAPI,
        graphQL: graphQL,
        policy: RepoDetailCachePolicy.default
    )
    private var prefetchedRepos: [Repository] = []
    private var prefetchedReposExpiry: Date?
    private var inflightRepoDetails: [String: Task<Repository, Error>] = [:]

    public init(
        accountID: String? = nil,
        archiveSettingsProvider: @Sendable @escaping () -> GitHubArchiveSettings = {
            SettingsStore().load().githubArchives
        }
    ) {
        self.responseDiskCache = HTTPResponseDiskCache.scoped(accountID: accountID)
        self.requestRunner = GitHubRequestRunner(etagCache: ETagCache.persistent(accountID: accountID))
        self.graphQL = GraphQLClient(responseCache: GraphQLResponseDiskCache.scoped(accountID: accountID))
        self.archiveSettingsProvider = archiveSettingsProvider
    }

    // MARK: - Config

    public func setAPIHost(_ host: URL) {
        do {
            let trusted = try self.trusted(host)
            self.apiHost = trusted
            Task { await self.graphQL.setEndpoint(apiHost: trusted) }
            Task { await self.diag.message("API host set to \(trusted.absoluteString)") }
        } catch {
            Task { await self.diag.message("Rejected API host \(host) (must be https with hostname)") }
        }
    }

    private func trusted(_ host: URL) throws -> URL {
        guard host.scheme?.lowercased() == "https" else { throw GitHubAPIError.invalidHost }
        guard host.host != nil else { throw GitHubAPIError.invalidHost }

        return host
    }

    public func setTokenProvider(_ provider: @Sendable @escaping () async throws -> OAuthTokens?) {
        self.tokenProvider = provider
        // swiftlint:disable:next unhandled_throwing_task
        Task {
            await self.graphQL.setTokenProvider {
                guard let tokens = try await provider() else { throw URLError(.userAuthenticationRequired) }

                return tokens.accessToken
            }
        }
    }

    public func rateLimitReset(now: Date = Date()) async -> Date? {
        await self.requestRunner.rateLimitReset(now: now)
    }

    public func rateLimitMessage(now: Date = Date()) async -> String? {
        await self.requestRunner.rateLimitMessage(now: now)
    }

    public func refreshRateLimitResources() async throws -> RateLimitResourcesSnapshot {
        try await self.restAPI.rateLimitResources()
    }

    // MARK: - High level fetchers

    public func repositoryList(limit: Int?) async throws -> [Repository] {
        let items = try await self.restAPI.userReposPaginated(limit: limit)
        await self.repoDetailCoordinator.updateDiscussionsCapability(
            from: items,
            source: "repositoryList"
        )
        return items.map { Repository.from(item: $0) }
    }

    public func cachedRepositoryList(limit: Int?) async throws -> [Repository] {
        let items = try await self.restAPI.cachedUserReposPaginated(limit: limit)
        return await self.repoDetailCoordinator.cachedRepositories(from: items)
    }

    public func cachedReferenceMatches(
        query: GitHubReferenceQuery,
        repositories: [Repository],
        limit: Int = 20
    ) async -> [GitHubReferenceMatch] {
        await self.restAPI.cachedReferenceMatches(query: query, repositories: repositories, limit: limit)
    }

    public func liveReferenceMatch(
        query: GitHubReferenceQuery,
        repositories: [Repository]
    ) async -> GitHubReferenceMatch? {
        await self.restAPI.liveReferenceMatch(query: query, repositories: repositories)
    }

    public func liveReferenceMatch(query: GitHubReferenceQuery) async -> GitHubReferenceMatch? {
        await self.restAPI.liveReferenceMatch(query: query)
    }

    public func searchIssueReferences(
        matching query: String,
        repositoryFullName: String?,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int
    ) async throws -> [GitHubReferenceMatch] {
        try await self.restAPI.searchIssueReferences(
            matching: query,
            repositoryFullName: repositoryFullName,
            includeIssues: includeIssues,
            includePullRequests: includePullRequests,
            limit: limit
        )
    }

    public func recentIssueReferences(
        filter: String,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int
    ) async throws -> [GitHubReferenceMatch] {
        try await self.restAPI.recentIssueReferences(
            filter: filter,
            includeIssues: includeIssues,
            includePullRequests: includePullRequests,
            limit: limit
        )
    }

    public func defaultRepositories(limit: Int, for _: String) async throws -> [Repository] {
        let repos = try await self.restAPI.userReposSorted(limit: max(limit, 10))
        await self.repoDetailCoordinator.updateDiscussionsCapability(
            from: repos,
            source: "defaultRepositories"
        )
        return try await self.expandRepoItems(Array(repos.prefix(limit)))
    }

    public func activityRepositories(limit: Int?) async throws -> [Repository] {
        let items = try await self.restAPI.userReposPaginated(limit: limit)
        await self.repoDetailCoordinator.updateDiscussionsCapability(
            from: items,
            source: "activityRepositories"
        )
        let activityResults = await self.fetchActivityResults(for: items)
        return items.map { item in
            let fullName = "\(item.owner.login)/\(item.name)"
            let result = activityResults[fullName] ?? ActivityFetchResult(
                pulls: .failure(URLError(.unknown)),
                activity: .failure(URLError(.unknown))
            )
            return self.activityRepository(
                from: item,
                openPullsResult: result.pulls,
                activityResult: result.activity
            )
        }
    }

    public func userActivityEvents(
        username: String,
        scope: GlobalActivityScope,
        limit: Int
    ) async throws -> [ActivityEvent] {
        let events = try await self.restAPI.userEvents(username: username, scope: scope)
        let webHost = self.webHostURL()
        let mapped = events.compactMap { $0.activityEventFromRepo(webHost: webHost) }
        return Array(mapped.prefix(max(limit, 0)))
    }

    public func userCommitEvents(
        username: String,
        scope: GlobalActivityScope,
        limit: Int
    ) async throws -> [RepoCommitSummary] {
        let events = try await self.restAPI.userEvents(username: username, scope: scope)
        let webHost = self.webHostURL()
        let commits = events.flatMap { $0.commitSummaries(webHost: webHost) }
        return Array(commits.prefix(max(limit, 0)))
    }

    /// Latest release (including prereleases). Returns `nil` if the repo has no releases.
    public func latestRelease(owner: String, name: String) async throws -> Release? {
        do {
            return try await self.restAPI.latestReleaseAny(owner: owner, name: name)
        } catch let error as URLError where error.code == .fileDoesNotExist {
            return nil
        }
    }

    private func expandRepoItems(_ items: [RepoItem]) async throws -> [Repository] {
        var out: [Repository] = []
        for batch in items.repoBarBatches(of: Self.repositoryHydrationConcurrencyLimit) {
            let batchRepos = try await withThrowingTaskGroup(of: Repository.self) { group in
                for repo in batch {
                    group.addTask { try await self.fullRepository(owner: repo.owner.login, name: repo.name) }
                }
                var batchOut: [Repository] = []
                for try await repo in group {
                    batchOut.append(repo)
                }
                return batchOut
            }
            out.append(contentsOf: batchRepos)
        }
        return out
    }

    private struct ActivityFetchResult {
        let pulls: Result<Int?, Error>
        let activity: Result<ActivitySnapshot, Error>
    }

    private func fetchActivityResults(for items: [RepoItem]) async -> [String: ActivityFetchResult] {
        var out: [String: ActivityFetchResult] = [:]
        for batch in items.repoBarBatches(of: Self.activityFetchConcurrencyLimit) {
            let batchResults = await withTaskGroup(of: (String, ActivityFetchResult).self) { group in
                for item in batch {
                    group.addTask { [self] in
                        let owner = item.owner.login
                        let name = item.name
                        let fullName = "\(owner)/\(name)"
                        async let openPullsResult: Result<Int?, Error> = self.capture {
                            try await self.restAPI.openPullRequestCount(owner: owner, name: name)
                        }
                        async let activityResult: Result<ActivitySnapshot, Error> = self.capture {
                            try await self.restAPI.recentActivity(owner: owner, name: name, limit: 25)
                        }
                        let result = await ActivityFetchResult(
                            pulls: openPullsResult,
                            activity: activityResult
                        )
                        return (fullName, result)
                    }
                }
                var batchOut: [String: ActivityFetchResult] = [:]
                for await (fullName, result) in group {
                    batchOut[fullName] = result
                }
                return batchOut
            }
            out.merge(batchResults) { _, new in new }
        }
        return out
    }

    public func fullRepository(
        owner: String,
        name: String,
        options: RepositoryDetailOptions = .default
    ) async throws -> Repository {
        let key = "\(owner.lowercased())/\(name.lowercased())#heatmap:\(options.fetchHeatmap)"
        if let task = self.inflightRepoDetails[key] {
            return try await task.value
        }
        let task = Task { [weak self] () throws -> Repository in
            guard let self else { throw CancellationError() }

            return try await self.fullRepositoryInternal(owner: owner, name: name, options: options)
        }
        self.inflightRepoDetails[key] = task
        defer { self.inflightRepoDetails[key] = nil }
        return try await task.value
    }

    private func fullRepositoryInternal(
        owner: String,
        name: String,
        options: RepositoryDetailOptions
    ) async throws -> Repository {
        try await self.repoDetailCoordinator.fullRepository(owner: owner, name: name, options: options)
    }

    private func activityRepository(
        from item: RepoItem,
        openPullsResult: Result<Int?, Error>,
        activityResult: Result<ActivitySnapshot, Error>
    ) -> Repository {
        var accumulator = RepoErrorAccumulator()
        let openPulls: Int
        switch openPullsResult {
        case let .success(value):
            openPulls = value ?? 0
        case let .failure(error):
            accumulator.absorb(error)
            openPulls = 0
        }
        let issues = max(item.openIssuesCount - openPulls, 0)
        let snapshot = self.value(from: activityResult, into: &accumulator)
        let activity: ActivityEvent? = snapshot?.latest ?? snapshot?.events.first
        let activityEvents = snapshot?.events ?? []

        return Repository.from(
            item: item,
            openPulls: openPulls,
            issues: issues,
            latestActivity: activity,
            activityEvents: activityEvents,
            error: accumulator.message,
            rateLimitedUntil: accumulator.rateLimit
        )
    }

    public func currentUser() async throws -> UserIdentity {
        let user = try await self.restAPI.fetchCurrentUser()
        return UserIdentity(username: user.login, host: self.webHostURL(), planName: user.plan?.name)
    }

    public func userOrganizations() async throws -> [String] {
        try await self.restAPI.fetchUserOrganizations()
    }

    public func organizationPlan(org: String) async throws -> String? {
        try await self.restAPI.fetchOrganizationPlan(org: org)
    }

    public func searchRepositories(matching query: String) async throws -> [Repository] {
        let items = try await self.restAPI.searchRepositories(matching: query)
        await self.repoDetailCoordinator.updateDiscussionsCapability(
            from: items,
            source: "searchRepositories"
        )
        return items.map { Repository.from(item: $0) }
    }

    // MARK: - Actions & Runners

    public func selfHostedRunners(owner: String, repo: String? = nil) async throws -> ActionsRunnerInfo {
        try await self.restAPI.selfHostedRunners(owner: owner, repo: repo)
    }

    public func actionsQueueStatus(owner: String, name: String) async throws -> ActionsQueueStatus {
        try await self.restAPI.actionsQueueStatus(owner: owner, name: name)
    }

    public func actionsBillingUsage(owner: String, isOrg: Bool) async throws -> ActionsUsageInfo {
        try await self.restAPI.actionsBillingUsage(owner: owner, isOrg: isOrg)
    }

    public func hostedRunnerLimits(org: String) async throws -> HostedRunnerLimits {
        try await self.restAPI.hostedRunnerLimits(org: org)
    }

    public func actionsCacheUsage(org: String) async throws -> ActionsCacheUsage {
        try await self.restAPI.actionsCacheUsage(org: org)
    }

    public func artifactRetentionPolicy(org: String) async throws -> ArtifactRetentionPolicy {
        try await self.restAPI.artifactRetentionPolicy(org: org)
    }

    public func clearCache() async {
        await self.requestRunner.clear()
        self.prefetchedRepos = []
        self.prefetchedReposExpiry = nil
        await self.clearRepoDetailCache()
    }

    public func clearRepoDetailCache() async {
        await self.diag.message("Clearing repo detail cache (disk + memory)")
        await self.repoDetailCoordinator.clearCache()
    }

    public func diagnostics() async -> DiagnosticsSummary {
        let requestDiagnostics = await self.requestRunner.diagnosticsSnapshot()
        let graphQLRateLimit: RateLimitSnapshot? = if let graphQL = requestDiagnostics.rateLimitResources?["graphql"] {
            graphQL
        } else {
            await self.graphQL.rateLimitSnapshot()
        }
        return DiagnosticsSummary(
            apiHost: self.apiHost,
            rateLimitReset: requestDiagnostics.rateLimitReset,
            lastRateLimitError: requestDiagnostics.lastRateLimitError,
            etagEntries: requestDiagnostics.etagEntries,
            backoffEntries: requestDiagnostics.backoffEntries,
            endpointCooldowns: requestDiagnostics.endpointCooldowns,
            restRateLimit: requestDiagnostics.restRateLimit,
            graphQLRateLimit: graphQLRateLimit,
            rateLimitResources: requestDiagnostics.rateLimitResources
        )
    }

    private func webHostURL() -> URL {
        var components = URLComponents()
        components.scheme = self.apiHost.scheme ?? "https"
        let rawHost = self.apiHost.host ?? "github.com"
        components.host = rawHost == "api.github.com" ? "github.com" : rawHost
        return components.url ?? URL(string: "https://github.com")!
    }

    /// Recent repositories for the authenticated user, sorted by activity.
    public func recentRepositories(limit: Int = 8) async throws -> [Repository] {
        let items = try await self.restAPI.userReposSorted(limit: limit)
        await self.repoDetailCoordinator.updateDiscussionsCapability(
            from: items,
            source: "recentRepositories"
        )
        return items.map { Repository.from(item: $0) }
    }

    /// Contribution heatmap for a user (year view), used to render the header without fetching remote images.
    public func userContributionHeatmap(login: String) async throws -> [HeatmapCell] {
        try await self.graphQL.userContributionHeatmap(login: login)
    }

    /// Prefetch up to `RepoCacheConstants.maxRepositoriesToPrefetch` repos once per hour for fast autocomplete.
    public func prefetchedRepositories(
        max: Int = RepoCacheConstants.maxRepositoriesToPrefetch
    ) async throws -> [Repository] {
        let now = Date()
        if let expires = self.prefetchedReposExpiry, expires > now, !self.prefetchedRepos.isEmpty {
            return Array(self.prefetchedRepos.prefix(max))
        }

        let items = try await self.restAPI.userReposPaginated(limit: max)
        await self.repoDetailCoordinator.updateDiscussionsCapability(
            from: items,
            source: "prefetchedRepositories"
        )
        let repos = items.map { Repository.from(item: $0) }
        self.prefetchedRepos = repos
        self.prefetchedReposExpiry = now.addingTimeInterval(RepoCacheConstants.cacheTTL)
        return repos
    }

    public func recentPullRequests(
        owner: String,
        name: String,
        limit: Int = 20,
        state: GitHubPullRequestListState = .open,
        includeCommentCounts: Bool = false
    ) async throws -> [RepoPullRequestSummary] {
        do {
            return try await self.restAPI.recentPullRequests(
                owner: owner,
                name: name,
                limit: limit,
                state: state,
                includeCommentCounts: includeCommentCounts
            )
        } catch {
            if let fallback = self.archivePullRequestFallback(owner: owner, name: name, limit: limit, error: error), fallback.isEmpty == false {
                await self.diag.message("Using archive PR fallback for \(owner)/\(name) after \(error.userFacingMessage)")
                return fallback
            }
            throw error
        }
    }

    public func recentIssues(owner: String, name: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        do {
            return try await self.restAPI.recentIssues(owner: owner, name: name, limit: limit)
        } catch {
            if let fallback = self.archiveIssueFallback(owner: owner, name: name, limit: limit, error: error), fallback.isEmpty == false {
                await self.diag.message("Using archive issue fallback for \(owner)/\(name) after \(error.userFacingMessage)")
                return fallback
            }
            throw error
        }
    }

    public func recentReleases(owner: String, name: String, limit: Int = 20) async throws -> [RepoReleaseSummary] {
        try await self.restAPI.recentReleases(owner: owner, name: name, limit: limit)
    }

    public func recentWorkflowRuns(owner: String, name: String, limit: Int = 20) async throws -> [RepoWorkflowRunSummary] {
        try await self.restAPI.recentWorkflowRuns(owner: owner, name: name, limit: limit)
    }

    public func recentCommits(owner: String, name: String, limit: Int = 20) async throws -> RepoCommitList {
        try await self.restAPI.recentCommits(owner: owner, name: name, limit: limit)
    }

    public func recentDiscussions(owner: String, name: String, limit: Int = 20) async throws -> [RepoDiscussionSummary] {
        let now = Date()
        let cachedEnabled = await self.repoDetailCoordinator.cachedDiscussionsEnabled(
            owner: owner,
            name: name,
            now: now
        )
        if cachedEnabled == false {
            await self.diag.message("Discussions disabled (cached) for \(owner)/\(name)")
            return []
        }

        do {
            let discussions = try await self.restAPI.recentDiscussions(owner: owner, name: name, limit: limit)
            await self.repoDetailCoordinator.updateDiscussionsCapability(
                owner: owner,
                name: name,
                enabled: true,
                checkedAt: now,
                source: "recentDiscussions"
            )
            return discussions
        } catch let error as GitHubAPIError {
            if case let .badStatus(code, _) = error, code == 404 || code == 410 {
                await self.repoDetailCoordinator.updateDiscussionsCapability(
                    owner: owner,
                    name: name,
                    enabled: false,
                    checkedAt: now,
                    source: "recentDiscussions"
                )
                await self.diag.message("Discussions disabled for \(owner)/\(name) (HTTP \(code))")
                return []
            }
            throw error
        }
    }

    public func recentTags(owner: String, name: String, limit: Int = 20) async throws -> [RepoTagSummary] {
        try await self.restAPI.recentTags(owner: owner, name: name, limit: limit)
    }

    public func recentBranches(owner: String, name: String, limit: Int = 20) async throws -> [RepoBranchSummary] {
        try await self.restAPI.recentBranches(owner: owner, name: name, limit: limit)
    }

    public func repoContents(owner: String, name: String, path: String? = nil) async throws -> [RepoContentItem] {
        try await self.restAPI.repoContents(owner: owner, name: name, path: path)
    }

    public func repoFileContents(owner: String, name: String, path: String) async throws -> Data {
        try await self.restAPI.repoFileContents(owner: owner, name: name, path: path)
    }

    public func topContributors(owner: String, name: String, limit: Int = 20) async throws -> [RepoContributorSummary] {
        try await self.restAPI.topContributors(owner: owner, name: name, limit: limit)
    }

    // MARK: - Internal helpers

    private func validAccessToken() async throws -> String {
        if let provider = tokenProvider {
            guard let tokens = try await provider() else { throw URLError(.userAuthenticationRequired) }

            return tokens.accessToken
        }
        if let token = try tokenStore.load()?.accessToken { return token }
        throw URLError(.userAuthenticationRequired)
    }

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }

    private func value<T>(from result: Result<T, Error>, into accumulator: inout RepoErrorAccumulator) -> T? {
        switch result {
        case let .success(value): return value
        case let .failure(error):
            accumulator.absorb(error)
            return nil
        }
    }

    private func archiveIssueFallback(owner: String, name: String, limit: Int, error: Error) -> [RepoIssueSummary]? {
        guard self.shouldUseArchiveFallback(for: error) else { return nil }

        let archiveSettings = self.archiveSettingsProvider()
        guard archiveSettings.preferArchiveWhenRateLimited else { return nil }

        return GitHubArchiveReader.recentIssues(settings: archiveSettings, owner: owner, name: name, limit: limit)
    }

    private func archivePullRequestFallback(owner: String, name: String, limit: Int, error: Error) -> [RepoPullRequestSummary]? {
        guard self.shouldUseArchiveFallback(for: error) else { return nil }

        let archiveSettings = self.archiveSettingsProvider()
        guard archiveSettings.preferArchiveWhenRateLimited else { return nil }

        return GitHubArchiveReader.recentPullRequests(settings: archiveSettings, owner: owner, name: name, limit: limit)
    }

    private func shouldUseArchiveFallback(for error: Error) -> Bool {
        if let gh = error as? GitHubAPIError {
            switch gh {
            case .rateLimited, .serviceUnavailable:
                return true
            case let .badStatus(code, _):
                return code == 429 || code == 502 || code == 503 || code == 504
            case .invalidHost, .invalidPEM:
                return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }
        return false
    }
}

public struct DiagnosticsSummary: Sendable {
    public let apiHost: URL
    public let rateLimitReset: Date?
    public let lastRateLimitError: String?
    public let etagEntries: Int
    public let backoffEntries: Int
    public let endpointCooldowns: [EndpointCooldownSummary]
    public let restRateLimit: RateLimitSnapshot?
    public let graphQLRateLimit: RateLimitSnapshot?
    public let rateLimitResources: RateLimitResourcesSnapshot?

    public init(
        apiHost: URL,
        rateLimitReset: Date?,
        lastRateLimitError: String?,
        etagEntries: Int,
        backoffEntries: Int,
        endpointCooldowns: [EndpointCooldownSummary] = [],
        restRateLimit: RateLimitSnapshot?,
        graphQLRateLimit: RateLimitSnapshot?,
        rateLimitResources: RateLimitResourcesSnapshot?
    ) {
        self.apiHost = apiHost
        self.rateLimitReset = rateLimitReset
        self.lastRateLimitError = lastRateLimitError
        self.etagEntries = etagEntries
        self.backoffEntries = backoffEntries
        self.endpointCooldowns = endpointCooldowns
        self.restRateLimit = restRateLimit
        self.graphQLRateLimit = graphQLRateLimit
        self.rateLimitResources = rateLimitResources
    }

    public static let empty = DiagnosticsSummary(
        apiHost: URL(string: "https://api.github.com")!,
        rateLimitReset: nil,
        lastRateLimitError: nil,
        etagEntries: 0,
        backoffEntries: 0,
        endpointCooldowns: [],
        restRateLimit: nil,
        graphQLRateLimit: nil,
        rateLimitResources: nil
    )
}

public struct EndpointCooldownSummary: Codable, Equatable, Hashable, Sendable {
    public let endpoint: String
    public let repository: String?
    public let url: String
    public let retryAfter: Date

    public init(
        endpoint: String,
        repository: String?,
        url: String,
        retryAfter: Date
    ) {
        self.endpoint = endpoint
        self.repository = repository
        self.url = url
        self.retryAfter = retryAfter
    }
}
