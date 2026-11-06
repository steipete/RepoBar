import Foundation
import Observation
import RepoBarCore

@MainActor
@Observable
final class AppModel {
    var session = AppSession()
    let github = GitHubClient()
    let auth = OAuthCoordinator()
    let refreshScheduler = RefreshScheduler()
    let settingsStore = SettingsStore()
    private var refreshTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    private let tokenRefreshInterval: TimeInterval = 300
    private let hydrateConcurrencyLimit = 4

    let defaultClientID = RepoBarAuthDefaults.clientID
    let defaultClientSecret = RepoBarAuthDefaults.clientSecret
    let defaultGitHubHost = RepoBarAuthDefaults.githubHost
    let defaultAPIHost = RepoBarAuthDefaults.apiHost

    init() {
        self.session.settings = self.settingsStore.load()
        RepoBarLogging.bootstrapIfNeeded()
        RepoBarLogging.configure(
            verbosity: self.session.settings.loggingVerbosity,
            fileLoggingEnabled: self.session.settings.fileLoggingEnabled
        )
        Task {
            await self.github.setTokenProvider { @Sendable [weak self] () async throws -> OAuthTokens? in
                try? await self?.auth.refreshIfNeeded()
            }
        }
        Task { await DiagnosticsLogger.shared.setEnabled(self.session.settings.diagnosticsEnabled) }
        self.refreshScheduler.configure(interval: self.session.settings.refreshInterval.seconds) { [weak self] in
            self?.requestRefresh()
        }
        Task { [weak self] in
            await self?.applyHostSettings()
            await self?.bootstrapIfNeeded()
        }
        self.tokenRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if self.auth.loadTokens() != nil {
                    _ = try? await self.auth.refreshIfNeeded()
                }
                try? await Task.sleep(for: .seconds(self.tokenRefreshInterval))
            }
        }
    }

    func persistSettings() {
        self.settingsStore.save(self.session.settings)
    }

    func applyHostSettings() async {
        if let enterprise = self.session.settings.enterpriseHost {
            await self.github.setAPIHost(enterprise.appending(path: "/api/v3"))
            self.session.settings.githubHost = enterprise
        } else {
            await self.github.setAPIHost(self.defaultAPIHost)
            self.session.settings.githubHost = self.defaultGitHubHost
        }
        self.persistSettings()
    }

    func updateHeatmapRange(now: Date = Date()) {
        self.session.heatmapRange = HeatmapFilter.range(
            span: self.session.settings.heatmap.span,
            now: now,
            alignToWeek: true
        )
    }

    func bootstrapIfNeeded() async {
        guard self.auth.loadTokens() != nil else { return }
        self.session.account = .loggingIn
        if let user = try? await self.github.currentUser() {
            self.session.account = .loggedIn(user)
            self.session.lastError = nil
            await self.refresh()
        } else {
            self.session.account = .loggedIn(UserIdentity(username: "", host: self.session.settings.githubHost))
        }
    }

    func login() async {
        self.session.account = .loggingIn
        do {
            try await self.auth.login(
                clientID: self.defaultClientID,
                clientSecret: self.defaultClientSecret,
                host: self.session.settings.githubHost,
                devicePrompt: { code, url in
                    self.session.lastError = "Enter \(code) at \(url.absoluteString)"
                }
            )
            if let user = try? await self.github.currentUser() {
                self.session.account = .loggedIn(user)
                self.session.lastError = nil
            } else {
                self.session.account = .loggedIn(UserIdentity(username: "", host: self.session.settings.githubHost))
            }
            await self.refresh()
        } catch {
            self.session.account = .loggedOut
            self.session.lastError = error.userFacingMessage
        }
    }

    func logout() async {
        await self.auth.logout()
        self.session.account = .loggedOut
        self.session.repositories = []
        self.session.globalActivityEvents = []
        self.session.globalCommitEvents = []
        self.session.contributionHeatmap = []
        self.session.referenceDraftText = ""
        self.session.referenceMatches = []
        self.session.referenceError = nil
        self.session.isResolvingReferences = false
        self.session.lastError = nil
    }

    func requestRefresh(cancelInFlight: Bool = false) {
        if cancelInFlight {
            self.refreshTask?.cancel()
        }
        guard cancelInFlight || self.refreshTask == nil else { return }
        self.refreshTask = Task { [weak self] in
            await self?.refresh()
            await MainActor.run { [weak self] in self?.refreshTask = nil }
        }
    }

    func refresh() async {
        guard self.auth.loadTokens() != nil else {
            self.session.isRefreshing = false
            self.session.repositories = []
            self.session.globalActivityEvents = []
            self.session.globalCommitEvents = []
            self.session.contributionHeatmap = []
            self.session.referenceDraftText = ""
            self.session.referenceMatches = []
            self.session.referenceError = nil
            self.session.isResolvingReferences = false
            self.session.diagnostics = .empty
            self.session.rateLimitError = nil
            self.session.lastError = nil
            return
        }

        self.session.isRefreshing = true
        let now = Date()
        self.updateHeatmapRange(now: now)

        do {
            if case .loggedOut = self.session.account {
                if let user = try? await self.github.currentUser() {
                    self.session.account = .loggedIn(user)
                }
            }

            let repos = try await self.github.repositoryList(limit: nil)
            let pinned = await self.fetchMissingPinned(from: repos)
            let merged = self.mergeUnique(repos + pinned)
            let visible = RepositoryPipeline.apply(merged, query: self.repoQuery(now: now))
            let hydrated = await self.hydrate(repos: visible)
            self.session.repositories = hydrated
            self.session.lastError = nil

            let activityUsername: String? = {
                guard case let .loggedIn(user) = self.session.account,
                      user.username.isEmpty == false else { return nil }
                return user.username
            }()

            async let contributionsTask: (items: [HeatmapCell], error: String?) = self.loadContributions()
            async let globalActivityTask: GlobalActivityResult = self.loadGlobalActivity(
                username: activityUsername,
                repos: hydrated
            )

            let contributions = await contributionsTask
            self.session.contributionHeatmap = contributions.items
            self.session.contributionError = contributions.error

            let globalActivity = await globalActivityTask
            self.session.globalActivityEvents = globalActivity.events
            self.session.globalActivityError = globalActivity.error
            self.session.globalCommitEvents = globalActivity.commits
            self.session.globalCommitError = globalActivity.commitError
            await self.refreshRateLimits()

            if let message = await self.github.rateLimitMessage(now: now) {
                self.session.lastError = message
            }
        } catch {
            self.session.lastError = error.userFacingMessage
        }

        self.session.isRefreshing = false
    }

    func refreshRateLimits() async {
        guard self.auth.loadTokens() != nil else {
            self.session.diagnostics = .empty
            self.session.rateLimitError = nil
            return
        }

        do {
            _ = try await self.github.refreshRateLimitResources()
            self.session.rateLimitError = nil
        } catch {
            self.session.rateLimitError = error.userFacingMessage
        }
        self.session.diagnostics = await self.github.diagnostics()
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard let text = IncomingReferenceURL.text(from: url) else { return false }

        self.session.referenceDraftText = text
        self.session.referenceError = nil
        if self.auth.loadTokens() != nil {
            Task { await self.resolveReferences(from: text) }
        }
        return true
    }

    func resolveReferences(from text: String) async {
        let queries = GitHubReferenceTranslator.queries(from: text)
        guard queries.isEmpty == false else {
            self.session.referenceMatches = []
            self.session.referenceError = "No GitHub references found."
            return
        }

        self.session.isResolvingReferences = true
        self.session.referenceError = nil
        let repositories = self.session.repositories
        let github = self.github
        let results = await withTaskGroup(of: (Int, GitHubReferenceMatch?).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    let match = await Self.resolveReferenceMatch(
                        query: query,
                        github: github,
                        repositories: repositories
                    )
                    return (index, match)
                }
            }

            var matchesByIndex: [Int: GitHubReferenceMatch] = [:]
            for await (index, match) in group {
                if let match {
                    matchesByIndex[index] = match
                }
            }
            return queries.indices.compactMap { matchesByIndex[$0] }
        }

        var seenURLs: Set<URL> = []
        self.session.referenceMatches = results.filter { seenURLs.insert($0.url).inserted }
        self.session.referenceError = self.session.referenceMatches.isEmpty
            ? "No visible matches for \(queries.map(\.displayText).joined(separator: ", "))."
            : nil
        self.session.isResolvingReferences = false
    }

    func addPinned(_ fullName: String) async {
        guard !self.session.settings.repoList.pinnedRepositories.contains(fullName) else { return }
        self.session.settings.repoList.pinnedRepositories.append(fullName)
        self.persistSettings()
        await self.refresh()
    }

    func removePinned(_ fullName: String) async {
        self.session.settings.repoList.pinnedRepositories.removeAll { $0 == fullName }
        self.persistSettings()
        await self.refresh()
    }

    func hide(_ fullName: String) async {
        guard !self.session.settings.repoList.hiddenRepositories.contains(fullName) else { return }
        self.session.settings.repoList.hiddenRepositories.append(fullName)
        self.session.settings.repoList.pinnedRepositories.removeAll { $0 == fullName }
        self.persistSettings()
        await self.refresh()
    }

    func unhide(_ fullName: String) async {
        self.session.settings.repoList.hiddenRepositories.removeAll { $0 == fullName }
        self.persistSettings()
        await self.refresh()
    }

    func searchRepositories(query: String) async throws -> [Repository] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try await self.github.recentRepositories(limit: AppLimits.Autocomplete.addRepoRecentLimit)
        }
        return try await self.github.searchRepositories(matching: trimmed)
    }

    private func repoQuery(now: Date) -> RepositoryQuery {
        let settings = self.session.settings
        let repositoryFilter = self.session.repositoryFilter
        let ageCutoff = RepositoryQueryDefaults.ageCutoff(
            now: now,
            scope: repositoryFilter.scope,
            ageDays: RepositoryQueryDefaults.defaultAgeDays
        )
        return RepositoryQuery(
            scope: repositoryFilter.scope,
            onlyWith: repositoryFilter.onlyWith,
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            sortKey: settings.repoList.menuSortKey,
            limit: settings.repoList.displayLimit,
            ageCutoff: ageCutoff,
            pinned: settings.repoList.pinnedRepositories,
            hidden: Set(settings.repoList.hiddenRepositories),
            pinPriority: true,
            ownerFilter: settings.repoList.ownerFilter
        )
    }

    private nonisolated static func resolveReferenceMatch(
        query: GitHubReferenceQuery,
        github: GitHubClient,
        repositories: [Repository]
    ) async -> GitHubReferenceMatch? {
        let cachedMatches = await github.cachedReferenceMatches(
            query: query,
            repositories: repositories,
            limit: query.repositoryFullName == nil ? 20 : 5
        )
        if let match = GitHubReferenceMatch.newestCreated(in: cachedMatches) {
            return match
        }

        if query.repositoryFullName != nil {
            return await github.liveReferenceMatch(query: query)
        }
        if repositories.isEmpty == false,
           let match = await github.liveReferenceMatch(query: query, repositories: repositories) {
            return match
        }
        return await github.liveReferenceMatch(query: query)
    }

    private func fetchMissingPinned(from repos: [Repository]) async -> [Repository] {
        let pinned = self.session.settings.repoList.pinnedRepositories
        guard pinned.isEmpty == false else { return [] }
        let existing = Set(repos.map(\.fullName))
        let missing = pinned.filter { !existing.contains($0) }
        guard missing.isEmpty == false else { return [] }

        return await withTaskGroup(of: Repository?.self) { group in
            for fullName in missing {
                let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                group.addTask { [github] in
                    try? await github.fullRepository(owner: parts[0], name: parts[1])
                }
            }
            var out: [Repository] = []
            for await repo in group {
                if let repo { out.append(repo) }
            }
            return out
        }
    }

    private func hydrate(repos: [Repository]) async -> [Repository] {
        guard repos.isEmpty == false else { return [] }
        let limit = max(1, min(self.hydrateConcurrencyLimit, repos.count))
        var detailed: [Repository] = []
        for batch in repos.repoBarBatches(of: limit) {
            let batchResult = await withTaskGroup(of: Repository?.self) { group in
                for repo in batch {
                    group.addTask { [github] in
                        try? await github.fullRepository(owner: repo.owner, name: repo.name)
                    }
                }
                var output: [Repository] = []
                for await repo in group {
                    if let repo { output.append(repo) }
                }
                return output
            }
            detailed.append(contentsOf: batchResult)
        }
        return self.mergeHydrated(detailed, into: repos)
    }

    private func mergeHydrated(_ detailed: [Repository], into repos: [Repository]) -> [Repository] {
        let lookup = Dictionary(uniqueKeysWithValues: detailed.map { ($0.fullName, $0) })
        return repos.map { lookup[$0.fullName] ?? $0 }
    }

    private func mergeUnique(_ repos: [Repository]) -> [Repository] {
        var seen: Set<String> = []
        var out: [Repository] = []
        for repo in repos {
            guard seen.insert(repo.fullName).inserted else { continue }
            out.append(repo)
        }
        return out
    }

    private func loadContributions() async -> (items: [HeatmapCell], error: String?) {
        guard self.session.settings.appearance.showContributionHeader else { return ([], nil) }
        guard case let .loggedIn(user) = self.session.account else { return ([], nil) }
        do {
            let heatmap = try await self.github.userContributionHeatmap(login: user.username)
            return (heatmap, nil)
        } catch {
            return ([], error.userFacingMessage)
        }
    }

    private struct GlobalActivityResult {
        let events: [ActivityEvent]
        let commits: [RepoCommitSummary]
        let error: String?
        let commitError: String?
    }

    private func loadGlobalActivity(username: String?, repos: [Repository]) async -> GlobalActivityResult {
        guard let username else {
            return GlobalActivityResult(events: [], commits: [], error: nil, commitError: nil)
        }
        let repoEvents = repos.flatMap(\.activityEvents)
        let activityScope = self.session.settings.appearance.activityScope
        let github = self.github
        async let activityResult: Result<[ActivityEvent], Error> = self.capture { [github] in
            try await github.userActivityEvents(
                username: username,
                scope: activityScope,
                limit: AppLimits.GlobalActivity.limit
            )
        }
        async let commitResult: Result<[RepoCommitSummary], Error> = self.capture { [github] in
            try await github.userCommitEvents(
                username: username,
                scope: activityScope,
                limit: AppLimits.GlobalCommits.limit
            )
        }

        let activityEvents: [ActivityEvent]
        let activityError: String?
        switch await activityResult {
        case let .success(events):
            activityEvents = events
            activityError = nil
        case let .failure(error):
            activityEvents = []
            activityError = error.userFacingMessage
        }

        let commitEvents: [RepoCommitSummary]
        let commitError: String?
        switch await commitResult {
        case let .success(commits):
            commitEvents = commits
            commitError = nil
        case let .failure(error):
            commitEvents = []
            commitError = error.userFacingMessage
        }

        let merged = self.mergeGlobalActivityEvents(
            userEvents: activityEvents,
            repoEvents: repoEvents,
            username: username,
            scope: activityScope,
            limit: AppLimits.GlobalActivity.limit
        )

        return GlobalActivityResult(
            events: merged,
            commits: commitEvents,
            error: activityError,
            commitError: commitError
        )
    }

    private func mergeGlobalActivityEvents(
        userEvents: [ActivityEvent],
        repoEvents: [ActivityEvent],
        username: String,
        scope: GlobalActivityScope,
        limit: Int
    ) -> [ActivityEvent] {
        let combined = userEvents + repoEvents
        let filtered = scope == .myActivity
            ? combined.filter { $0.actor.caseInsensitiveCompare(username) == .orderedSame }
            : combined
        let sorted = filtered.sorted { $0.date > $1.date }
        var seen: Set<String> = []
        var results: [ActivityEvent] = []
        results.reserveCapacity(limit)
        for event in sorted {
            let key = "\(event.url.absoluteString)|\(event.date.timeIntervalSinceReferenceDate)|\(event.actor)"
            guard seen.insert(key).inserted else { continue }
            results.append(event)
            if results.count >= limit { break }
        }
        return results
    }

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }
}
