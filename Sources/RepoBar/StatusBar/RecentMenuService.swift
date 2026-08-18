import Foundation
import RepoBarCore

@MainActor
final class RecentMenuService {
    let listLimit: Int
    let previewLimit: Int
    let cacheTTL: TimeInterval
    let loadTimeout: TimeInterval

    private let clientResolver: @MainActor (String) throws -> GitHubClient
    private let activeAccountID: @MainActor () -> String?
    private let recentIssuesCache = RecentListCache<RepoIssueSummary>()
    private let recentPullRequestsCache = RecentListCache<RepoPullRequestSummary>()
    private let recentReleasesCache = RecentListCache<RepoReleaseSummary>()
    private let recentWorkflowRunsCache = RecentListCache<RepoWorkflowRunSummary>()
    private let recentCommitsCache = RecentListCache<RepoCommitSummary>()
    private let recentDiscussionsCache = RecentListCache<RepoDiscussionSummary>()
    private let recentTagsCache = RecentListCache<RepoTagSummary>()
    private let recentBranchesCache = RecentListCache<RepoBranchSummary>()
    private let recentContributorsCache = RecentListCache<RepoContributorSummary>()
    private var recentCommitCounts: [AccountScopedCacheKey: Int] = [:]

    init(
        github: @escaping @MainActor () -> GitHubClient,
        cacheNamespace: @escaping @MainActor () -> String,
        listLimit: Int = AppLimits.RecentLists.limit,
        previewLimit: Int = AppLimits.RecentLists.previewLimit,
        cacheTTL: TimeInterval = AppLimits.RecentLists.cacheTTL,
        loadTimeout: TimeInterval = AppLimits.RecentLists.loadTimeout
    ) {
        self.clientResolver = { _ in github() }
        self.activeAccountID = { cacheNamespace() }
        self.listLimit = listLimit
        self.previewLimit = previewLimit
        self.cacheTTL = cacheTTL
        self.loadTimeout = loadTimeout
    }

    convenience init(appState: AppState) {
        self.init(
            clientResolver: { [appState] accountID in
                try appState.accountManager.resolveClient(for: accountID)
            },
            activeAccountID: { [appState] in
                appState.session.settings.resolvedActiveAccount()?.id
            }
        )
    }

    init(
        clientResolver: @escaping @MainActor (String) throws -> GitHubClient,
        activeAccountID: @escaping @MainActor () -> String?,
        listLimit: Int = AppLimits.RecentLists.limit,
        previewLimit: Int = AppLimits.RecentLists.previewLimit,
        cacheTTL: TimeInterval = AppLimits.RecentLists.cacheTTL,
        loadTimeout: TimeInterval = AppLimits.RecentLists.loadTimeout
    ) {
        self.clientResolver = clientResolver
        self.activeAccountID = activeAccountID
        self.listLimit = listLimit
        self.previewLimit = previewLimit
        self.cacheTTL = cacheTTL
        self.loadTimeout = loadTimeout
    }

    func cacheKey(accountID: String, fullName: String) -> AccountScopedCacheKey {
        AccountScopedCacheKey(accountID: accountID, key: fullName)
    }

    func cacheKey(fullName: String) -> AccountScopedCacheKey? {
        self.activeAccountID().map { self.cacheKey(accountID: $0, fullName: fullName) }
    }

    func cacheContext(accountID: String, fullName: String) throws
        -> (key: AccountScopedCacheKey, github: GitHubClient) {
        try (
            self.cacheKey(accountID: accountID, fullName: fullName),
            self.clientResolver(accountID)
        )
    }

    func cacheContext(fullName: String) throws -> (key: AccountScopedCacheKey, github: GitHubClient) {
        guard let accountID = self.activeAccountID() else {
            throw AccountManagerError.clientUnavailable("active")
        }

        return try self.cacheContext(accountID: accountID, fullName: fullName)
    }

    func descriptor(for kind: RepoRecentMenuKind) -> RecentMenuDescriptor? {
        self.descriptors()[kind]
    }

