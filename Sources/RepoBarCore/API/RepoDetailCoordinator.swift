import Foundation

public struct RepositoryDetailOptions: Sendable {
    public let fetchHeatmap: Bool

    public init(fetchHeatmap: Bool = true) {
        self.fetchHeatmap = fetchHeatmap
    }

    public static let `default` = RepositoryDetailOptions()
}

actor RepoDetailCoordinator {
    private var store: RepoDetailStore
    private let policy: RepoDetailCachePolicy
    private let restAPI: GitHubRestAPI
    private let graphQL: GraphQLClient
    private let logger = RepoBarLogging.logger("repo-capability")

    init(
        restAPI: GitHubRestAPI,
        graphQL: GraphQLClient,
        policy: RepoDetailCachePolicy,
        store: RepoDetailStore = RepoDetailStore()
    ) {
        self.restAPI = restAPI
        self.graphQL = graphQL
        self.policy = policy
        self.store = store
    }

    func fullRepository(owner: String, name: String, options: RepositoryDetailOptions = .default) async throws -> Repository {
        var accumulator = RepoErrorAccumulator()

        let details: RepoItem
        do {
            details = try await self.restAPI.repoDetails(owner: owner, name: name)
        } catch {
            accumulator.absorb(error)
            return Repository.placeholder(
                owner: owner,
                name: name,
                error: accumulator.message,
                rateLimitedUntil: accumulator.rateLimit
            )
        }

        let now = Date()
        let resolvedOwner = details.owner.login
        let resolvedName = details.name
        let apiHost = await self.restAPI.apiHost()
        var cache = self.store.load(apiHost: apiHost, owner: resolvedOwner, name: resolvedName)
        var didUpdateCache = false
        if let discussionsEnabled = details.hasDiscussions {
            if cache.discussionsEnabled != discussionsEnabled {
                self.logger.info(
                    "Discussions capability \(discussionsEnabled ? "enabled" : "disabled") for \(resolvedOwner)/\(resolvedName) source=repoDetails"
                )
            }
            cache.discussionsEnabled = discussionsEnabled
            cache.discussionsCheckedAt = now
            didUpdateCache = true
        }
        let cacheState = self.policy.state(for: cache, now: now)
        let cachedCiDetails = cache.ciDetails ?? CIStatusDetails(status: .unknown, runCount: nil)
        let cachedActivitySnapshot = Self.cachedActivitySnapshot(
            latest: cache.latestActivity,
            events: cache.activityEvents ?? []
        )
        let cachedActivity = cachedActivitySnapshot.latest
        let cachedActivityEvents = cachedActivitySnapshot.events
        let cachedTraffic = cache.traffic
        let cachedHeatmap = cache.heatmap ?? []

        let shouldFetchPulls = cacheState.openPulls.needsRefresh
        let shouldFetchCI = cacheState.ci.needsRefresh
        let shouldFetchActivity = cacheState.activity.needsRefresh
        let shouldFetchTraffic = cacheState.traffic.needsRefresh
        let shouldFetchHeatmap = options.fetchHeatmap && cacheState.heatmap.needsRefresh
        let shouldFetchRelease = cacheState.release.needsRefresh
        let shouldFetchSummary = shouldFetchPulls || shouldFetchRelease

        // Run all expensive lookups in parallel; individual failures are folded into the accumulator.
        let restAPI = self.restAPI
        let graphQL = self.graphQL
        async let summaryResult: Result<RepoSummary?, Error> = shouldFetchSummary
            ? Self.capture { try await graphQL.repoSummary(owner: resolvedOwner, name: resolvedName) }
            : .success(nil)
        async let ciResult: Result<CIStatusDetails, Error> = shouldFetchCI
            ? Self.capture { try await restAPI.ciStatus(owner: resolvedOwner, name: resolvedName) }
            : .success(cachedCiDetails)
        async let activityResult: Result<ActivitySnapshot, Error> = shouldFetchActivity
            ? Self.capture { try await restAPI.recentActivity(owner: resolvedOwner, name: resolvedName, limit: 25) }
            : .success(ActivitySnapshot(events: cachedActivityEvents, latest: cachedActivity))
        async let trafficResult: Result<TrafficStats?, Error> = shouldFetchTraffic
            ? Self.capture { try await restAPI.trafficStats(owner: resolvedOwner, name: resolvedName) }
            : .success(cachedTraffic)
        async let heatmapResult: Result<[HeatmapCell], Error> = shouldFetchHeatmap
            ? Self.capture { try await restAPI.commitHeatmap(owner: resolvedOwner, name: resolvedName) }
            : .success(cachedHeatmap)
        let summary: RepoSummary?
        switch await summaryResult {
        case let .success(value):
            summary = value
        case let .failure(error):
            accumulator.absorb(error)
            summary = nil
        }

        let openPulls: Int
        if let summary, shouldFetchPulls {
            openPulls = summary.openPulls
            cache.openPulls = summary.openPulls
            cache.openPullsFetchedAt = now
            didUpdateCache = true
        } else {
            openPulls = cache.openPulls ?? 0
        }
        let issues = summary?.openIssues ?? max(details.openIssuesCount - openPulls, 0)

        let ciDetails: CIStatusDetails?
        switch await ciResult {
        case let .success(value):
            ciDetails = value
            if shouldFetchCI {
                cache.ciDetails = value
                cache.ciFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            ciDetails = cache.ciDetails
        }
        let ci = ciDetails?.status ?? .unknown
        let ciRunCount = ciDetails?.runCount

        let activity: ActivityEvent?
        let activityEvents: [ActivityEvent]
        switch await activityResult {
        case let .success(snapshot):
            activity = snapshot.latest ?? snapshot.events.first
            activityEvents = snapshot.events
            if shouldFetchActivity {
                cache.latestActivity = activity
                cache.activityEvents = snapshot.events
                cache.activityFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            activity = cache.latestActivity
            activityEvents = cache.activityEvents ?? []
        }

        let traffic: TrafficStats?
        switch await trafficResult {
        case let .success(value):
            traffic = value
            if shouldFetchTraffic {
                cache.traffic = value
                cache.trafficFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            traffic = cache.traffic
        }

        let heatmap: [HeatmapCell]
        switch await heatmapResult {
        case let .success(value):
            heatmap = value
            if shouldFetchHeatmap {
                cache.heatmap = value
                cache.heatmapFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            heatmap = cache.heatmap ?? []
        }

        let releaseREST: Release?
        if let summary, shouldFetchRelease {
            releaseREST = summary.release
            cache.latestRelease = summary.release
            cache.releaseFetchedAt = now
            didUpdateCache = true
        } else {
            releaseREST = cache.latestRelease
        }

        let finalCacheState = self.policy.state(for: cache, now: now)
        if didUpdateCache {
            self.store.save(cache, apiHost: apiHost, owner: resolvedOwner, name: resolvedName)
        }

        return Repository.from(
            item: details,
            openPulls: openPulls,
            issues: issues,
            ciStatus: ci,
            ciRunCount: ciRunCount,
            latestRelease: releaseREST,
            latestActivity: activity,
            activityEvents: activityEvents,
            traffic: traffic,
            heatmap: heatmap,
            error: accumulator.message,
            rateLimitedUntil: accumulator.rateLimit,
            detailCacheState: finalCacheState,
            discussionsEnabled: cache.discussionsEnabled
        )
    }

    func cachedRepositories(from items: [RepoItem], now: Date = Date()) async -> [Repository] {
        let apiHost = await self.restAPI.apiHost()
        return items.compactMap { self.cachedRepository(from: $0, apiHost: apiHost, now: now) }
    }

    private func cachedRepository(from item: RepoItem, apiHost: URL, now: Date) -> Repository? {
        let cache = self.store.load(apiHost: apiHost, owner: item.owner.login, name: item.name)
        let cacheState = self.policy.state(for: cache, now: now)
        guard let openPulls = cache.openPulls else {
            return Repository.from(item: item, detailCacheState: cacheState)
        }

        let ciDetails = cache.ciDetails
        let activitySnapshot = Self.cachedActivitySnapshot(
            latest: cache.latestActivity,
            events: cache.activityEvents ?? []
        )
        return Repository.from(
            item: item,
            openPulls: openPulls,
            issues: max(item.openIssuesCount - openPulls, 0),
            ciStatus: ciDetails?.status ?? .unknown,
            ciRunCount: ciDetails?.runCount,
            latestRelease: cache.latestRelease,
            latestActivity: activitySnapshot.latest,
            activityEvents: activitySnapshot.events,
            traffic: cache.traffic,
            heatmap: cache.heatmap ?? [],
            detailCacheState: cacheState,
            discussionsEnabled: cache.discussionsEnabled
        )
    }

    func clearCache() {
        self.logger.info("Clearing repo detail cache (disk + memory)")
        self.store.clear()
    }

    func cachedDiscussionsEnabled(
        owner: String,
        name: String,
        now: Date = Date(),
        ttl: TimeInterval = RepoDetailCacheConstants.discussionsCapabilityTTL
    ) async -> Bool? {
        let apiHost = await self.restAPI.apiHost()
        return self.store.discussionsEnabled(
            apiHost: apiHost,
            owner: owner,
            name: name,
            now: now,
            ttl: ttl
        )
    }

    func updateDiscussionsCapability(
        owner: String,
        name: String,
        enabled: Bool,
        checkedAt: Date = Date(),
        source: String
    ) async {
        let apiHost = await self.restAPI.apiHost()
        let updated = self.store.updateDiscussionsEnabled(
            apiHost: apiHost,
            owner: owner,
            name: name,
            enabled: enabled,
            checkedAt: checkedAt
        )
        if updated {
            self.logger.info(
                "Discussions capability \(enabled ? "enabled" : "disabled") for \(owner)/\(name) source=\(source)"
            )
        }
    }

    func updateDiscussionsCapability(
        from items: [RepoItem],
        checkedAt: Date = Date(),
        source: String
    ) async {
        let apiHost = await self.restAPI.apiHost()
        var updatedCount = 0
        for item in items {
            guard let enabled = item.hasDiscussions else { continue }

            if self.store.updateDiscussionsEnabled(
                apiHost: apiHost,
                owner: item.owner.login,
                name: item.name,
                enabled: enabled,
                checkedAt: checkedAt
            ) {
                updatedCount += 1
            }
        }
        if updatedCount > 0 {
            self.logger.info("Updated discussions capability for \(updatedCount) repos source=\(source)")
        }
    }

    private static func capture<T>(_ work: @escaping @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }

    static func cachedActivitySnapshot(latest: ActivityEvent?, events: [ActivityEvent]) -> ActivitySnapshot {
        let sorted = events.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.date == rhs.element.date {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.date > rhs.element.date
            }
            .map(\.element)
        return ActivitySnapshot(events: sorted, latest: sorted.first ?? latest)
    }
}
