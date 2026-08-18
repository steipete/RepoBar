import Foundation
import RepoBarCore

extension AppState {
    func refreshIfNeededForMenu() {
        let now = Date()
        if let lastRequest = self.lastMenuRefreshRequest, now.timeIntervalSince(lastRequest) < self.menuRefreshDebounceInterval {
            return
        }
        let hasFreshSnapshot = self.session.menuSnapshot.map {
            $0.isStale(now: now, interval: self.menuRefreshInterval) == false
        } ?? false
        if hasFreshSnapshot {
            return
        }
        if self.refreshTask != nil || self.menuRefreshTask != nil {
            return
        }
        self.lastMenuRefreshRequest = now
        self.menuRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await MainActor.run {
                guard let self else { return }

                self.menuRefreshTask = nil
                self.requestRefresh(cancelInFlight: false)
            }
        }
    }

    func requestRefresh(cancelInFlight: Bool = false) {
        if cancelInFlight {
            self.refreshTask?.cancel()
            self.prefetchTask?.cancel()
        }
        guard cancelInFlight || self.refreshTask == nil else { return }

        let token = UUID()
        self.refreshTaskToken = token
        self.refreshTask = Task { [weak self] in
            await self?.refresh()
            await MainActor.run {
                guard let self, self.refreshTaskToken == token else { return }

                self.refreshTask = nil
            }
        }
    }

    func refresh() async {
        let localSettings = self.session.settings.localProjects
        self.session.localProjectsScanInProgress = (localSettings.rootPath?.isEmpty == false)
        do {
            if Task.isCancelled {
                return
            }
            let now = Date()
            self.updateHeatmapRange(now: now)
            if await self.hasAuthenticationMaterial() == false {
                let localSnapshot = await self.snapshotForLoggedOutState(localSettings: localSettings)
                await self.applyLoggedOutState(localSnapshot: localSnapshot, lastError: nil)
                return
            }
            let accountRefresh = await self.refreshAccountRepositorySnapshots(now: now)
            guard accountRefresh.published else { return }

            if let failure = accountRefresh.activeFailure, self.session.settings.consolidateAccounts == false {
                if failure.authenticationFailure {
                    await self.handleAuthenticationFailure(failure)
                    return
                }
                throw failure
            }
            guard let activeAccountSession = accountRefresh.activeSession else {
                let localSnapshot = await self.snapshotForLoggedOutState(localSettings: localSettings)
                await MainActor.run {
                    self.session.localRepoIndex = localSnapshot.repoIndex
                    self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
                    self.session.localProjectsAccessDenied = localSnapshot.accessDenied
                    self.session.localProjectsScanInProgress = false
                }
                return
            }

            // If we have tokens but no user in session, fetch identity once per launch.
            if case .loggedOut = self.session.account {
                if let user = try? await self.github.currentUser() {
                    await MainActor.run { self.session.account = .loggedIn(user) }
                }
            }
            if accountRefresh.activeFailure == nil {
                await self.processGitHubPullRequestNotifications()
                await self.processGitHubReleaseNotifications()
            }
            let repos = activeAccountSession.accessibleRepositories
            try Task.checkCancellation()
            let ordered = activeAccountSession.repositories
            // The lightweight repository list uses GitHub's open_issues_count, which includes PRs.
            // Only publish the menu snapshot after hydrating real issue/PR counts.
            let matchNames = self.localMatchRepoNamesForLocalProjects(repos: ordered, includePinned: true)
            let localSnapshotTask = Task {
                await self.localRepoManager.snapshot(
                    rootPath: localSettings.rootPath,
                    rootBookmarkData: localSettings.rootBookmarkData,
                    options: LocalRepoManager.SnapshotOptions(
                        autoSyncEnabled: localSettings.autoSyncEnabled,
                        fetchInterval: localSettings.fetchInterval.seconds,
                        preferredPathsByFullName: localSettings.preferredLocalPathsByFullName,
                        matchRepoNames: matchNames,
                        forceRescan: false,
                        maxDepth: localSettings.maxDepth
                    )
                )
            }
            let targets = self.selectMenuTargets(from: ordered)
            let hydrated = await self.hydrateMenuTargets(targets, fetchHeatmap: true)
            try Task.checkCancellation()
            let hydratedAccessible = self.mergeHydrated(hydrated, into: repos)
            let merged = self.mergeHydrated(hydrated, into: ordered)
            let activePinned = self.session.settings.pinnedRepositories(for: activeAccountSession.id)
            let final = Self.applyPinnedOrder(to: merged, pinned: activePinned)
            guard self.publishHydratedActiveRepositorySnapshot(
                accessibleRepositories: hydratedAccessible,
                repositories: final,
                accountID: activeAccountSession.id,
                generation: accountRefresh.generation,
                now: now
            ) else { return }

            let localSnapshot = await localSnapshotTask.value
            let activityUsername: String? = {
                guard case let .loggedIn(user) = self.session.account,
                      user.username.isEmpty == false else { return nil }

                return user.username
            }()
            let globalActivityTask = Task { [weak self] in
                guard let self, let activityUsername else {
                    return GlobalActivityResult(events: [], commits: [], error: nil, commitError: nil)
                }

                return await self.fetchGlobalActivityEvents(
                    username: activityUsername,
                    scope: self.session.settings.appearance.activityScope,
                    repos: final
                )
            }
            let globalActivity = await globalActivityTask.value
            try self.checkAccountRepositoryRefreshIsCurrent(
                generation: accountRefresh.generation,
                accountID: activeAccountSession.id
            )
            await MainActor.run {
                self.session.localRepoIndex = localSnapshot.repoIndex
                self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
                self.session.localProjectsAccessDenied = localSnapshot.accessDenied
                self.session.localProjectsScanInProgress = false
                self.session.globalActivityEvents = globalActivity.events
                self.session.globalActivityError = globalActivity.error
                self.session.globalCommitEvents = globalActivity.commits
                self.session.globalCommitError = globalActivity.commitError
                NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
            }
            await self.updateMenuDisplayIndex(now: now)
            try self.checkAccountRepositoryRefreshIsCurrent(
                generation: accountRefresh.generation,
                accountID: activeAccountSession.id
            )
            self.prefetchMenuTargets(from: final, visibleCount: targets.count, token: self.refreshTaskToken)
            await self.refreshRateLimitDisplayState()
            try self.checkAccountRepositoryRefreshIsCurrent(
                generation: accountRefresh.generation,
                accountID: activeAccountSession.id
            )
            await self.refreshActionsLimitsState()
            try self.checkAccountRepositoryRefreshIsCurrent(
                generation: accountRefresh.generation,
                accountID: activeAccountSession.id
            )
            let message = await self.github.rateLimitMessage(now: now)
            try self.checkAccountRepositoryRefreshIsCurrent(
                generation: accountRefresh.generation,
                accountID: activeAccountSession.id
            )
            await MainActor.run {
                self.session.lastError = message ?? accountRefresh.activeFailure?.message
                NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
            }
        } catch {
            if error is CancellationError {
                return
            }
            if error.isAuthenticationFailure {
                await self.handleAuthenticationFailure(error)
                return
            }
            let diagnostics = await self.github.diagnostics()
            let cacheSummary = try? RepoBarPersistentCache.summary(limit: 100)
            await MainActor.run {
                self.session.localProjectsScanInProgress = false
                self.session.rateLimitReset = (error as? GitHubAPIError)?.rateLimitedUntil
                self.session.rateLimitDiagnostics = diagnostics
                self.session.rateLimitCacheSummary = cacheSummary
                self.session.lastError = error.userFacingMessage
                NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
            }
            await self.refreshActionsLimitsState()
        }
    }

    private func hasAuthenticationMaterial() async -> Bool {
        if self.session.settings.accounts.isEmpty == false {
            let selectedIDs = self.selectedAccountIDsForRepositoryRefresh()
            return self.accountManager.accountClientSnapshots(accountIDs: selectedIDs).isEmpty == false
        }
        if let accountID = self.session.settings.resolvedActiveAccount()?.id {
            return (try? TokenStore.shared.loadTokens(accountID: accountID)) != nil
                || (try? TokenStore.shared.loadPAT(accountID: accountID)) != nil
        }
        return self.auth.loadTokens() != nil || self.patAuth.loadPAT() != nil
    }

    func refreshLocalProjects(cancelInFlight: Bool = true, forceRescan: Bool = false) {
        if cancelInFlight {
            self.localProjectsTask?.cancel()
        }

        let settings = self.session.settings.localProjects
        guard let rootPath = settings.rootPath,
              rootPath.isEmpty == false
        else {
            self.session.localRepoIndex = .empty
            self.session.localDiscoveredRepoCount = 0
            self.session.localProjectsAccessDenied = false
            self.session.localProjectsScanInProgress = false
            return
        }

        self.session.localProjectsScanInProgress = true
        self.localProjectsTask = Task { [weak self] in
            guard let self else { return }

            let matchNames = self.localMatchRepoNamesForLocalProjects(
                repos: self.session.repositories.isEmpty
                    ? (self.session.menuSnapshot?.repositories ?? [])
                    : self.session.repositories,
                includePinned: true
            )
            let localSnapshot = await self.localRepoManager.snapshot(
                rootPath: settings.rootPath,
                rootBookmarkData: settings.rootBookmarkData,
                options: LocalRepoManager.SnapshotOptions(
                    autoSyncEnabled: settings.autoSyncEnabled,
                    fetchInterval: settings.fetchInterval.seconds,
                    preferredPathsByFullName: settings.preferredLocalPathsByFullName,
                    matchRepoNames: matchNames,
                    forceRescan: forceRescan,
                    maxDepth: settings.maxDepth
                )
            )
            await MainActor.run {
                self.session.localRepoIndex = localSnapshot.repoIndex
                self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
                self.session.localProjectsAccessDenied = localSnapshot.accessDenied
                self.session.localProjectsScanInProgress = false
            }
        }
    }

    func updateHeatmapRange(now: Date = Date()) {
        self.session.heatmapRange = HeatmapFilter.range(
            span: self.session.settings.heatmap.span,
            now: now,
            alignToWeek: true
        )
    }

    func handleAuthenticationFailure(_ error: Error) async {
        if let accountID = self.session.settings.resolvedActiveAccount()?.id {
            TokenStore.shared.clear(accountID: accountID)
        }
        await self.auth.logout()
        await self.patAuth.logout()
        let localSnapshot = await self.snapshotForLoggedOutState(localSettings: self.session.settings.localProjects)
        await self.applyLoggedOutState(localSnapshot: localSnapshot, lastError: error.userFacingMessage)
    }

    private func hydrateMenuTargets(_ repos: [Repository], fetchHeatmap: Bool) async -> [Repository] {
        guard !repos.isEmpty else { return [] }

        let limit = max(1, min(self.hydrateConcurrencyLimit, repos.count))
        let options = RepositoryDetailOptions(fetchHeatmap: fetchHeatmap)
        var detailed: [Repository] = []
        for batch in repos.chunked(into: limit) {
            if Task.isCancelled {
                break
            }
            let batchResult = await withTaskGroup(of: Repository?.self) { group in
                for repo in batch {
                    group.addTask { [github, options] in
                        try? await github.fullRepository(owner: repo.owner, name: repo.name, options: options)
                    }
                }
                var batchOutput: [Repository] = []
                for await repo in group {
                    if let repo {
                        batchOutput.append(repo)
                    }
                }
                return batchOutput
            }
            detailed.append(contentsOf: batchResult)
        }
        return detailed
    }

    private func snapshotForLoggedOutState(
        localSettings: LocalProjectsSettings
    ) async -> LocalRepoManager.SnapshotResult {
        let matchNames = self.localMatchRepoNamesForLocalProjects(repos: [], includePinned: true)
        return await self.localRepoManager.snapshot(
            rootPath: localSettings.rootPath,
            rootBookmarkData: localSettings.rootBookmarkData,
            options: LocalRepoManager.SnapshotOptions(
                autoSyncEnabled: localSettings.autoSyncEnabled,
                fetchInterval: localSettings.fetchInterval.seconds,
                preferredPathsByFullName: localSettings.preferredLocalPathsByFullName,
                matchRepoNames: matchNames,
                forceRescan: false,
                maxDepth: localSettings.maxDepth
            )
        )
    }

    private func applyLoggedOutState(
        localSnapshot: LocalRepoManager.SnapshotResult,
        lastError: String?
    ) async {
        await MainActor.run {
            self.session.account = .loggedOut
            self.session.hasStoredTokens = false
            self.session.accessibleRepositories = []
            self.session.repositories = []
            self.session.accountSessions = []
            self.session.aggregatedRepositories = []
            self.session.menuSnapshot = nil
            self.session.menuDisplayIndex = [:]
            self.session.hasLoadedRepositories = false
            self.session.lastError = lastError
            self.session.localRepoIndex = localSnapshot.repoIndex
            self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
            self.session.localProjectsAccessDenied = localSnapshot.accessDenied
            self.session.localProjectsScanInProgress = false
            self.session.globalActivityEvents = []
            self.session.globalActivityError = nil
            self.session.globalCommitEvents = []
            self.session.globalCommitError = nil
            // Auto-select local filter when logged out (other filters require GitHub)
            if self.session.menuRepoSelection != .local {
                self.session.menuRepoSelection = .local
            }
        }
    }

    private func mergeHydrated(_ detailed: [Repository], into repos: [Repository]) -> [Repository] {
        RepositoryHydration.merge(detailed, into: repos)
    }

    @discardableResult
    func publishHydratedActiveRepositorySnapshot(
        accessibleRepositories: [Repository],
        repositories: [Repository],
        accountID: String,
        generation: UUID,
        now: Date
    ) -> Bool {
        guard self.canContinueAccountRepositoryRefresh(generation: generation, accountID: accountID),
              let accountIndex = self.session.accountSessions.firstIndex(where: { $0.id == accountID })
        else { return false }

        let accessible = RepositoryUniquing.byFullName(accessibleRepositories)
        self.session.accessibleRepositories = accessible
        self.session.repositories = repositories
        self.session.menuSnapshot = MenuSnapshot(repositories: repositories, capturedAt: now)
        self.session.menuDisplayIndex = self.menuDisplayIndex(for: repositories, now: now)
        self.session.hasLoadedRepositories = true
        self.session.rateLimitReset = nil
        self.session.lastError = nil
        self.session.accountSessions[accountIndex].accessibleRepositories = accessible
        self.session.accountSessions[accountIndex].repositories = repositories
        self.rebuildAggregatedRepositories()
        NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
        return true
    }

    private func canContinueAccountRepositoryRefresh(generation: UUID, accountID: String) -> Bool {
        self.canPublishAccountRepositoryRefresh(generation)
            && self.session.activeAccountID == accountID
    }

    private func checkAccountRepositoryRefreshIsCurrent(generation: UUID, accountID: String) throws {
        guard self.canContinueAccountRepositoryRefresh(generation: generation, accountID: accountID) else {
            throw CancellationError()
        }
    }

    private func updateMenuDisplayIndex(now: Date) async {
        let repos = self.session.repositories
        let index = self.menuDisplayIndex(for: repos, now: now)
        await MainActor.run {
            self.session.menuDisplayIndex = index
            NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
        }
    }

    func menuDisplayIndex(for repos: [Repository], now: Date) -> [String: RepositoryDisplayModel] {
        let localIndex = self.session.localRepoIndex
        let models = repos.map { repo in
            RepositoryDisplayModel(
                repo: repo,
                localStatus: localIndex.status(for: repo, host: self.session.settings.githubHost),
                now: now
            )
        }
        return Dictionary(
            models.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func prefetchMenuTargets(
        from repos: [Repository],
        visibleCount: Int,
        token: UUID
    ) {
        let limit = self.session.settings.repoList.displayLimit
        guard limit > 0 else { return }

        let startIndex = min(visibleCount, repos.count)
        let prefetchTargets = Array(repos.dropFirst(startIndex).prefix(limit))
        guard prefetchTargets.isEmpty == false else { return }

        self.prefetchTask?.cancel()
        self.prefetchTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }

            let hydrated = await self.hydrateMenuTargets(prefetchTargets, fetchHeatmap: false)
            guard Task.isCancelled == false, hydrated.isEmpty == false else { return }

            await MainActor.run {
                guard self.refreshTaskToken == token else { return }

                let merged = self.mergeHydrated(hydrated, into: self.session.repositories)
                self.session.repositories = merged
                let capturedAt = self.session.menuSnapshot?.capturedAt ?? Date()
                self.session.menuSnapshot = MenuSnapshot(
                    repositories: merged,
                    capturedAt: capturedAt
                )
                let models = merged.map { repo in
                    RepositoryDisplayModel(
                        repo: repo,
                        localStatus: self.session.localRepoIndex.status(
                            for: repo,
                            host: self.session.settings.githubHost
                        ),
                        now: capturedAt
                    )
                }
                self.session.menuDisplayIndex = Dictionary(
                    models.map { ($0.title.lowercased(), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
            }
        }
    }
}