    func descriptors() -> [RepoRecentMenuKind: RecentMenuDescriptor] {
        let commitDescriptor = self.commitDescriptor()

        let descriptors: [RecentMenuDescriptor] = [
            commitDescriptor,
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .issues,
                headerTitle: "Open Issues",
                headerIcon: "exclamationmark.circle",
                emptyTitle: "No open issues",
                cache: self.recentIssuesCache,
                wrap: RecentMenuItems.issues,
                unwrap: { boxed in
                    if case let .issues(items) = boxed {
                        return items
                    }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentIssues(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .pullRequests,
                headerTitle: "Open Pull Requests",
                headerIcon: "arrow.triangle.branch",
                emptyTitle: "No open pull requests",
                cache: self.recentPullRequestsCache,
                wrap: RecentMenuItems.pullRequests,
                unwrap: { boxed in
                    if case let .pullRequests(items) = boxed {
                        return items
                    }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentPullRequests(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .releases,
                headerTitle: "Open Releases",
                headerIcon: "tag",
                emptyTitle: "No releases",
                cache: self.recentReleasesCache,
                wrap: RecentMenuItems.releases,
                unwrap: { boxed in
                    if case let .releases(items) = boxed {
                        return items
                    }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentReleases(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .ciRuns,
                headerTitle: "Open Actions",
                headerIcon: "bolt",
                emptyTitle: "No CI runs",
                cache: self.recentWorkflowRunsCache,
                wrap: RecentMenuItems.workflowRuns,
                unwrap: { boxed in
                    if case let .workflowRuns(items) = boxed {
                        return items
                    }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentWorkflowRuns(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .discussions,
                headerTitle: "Open Discussions",
                headerIcon: "bubble.left.and.bubble.right",
                emptyTitle: "No discussions",
                cache: self.recentDiscussionsCache,
                wrap: RecentMenuItems.discussions,
                unwrap: { boxed in
                    if case let .discussions(items) = boxed {
                        return items
                    }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentDiscussions(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .tags,
                headerTitle: "Open Tags",
                headerIcon: "tag",
                emptyTitle: "No tags",
                cache: self.recentTagsCache,
                wrap: RecentMenuItems.tags,
                unwrap: { boxed in
                    if case let .tags(items) = boxed {
                        return items
                    }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentTags(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .branches,
                headerTitle: "Open Branches",
                headerIcon: "point.topleft.down.curvedto.point.bottomright.up",
                emptyTitle: "No branches",
                cache: self.recentBranchesCache,
                wrap: RecentMenuItems.branches,
                unwrap: { boxed in
                    if case let .branches(items) = boxed {
                        return items
                    }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentBranches(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .contributors,
                headerTitle: "Open Contributors",
                headerIcon: "person.2",
                emptyTitle: "No contributors",
                cache: self.recentContributorsCache,
                wrap: RecentMenuItems.contributors,
                unwrap: { boxed in
                    if case let .contributors(items) = boxed {
                        return items
                    }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.topContributors(owner: owner, name: name, limit: limit)
                }
            ))
        ]

        return Dictionary(uniqueKeysWithValues: descriptors.map { ($0.kind, $0) })
    }

    func cachedRecentCommitCount(fullName: String) -> Int? {
        guard let key = self.cacheKey(fullName: fullName) else { return nil }

        return self.cachedRecentCommitCount(key: key)
    }

    func cachedRecentCommitCount(accountID: String, fullName: String) -> Int? {
        self.cachedRecentCommitCount(key: self.cacheKey(accountID: accountID, fullName: fullName))
    }

    private func cachedRecentCommitCount(key: AccountScopedCacheKey) -> Int? {
        if let total = self.recentCommitCounts[key] {
            return total
        }
        return self.recentCommitsCache.stale(for: key)?.count
    }

    func cachedCommits(fullName: String, now: Date = Date()) -> [RepoCommitSummary]? {
        guard let key = self.cacheKey(fullName: fullName) else { return nil }

        return self.cachedCommits(key: key, now: now)
    }

    func cachedCommits(accountID: String, fullName: String, now: Date = Date()) -> [RepoCommitSummary]? {
        self.cachedCommits(key: self.cacheKey(accountID: accountID, fullName: fullName), now: now)
    }

    private func cachedCommits(key: AccountScopedCacheKey, now: Date) -> [RepoCommitSummary]? {
        self.recentCommitsCache.cached(for: key, now: now, maxAge: self.cacheTTL)
            ?? self.recentCommitsCache.stale(for: key)
    }

    func cachedCommitDigest(fullName: String) -> Int? {
        let now = Date()
        guard let commits = self.cachedCommits(fullName: fullName, now: now), commits.isEmpty == false else { return nil }

        var hasher = Hasher()
        for commit in commits {
            hasher.combine(commit.sha)
            hasher.combine(commit.authoredAt.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    func removeCachedState(accountID: String) {
        self.recentIssuesCache.remove(accountID: accountID)
        self.recentPullRequestsCache.remove(accountID: accountID)
        self.recentReleasesCache.remove(accountID: accountID)
        self.recentWorkflowRunsCache.remove(accountID: accountID)
        self.recentCommitsCache.remove(accountID: accountID)
        self.recentDiscussionsCache.remove(accountID: accountID)
        self.recentTagsCache.remove(accountID: accountID)
        self.recentBranchesCache.remove(accountID: accountID)
        self.recentContributorsCache.remove(accountID: accountID)
        self.recentCommitCounts = self.recentCommitCounts.filter { $0.key.accountID != accountID }
    }

    func load(
        accountID: String,
        fullName: String,
        kind: RepoRecentMenuKind,
        limit: Int? = nil
    ) async throws -> RecentMenuItems {
        let parts = fullName.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else {
            throw RecentMenuServiceError.invalidRepositoryName(fullName)
        }
        guard let descriptor = self.descriptor(for: kind) else {
            throw RecentMenuServiceError.unsupportedKind
        }

        let context = try self.cacheContext(accountID: accountID, fullName: fullName)
        return try await descriptor.load(
            context.key,
            String(parts[0]),
            String(parts[1]),
            limit ?? self.listLimit,
            context.github
        )
    }

    private enum RecentMenuServiceError: LocalizedError {
        case invalidRepositoryName(String)
        case unsupportedKind

        var errorDescription: String? {
            switch self {
            case let .invalidRepositoryName(fullName):
                "Invalid repository name: \(fullName)"
            case .unsupportedKind:
                "Unsupported recent-list kind."
            }
        }
    }

    private func commitDescriptor() -> RecentMenuDescriptor {
        RecentMenuDescriptor(
            kind: .commits,
            headerTitle: "Open Commits",
            headerIcon: "arrow.turn.down.right",
            emptyTitle: "No commits",
            cached: { key, now, ttl in
                self.recentCommitsCache.cached(for: key, now: now, maxAge: ttl).map(RecentMenuItems.commits)
            },
            stale: { key in
                self.recentCommitsCache.stale(for: key).map(RecentMenuItems.commits)
            },
            needsRefresh: { key, now, ttl in
                self.recentCommitsCache.needsRefresh(for: key, now: now, maxAge: ttl)
            },
            load: { key, owner, name, limit, github in
                let task = self.recentCommitsCache.task(for: key) {
                    let list = try await github.recentCommits(owner: owner, name: name, limit: limit)
                    await MainActor.run {
                        self.recentCommitCounts[key] = list.totalCount ?? list.items.count
                    }
                    return list.items
                }
                defer { self.recentCommitsCache.clearInflight(for: key) }
                let items = try await AsyncTimeout.value(within: self.loadTimeout, task: task)
                let evictedKeys = self.recentCommitsCache.store(items, for: key, fetchedAt: Date())
                for evictedKey in evictedKeys {
                    self.recentCommitCounts[evictedKey] = nil
                }
                return RecentMenuItems.commits(items)
            }
        )
    }

    private func makeDescriptor(
        _ config: RecentMenuDescriptorConfig<some Sendable>
    ) -> RecentMenuDescriptor {
        let fetch = config.fetch

        return RecentMenuDescriptor(
            kind: config.kind,
            headerTitle: config.headerTitle,
            headerIcon: config.headerIcon,
            emptyTitle: config.emptyTitle,
            cached: { key, now, ttl in
                config.cache.cached(for: key, now: now, maxAge: ttl).map(config.wrap)
            },
            stale: { key in
                config.cache.stale(for: key).map(config.wrap)
            },
            needsRefresh: { key, now, ttl in
                config.cache.needsRefresh(for: key, now: now, maxAge: ttl)
            },
            load: { key, owner, name, limit, github in
                let task = config.cache.task(for: key) {
                    try await fetch(github, owner, name, limit)
                }
                defer { config.cache.clearInflight(for: key) }
                let items = try await AsyncTimeout.value(within: self.loadTimeout, task: task)
                _ = config.cache.store(items, for: key, fetchedAt: Date())
                return config.wrap(items)
            }
        )
    }
}

struct RecentMenuDescriptorConfig<Item: Sendable> {
    let kind: RepoRecentMenuKind
    let headerTitle: String
    let headerIcon: String?
    let emptyTitle: String
    let cache: RecentListCache<Item>
    let wrap: ([Item]) -> RecentMenuItems
    let unwrap: (RecentMenuItems) -> [Item]?
    let fetch: @Sendable (GitHubClient, String, String, Int) async throws -> [Item]
}

struct RecentMenuDescriptor {
    let kind: RepoRecentMenuKind
    let headerTitle: String
    let headerIcon: String?
    let emptyTitle: String
    let cached: (AccountScopedCacheKey, Date, TimeInterval) -> RecentMenuItems?
    let stale: (AccountScopedCacheKey) -> RecentMenuItems?
    let needsRefresh: (AccountScopedCacheKey, Date, TimeInterval) -> Bool
    let load: @MainActor (AccountScopedCacheKey, String, String, Int, GitHubClient) async throws -> RecentMenuItems
}

enum RecentMenuItems {
    case commits([RepoCommitSummary])
    case issues([RepoIssueSummary])
    case pullRequests([RepoPullRequestSummary])
    case releases([RepoReleaseSummary])
    case workflowRuns([RepoWorkflowRunSummary])
    case discussions([RepoDiscussionSummary])
    case tags([RepoTagSummary])
    case branches([RepoBranchSummary])
    case contributors([RepoContributorSummary])

    var isEmpty: Bool {
        switch self {
        case let .commits(items): items.isEmpty
        case let .issues(items): items.isEmpty
        case let .pullRequests(items): items.isEmpty
        case let .releases(items): items.isEmpty
        case let .workflowRuns(items): items.isEmpty
        case let .discussions(items): items.isEmpty
        case let .tags(items): items.isEmpty
        case let .branches(items): items.isEmpty
        case let .contributors(items): items.isEmpty
        }
    }

    var count: Int {
        switch self {
        case let .commits(items): items.count
        case let .issues(items): items.count
        case let .pullRequests(items): items.count
        case let .releases(items): items.count
        case let .workflowRuns(items): items.count
        case let .discussions(items): items.count
        case let .tags(items): items.count
        case let .branches(items): items.count
        case let .contributors(items): items.count
        }
    }
}

final class RecentListCache<Item: Sendable> {
    struct Entry {
        var fetchedAt: Date
        var items: [Item]
    }

    private let maxEntries: Int
    private var entries: [AccountScopedCacheKey: Entry] = [:]
    private var entryOrder: [AccountScopedCacheKey] = []
    private var inflight: [AccountScopedCacheKey: Task<[Item], Error>] = [:]

    init(maxEntries: Int = AppLimits.RecentLists.cacheEntries) {
        self.maxEntries = max(0, maxEntries)
    }

    func cached(for key: AccountScopedCacheKey, now: Date, maxAge: TimeInterval) -> [Item]? {
        guard let entry = self.entries[key] else { return nil }
        guard now.timeIntervalSince(entry.fetchedAt) <= maxAge else { return nil }

        self.touch(key)
        return entry.items
    }

    func stale(for key: AccountScopedCacheKey) -> [Item]? {
        guard let entry = self.entries[key] else { return nil }

        self.touch(key)
        return entry.items
    }

    func needsRefresh(for key: AccountScopedCacheKey, now: Date, maxAge: TimeInterval) -> Bool {
        guard let entry = self.entries[key] else { return true }

        return now.timeIntervalSince(entry.fetchedAt) > maxAge
    }

    func task(
        for key: AccountScopedCacheKey,
        factory: @escaping @Sendable () async throws -> [Item]
    ) -> Task<[Item], Error> {
        if let existing = self.inflight[key] {
            return existing
        }
        let task = Task { try await factory() }
        self.inflight[key] = task
        return task
    }

    func clearInflight(for key: AccountScopedCacheKey) {
        self.inflight[key] = nil
    }

    @discardableResult
    func store(
        _ items: [Item],
        for key: AccountScopedCacheKey,
        fetchedAt: Date
    ) -> [AccountScopedCacheKey] {
        guard self.maxEntries > 0 else { return [] }

        self.entries[key] = Entry(fetchedAt: fetchedAt, items: items)
        self.touch(key)
        return self.evictIfNeeded()
    }

    func count() -> Int {
        self.entries.count
    }

    func remove(accountID: String) {
        let keys = self.entries.keys.filter { $0.accountID == accountID }
        for key in keys {
            self.entries[key] = nil
        }
        self.entryOrder.removeAll { $0.accountID == accountID }
        let tasks = self.inflight.filter { $0.key.accountID == accountID }.map(\.value)
        self.inflight = self.inflight.filter { $0.key.accountID != accountID }
        tasks.forEach { $0.cancel() }
    }

    private func touch(_ key: AccountScopedCacheKey) {
        self.entryOrder.removeAll { $0 == key }
        self.entryOrder.append(key)
    }

    private func evictIfNeeded() -> [AccountScopedCacheKey] {
        var evicted: [AccountScopedCacheKey] = []
        while self.entries.count > self.maxEntries, let oldest = self.entryOrder.first {
            self.entryOrder.removeFirst()
            if self.entries.removeValue(forKey: oldest) != nil {
                evicted.append(oldest)
            }
        }
        return evicted
    }
}
