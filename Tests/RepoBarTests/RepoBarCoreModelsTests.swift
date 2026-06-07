import Foundation
@testable import RepoBarCore
import Testing

struct RepoBarCoreModelsTests {
    @Test
    func `user identity init`() throws {
        let host = try #require(URL(string: "https://github.com"))
        let identity = UserIdentity(username: "steipete", host: host)
        #expect(identity.username == "steipete")
        #expect(identity.host == host)
    }

    @Test
    func `repository full name and with order`() {
        var repo = Repository(
            id: "1",
            name: "RepoBar",
            owner: "steipete",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 1,
            openPulls: 2,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        #expect(repo.fullName == "steipete/RepoBar")
        repo = repo.withOrder(5)
        #expect(repo.sortOrder == 5)
    }

    @Test
    func `local projects refresh interval labels`() {
        #expect(LocalProjectsRefreshInterval.oneMinute.label == "1 minute")
        #expect(LocalProjectsRefreshInterval.twoMinutes.label == "2 minutes")
        #expect(LocalProjectsRefreshInterval.fiveMinutes.label == "5 minutes")
        #expect(LocalProjectsRefreshInterval.fifteenMinutes.label == "15 minutes")
        #expect(LocalProjectsRefreshInterval.fiveMinutes.seconds == 300)
    }

    @Test
    func `user settings defaults`() {
        let settings = UserSettings()
        #expect(settings.localProjects.worktreeFolderName == ".work")
        #expect(settings.localProjects.autoSyncEnabled == true)
    }

    @Test
    func `repo recent items init`() throws {
        let now = Date()
        let url = try #require(URL(string: "https://example.com"))
        _ = RepoIssueSummary(
            number: 1,
            title: "Issue",
            url: url,
            updatedAt: now,
            authorLogin: "user",
            authorAvatarURL: url,
            assigneeLogins: ["a"],
            commentCount: 2,
            labels: [RepoIssueLabel(name: "bug", colorHex: "ff0000")]
        )
        _ = RepoPullRequestSummary(
            number: 2,
            title: "PR",
            url: url,
            updatedAt: now,
            authorLogin: nil,
            authorAvatarURL: nil,
            isDraft: false,
            commentCount: 1,
            reviewCommentCount: 0,
            labels: [],
            headRefName: "feature",
            baseRefName: "main"
        )
        _ = RepoReleaseSummary(
            name: "v1",
            tag: "v1.0",
            url: url,
            publishedAt: now,
            isPrerelease: false,
            authorLogin: "user",
            authorAvatarURL: url,
            assetCount: 1,
            downloadCount: 2,
            assets: []
        )
        _ = RepoWorkflowRunSummary(
            name: "CI",
            url: url,
            updatedAt: now,
            status: .passing,
            conclusion: "success",
            branch: "main",
            event: "push",
            actorLogin: "user",
            actorAvatarURL: url,
            runNumber: 12
        )
        _ = RepoDiscussionSummary(
            title: "Discussion",
            url: url,
            updatedAt: now,
            authorLogin: nil,
            authorAvatarURL: nil,
            commentCount: 0,
            categoryName: "General"
        )
        _ = RepoTagSummary(name: "v1.0", commitSHA: "abc123")
    }

    @Test
    func `github reference matches prefer newest created date`() throws {
        let url = try #require(URL(string: "https://example.com"))
        let older = GitHubReferenceMatch(
            query: .issueNumber(42),
            title: "Older",
            url: url,
            repositoryFullName: "owner/old",
            kind: .issue,
            state: .open,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let newer = GitHubReferenceMatch(
            query: .issueNumber(42),
            title: "Newer",
            url: url,
            repositoryFullName: "owner/new",
            kind: .pullRequest,
            state: .closed,
            createdAt: Date(timeIntervalSinceReferenceDate: 20),
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        )

        #expect(GitHubReferenceMatch.newestCreated(in: [older, newer])?.repositoryFullName == "owner/new")
    }

    @Test
    func `github reference match stores preview metadata`() throws {
        let url = try #require(URL(string: "https://example.com"))
        let match = GitHubReferenceMatch(
            query: .repositoryIssueNumber(repositoryFullName: "owner/repo", number: 5),
            title: "Title",
            url: url,
            repositoryFullName: "owner/repo",
            kind: .pullRequest,
            state: .open,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 20),
            bodyPreview: "Preview text",
            aiSummary: "AI summary",
            authorLogin: "alice"
        )

        #expect(match.bodyPreview == "Preview text")
        #expect(match.aiSummary == "AI summary")
        #expect(match.authorLogin == "alice")
    }

    @Test
    func `github reference query display text`() {
        #expect(GitHubReferenceQuery.issueNumber(7).displayText == "#7")
        #expect(GitHubReferenceState.open.label == "Open")
        #expect(GitHubReferenceState.closed.label == "Closed")
        #expect(GitHubReferenceState.merged.label == "Merged")
        #expect(
            GitHubReferenceQuery.repositoryNameIssueNumber(
                repositoryName: "discrawl",
                number: 64
            ).displayText == "discrawl#64"
        )
        #expect(
            GitHubReferenceQuery.repositoryIssueNumber(
                repositoryFullName: "openclaw/openclaw",
                number: 73655
            ).displayText == "openclaw/openclaw#73655"
        )
        #expect(GitHubReferenceQuery.commitHash("ffd212ca43abcdef").displayText == "ffd212ca43")
        #expect(
            GitHubReferenceQuery.repositoryCommitHash(
                repositoryFullName: "openclaw/openclaw",
                hash: "ffd212ca43abcdef"
            ).displayText == "openclaw/openclaw@ffd212ca43"
        )
        #expect(
            GitHubReferenceQuery.repositoryWorkflowRun(
                repositoryFullName: "openclaw/songsee",
                runID: 25_620_622_163
            ).displayText == "openclaw/songsee run 25620622163"
        )
        let scoped = GitHubReferenceQuery.repositoryIssueNumber(
            repositoryFullName: "openclaw/openclaw",
            number: 73655
        )
        #expect(scoped.repositoryOwnerAndName?.owner == "openclaw")
        #expect(scoped.repositoryOwnerAndName?.name == "openclaw")
    }

    @Test
    func `backoff tracker lifecycle`() async throws {
        let tracker = BackoffTracker()
        let url = try #require(URL(string: "https://example.com"))
        let now = Date()
        #expect(await tracker.isCoolingDown(url: url, now: now) == false)
        await tracker.setCooldown(url: url, until: now.addingTimeInterval(60))
        #expect(await tracker.isCoolingDown(url: url, now: now) == true)
        #expect(await tracker.cooldown(for: url, now: now) != nil)
        #expect(await tracker.count() == 1)
        await tracker.clear()
        #expect(await tracker.count() == 0)
    }

    @Test
    func `git executable locator version`() {
        let result = GitExecutableLocator.version(at: URL(fileURLWithPath: "/usr/bin/git"))
        #expect(result.version != nil)
        #expect(result.error == nil)
    }
}
