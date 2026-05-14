import Foundation

extension GitHubClient {
    static func decodeRecentPullRequests(from data: Data) throws -> [RepoPullRequestSummary] {
        try GitHubRecentDecoders.decodeRecentPullRequests(from: data)
    }

    static func decodeRecentIssues(from data: Data) throws -> [RepoIssueSummary] {
        try GitHubRecentDecoders.decodeRecentIssues(from: data)
    }

    static func decodePullRequestIssueCommentCounts(from data: Data) throws -> [Int: Int] {
        try GitHubRecentDecoders.decodePullRequestIssueCommentCounts(from: data)
    }

    static func decodeRecentReleases(from data: Data) throws -> [RepoReleaseSummary] {
        try GitHubRecentDecoders.decodeRecentReleases(from: data)
    }

    static func decodeRecentWorkflowRuns(from data: Data) throws -> [RepoWorkflowRunSummary] {
        try GitHubRecentDecoders.decodeRecentWorkflowRuns(from: data)
    }

    static func decodeRecentDiscussions(from data: Data) throws -> [RepoDiscussionSummary] {
        try GitHubRecentDecoders.decodeRecentDiscussions(from: data)
    }

    static func decodeRecentTags(from data: Data) throws -> [RepoTagSummary] {
        try GitHubRecentDecoders.decodeRecentTags(from: data)
    }

    static func decodeRecentBranches(from data: Data) throws -> [RepoBranchSummary] {
        try GitHubRecentDecoders.decodeRecentBranches(from: data)
    }

    static func decodeRecentCommits(from data: Data) throws -> [RepoCommitSummary] {
        try GitHubRecentDecoders.decodeRecentCommits(from: data)
    }

    static func decodeContributors(from data: Data) throws -> [RepoContributorSummary] {
        try GitHubRecentDecoders.decodeContributors(from: data)
    }

    static func latestRelease(from responses: [ReleaseResponse]) -> Release? {
        GitHubReleasePicker.latestRelease(from: responses)
    }
}
