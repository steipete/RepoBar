import Foundation
import RepoBarCore

struct ReleaseOutput: Encodable {
    let name: String
    let tag: String
    let url: URL
    let publishedAt: Date
    let isPrerelease: Bool
    let authorLogin: String?
    let authorAvatarURL: URL?
    let assetCount: Int
    let downloadCount: Int
    let assets: [ReleaseAssetOutput]

    init(_ release: RepoReleaseSummary) {
        self.name = release.name
        self.tag = release.tag
        self.url = release.url
        self.publishedAt = release.publishedAt
        self.isPrerelease = release.isPrerelease
        self.authorLogin = release.authorLogin
        self.authorAvatarURL = release.authorAvatarURL
        self.assetCount = release.assetCount
        self.downloadCount = release.downloadCount
        self.assets = release.assets.map(ReleaseAssetOutput.init)
    }
}

struct ReleaseAssetOutput: Encodable {
    let name: String
    let sizeBytes: Int?
    let downloadCount: Int
    let url: URL

    init(_ asset: RepoReleaseAssetSummary) {
        self.name = asset.name
        self.sizeBytes = asset.sizeBytes
        self.downloadCount = asset.downloadCount
        self.url = asset.url
    }
}

struct WorkflowRunOutput: Encodable {
    let name: String
    let workflowName: String?
    let url: URL
    let updatedAt: Date
    let status: CIStatus
    let conclusion: String?
    let branch: String?
    let event: String?
    let actorLogin: String?
    let actorAvatarURL: URL?
    let runNumber: Int?

    init(_ run: RepoWorkflowRunSummary) {
        self.name = run.name
        self.workflowName = run.workflowName
        self.url = run.url
        self.updatedAt = run.updatedAt
        self.status = run.status
        self.conclusion = run.conclusion
        self.branch = run.branch
        self.event = run.event
        self.actorLogin = run.actorLogin
        self.actorAvatarURL = run.actorAvatarURL
        self.runNumber = run.runNumber
    }
}

struct DiscussionOutput: Encodable {
    let title: String
    let url: URL
    let updatedAt: Date
    let authorLogin: String?
    let authorAvatarURL: URL?
    let commentCount: Int
    let categoryName: String?

    init(_ discussion: RepoDiscussionSummary) {
        self.title = discussion.title
        self.url = discussion.url
        self.updatedAt = discussion.updatedAt
        self.authorLogin = discussion.authorLogin
        self.authorAvatarURL = discussion.authorAvatarURL
        self.commentCount = discussion.commentCount
        self.categoryName = discussion.categoryName
    }
}

struct TagOutput: Encodable {
    let name: String
    let commitSHA: String

    init(_ tag: RepoTagSummary) {
        self.name = tag.name
        self.commitSHA = tag.commitSHA
    }
}

struct BranchOutput: Encodable {
    let name: String
    let commitSHA: String
    let isProtected: Bool

    init(_ branch: RepoBranchSummary) {
        self.name = branch.name
        self.commitSHA = branch.commitSHA
        self.isProtected = branch.isProtected
    }
}

struct ContributorOutput: Encodable {
    let login: String
    let avatarURL: URL?
    let url: URL?
    let contributions: Int

    init(_ contributor: RepoContributorSummary) {
        self.login = contributor.login
        self.avatarURL = contributor.avatarURL
        self.url = contributor.url
        self.contributions = contributor.contributions
    }
}

struct CommitOutput: Encodable {
    let sha: String
    let message: String
    let url: URL
    let authoredAt: Date
    let authorName: String?
    let authorLogin: String?
    let authorAvatarURL: URL?
    let repoFullName: String?

    init(_ commit: RepoCommitSummary) {
        self.sha = commit.sha
        self.message = commit.message
        self.url = commit.url
        self.authoredAt = commit.authoredAt
        self.authorName = commit.authorName
        self.authorLogin = commit.authorLogin
        self.authorAvatarURL = commit.authorAvatarURL
        self.repoFullName = commit.repoFullName
    }
}
