import Foundation

enum GitHubRecentDecoders {
    static func decodeRecentPullRequests(from data: Data) throws -> [RepoPullRequestSummary] {
        let responses = try GitHubDecoding.decode([PullRequestRecentResponse].self, from: data)
        return responses.map {
            RepoPullRequestSummary(
                number: $0.number,
                title: $0.title,
                url: $0.htmlUrl,
                updatedAt: $0.updatedAt,
                createdAt: $0.createdAt,
                state: $0.state ?? .open,
                mergedAt: $0.mergedAt,
                authorLogin: $0.user?.login,
                authorAvatarURL: $0.user?.avatarUrl,
                isDraft: $0.draft ?? false,
                commentCount: $0.comments ?? 0,
                reviewCommentCount: $0.reviewComments ?? 0,
                labels: ($0.labels ?? []).map { RepoIssueLabel(name: $0.name, colorHex: $0.color) },
                headRefName: $0.head?.refName,
                baseRefName: $0.base?.refName,
                bodyPreview: Self.bodyPreview(from: $0.body),
                requestedReviewerLogins: ($0.requestedReviewers ?? []).map(\.login),
                requestedTeamNames: ($0.requestedTeams ?? []).map(\.name)
            )
        }
    }

    static func decodeRecentIssues(from data: Data) throws -> [RepoIssueSummary] {
        let responses = try GitHubDecoding.decode([IssueRecentResponse].self, from: data)
        return self.issueSummaries(from: responses)
    }

    static func decodeRecentIssuePage(from data: Data) throws -> RecentIssuePage {
        let responses = try GitHubDecoding.decode([IssueRecentResponse].self, from: data)
        return RecentIssuePage(rawCount: responses.count, issues: self.issueSummaries(from: responses))
    }

    static func decodePullRequestIssueCommentCounts(from data: Data) throws -> [Int: Int] {
        let responses = try GitHubDecoding.decode([IssueRecentResponse].self, from: data)
        return Dictionary(
            uniqueKeysWithValues: responses
                .filter { $0.pullRequest != nil }
                .map { ($0.number, $0.comments) }
        )
    }

    private static func issueSummaries(from responses: [IssueRecentResponse]) -> [RepoIssueSummary] {
        responses
            .filter { $0.pullRequest == nil }
            .map {
                RepoIssueSummary(
                    number: $0.number,
                    title: $0.title,
                    url: $0.htmlUrl,
                    updatedAt: $0.updatedAt,
                    createdAt: $0.createdAt,
                    authorLogin: $0.user?.login,
                    authorAvatarURL: $0.user?.avatarUrl,
                    assigneeLogins: ($0.assignees ?? []).compactMap(\.login),
                    commentCount: $0.comments,
                    labels: $0.labels.map { RepoIssueLabel(name: $0.name, colorHex: $0.color) }
                )
            }
    }

    struct RecentIssuePage {
        let rawCount: Int
        let issues: [RepoIssueSummary]
    }

    static func decodeRecentReleases(from data: Data) throws -> [RepoReleaseSummary] {
        let responses = try GitHubDecoding.decode([ReleaseRecentResponse].self, from: data)
        return responses
            .filter { $0.draft != true }
            .map {
                let title = ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let published = $0.publishedAt ?? $0.createdAt ?? Date.distantPast
                let rawAssets = $0.assets ?? []
                let assets = rawAssets.compactMap { asset -> RepoReleaseAssetSummary? in
                    guard let name = asset.name,
                          let url = asset.browserDownloadUrl
                    else {
                        return nil
                    }

                    return RepoReleaseAssetSummary(
                        name: name,
                        sizeBytes: asset.size,
                        downloadCount: asset.downloadCount ?? 0,
                        url: url
                    )
                }
                let downloads = rawAssets.reduce(0) { $0 + ($1.downloadCount ?? 0) }
                return RepoReleaseSummary(
                    name: title.isEmpty ? $0.tagName : title,
                    tag: $0.tagName,
                    url: $0.htmlUrl,
                    publishedAt: published,
                    isPrerelease: $0.prerelease ?? false,
                    authorLogin: $0.author?.login,
                    authorAvatarURL: $0.author?.avatarUrl,
                    assetCount: rawAssets.count,
                    downloadCount: downloads,
                    assets: assets
                )
            }
    }

