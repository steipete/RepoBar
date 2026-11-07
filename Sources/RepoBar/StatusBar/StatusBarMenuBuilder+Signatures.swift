import AppKit
import RepoBarCore

struct MainMenuPlan {
    let repos: [RepositoryDisplayModel]
    let signature: MenuBuildSignature
}

struct MenuBuildSignature: Hashable {
    let attention: AccountAttention
    let account: AccountSignature
    let settings: MenuSettingsSignature
    let isLightAppearance: Bool
    let hasLoadedRepositories: Bool
    let rateLimitReset: Date?
    let rateLimits: RateLimitMenuSignature
    let lastError: String?
    let contribution: ContributionSignature
    let globalActivity: ActivitySignature
    let globalCommits: CommitSignature
    let heatmapRangeStart: TimeInterval
    let heatmapRangeEnd: TimeInterval
    let reposDigest: Int
    let actionsDigest: Int
    let timeBucket: Int
}

struct RateLimitMenuSignature: Hashable {
    let authMethod: AuthMethod?
    let reset: Date?
    let lastError: String?
    let restResource: String?
    let restRemaining: Int?
    let restLimit: Int?
    let restReset: Date?
    let graphQLResource: String?
    let graphQLRemaining: Int?
    let graphQLLimit: Int?
    let graphQLReset: Date?
    let graphQLBlockedUntil: Date?
    let liveResources: [LiveRateLimitResourceSignature]
    let endpointCooldowns: [EndpointCooldownSignature]
    let cachedResponses: [CachedRateLimitSignature]
    let activeLimits: [ActiveRateLimitSignature]

    init(_ diagnostics: DiagnosticsSummary) {
        self.init(RateLimitDisplayState(diagnostics: diagnostics))
    }

    init(_ state: RateLimitDisplayState) {
        let diagnostics = state.diagnostics
        self.authMethod = state.authMethod
        self.reset = diagnostics.rateLimitReset
        self.lastError = diagnostics.lastRateLimitError
        self.restResource = diagnostics.restRateLimit?.resource
        self.restRemaining = diagnostics.restRateLimit?.remaining
        self.restLimit = diagnostics.restRateLimit?.limit
        self.restReset = diagnostics.restRateLimit?.reset
        self.graphQLResource = diagnostics.graphQLRateLimit?.resource
        self.graphQLRemaining = diagnostics.graphQLRateLimit?.remaining
        self.graphQLLimit = diagnostics.graphQLRateLimit?.limit
        self.graphQLReset = diagnostics.graphQLRateLimit?.reset
        self.graphQLBlockedUntil = diagnostics.graphQLRateLimitReset
        self.liveResources = diagnostics.rateLimitResources?.resources
            .map { resource, snapshot in
                LiveRateLimitResourceSignature(resource: resource, snapshot: snapshot)
            }
            .sorted { $0.resource < $1.resource } ?? []
        self.endpointCooldowns = diagnostics.endpointCooldowns.map(EndpointCooldownSignature.init)
        self.cachedResponses = state.cacheSummary
            .map(RateLimitStatusFormatter.observedRateLimitRows(from:))?
            .map(CachedRateLimitSignature.init) ?? []
        self.activeLimits = state.cacheSummary?.rateLimits.map(ActiveRateLimitSignature.init) ?? []
    }
}

struct LiveRateLimitResourceSignature: Hashable {
    let resource: String
    let remaining: Int?
    let limit: Int?
    let reset: Date?

    init(resource: String, snapshot: RateLimitSnapshot) {
        self.resource = resource
        self.remaining = snapshot.remaining
        self.limit = snapshot.limit
        self.reset = snapshot.reset
    }
}

struct EndpointCooldownSignature: Hashable {
    let endpoint: String
    let repository: String?
    let url: String
    let retryAfter: Date

    init(_ cooldown: EndpointCooldownSummary) {
        self.endpoint = cooldown.endpoint
        self.repository = cooldown.repository
        self.url = cooldown.url
        self.retryAfter = cooldown.retryAfter
    }
}

