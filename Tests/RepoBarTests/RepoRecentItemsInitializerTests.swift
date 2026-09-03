import Foundation
import RepoBarCore
import Testing

struct RepoRecentItemsInitializerTests {
    @Test
    func `initializers assign fields`() throws {
        let url = try #require(URL(string: "https://example.com"))
        let avatar = try #require(URL(string: "https://example.com/a.png"))
        let now = Date(timeIntervalSinceReferenceDate: 1_234_567)

        let label = RepoIssueLabel(name: "bug", colorHex: "ff0000")
        let issue = RepoIssueSummary(
            number: 1,
            title: "Issue",
            url: url,
            updatedAt: now,
            authorLogin: "me",
            authorAvatarURL: avatar,
            assigneeLogins: ["you"],
            commentCount: 2,
            labels: [label]
        )
        #expect(issue.number == 1)
        #expect(issue.labels.first?.name == "bug")

        let pr = RepoPullRequestSummary(
            number: 2,
            title: "PR",
            url: url,
            updatedAt: now,
            authorLogin: "me",
            authorAvatarURL: avatar,
            isDraft: true,
            commentCount: 3,
            reviewCommentCount: 4,
            labels: [label],
            headRefName: "feature",
            baseRefName: "main"
        )
        #expect(pr.isDraft == true)
        #expect(pr.headRefName == "feature")

        let asset = RepoReleaseAssetSummary(name: "bin", sizeBytes: 123, downloadCount: 4, url: url)
        let release = RepoReleaseSummary(
            name: "Release",
            tag: "v1.0",
            url: url,
            publishedAt: now,
            isPrerelease: false,
            authorLogin: "me",
            authorAvatarURL: avatar,
            assetCount: 1,
            downloadCount: 4,
            assets: [asset]
        )
        #expect(release.assets.first?.name == "bin")

        let run = RepoWorkflowRunSummary(
            name: "CI",
            workflowName: "Deploy",
            url: url,
            updatedAt: now,
            status: .passing,
            conclusion: "success",
            branch: "main",
            event: "push",
            actorLogin: "me",
            actorAvatarURL: avatar,
            runNumber: 7
        )
        #expect(run.status == .passing)
        #expect(run.runNumber == 7)
        #expect(run.workflowName == "Deploy")

        let discussion = RepoDiscussionSummary(
            title: "Discuss",
            url: url,
            updatedAt: now,
            authorLogin: "me",
            authorAvatarURL: avatar,
            commentCount: 5,
            categoryName: "General"
        )
        #expect(discussion.categoryName == "General")

        let tag = RepoTagSummary(name: "v1.0", commitSHA: "abc")
        #expect(tag.commitSHA == "abc")

        let branch = RepoBranchSummary(name: "main", commitSHA: "def", isProtected: true)
        #expect(branch.isProtected == true)

        let contributor = RepoContributorSummary(login: "me", avatarURL: avatar, url: url, contributions: 10)
        #expect(contributor.contributions == 10)

        let commit = RepoCommitSummary(
            sha: "123",
            message: "msg",
            url: url,
            authoredAt: now,
            authorName: "Me",
            authorLogin: "me",
            authorAvatarURL: avatar,
            repoFullName: "me/Repo"
        )
        let list = RepoCommitList(items: [commit], totalCount: 20)
        #expect(list.items.count == 1)
        #expect(list.totalCount == 20)
    }
}
