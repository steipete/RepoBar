import Foundation

public enum GitHubPullRequestNotificationEventKind: String, Codable, Equatable, Sendable {
    case newPullRequest
    case pullRequestUpdated
    case reviewRequested
    case newComment
}

public struct GitHubPullRequestNotificationEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: GitHubPullRequestNotificationEventKind
    public let repositoryFullName: String
    public let pullRequestNumber: Int
    public let title: String
    public let url: URL
    public let detail: String?

    public init(
        id: String,
        kind: GitHubPullRequestNotificationEventKind,
        repositoryFullName: String,
        pullRequestNumber: Int,
        title: String,
        url: URL,
        detail: String?
    ) {
        self.id = id
        self.kind = kind
        self.repositoryFullName = repositoryFullName
        self.pullRequestNumber = pullRequestNumber
        self.title = title
        self.url = url
        self.detail = detail
    }
}

public struct GitHubPullRequestNotificationSnapshot: Equatable, Codable, Sendable {
    public let updatedAt: Date
    public let state: RepoPullRequestSummary.State
    public let mergedAt: Date?
    public let commentCount: Int
    public let reviewCommentCount: Int
    public let requestedReviewerLogins: [String]
    public let requestedTeamNames: [String]

    public init(
        updatedAt: Date,
        state: RepoPullRequestSummary.State = .open,
        mergedAt: Date? = nil,
        commentCount: Int,
        reviewCommentCount: Int,
        requestedReviewerLogins: [String],
        requestedTeamNames: [String]
    ) {
        self.updatedAt = updatedAt
        self.state = state
        self.mergedAt = mergedAt
        self.commentCount = commentCount
        self.reviewCommentCount = reviewCommentCount
        self.requestedReviewerLogins = requestedReviewerLogins
        self.requestedTeamNames = requestedTeamNames
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case state
        case mergedAt
        case commentCount
        case reviewCommentCount
        case requestedReviewerLogins
        case requestedTeamNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.state = try container.decodeIfPresent(RepoPullRequestSummary.State.self, forKey: .state) ?? .open
        self.mergedAt = try container.decodeIfPresent(Date.self, forKey: .mergedAt)
        self.commentCount = try container.decode(Int.self, forKey: .commentCount)
        self.reviewCommentCount = try container.decode(Int.self, forKey: .reviewCommentCount)
        self.requestedReviewerLogins = try container.decode([String].self, forKey: .requestedReviewerLogins)
        self.requestedTeamNames = try container.decode([String].self, forKey: .requestedTeamNames)
    }
}

public struct GitHubPullRequestNotificationSnapshotState: Equatable, Codable, Sendable {
    public var repositories: [String: [Int: GitHubPullRequestNotificationSnapshot]]
    public var repositoryBaselines: [String: Date]
    public var commentTrackingRepositories: Set<String>

    public init(
        repositories: [String: [Int: GitHubPullRequestNotificationSnapshot]] = [:],
        repositoryBaselines: [String: Date] = [:],
        commentTrackingRepositories: Set<String> = []
    ) {
        self.repositories = repositories
        self.repositoryBaselines = repositoryBaselines
        self.commentTrackingRepositories = commentTrackingRepositories
    }

    private enum CodingKeys: String, CodingKey {
        case repositories
        case repositoryBaselines
        case commentTrackingRepositories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.repositories = try container.decode([String: [Int: GitHubPullRequestNotificationSnapshot]].self, forKey: .repositories)
        self.repositoryBaselines = try container.decodeIfPresent([String: Date].self, forKey: .repositoryBaselines) ?? [:]
        self.commentTrackingRepositories = try container.decodeIfPresent(Set<String>.self, forKey: .commentTrackingRepositories) ?? []
    }
}

