import Foundation
@testable import RepoBar
@testable import RepoBarCore
import Testing

struct MenuSignatureTests {
    @Test
    func `unavailable account has distinct menu signature`() {
        #expect(AccountSignature(.credentialsUnavailable(nil)) != AccountSignature(.loggedOut))
    }

    @MainActor
    @Test
    func `menu signature changes with relaunch attention and update version`() throws {
        let fixture = try CredentialFixture()
        defer { fixture.cleanUp() }
        let app = fixture.makeApp()
        let manager = StatusBarMenuManager(appState: app)
        let builder = StatusBarMenuBuilder(appState: app, target: manager)
        let now = Date(timeIntervalSinceReferenceDate: 1234)
        let original = builder.mainMenuPlan(now: now).signature
        app.session.bundleReplacement = AppBundleReplacement(version: nil)
        let unversioned = builder.mainMenuPlan(now: now).signature
        app.session.bundleReplacement = AppBundleReplacement(version: "2.0")
        let versioned = builder.mainMenuPlan(now: now).signature
        #expect(original != unversioned)
        #expect(unversioned != versioned)
    }

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

        #expect(builder.repoFullName(for: submenu) == "owner/Repo")
        #expect(builder.repoSubmenusByFullName["owner/Repo"]?.menu === submenu)
        #expect(builder.repoSubmenusByFullName[repo.id] == nil)
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
            isPinned: false,
            isLightAppearance: true
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
            isPinned: false,
            isLightAppearance: true
        )

        #expect(signatureA != signatureB)
    }

    @Test
    func `repo submenu signature changes with heatmap color`() {
        let now = Date(timeIntervalSinceReferenceDate: 1_500_000)
        let range = HeatmapRange(start: now.addingTimeInterval(-86400), end: now)
        let repo = Repository(
            id: "1",
            name: "Repo",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
        let display = RepositoryDisplayModel(repo: repo, now: now)
        func signature(_ settings: UserSettings) -> RepoSubmenuSignature {
            RepoSubmenuSignature(
                repo: display,
                settings: settings,
                heatmapRange: range,
                recentCounts: RepoRecentCountSignature(commits: nil, commitsDigest: nil),
                changelogPresentation: nil,
                changelogHeadline: nil,
                isPinned: false,
                isLightAppearance: true
            )
        }
        var settings = UserSettings()
        settings.heatmap.display = .submenu
        settings.appearance.accentTone = .githubGreen
        let green = signature(settings)
        settings.appearance.accentTone = .system

        #expect(green != signature(settings))
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
            attention: .none,
            account: AccountSignature(.loggedOut),
            settings: MenuSettingsSignature(settings: settings, selection: .all),
            isLightAppearance: true,
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
            attention: .none,
            account: AccountSignature(.loggedOut),
            settings: MenuSettingsSignature(settings: settings, selection: .all),
            isLightAppearance: true,
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
    func `menu build signature changes with effective appearance`() {
        let now = Date(timeIntervalSinceReferenceDate: 2_500_000)
        let settings = UserSettings()

        #expect(Self.emptyMenuBuildSignature(settings: settings, isLightAppearance: true, now: now)
            != Self.emptyMenuBuildSignature(settings: settings, isLightAppearance: false, now: now))
    }

    @Test
    func `repo submenu signature changes with effective appearance`() {
        let now = Date(timeIntervalSinceReferenceDate: 2_600_000)
        let range = HeatmapRange(start: now.addingTimeInterval(-86400), end: now)
        let repo = Repository(
            id: "3",
            name: "Heatmap",
            owner: "me",
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
        let display = RepositoryDisplayModel(repo: repo, now: now)
        var settings = UserSettings()
        settings.heatmap.display = .submenu
        func signature(isLightAppearance: Bool) -> RepoSubmenuSignature {
            RepoSubmenuSignature(
                repo: display,
                settings: settings,
                heatmapRange: range,
                recentCounts: RepoRecentCountSignature(commits: nil, commitsDigest: nil),
                changelogPresentation: nil,
                changelogHeadline: nil,
                isPinned: false,
                isLightAppearance: isLightAppearance
            )
        }

        #expect(signature(isLightAppearance: true) != signature(isLightAppearance: false))
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

    private static func emptyMenuBuildSignature(
        settings: UserSettings,
        isLightAppearance: Bool,
        now: Date
    ) -> MenuBuildSignature {
        MenuBuildSignature(
            attention: .none,
            account: AccountSignature(.loggedOut),
            settings: MenuSettingsSignature(settings: settings, selection: .all),
            isLightAppearance: isLightAppearance,
            hasLoadedRepositories: true,
            rateLimitReset: nil,
            rateLimits: RateLimitMenuSignature(.empty),
            lastError: nil,
            contribution: ContributionSignature(user: nil, error: nil, heatmapCount: 0),
            globalActivity: ActivitySignature(events: [], error: nil),
            globalCommits: CommitSignature(commits: [], error: nil),
            heatmapRangeStart: now.timeIntervalSinceReferenceDate,
            heatmapRangeEnd: now.timeIntervalSinceReferenceDate,
            reposDigest: RepoSignature.digest(for: []),
            actionsDigest: 0,
            timeBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )
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
}