struct CachedRateLimitSignature: Hashable {
    let resource: String?
    let remaining: Int?
    let limit: Int?
    let reset: Date?

    init(_ row: RepoBarCachedResponseSummary) {
        self.resource = row.rateLimitResource
        self.remaining = row.rateLimitRemaining
        self.limit = row.rateLimitLimit
        self.reset = row.rateLimitReset
    }
}

struct ActiveRateLimitSignature: Hashable {
    let resource: String
    let remaining: Int?
    let reset: Date
    let lastError: String?

    init(_ row: RepoBarRateLimitSummary) {
        self.resource = row.resource
        self.remaining = row.remaining
        self.reset = row.resetAt
        self.lastError = row.lastError
    }
}

struct ActionsSnapshotSignature: Hashable {
    let org: String
    let planTier: GitHubPlanTier
    let isOrg: Bool
    let minutesUsed: Int?
    let minutesIncluded: Int?
    let runnerCount: Int
    let onlineRunners: Int
    let busyRunners: Int
    let displayedRunners: [DisplayedRunnerSignature]
    let runnerScannedRepositoryCount: Int
    let runnerTotalRepositoryCount: Int
    let inProgressJobs: Int
    let queuedJobs: Int
    let runIDs: [Int]
    let cacheSizeBytes: Int?
    let cacheCount: Int?
    let retentionDays: Int?

    init(_ snapshot: ActionsOrgSnapshot) {
        self.org = snapshot.org
        self.planTier = snapshot.planTier
        self.isOrg = snapshot.isOrg
        self.minutesUsed = snapshot.minutesUsed
        self.minutesIncluded = snapshot.minutesIncluded
        self.runnerCount = snapshot.runners?.totalCount ?? 0
        self.onlineRunners = snapshot.runners?.onlineCount ?? 0
        self.busyRunners = snapshot.runners?.busyCount ?? 0
        self.displayedRunners = snapshot.runners?.runners.prefix(10).map(DisplayedRunnerSignature.init) ?? []
        self.runnerScannedRepositoryCount = snapshot.runners?.scannedRepositoryCount ?? 0
        self.runnerTotalRepositoryCount = snapshot.runners?.totalRepositoryCount ?? 0
        self.inProgressJobs = snapshot.queueStatus?.inProgressCount ?? 0
        self.queuedJobs = snapshot.queueStatus?.queuedCount ?? 0
        self.runIDs = snapshot.queueStatus?.runs.map(\.id) ?? []
        self.cacheSizeBytes = snapshot.cacheUsage?.totalCachesSizeBytes
        self.cacheCount = snapshot.cacheUsage?.totalCachesCount
        self.retentionDays = snapshot.artifactRetention?.retentionDays
    }

    static func digest(for snapshots: [ActionsOrgSnapshot]) -> Int {
        var hasher = Hasher()
        snapshots.map(Self.init).forEach { hasher.combine($0) }
        return hasher.finalize()
    }
}

struct DisplayedRunnerSignature: Hashable {
    let id: Int
    let name: String
    let os: String
    let status: String
    let busy: Bool
    let labels: [String]

    init(_ runner: RunnerSummary) {
        self.id = runner.id
        self.name = runner.name
        self.os = runner.os
        self.status = runner.status
        self.busy = runner.busy
        self.labels = Array(runner.labels.prefix(3))
    }
}

struct AccountSignature: Hashable {
    let state: String
    let user: String?
    let host: String?

    init(_ account: AccountState) {
        switch account {
        case let .credentialsUnavailable(user):
            self.state = "credentialsUnavailable"
            self.user = user?.username
            self.host = user?.host.host
        case .loggedOut:
            self.state = "loggedOut"
            self.user = nil
            self.host = nil
        case .loggingIn:
            self.state = "loggingIn"
            self.user = nil
            self.host = nil
        case let .loggedIn(user):
            self.state = "loggedIn"
            self.user = user.username
            self.host = user.host.host
        }
    }
}