    static func decodeRecentWorkflowRuns(from data: Data) throws -> [RepoWorkflowRunSummary] {
        let response = try GitHubDecoding.decode(ActionsRunsResponse.self, from: data)
        return response.workflowRuns.compactMap { run in
            guard let url = run.htmlUrl else { return nil }

            let title = self.workflowRunTitle(run)
            let updatedAt = run.updatedAt ?? run.createdAt ?? Date.distantPast
            return RepoWorkflowRunSummary(
                name: title,
                url: url,
                updatedAt: updatedAt,
                status: GitHubStatusMapper.ciStatus(fromStatus: run.status, conclusion: run.conclusion),
                conclusion: run.conclusion,
                branch: run.headBranch,
                event: run.event,
                actorLogin: run.actor?.login,
                actorAvatarURL: run.actor?.avatarUrl,
                runNumber: run.runNumber
            )
        }
    }

    static func decodeRecentDiscussions(from data: Data) throws -> [RepoDiscussionSummary] {
        let responses = try GitHubDecoding.decode([DiscussionRecentResponse].self, from: data)
        return responses.map {
            RepoDiscussionSummary(
                title: $0.title,
                url: $0.htmlUrl,
                updatedAt: $0.updatedAt,
                authorLogin: $0.user?.login,
                authorAvatarURL: $0.user?.avatarUrl,
                commentCount: $0.comments ?? 0,
                categoryName: $0.category?.name
            )
        }
    }

    static func decodeRecentTags(from data: Data) throws -> [RepoTagSummary] {
        let responses = try GitHubDecoding.decode([TagRecentResponse].self, from: data)
        return responses.map {
            RepoTagSummary(name: $0.name, commitSHA: $0.commit.sha)
        }
    }

    static func decodeRecentBranches(from data: Data) throws -> [RepoBranchSummary] {
        let responses = try GitHubDecoding.decode([BranchRecentResponse].self, from: data)
        return responses.map {
            RepoBranchSummary(name: $0.name, commitSHA: $0.commit.sha, isProtected: $0.protected)
        }
    }

    static func decodeRecentCommits(from data: Data) throws -> [RepoCommitSummary] {
        let responses = try GitHubDecoding.decode([CommitRecentResponse].self, from: data)
        return responses.compactMap { response in
            guard let url = response.htmlUrl else { return nil }

            let message = response.commit.message.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
            return RepoCommitSummary(
                sha: response.sha,
                message: title,
                url: url,
                authoredAt: response.commit.author.date,
                authorName: response.commit.author.name,
                authorLogin: response.author?.login,
                authorAvatarURL: response.author?.avatarUrl
            )
        }
    }

    static func decodeContributors(from data: Data) throws -> [RepoContributorSummary] {
        let responses = try GitHubDecoding.decode([ContributorResponse].self, from: data)
        return responses.compactMap {
            guard let login = $0.login else { return nil }

            return RepoContributorSummary(
                login: login,
                avatarURL: $0.avatarUrl,
                url: $0.htmlUrl,
                contributions: $0.contributions ?? 0
            )
        }
    }