public enum GitHubPullRequestNotificationDetector {
    public static func events(
        for currentPullRequests: [String: [RepoPullRequestSummary]],
        previousState: GitHubPullRequestNotificationSnapshotState,
        settings: GitHubPullRequestNotificationSettings,
        trackedRepositoryFullNames: [String]? = nil,
        observedAt: Date = Date()
    ) -> (events: [GitHubPullRequestNotificationEvent], state: GitHubPullRequestNotificationSnapshotState) {
        guard settings.enabled else {
            return ([], previousState)
        }

        let trackedRepositoryKeys = Set((trackedRepositoryFullNames ?? Array(currentPullRequests.keys)).map(Self.repositoryKey))
        let previousRepositories = previousState.repositories.filter { trackedRepositoryKeys.contains($0.key) }
        let previousBaselines = previousState.repositoryBaselines.filter { trackedRepositoryKeys.contains($0.key) }
        let previousCommentTracking = settings.comments
            ? previousState.commentTrackingRepositories.intersection(trackedRepositoryKeys)
            : []
        var nextState = GitHubPullRequestNotificationSnapshotState(
            repositories: previousRepositories,
            repositoryBaselines: previousBaselines,
            commentTrackingRepositories: previousCommentTracking
        )
        var events: [GitHubPullRequestNotificationEvent] = []

        for (repositoryFullName, pullRequests) in currentPullRequests {
            let repositoryKey = Self.repositoryKey(repositoryFullName)
            guard trackedRepositoryKeys.contains(repositoryKey) else { continue }

            let previousPullRequests = previousRepositories[repositoryKey]
            let previousBaseline = previousBaselines[repositoryKey]
                ?? previousPullRequests?.values.map(\.updatedAt).max()
            nextState.repositories[repositoryKey] = Dictionary(
                uniqueKeysWithValues: pullRequests.map { ($0.number, Self.snapshot(from: $0)) }
            )
            nextState.repositoryBaselines[repositoryKey] = max(previousBaseline ?? observedAt, observedAt)
            let commentsWereTracked = previousCommentTracking.contains(repositoryKey)
            if settings.comments {
                nextState.commentTrackingRepositories.insert(repositoryKey)
            }

            guard let previousPullRequests else {
                continue
            }

            for pullRequest in pullRequests {
                guard let previous = previousPullRequests[pullRequest.number] else {
                    let createdAt = pullRequest.createdAt ?? pullRequest.updatedAt
                    let isNewAfterBaseline = previousBaseline.map { createdAt > $0 } ?? false
                    if settings.newPullRequests, isNewAfterBaseline {
                        events.append(Self.event(
                            kind: .newPullRequest,
                            repositoryFullName: repositoryFullName,
                            pullRequest: pullRequest,
                            marker: "created-\(Self.dateMarker(pullRequest.createdAt ?? pullRequest.updatedAt))",
                            detail: nil
                        ))
                    }
                    continue
                }

                var emittedSpecificEvent = false
                let reviewRequestDetail = Self.reviewRequestDetail(previous: previous, current: pullRequest)
                if settings.reviewRequests, let detail = reviewRequestDetail {
                    emittedSpecificEvent = true
                    events.append(Self.event(
                        kind: .reviewRequested,
                        repositoryFullName: repositoryFullName,
                        pullRequest: pullRequest,
                        marker: "review-\(Self.reviewMarker(pullRequest))",
                        detail: detail
                    ))
                }

                if settings.comments, commentsWereTracked {
                    let newComments = max(0, pullRequest.commentCount - previous.commentCount)
                    let newReviewComments = max(0, pullRequest.reviewCommentCount - previous.reviewCommentCount)
                    let totalNewComments = newComments + newReviewComments
                    if totalNewComments > 0 {
                        emittedSpecificEvent = true
                        events.append(Self.event(
                            kind: .newComment,
                            repositoryFullName: repositoryFullName,
                            pullRequest: pullRequest,
                            marker: "comments-\(pullRequest.commentCount)-\(pullRequest.reviewCommentCount)",
                            detail: Self.commentDetail(count: totalNewComments)
                        ))
                    }
                }

                if settings.pullRequestUpdates, !emittedSpecificEvent {
                    let detail = Self.pullRequestStateChangeDetail(previous: previous, current: pullRequest)
                    guard detail != nil || pullRequest.updatedAt > previous.updatedAt else { continue }

                    events.append(Self.event(
                        kind: .pullRequestUpdated,
                        repositoryFullName: repositoryFullName,
                        pullRequest: pullRequest,
                        marker: "updated-\(Self.dateMarker(pullRequest.updatedAt))-\(pullRequest.state.rawValue)-\(Self.mergedMarker(pullRequest.mergedAt))",
                        detail: detail
                    ))
                }
            }
        }

        return (events, nextState)
    }