struct MenuSettingsSignature: Hashable {
    let showContributionHeader: Bool
    let cardDensity: CardDensity
    let accentTone: AccentTone
    let activityScope: GlobalActivityScope
    let heatmapDisplay: HeatmapDisplay
    let heatmapSpan: HeatmapSpan
    let displayLimit: Int
    let showForks: Bool
    let showArchived: Bool
    let showDirtyFilesInMenu: Bool
    let menuSortKey: RepositorySortKey
    let pinned: [String]
    let hidden: [String]
    let selection: MenuRepoSelection
    let menuCustomization: MenuCustomization

    init(settings: UserSettings, selection: MenuRepoSelection) {
        self.showContributionHeader = settings.appearance.showContributionHeader
        self.cardDensity = settings.appearance.cardDensity
        self.accentTone = settings.appearance.accentTone
        self.activityScope = settings.appearance.activityScope
        self.heatmapDisplay = settings.heatmap.display
        self.heatmapSpan = settings.heatmap.span
        self.displayLimit = settings.repoList.displayLimit
        self.showForks = settings.repoList.showForks
        self.showArchived = settings.repoList.showArchived
        self.showDirtyFilesInMenu = settings.localProjects.showDirtyFilesInMenu
        self.menuSortKey = settings.repoList.menuSortKey
        self.pinned = settings.repoList.pinnedRepositories
        self.hidden = settings.repoList.hiddenRepositories
        self.selection = selection
        self.menuCustomization = settings.menuCustomization.normalized()
    }
}

struct ContributionSignature: Hashable {
    let user: String?
    let error: String?
    let heatmapCount: Int
}

struct ActivitySignature: Hashable {
    let count: Int
    let latestDate: Date?
    let error: String?

    init(events: [ActivityEvent], error: String?) {
        self.count = events.count
        self.latestDate = events.first?.date
        self.error = error
    }
}

struct CommitSignature: Hashable {
    let count: Int
    let latestDate: Date?
    let error: String?

    init(commits: [RepoCommitSummary], error: String?) {
        self.count = commits.count
        self.latestDate = commits.first?.authoredAt
        self.error = error
    }
}

struct RepoSignature: Hashable {
    let fullName: String
    let ciStatus: CIStatus
    let ciRunCount: Int?
    let issues: Int
    let pulls: Int
    let stars: Int
    let forks: Int
    let pushedAt: Date?
    let latestReleaseTag: String?
    let latestActivityDate: Date?
    let activityEventCount: Int
    let trafficVisitors: Int?
    let trafficCloners: Int?
    let heatmapCount: Int
    let error: String?
    let rateLimitedUntil: Date?
    let localBranch: String?
    let localSyncState: LocalSyncState?
    let localDirtySummary: String?
    let localDirtyFilesDigest: Int?

    static func digest(for repos: [RepositoryDisplayModel]) -> Int {
        var hasher = Hasher()
        repos.map(Self.init).forEach { hasher.combine($0) }
        return hasher.finalize()
    }

    init(_ repo: RepositoryDisplayModel) {
        self.fullName = repo.title
        self.ciStatus = repo.ciStatus
        self.ciRunCount = repo.ciRunCount
        self.issues = repo.issues
        self.pulls = repo.pulls
        self.stars = repo.stars
        self.forks = repo.forks
        self.pushedAt = repo.source.stats.pushedAt
        self.latestReleaseTag = repo.source.latestRelease?.tag
        self.latestActivityDate = repo.source.latestActivity?.date
        self.activityEventCount = repo.activityEvents.count
        self.trafficVisitors = repo.trafficVisitors
        self.trafficCloners = repo.trafficCloners
        self.heatmapCount = repo.heatmap.count
        self.error = repo.error
        self.rateLimitedUntil = repo.rateLimitedUntil
        self.localBranch = repo.localStatus?.branch
        self.localSyncState = repo.localStatus?.syncState
        self.localDirtySummary = repo.localStatus?.dirtyCounts?.summary
        self.localDirtyFilesDigest = repo.localStatus.map { RepoSignature.digest(files: $0.dirtyFiles) }
    }

