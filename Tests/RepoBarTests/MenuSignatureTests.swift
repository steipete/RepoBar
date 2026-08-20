import Foundation
@testable import RepoBar
@testable import RepoBarCore
import Testing

struct MenuSignatureTests {
    @MainActor
    @Test
    func `repo submenu cache preserves full name when API id differs`() {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let builder = StatusBarMenuBuilder(appState: appState, target: manager)
        let repo = Repository(
            id: "opaque-api-node-id",
            name: "Repo",
            owner: "owner",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )

        let submenu = builder.repoSubmenu(
            for: RepositoryDisplayModel(repo: repo),
            isPinned: false
        )

        let fullNameKey = AccountScopedCacheKey(accountID: "legacy", key: "owner/Repo")
        let idKey = AccountScopedCacheKey(accountID: "legacy", key: repo.id)
        #expect(builder.repoFullName(for: submenu) == "owner/Repo")
        #expect(builder.repoSubmenusByFullName[fullNameKey]?.menu === submenu)
        #expect(builder.repoSubmenusByFullName[idKey] == nil)
    }

    @MainActor
    @Test
    func `local scope does not substitute remote model from another host`() throws {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let builder = StatusBarMenuBuilder(appState: appState, target: manager)
        let repository = Self.repository(id: "remote-node", owner: "owner", name: "Repo")
        let enterpriseAccount = try Account(
            username: "alice",
            host: #require(URL(string: "https://ghe.example.com:8443")),
            authMethod: .oauth
        )
        let localStatus = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/Repo"),
            name: "Repo",
            fullName: "owner/Repo",
            remoteHost: "github.com",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        appState.session.localRepoIndex = LocalRepoIndex(statuses: [localStatus])
        appState.session.menuDisplayIndex = [
            repository.fullName.lowercased(): RepositoryDisplayModel(repo: repository)
        ]
        appState.session.settings.accounts = [enterpriseAccount]
        appState.session.settings.activeAccountID = enterpriseAccount.id

        let models = builder.localScopeViewModels(
            session: appState.session,
            settings: appState.session.settings,
            now: Date()
        )

        #expect(models.count == 1)
        #expect(models.first?.id == "local:/tmp/Repo")
        #expect(models.first?.localStatus?.remoteHost == "github.com")
    }

    @MainActor
    @Test
    func `local scope substitutes remote model for active Enterprise host with custom port`() throws {
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let builder = StatusBarMenuBuilder(appState: appState, target: manager)
        let repository = Self.repository(id: "remote-node", owner: "owner", name: "Repo")
        let enterpriseAccount = try Account(
            username: "alice",
            host: #require(URL(string: "https://ghe.example.com:8443")),
            authMethod: .oauth
        )
        let localStatus = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/Repo"),
            name: "Repo",
            fullName: "owner/Repo",
            remoteHost: "ghe.example.com:8443",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        appState.session.localRepoIndex = LocalRepoIndex(statuses: [localStatus])
        appState.session.menuDisplayIndex = [
            repository.fullName.lowercased(): RepositoryDisplayModel(repo: repository, localStatus: localStatus)
        ]
        appState.session.settings.accounts = [enterpriseAccount]
        appState.session.settings.activeAccountID = enterpriseAccount.id

        let models = builder.localScopeViewModels(
            session: appState.session,
            settings: appState.session.settings,
            now: Date()
        )

        #expect(models.count == 1)
        #expect(models.first?.id == repository.id)
        #expect(models.first?.localStatus?.remoteHost == "ghe.example.com:8443")
    }