    private static func workflowRunTitle(_ run: ActionsRunsResponse.WorkflowRun) -> String {
        let preferred = (run.displayTitle ?? run.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if preferred.isEmpty == false { return preferred }
        if let runNumber = run.runNumber { return "Run #\(runNumber)" }
        return "Workflow run"
    }

    private struct PullRequestRecentResponse: Decodable {
        let number: Int
        let title: String
        let htmlUrl: URL
        let updatedAt: Date
        let createdAt: Date?
        let state: RepoPullRequestSummary.State?
        let mergedAt: Date?
        let user: RecentUser?
        let draft: Bool?
        let comments: Int?
        let reviewComments: Int?
        let labels: [IssueLabel]?
        let head: PullRequestRef?
        let base: PullRequestRef?
        let body: String?
        let requestedReviewers: [RecentUser]?
        let requestedTeams: [RequestedTeam]?

        enum CodingKeys: String, CodingKey {
            case number, title, state, user, draft, comments, labels, head, base, body
            case htmlUrl = "html_url"
            case updatedAt = "updated_at"
            case createdAt = "created_at"
            case mergedAt = "merged_at"
            case reviewComments = "review_comments"
            case requestedReviewers = "requested_reviewers"
            case requestedTeams = "requested_teams"
        }
    }

    private static func bodyPreview(from body: String?) -> String? {
        guard let body else { return nil }

        let collapsed = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        guard collapsed.isEmpty == false else { return nil }

        if collapsed.count <= 240 { return collapsed }
        return "\(collapsed.prefix(237))..."
    }

    private struct RequestedTeam: Decodable {
        let name: String
    }

    private struct PullRequestRef: Decodable {
        let refName: String

        enum CodingKeys: String, CodingKey {
            case refName = "ref"
        }
    }

    private struct IssueRecentResponse: Decodable {
        let number: Int
        let title: String
        let htmlUrl: URL
        let updatedAt: Date
        let createdAt: Date?
        let comments: Int
        let user: RecentUser?
        let labels: [IssueLabel]
        let assignees: [RecentUser]?
        let pullRequest: PullRequestMarker?

        enum CodingKeys: String, CodingKey {
            case number, title, user, comments, labels, assignees
            case htmlUrl = "html_url"
            case updatedAt = "updated_at"
            case createdAt = "created_at"
            case pullRequest = "pull_request"
        }
    }

    private struct PullRequestMarker: Decodable {}

    private struct RecentUser: Decodable {
        let login: String
        let avatarUrl: URL?

        enum CodingKeys: String, CodingKey {
            case login
            case avatarUrl = "avatar_url"
        }
    }

    private struct ReleaseRecentResponse: Decodable {
        let name: String?
        let tagName: String
        let publishedAt: Date?
        let createdAt: Date?
        let draft: Bool?
        let prerelease: Bool?
        let htmlUrl: URL
        let author: RecentUser?
        let assets: [ReleaseAsset]?

        enum CodingKeys: String, CodingKey {
            case name, draft, prerelease, author, assets
            case tagName = "tag_name"
            case publishedAt = "published_at"
            case createdAt = "created_at"
            case htmlUrl = "html_url"
        }

        struct ReleaseAsset: Decodable {
            let name: String?
            let size: Int?
            let downloadCount: Int?
            let browserDownloadUrl: URL?

            enum CodingKeys: String, CodingKey {
                case name
                case size
                case downloadCount = "download_count"
                case browserDownloadUrl = "browser_download_url"
            }
        }
    }

    private struct DiscussionRecentResponse: Decodable {
        let title: String
        let htmlUrl: URL
        let updatedAt: Date
        let comments: Int?
        let user: RecentUser?
        let category: DiscussionCategory?

        struct DiscussionCategory: Decodable {
            let name: String
        }

        enum CodingKeys: String, CodingKey {
            case title, user, comments, category
            case htmlUrl = "html_url"
            case updatedAt = "updated_at"
        }
    }

    private struct TagRecentResponse: Decodable {
        let name: String
        let commit: TagCommit

        struct TagCommit: Decodable {
            let sha: String
        }
    }

    private struct BranchRecentResponse: Decodable {
        let name: String
        let protected: Bool
        let commit: TagCommit

        struct TagCommit: Decodable {
            let sha: String
        }
    }

    private struct CommitRecentResponse: Decodable {
        let sha: String
        let htmlUrl: URL?
        let commit: CommitDetail
        let author: RecentUser?

        enum CodingKeys: String, CodingKey {
            case sha
            case htmlUrl = "html_url"
            case commit
            case author
        }

        struct CommitDetail: Decodable {
            let message: String
            let author: CommitAuthor
        }

        struct CommitAuthor: Decodable {
            let name: String?
            let date: Date
        }
    }

    private struct ContributorResponse: Decodable {
        let login: String?
        let avatarUrl: URL?
        let htmlUrl: URL?
        let contributions: Int?

        enum CodingKeys: String, CodingKey {
            case login, contributions
            case avatarUrl = "avatar_url"
            case htmlUrl = "html_url"
        }
    }

    private struct IssueLabel: Decodable {
        let name: String
        let color: String
    }
}