    static func digest(files: [String]) -> Int {
        var hasher = Hasher()
        for file in files {
            hasher.combine(file)
        }
        return hasher.finalize()
    }
}

struct RepoSubmenuCacheEntry {
    let menu: NSMenu
    let signature: RepoSubmenuSignature
}

struct RepoRecentCountSignature: Hashable {
    let commits: Int?
    let commitsDigest: Int?
}

struct RepoSubmenuSignature: Hashable {
    let fullName: String
    let issues: Int
    let pulls: Int
    let ciRunCount: Int?
    let activityURLPresent: Bool
    let localPath: String?
    let localBranch: String?
    let localWorktreeName: String?
    let localSyncState: LocalSyncState?
    let localDirtySummary: String?
    let localDirtyFilesDigest: Int?
    let localUpstream: String?
    let localLastFetchAt: TimeInterval?
    let trafficVisitors: Int?
    let trafficCloners: Int?
    let heatmapDisplay: HeatmapDisplay
    let heatmapCount: Int
    let heatmapRangeStart: TimeInterval
    let heatmapRangeEnd: TimeInterval
    let accentTone: AccentTone
    let activityDigest: Int
    let recentCounts: RepoRecentCountSignature
    let changelogPresentation: ChangelogRowPresentation?
    let changelogHeadline: String?
    let isPinned: Bool
    let menuCustomization: MenuCustomization
    let isLightAppearance: Bool

    init(
        repo: RepositoryDisplayModel,
        settings: UserSettings,
        heatmapRange: HeatmapRange,
        recentCounts: RepoRecentCountSignature,
        changelogPresentation: ChangelogRowPresentation?,
        changelogHeadline: String?,
        isPinned: Bool,
        isLightAppearance: Bool
    ) {
        self.fullName = repo.title
        self.issues = repo.issues
        self.pulls = repo.pulls
        self.ciRunCount = repo.ciRunCount
        self.activityURLPresent = repo.activityURL != nil
        self.localPath = repo.localStatus?.path.path
        self.localBranch = repo.localStatus?.branch
        self.localWorktreeName = repo.localStatus?.worktreeName
        self.localSyncState = repo.localStatus?.syncState
        self.localDirtySummary = repo.localStatus?.dirtyCounts?.summary
        self.localDirtyFilesDigest = repo.localStatus.map { RepoSignature.digest(files: $0.dirtyFiles) }
        self.localUpstream = repo.localStatus?.upstreamBranch
        self.localLastFetchAt = repo.localStatus?.lastFetchAt?.timeIntervalSinceReferenceDate
        self.trafficVisitors = repo.trafficVisitors
        self.trafficCloners = repo.trafficCloners
        self.heatmapDisplay = settings.heatmap.display
        self.heatmapCount = repo.heatmap.count
        self.heatmapRangeStart = heatmapRange.start.timeIntervalSinceReferenceDate
        self.heatmapRangeEnd = heatmapRange.end.timeIntervalSinceReferenceDate
        self.accentTone = settings.appearance.accentTone
        self.activityDigest = RepoSubmenuSignature.digest(events: repo.activityEvents)
        self.recentCounts = recentCounts
        self.changelogPresentation = changelogPresentation
        self.changelogHeadline = changelogHeadline
        self.isPinned = isPinned
        self.menuCustomization = settings.menuCustomization.normalized()
        self.isLightAppearance = isLightAppearance
    }

    private static func digest(events: [ActivityEvent]) -> Int {
        var hasher = Hasher()
        for event in events.prefix(10) {
            hasher.combine(event.title)
            hasher.combine(event.actor)
            hasher.combine(event.date.timeIntervalSinceReferenceDate)
            hasher.combine(event.eventType ?? "")
        }
        return hasher.finalize()
    }
}
