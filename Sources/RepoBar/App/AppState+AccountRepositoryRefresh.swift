import Foundation
import RepoBarCore

struct AccountRepositoryRefreshFailure: Error, LocalizedError {
    let accountID: String
    let message: String
    let authenticationFailure: Bool
    let rateLimitedUntil: Date?
    let diagnostics: DiagnosticsSummary
    let cacheSummary: RepoBarCacheSummary?

    var errorDescription: String? {
        self.message
    }
}

struct AccountRepositoryRefreshOutcome {
    let activeSession: AccountSession?
    let activeFailure: AccountRepositoryRefreshFailure?
    let generation: UUID
    let published: Bool
}

extension AppState {
    func selectedAccountIDsForRepositoryRefresh() -> [String] {
        if self.session.settings.consolidateAccounts {
            return self.session.settings.visibleAccountIDs
        }
        return self.session.settings.resolvedActiveAccount().map { [$0.id] } ?? []
    }

    func refreshAccountRepositorySnapshots(now: Date = Date()) async -> AccountRepositoryRefreshOutcome {
        let generation = UUID()
        self.accountRepositoryRefreshGeneration = generation
        let settings = self.session.settings
        let activeAccountID = settings.resolvedActiveAccount()?.id
        let accountIDs = self.selectedAccountIDsForRepositoryRefresh()
        let pairs = self.accountManager.accountClientSnapshots(accountIDs: accountIDs)

        self.resetPublishedAccountSessions(to: pairs, activeAccountID: activeAccountID)
        guard pairs.isEmpty == false else {
            return AccountRepositoryRefreshOutcome(
                activeSession: nil,
                activeFailure: nil,
                generation: generation,
                published: true
            )
        }

        let cachedResults = await self.loadAccountRepositorySnapshots(
            pairs: pairs,
            settings: settings,
            now: now,
            cached: true
        )
        guard self.canPublishAccountRepositoryRefresh(generation) else {
            return AccountRepositoryRefreshOutcome(
                activeSession: nil,
                activeFailure: nil,
                generation: generation,
                published: false
            )
        }

        self.publishCachedAccountRepositorySnapshots(
            cachedResults,
            pairs: pairs,
            activeAccountID: activeAccountID,
            now: now
        )

        let liveResults = await self.loadAccountRepositorySnapshots(
            pairs: pairs,
            settings: settings,
            now: now,
            cached: false
        )
        guard self.canPublishAccountRepositoryRefresh(generation) else {
            return AccountRepositoryRefreshOutcome(
                activeSession: nil,
                activeFailure: nil,
                generation: generation,
                published: false
            )
        }

        let activeFailure = self.publishLiveAccountRepositorySnapshots(
            liveResults,
            pairs: pairs,
            activeAccountID: activeAccountID,
            now: now
        )
        return AccountRepositoryRefreshOutcome(
            activeSession: self.session.accountSessions.first(where: { $0.id == activeAccountID }),
            activeFailure: activeFailure,
            generation: generation,
            published: true
        )
    }

    func rebuildAggregatedRepositories() {
        self.session.aggregatedRepositories = self.session.accountSessions.flatMap { accountSession in
            accountSession.repositories.map { TaggedRepo(repo: $0, accountID: accountSession.id) }
        }
    }

    private func resetPublishedAccountSessions(
        to pairs: [AccountManager.AccountClientSnapshot],
        activeAccountID: String?
    ) {
        let previous = Dictionary(uniqueKeysWithValues: self.session.accountSessions.map { ($0.id, $0) })
        self.session.accountSessions = pairs.map { pair in
            var accountSession = previous[pair.account.id] ?? AccountSession(account: pair.account)
            accountSession.account = pair.account
            return accountSession
        }
        self.rebuildAggregatedRepositories()
        self.publishActiveAccountCompatibility(activeAccountID: activeAccountID)
    }