    private static func snapshot(from pullRequest: RepoPullRequestSummary) -> GitHubPullRequestNotificationSnapshot {
        GitHubPullRequestNotificationSnapshot(
            updatedAt: pullRequest.updatedAt,
            state: pullRequest.state,
            mergedAt: pullRequest.mergedAt,
            commentCount: pullRequest.commentCount,
            reviewCommentCount: pullRequest.reviewCommentCount,
            requestedReviewerLogins: self.normalized(pullRequest.requestedReviewerLogins),
            requestedTeamNames: self.normalized(pullRequest.requestedTeamNames)
        )
    }

    private static func event(
        kind: GitHubPullRequestNotificationEventKind,
        repositoryFullName: String,
        pullRequest: RepoPullRequestSummary,
        marker: String,
        detail: String?
    ) -> GitHubPullRequestNotificationEvent {
        let id = [
            "github-pr",
            Self.repositoryKey(repositoryFullName).replacingOccurrences(of: "/", with: "-"),
            "\(pullRequest.number)",
            kind.rawValue,
            marker
        ].joined(separator: "-")

        return GitHubPullRequestNotificationEvent(
            id: id,
            kind: kind,
            repositoryFullName: repositoryFullName,
            pullRequestNumber: pullRequest.number,
            title: pullRequest.title,
            url: pullRequest.url,
            detail: detail
        )
    }

    private static func reviewRequestDetail(
        previous: GitHubPullRequestNotificationSnapshot,
        current: RepoPullRequestSummary
    ) -> String? {
        let previousReviewers = Set(previous.requestedReviewerLogins)
        let currentReviewers = Set(Self.normalized(current.requestedReviewerLogins))
        let addedReviewers = currentReviewers.subtracting(previousReviewers)

        let previousTeams = Set(previous.requestedTeamNames)
        let currentTeams = Set(Self.normalized(current.requestedTeamNames))
        let addedTeams = currentTeams.subtracting(previousTeams)

        let added = Array(addedReviewers) + addedTeams.map { "@\($0)" }
        let sortedAdded = added.sorted()
        guard sortedAdded.isEmpty == false else { return nil }

        if sortedAdded.count == 1, let first = sortedAdded.first {
            return "Review requested from \(first)"
        }
        return "Review requested from \(sortedAdded.count) reviewers"
    }

    private static func pullRequestStateChangeDetail(
        previous: GitHubPullRequestNotificationSnapshot,
        current: RepoPullRequestSummary
    ) -> String? {
        if current.mergedAt != nil, previous.mergedAt == nil {
            return "PR merged"
        }
        if previous.state == .closed, current.state == .open {
            return "PR reopened"
        }
        if previous.state == .open, current.state == .closed {
            return "PR closed"
        }
        return nil
    }

    private static func mergedMarker(_ date: Date?) -> String {
        date.map(self.dateMarker) ?? "unmerged"
    }

    private static func commentDetail(count: Int) -> String {
        count == 1 ? "1 new comment" : "\(count) new comments"
    }

    private static func reviewMarker(_ pullRequest: RepoPullRequestSummary) -> String {
        (self.normalized(pullRequest.requestedReviewerLogins) + self.normalized(pullRequest.requestedTeamNames))
            .joined(separator: "-")
    }

    private static func normalized(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }
            .sorted()
    }

    private static func repositoryKey(_ repositoryFullName: String) -> String {
        repositoryFullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func dateMarker(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }
}
