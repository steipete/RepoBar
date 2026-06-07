import Foundation

public enum GitHubPullRequestListState: String, Sendable {
    case open
    case closed
    case all
}

public struct RepoIssueLabel: Sendable, Hashable {
    public let name: String
    public let colorHex: String

    public init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }
}

public struct RepoIssueSummary: Sendable, Hashable {
    public let number: Int
    public let title: String
    public let url: URL
    public let updatedAt: Date
    public let createdAt: Date?
    public let authorLogin: String?
    public let authorAvatarURL: URL?
    public let assigneeLogins: [String]
    public let commentCount: Int
    public let labels: [RepoIssueLabel]

    public init(
        number: Int,
        title: String,
        url: URL,
        updatedAt: Date,
        createdAt: Date? = nil,
        authorLogin: String?,
        authorAvatarURL: URL?,
        assigneeLogins: [String],
        commentCount: Int,
        labels: [RepoIssueLabel]
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.assigneeLogins = assigneeLogins
        self.commentCount = commentCount
        self.labels = labels
    }
}

public struct RepoPullRequestSummary: Sendable, Hashable {
    public enum State: String, Sendable, Hashable, Codable {
        case open
        case closed
    }

    public let number: Int
    public let title: String
    public let url: URL
    public let updatedAt: Date
    public let createdAt: Date?
    public let state: State
    public let mergedAt: Date?
    public let authorLogin: String?
    public let authorAvatarURL: URL?
    public let isDraft: Bool
    public let commentCount: Int
    public let reviewCommentCount: Int
    public let labels: [RepoIssueLabel]
    public let headRefName: String?
    public let baseRefName: String?
    public let bodyPreview: String?
    public let requestedReviewerLogins: [String]
    public let requestedTeamNames: [String]

    public init(
        number: Int,
        title: String,
        url: URL,
        updatedAt: Date,
        createdAt: Date? = nil,
        state: State = .open,
        mergedAt: Date? = nil,
        authorLogin: String?,
        authorAvatarURL: URL?,
        isDraft: Bool,
        commentCount: Int,
        reviewCommentCount: Int,
        labels: [RepoIssueLabel],
        headRefName: String?,
        baseRefName: String?,
        bodyPreview: String? = nil,
        requestedReviewerLogins: [String] = [],
        requestedTeamNames: [String] = []
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.state = state
        self.mergedAt = mergedAt
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.isDraft = isDraft
        self.commentCount = commentCount
        self.reviewCommentCount = reviewCommentCount
        self.labels = labels
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.bodyPreview = bodyPreview
        self.requestedReviewerLogins = requestedReviewerLogins
        self.requestedTeamNames = requestedTeamNames
    }
}

public struct RepoReleaseSummary: Sendable, Hashable {
    public let name: String
    public let tag: String
    public let url: URL
    public let publishedAt: Date
    public let isPrerelease: Bool
    public let authorLogin: String?
    public let authorAvatarURL: URL?
    public let assetCount: Int
    public let downloadCount: Int
    public let assets: [RepoReleaseAssetSummary]

    public init(
        name: String,
        tag: String,
        url: URL,
        publishedAt: Date,
        isPrerelease: Bool,
        authorLogin: String?,
        authorAvatarURL: URL?,
        assetCount: Int,
        downloadCount: Int,
        assets: [RepoReleaseAssetSummary]
    ) {
        self.name = name
        self.tag = tag
        self.url = url
        self.publishedAt = publishedAt
        self.isPrerelease = isPrerelease
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.assetCount = assetCount
        self.downloadCount = downloadCount
        self.assets = assets
    }
}

public struct RepoWorkflowRunSummary: Sendable, Hashable {
    public let name: String
    public let url: URL
    public let updatedAt: Date
    public let status: CIStatus
    public let conclusion: String?
    public let branch: String?
    public let event: String?
    public let actorLogin: String?
    public let actorAvatarURL: URL?
    public let runNumber: Int?

    public init(
        name: String,
        url: URL,
        updatedAt: Date,
        status: CIStatus,
        conclusion: String?,
        branch: String?,
        event: String?,
        actorLogin: String?,
        actorAvatarURL: URL?,
        runNumber: Int?
    ) {
        self.name = name
        self.url = url
        self.updatedAt = updatedAt
        self.status = status
        self.conclusion = conclusion
        self.branch = branch
        self.event = event
        self.actorLogin = actorLogin
        self.actorAvatarURL = actorAvatarURL
        self.runNumber = runNumber
    }
}

public struct RepoDiscussionSummary: Sendable, Hashable {
    public let title: String
    public let url: URL
    public let updatedAt: Date
    public let authorLogin: String?
    public let authorAvatarURL: URL?
    public let commentCount: Int
    public let categoryName: String?

    public init(
        title: String,
        url: URL,
        updatedAt: Date,
        authorLogin: String?,
        authorAvatarURL: URL?,
        commentCount: Int,
        categoryName: String?
    ) {
        self.title = title
        self.url = url
        self.updatedAt = updatedAt
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.commentCount = commentCount
        self.categoryName = categoryName
    }
}

public struct RepoTagSummary: Sendable, Hashable {
    public let name: String
    public let commitSHA: String

    public init(name: String, commitSHA: String) {
        self.name = name
        self.commitSHA = commitSHA
    }
}

public struct RepoBranchSummary: Sendable, Hashable {
    public let name: String
    public let commitSHA: String
    public let isProtected: Bool

    public init(name: String, commitSHA: String, isProtected: Bool) {
        self.name = name
        self.commitSHA = commitSHA
        self.isProtected = isProtected
    }
}

public struct RepoContributorSummary: Sendable, Hashable {
    public let login: String
    public let avatarURL: URL?
    public let url: URL?
    public let contributions: Int

    public init(login: String, avatarURL: URL?, url: URL?, contributions: Int) {
        self.login = login
        self.avatarURL = avatarURL
        self.url = url
        self.contributions = contributions
    }
}

public struct RepoCommitSummary: Sendable, Hashable {
    public let sha: String
    public let message: String
    public let url: URL
    public let authoredAt: Date
    public let authorName: String?
    public let authorLogin: String?
    public let authorAvatarURL: URL?
    public let repoFullName: String?

    public init(
        sha: String,
        message: String,
        url: URL,
        authoredAt: Date,
        authorName: String?,
        authorLogin: String?,
        authorAvatarURL: URL?,
        repoFullName: String? = nil
    ) {
        self.sha = sha
        self.message = message
        self.url = url
        self.authoredAt = authoredAt
        self.authorName = authorName
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.repoFullName = repoFullName
    }
}

public struct RepoCommitList: Sendable, Hashable {
    public let items: [RepoCommitSummary]
    public let totalCount: Int?

    public init(items: [RepoCommitSummary], totalCount: Int?) {
        self.items = items
        self.totalCount = totalCount
    }
}

public struct RepoReleaseAssetSummary: Sendable, Hashable {
    public let name: String
    public let sizeBytes: Int?
    public let downloadCount: Int
    public let url: URL

    public init(name: String, sizeBytes: Int?, downloadCount: Int, url: URL) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.downloadCount = downloadCount
        self.url = url
    }
}
