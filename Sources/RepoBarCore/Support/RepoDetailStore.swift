import Foundation

actor RepoDetailStore {
    /// All clients share one snapshot, including clients for different accounts.
    static let shared = RepoDetailStore()

    private var memory: [String: RepoDetailCache] = [:]
    private var diskStore: RepoDetailCacheStore
    private let flushDelay: Duration
    private var hasLoaded = false
    private var isDirty = false
    private var flushTask: Task<Void, Never>?

    init(diskStore: RepoDetailCacheStore = RepoDetailCacheStore(), flushDelay: Duration = .seconds(30)) {
        self.diskStore = diskStore
        self.flushDelay = flushDelay
    }

    deinit {
        self.flushTask?.cancel()
    }

    func load(apiHost: URL, owner: String, name: String) -> RepoDetailCache {
        self.loadIfNeeded()
        let key = Self.cacheKey(apiHost: apiHost, owner: owner, name: name)
        return self.memory[key] ?? RepoDetailCache()
    }

    func save(_ cache: RepoDetailCache, apiHost: URL, owner: String, name: String) {
        self.loadIfNeeded()
        let key = Self.cacheKey(apiHost: apiHost, owner: owner, name: name)
        self.memory[key] = cache
        self.isDirty = true
        self.scheduleFlush()
    }

    /// Actor isolation keeps snapshot encoding and file IO off the main actor.
    func flush() {
        self.flushTask?.cancel()
        self.flushTask = nil
        guard self.isDirty else { return }

        if self.diskStore.save(self.memory) {
            self.isDirty = false
        } else {
            self.scheduleFlush()
        }
    }

    private func loadIfNeeded() {
        guard !self.hasLoaded else { return }

        self.memory = self.diskStore.load()
        self.hasLoaded = true
    }

    private func scheduleFlush() {
        guard self.flushTask == nil else { return }

        let delay = self.flushDelay
        // Anchor to the first dirty save so ongoing refreshes cannot starve persistence.
        self.flushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            await self?.flush()
        }
    }

    /// Capability cache: use TTL so newly-enabled discussions can reappear without a manual reset.
    func discussionsEnabled(
        apiHost: URL,
        owner: String,
        name: String,
        now: Date,
        ttl: TimeInterval
    ) -> Bool? {
        let cache = self.load(apiHost: apiHost, owner: owner, name: name)
        guard let enabled = cache.discussionsEnabled, let checkedAt = cache.discussionsCheckedAt else { return nil }
        guard now.timeIntervalSince(checkedAt) <= ttl else { return nil }

        return enabled
    }

    func updateDiscussionsEnabled(
        apiHost: URL,
        owner: String,
        name: String,
        enabled: Bool,
        checkedAt: Date
    ) -> Bool {
        var cache = self.load(apiHost: apiHost, owner: owner, name: name)
        let hasChanged = cache.discussionsEnabled != enabled
            || cache.discussionsCheckedAt != checkedAt
        cache.discussionsEnabled = enabled
        cache.discussionsCheckedAt = checkedAt
        if hasChanged {
            self.save(cache, apiHost: apiHost, owner: owner, name: name)
        }
        return hasChanged
    }

    func clear() {
        self.flushTask?.cancel()
        self.flushTask = nil
        self.memory = [:]
        self.hasLoaded = true
        self.isDirty = false
        self.diskStore.clear()
    }

    private static func cacheKey(apiHost: URL, owner: String, name: String) -> String {
        let host = apiHost.host ?? "api.github.com"
        return "\(host)::\(owner)/\(name)"
    }
}

struct RepoDetailCachePolicy {
    var openPullsTTL: TimeInterval
    var ciTTL: TimeInterval
    var activityTTL: TimeInterval
    var trafficTTL: TimeInterval
    var heatmapTTL: TimeInterval
    var releaseTTL: TimeInterval

    static let `default` = RepoDetailCachePolicy(
        openPullsTTL: RepoDetailCacheConstants.openPullsTTL,
        ciTTL: RepoDetailCacheConstants.ciTTL,
        activityTTL: RepoDetailCacheConstants.activityTTL,
        trafficTTL: RepoDetailCacheConstants.trafficTTL,
        heatmapTTL: RepoDetailCacheConstants.heatmapTTL,
        releaseTTL: RepoDetailCacheConstants.releaseTTL
    )

    func state(for cache: RepoDetailCache, now: Date) -> RepoDetailCacheState {
        RepoDetailCacheState(
            openPulls: self.freshness(lastFetched: cache.openPullsFetchedAt, now: now, ttl: self.openPullsTTL),
            ci: self.freshness(lastFetched: cache.ciFetchedAt, now: now, ttl: self.ciTTL),
            activity: self.freshness(lastFetched: cache.activityFetchedAt, now: now, ttl: self.activityTTL),
            traffic: self.freshness(lastFetched: cache.trafficFetchedAt, now: now, ttl: self.trafficTTL),
            heatmap: self.freshness(lastFetched: cache.heatmapFetchedAt, now: now, ttl: self.heatmapTTL),
            release: self.freshness(lastFetched: cache.releaseFetchedAt, now: now, ttl: self.releaseTTL)
        )
    }

    private func freshness(lastFetched: Date?, now: Date, ttl: TimeInterval) -> CacheFreshness {
        guard let lastFetched else { return .missing }
        guard now.timeIntervalSince(lastFetched) >= ttl else { return .fresh }

        return .stale
    }
}