    private func loadAccountRepositorySnapshots(
        pairs: [AccountManager.AccountClientSnapshot],
        settings: UserSettings,
        now: Date,
        cached: Bool
    ) async -> [String: AccountRepositoryLoadResult] {
        var output: [String: AccountRepositoryLoadResult] = [:]
        let limit = max(1, self.accountRepositoryRefreshConcurrencyLimit)
        var start = 0
        while start < pairs.count {
            if Task.isCancelled {
                return output
            }
            let end = min(start + limit, pairs.count)
            let batch = Array(pairs[start ..< end])
            let batchResults = await withTaskGroup(of: (String, AccountRepositoryLoadResult).self) { group in
                for pair in batch {
                    let request = self.snapshotRequest(pair: pair, settings: settings, now: now)
                    let loader = self.accountRepositorySnapshotLoader
                    group.addTask {
                        do {
                            if cached {
                                if let snapshot = try await loader.cachedSnapshot(for: request) {
                                    return (pair.account.id, .snapshot(snapshot))
                                }
                                return (pair.account.id, .emptyCache)
                            }
                            return try await (pair.account.id, .snapshot(loader.snapshot(for: request)))
                        } catch {
                            let diagnostics = await pair.client.diagnostics()
                            let cacheSummary = try? RepoBarPersistentCache.summary(
                                accountID: pair.account.id,
                                limit: 100
                            )
                            return (
                                pair.account.id,
                                .failure(AccountRepositoryRefreshFailure(
                                    accountID: pair.account.id,
                                    message: error.userFacingMessage,
                                    authenticationFailure: error.isAuthenticationFailure,
                                    rateLimitedUntil: Self.rateLimitDate(from: error),
                                    diagnostics: diagnostics,
                                    cacheSummary: cacheSummary
                                ))
                            )
                        }
                    }
                }
                var results: [(String, AccountRepositoryLoadResult)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            for (accountID, result) in batchResults {
                output[accountID] = result
            }
            start = end
        }
        return output
    }

    private func snapshotRequest(
        pair: AccountManager.AccountClientSnapshot,
        settings: UserSettings,
        now: Date
    ) -> AccountRepositorySnapshotRequest {
        let accountID = pair.account.id
        return AccountRepositorySnapshotRequest(
            account: pair.account,
            client: pair.client,
            preferences: AccountRepositoryPreferences(
                pinned: settings.accountRepoLists.pinned(
                    for: accountID,
                    legacy: settings.repoList.pinnedRepositories
                ),
                hidden: Set(settings.accountRepoLists.hidden(
                    for: accountID,
                    legacy: settings.repoList.hiddenRepositories
                )),
                includeForks: settings.repoList.showForks,
                includeArchived: settings.repoList.showArchived,
                ownerFilter: settings.repoList.ownerFilter
            ),
            now: now
        )
    }

    private func publishCachedAccountRepositorySnapshots(
        _ results: [String: AccountRepositoryLoadResult],
        pairs: [AccountManager.AccountClientSnapshot],
        activeAccountID: String?,
        now: Date
    ) {
        for pair in pairs {
            guard case let .snapshot(snapshot)? = results[pair.account.id],
                  let index = self.session.accountSessions.firstIndex(where: { $0.id == pair.account.id })
            else { continue }

            let previous = self.session.accountSessions[index]
            guard previous.lastSuccessfulRefreshAt == nil else { continue }

            self.session.accountSessions[index] = AccountSession(
                account: pair.account,
                state: .loggedIn(UserIdentity(username: pair.account.username, host: pair.account.host)),
                repositories: snapshot.repositories,
                accessibleRepositories: snapshot.accessibleRepositories,
                rateLimitReset: snapshot.diagnostics.rateLimitReset,
                diagnostics: snapshot.diagnostics,
                cacheSummary: snapshot.cacheSummary,
                lastAttemptAt: now,
                lastSuccessfulRefreshAt: previous.lastSuccessfulRefreshAt,
                isStale: true,
                lastError: nil
            )
        }
        self.rebuildAggregatedRepositories()
        self.publishActiveAccountCompatibility(activeAccountID: activeAccountID)
    }

    private func publishLiveAccountRepositorySnapshots(
        _ results: [String: AccountRepositoryLoadResult],
        pairs: [AccountManager.AccountClientSnapshot],
        activeAccountID: String?,
        now: Date
    ) -> AccountRepositoryRefreshFailure? {
        var activeFailure: AccountRepositoryRefreshFailure?
        for pair in pairs {
            guard let index = self.session.accountSessions.firstIndex(where: { $0.id == pair.account.id }),
                  let result = results[pair.account.id]
            else { continue }

            switch result {
            case let .snapshot(snapshot):
                self.session.accountSessions[index] = AccountSession(
                    account: pair.account,
                    state: .loggedIn(UserIdentity(username: pair.account.username, host: pair.account.host)),
                    repositories: snapshot.repositories,
                    accessibleRepositories: snapshot.accessibleRepositories,
                    rateLimitReset: snapshot.diagnostics.rateLimitReset,
                    diagnostics: snapshot.diagnostics,
                    cacheSummary: snapshot.cacheSummary,
                    lastAttemptAt: now,
                    lastSuccessfulRefreshAt: snapshot.capturedAt,
                    isStale: false,
                    lastError: nil
                )
            case let .failure(failure):
                var accountSession = self.session.accountSessions[index]
                accountSession.account = pair.account
                accountSession.state = failure.authenticationFailure
                    ? .loggedOut
                    : .loggedIn(UserIdentity(username: pair.account.username, host: pair.account.host))
                accountSession.rateLimitReset = failure.rateLimitedUntil ?? failure.diagnostics.rateLimitReset
                accountSession.diagnostics = failure.diagnostics
                accountSession.cacheSummary = failure.cacheSummary
                accountSession.lastAttemptAt = now
                accountSession.isStale = true
                accountSession.lastError = failure.message
                self.session.accountSessions[index] = accountSession
                if pair.account.id == activeAccountID {
                    activeFailure = failure
                }
            case .emptyCache:
                break
            }
        }
        self.rebuildAggregatedRepositories()
        self.publishActiveAccountCompatibility(activeAccountID: activeAccountID)
        return activeFailure
    }

    private func publishActiveAccountCompatibility(activeAccountID: String?) {
        guard let activeAccountID,
              let active = self.session.accountSessions.first(where: { $0.id == activeAccountID })
        else {
            self.session.accessibleRepositories = []
            self.session.repositories = []
            self.session.menuSnapshot = nil
            self.session.menuDisplayIndex = [:]
            self.session.hasLoadedRepositories = false
            return
        }

        self.session.account = active.state
        self.session.accessibleRepositories = active.accessibleRepositories
        self.session.repositories = active.repositories
        let capturedAt = active.lastSuccessfulRefreshAt ?? active.lastAttemptAt ?? Date()
        self.session.menuSnapshot = MenuSnapshot(
            repositories: active.repositories,
            capturedAt: capturedAt
        )
        self.session.menuDisplayIndex = self.menuDisplayIndex(for: active.repositories, now: capturedAt)
        self.session.hasLoadedRepositories = true
        self.session.rateLimitReset = active.rateLimitReset
        self.session.lastError = active.lastError
        NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
    }

    func canPublishAccountRepositoryRefresh(_ generation: UUID) -> Bool {
        Task.isCancelled == false && self.accountRepositoryRefreshGeneration == generation
    }

    private nonisolated static func rateLimitDate(from error: Error) -> Date? {
        guard let error = error as? GitHubAPIError else { return nil }

        return error.rateLimitedUntil ?? error.retryAfter
    }
}

private enum AccountRepositoryLoadResult {
    case snapshot(AccountRepositorySnapshot)
    case emptyCache
    case failure(AccountRepositoryRefreshFailure)
}