    @Test
    func `repo submenu signature changes with repo counts`() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let range = HeatmapRange(start: now.addingTimeInterval(-86400), end: now)
        let settings = UserSettings()
        let repo = Repository(
            id: "1",
            name: "Repo",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 1,
            openPulls: 2,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
        let display = RepositoryDisplayModel(repo: repo, now: now)
        let signatureA = RepoSubmenuSignature(
            repo: display,
            settings: settings,
            heatmapRange: range,
            recentCounts: RepoRecentCountSignature(
                commits: nil,
                commitsDigest: nil
            ),
            changelogPresentation: nil,
            changelogHeadline: nil,
            isPinned: false
        )

        let updatedRepo = Repository(
            id: "1",
            name: "Repo",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 3,
            openPulls: 2,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
        let updatedDisplay = RepositoryDisplayModel(repo: updatedRepo, now: now)
        let signatureB = RepoSubmenuSignature(
            repo: updatedDisplay,
            settings: settings,
            heatmapRange: range,
            recentCounts: RepoRecentCountSignature(
                commits: nil,
                commitsDigest: nil
            ),
            changelogPresentation: nil,
            changelogHeadline: nil,
            isPinned: false
        )

        #expect(signatureA != signatureB)
    }

    @Test
    func `menu build signature changes with pinned repos`() {
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        var settings = UserSettings()
        settings.repoList.pinnedRepositories = []
        let repo = Repository(
            id: "2",
            name: "Other",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .passing,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
        let display = RepositoryDisplayModel(repo: repo, now: now)
        let signatureA = MenuBuildSignature(
            account: AccountSignature(.loggedOut),
            settings: MenuSettingsSignature(settings: settings, selection: .all),
            hasLoadedRepositories: true,
            rateLimitReset: nil,
            rateLimits: RateLimitMenuSignature(.empty),
            lastError: nil,
            contribution: ContributionSignature(user: nil, error: nil, heatmapCount: 0),
            globalActivity: ActivitySignature(events: [], error: nil),
            globalCommits: CommitSignature(commits: [], error: nil),
            heatmapRangeStart: now.timeIntervalSinceReferenceDate,
            heatmapRangeEnd: now.timeIntervalSinceReferenceDate,
            reposDigest: RepoSignature.digest(for: [display]),
            actionsDigest: 0,
            timeBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )

        settings.repoList.pinnedRepositories = [repo.fullName]
        let signatureB = MenuBuildSignature(
            account: AccountSignature(.loggedOut),
            settings: MenuSettingsSignature(settings: settings, selection: .all),
            hasLoadedRepositories: true,
            rateLimitReset: nil,
            rateLimits: RateLimitMenuSignature(.empty),
            lastError: nil,
            contribution: ContributionSignature(user: nil, error: nil, heatmapCount: 0),
            globalActivity: ActivitySignature(events: [], error: nil),
            globalCommits: CommitSignature(commits: [], error: nil),
            heatmapRangeStart: now.timeIntervalSinceReferenceDate,
            heatmapRangeEnd: now.timeIntervalSinceReferenceDate,
            reposDigest: RepoSignature.digest(for: [display]),
            actionsDigest: 0,
            timeBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )

        #expect(signatureA != signatureB)
    }

    @Test
    func `rate limit menu signature changes with cached remaining count`() {
        let now = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let stale = Self.cacheSummary(remaining: 3700, now: now)
        let fresh = Self.cacheSummary(remaining: 4948, now: now)

        let signatureA = RateLimitMenuSignature(RateLimitDisplayState(diagnostics: .empty, cacheSummary: stale))
        let signatureB = RateLimitMenuSignature(RateLimitDisplayState(diagnostics: .empty, cacheSummary: fresh))

        #expect(signatureA != signatureB)
    }

    @Test
    func `actions snapshot signature changes with displayed runner state`() {
        let now = Date(timeIntervalSinceReferenceDate: 4_000_000)
        let idle = Self.actionsSnapshot(
            runner: RunnerSummary(id: 1, name: "mac-mini", os: "macOS", status: "online", busy: false, labels: ["self-hosted", "macOS"]),
            now: now
        )
        let busy = Self.actionsSnapshot(
            runner: RunnerSummary(id: 1, name: "mac-mini", os: "macOS", status: "online", busy: true, labels: ["self-hosted", "macOS"]),
            now: now
        )

        #expect(ActionsSnapshotSignature.digest(for: [idle]) != ActionsSnapshotSignature.digest(for: [busy]))
    }

    private static func actionsSnapshot(runner: RunnerSummary, now: Date) -> ActionsOrgSnapshot {
        ActionsOrgSnapshot(
            org: "openclaw",
            runners: ActionsRunnerInfo(totalCount: 1, runners: [runner], fetchedAt: now),
            queueStatus: nil,
            planTier: .team,
            isOrg: true
        )
    }

    private static func cacheSummary(remaining: Int, now: Date) -> RepoBarCacheSummary {
        RepoBarCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 1,
            graphQLResponseCount: 0,
            rateLimitCount: 0,
            latestResponses: [
                RepoBarCachedResponseSummary(
                    method: "GET",
                    url: "https://api.github.com/user/repos",
                    hasETag: true,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "core",
                    rateLimitLimit: 5000,
                    rateLimitRemaining: remaining,
                    rateLimitReset: now.addingTimeInterval(600)
                )
            ],
            rateLimits: []
        )
    }

    private static func repository(id: String, owner: String, name: String) -> Repository {
        Repository(
            id: id,
            name: name,
            owner: owner,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }
}
