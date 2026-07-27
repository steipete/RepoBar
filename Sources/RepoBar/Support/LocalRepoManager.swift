import Foundation
import RepoBarCore

actor LocalRepoManager {
    private let notifier = LocalSyncNotifier.shared
    private let discoveryCacheTTL: TimeInterval = AppLimits.LocalRepo.discoveryCacheTTL
    private let statusCacheTTL: TimeInterval = AppLimits.LocalRepo.statusCacheTTL
    private var discoveryCache: [String: DiscoveryCacheEntry] = [:]
    private var statusCache: [String: StatusCacheEntry] = [:]
    private var lastFetchByPath: [String: Date] = [:]

    struct SnapshotResult {
        let discoveredCount: Int
        let repoIndex: LocalRepoIndex
        let accessDenied: Bool
    }

    struct SnapshotOptions {
        let autoSyncEnabled: Bool
        let fetchInterval: TimeInterval
        let preferredPathsByFullName: [String: String]
        let matchRepoNames: Set<String>
        let forceRescan: Bool
        let maxDepth: Int
        let allowNetworkOperations: Bool

        init(
            autoSyncEnabled: Bool,
            fetchInterval: TimeInterval,
            preferredPathsByFullName: [String: String],
            matchRepoNames: Set<String>,
            forceRescan: Bool,
            maxDepth: Int,
            allowNetworkOperations: Bool = false
        ) {
            self.autoSyncEnabled = autoSyncEnabled
            self.fetchInterval = fetchInterval
            self.preferredPathsByFullName = preferredPathsByFullName
            self.matchRepoNames = matchRepoNames
            self.forceRescan = forceRescan
            self.maxDepth = maxDepth
            self.allowNetworkOperations = allowNetworkOperations
        }
    }

    func snapshot(
        rootPath: String?,
        rootBookmarkData: Data?,
        options: SnapshotOptions
    ) async -> SnapshotResult {
        guard let rootPath,
              rootPath.isEmpty == false
        else {
            return SnapshotResult(discoveredCount: 0, repoIndex: .empty, accessDenied: false)
        }

        let now = Date()

        let fallbackURL = URL(fileURLWithPath: PathFormatter.expandTilde(rootPath), isDirectory: true)
        let resolvedBookmark = rootBookmarkData.flatMap(SecurityScopedBookmark.resolve)

        // Try security-scoped bookmark first, fall back to direct path access
        let (scopedURL, didStart): (URL, Bool) = {
            if let resolved = resolvedBookmark {
                let started = resolved.startAccessingSecurityScopedResource()
                if started {
                    return (resolved, true)
                }
            }
            // Bookmark failed or didn't start - try fallback URL directly
            return (fallbackURL, false)
        }()

        defer {
            if didStart {
                scopedURL.stopAccessingSecurityScopedResource()
            }
        }

        // Only return accessDenied if we truly cannot access the folder
        let canAccess = didStart || FileManager.default.isReadableFile(atPath: scopedURL.path)
        if !canAccess {
            return SnapshotResult(discoveredCount: 0, repoIndex: .empty, accessDenied: true)
        }

        // Security-scoped bookmarks can resolve to file reference URLs (`/.file/id=…`).
        // FileManager APIs expect a path-based file URL for traversal.
        let rootURL = (scopedURL as NSURL).filePathURL ?? scopedURL
        let resolvedRoot = rootURL.resolvingSymlinksInPath().path

        let repoRoots = self.discoverRepoRoots(
            rootURL: rootURL,
            resolvedRoot: resolvedRoot,
            now: now,
            forceRescan: options.forceRescan,
            maxDepth: options.maxDepth
        )

        let (cachedStatuses, refreshRoots) = self.partitionStatusesToRefresh(
            repoRoots: repoRoots,
            now: now,
            options: options
        )

        let fetchTargets = self.fetchTargets(
            repoRoots: refreshRoots,
            fetchInterval: options.allowNetworkOperations ? options.fetchInterval : 0,
            now: now
        )

        let refreshedSnapshot = await LocalProjectsService().snapshot(
            repoRoots: refreshRoots,
            autoSyncEnabled: options.allowNetworkOperations && options.autoSyncEnabled,
            includeOnlyRepoNames: nil,
            concurrencyLimit: AppLimits.LocalRepo.snapshotConcurrencyLimit,
            fetchTargets: fetchTargets
        )

        for path in refreshedSnapshot.fetchedPaths {
            self.lastFetchByPath[path.path] = now
        }

        let enrichedRefreshed = refreshedSnapshot.statuses.map { status in
            status.withLastFetch(self.lastFetchByPath[status.path.path])
        }

        for status in enrichedRefreshed {
            self.statusCache[status.path.path] = StatusCacheEntry(status: status, updatedAt: now)
        }

        for status in refreshedSnapshot.syncAttemptedStatuses {
            await self.notifier.notifySync(for: status)
        }

        let enrichedCached = cachedStatuses.map { status in
            status.withLastFetch(self.lastFetchByPath[status.path.path])
        }
        let allStatuses = enrichedCached + enrichedRefreshed
        return SnapshotResult(
            discoveredCount: repoRoots.count,
            repoIndex: LocalRepoIndex(
                statuses: allStatuses,
                preferredPathsByFullName: options.preferredPathsByFullName
            ),
            accessDenied: false
        )
    }

    private struct DiscoveryCacheEntry {
        let repoRoots: [URL]
        let discoveredAt: Date
    }

    private struct StatusCacheEntry {
        let status: LocalRepoStatus
        let updatedAt: Date
    }

    private func discoverRepoRoots(
        rootURL: URL,
        resolvedRoot: String,
        now: Date,
        forceRescan: Bool,
        maxDepth: Int
    ) -> [URL] {
        if forceRescan == false, let cached = self.discoveryCache[resolvedRoot] {
            if now.timeIntervalSince(cached.discoveredAt) < self.discoveryCacheTTL {
                return cached.repoRoots
            }
        }

        let roots = LocalProjectsService().discoverRepoRoots(
            rootURL: rootURL,
            maxDepth: max(1, maxDepth)
        )
        self.discoveryCache[resolvedRoot] = DiscoveryCacheEntry(repoRoots: roots, discoveredAt: now)
        return roots
    }

    private func partitionStatusesToRefresh(
        repoRoots: [URL],
        now: Date,
        options: SnapshotOptions
    ) -> (cached: [LocalRepoStatus], refresh: [URL]) {
        guard repoRoots.isEmpty == false else { return ([], []) }

        let matchKeys = Set(options.matchRepoNames.map { $0.lowercased() })
        let matchingPaths: Set<String>
        let interesting: [URL]
        if !matchKeys.isEmpty, options.forceRescan == false {
            let matching = repoRoots.filter { matchKeys.contains($0.lastPathComponent.lowercased()) }
            matchingPaths = Set(matching.map(\.path))

            let cachedNonMatching = repoRoots.filter { repoURL in
                matchingPaths.contains(repoURL.path) == false && self.statusCache[repoURL.path] != nil
            }
            interesting = matching + cachedNonMatching
        } else {
            matchingPaths = Set(repoRoots.map(\.path))
            interesting = repoRoots
        }

        var cached: [LocalRepoStatus] = []
        var refresh: [URL] = []
        cached.reserveCapacity(interesting.count)
        refresh.reserveCapacity(interesting.count)

        for repoURL in interesting {
            let key = repoURL.path
            guard let entry = self.statusCache[key] else {
                if matchingPaths.contains(key) {
                    refresh.append(repoURL)
                }
                continue
            }

            if matchingPaths.contains(key) == false {
                cached.append(entry.status)
                continue
            }

            if options.forceRescan {
                refresh.append(repoURL)
                continue
            }

            if options.allowNetworkOperations, options.autoSyncEnabled, entry.status.canAutoSync {
                refresh.append(repoURL)
                continue
            }

            let shouldFetch = options.allowNetworkOperations
                && options.fetchInterval > 0
                && self.needsFetch(for: repoURL, now: now, interval: options.fetchInterval)
            if shouldFetch {
                refresh.append(repoURL)
                continue
            }

            if now.timeIntervalSince(entry.updatedAt) < self.statusCacheTTL {
                cached.append(entry.status)
            } else {
                refresh.append(repoURL)
            }
        }

        return (cached, refresh)
    }

    private func needsFetch(for repoURL: URL, now: Date, interval: TimeInterval) -> Bool {
        guard interval > 0 else { return false }

        let lastFetch = self.lastFetchByPath[repoURL.path]
        guard let lastFetch else { return true }

        return now.timeIntervalSince(lastFetch) >= interval
    }

    private func fetchTargets(
        repoRoots: [URL],
        fetchInterval: TimeInterval,
        now: Date
    ) -> Set<URL> {
        guard fetchInterval > 0 else { return [] }

        return Set(repoRoots.filter { self.needsFetch(for: $0, now: now, interval: fetchInterval) })
    }
}
