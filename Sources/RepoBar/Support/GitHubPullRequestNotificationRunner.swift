import Algorithms
import Foundation
import RepoBarCore

@MainActor
final class GitHubPullRequestNotificationRunner {
    private let snapshotStore: GitHubPullRequestNotificationSnapshotStore
    private let logger = RepoBarLogging.logger("GitHubNotifications")

    init(snapshotStore: GitHubPullRequestNotificationSnapshotStore = GitHubPullRequestNotificationSnapshotStore()) {
        self.snapshotStore = snapshotStore
    }

    func process(
        settings: GitHubPullRequestNotificationSettings,
        pinnedRepositories: [String],
        github: GitHubClient,
        concurrencyLimit: Int
    ) async {
        guard settings.enabled else { return }

        let pinnedRepositories = Self.uniqueRepositoryFullNames(pinnedRepositories)
        guard pinnedRepositories.isEmpty == false else {
            self.snapshotStore.save(GitHubPullRequestNotificationSnapshotState())
            return
        }

        let refreshStartedAt = Date()
        let pullRequestsByRepository = await self.fetchPinnedPullRequests(
            for: pinnedRepositories,
            github: github,
            concurrencyLimit: concurrencyLimit,
            includeCommentCounts: settings.comments
        )

        let previousState = self.snapshotStore.load()
        let result = GitHubPullRequestNotificationDetector.events(
            for: pullRequestsByRepository,
            previousState: previousState,
            settings: settings,
            trackedRepositoryFullNames: pinnedRepositories,
            observedAt: refreshStartedAt
        )
        self.snapshotStore.save(result.state)

        self.logger.debug(
            "GitHub PR notification refresh: repos=\(pullRequestsByRepository.count), previousRepos=\(previousState.repositories.count), events=\(result.events.count)"
        )
        if result.events.isEmpty == false {
            self.logger.info("GitHub PR notification events detected: \(result.events.count)")
        }

        for event in result.events {
            await RepoBarNotifier.shared.notify(Self.notification(for: event, clickAction: settings.clickAction))
        }
    }

    func resetSnapshots() {
        self.snapshotStore.clear()
    }

    private func fetchPinnedPullRequests(
        for fullNames: [String],
        github: GitHubClient,
        concurrencyLimit: Int,
        includeCommentCounts: Bool
    ) async -> [String: [RepoPullRequestSummary]] {
        var result: [String: [RepoPullRequestSummary]] = [:]
        for chunk in fullNames.chunks(ofCount: max(1, concurrencyLimit)) {
            await withTaskGroup(of: (String, [RepoPullRequestSummary])?.self) { group in
                for fullName in chunk {
                    guard let parts = Self.repositoryParts(from: fullName) else { continue }

                    group.addTask {
                        do {
                            let pulls = try await github.recentPullRequests(
                                owner: parts.owner,
                                name: parts.name,
                                limit: 20,
                                state: .all,
                                includeCommentCounts: includeCommentCounts
                            )
                            return (fullName, pulls)
                        } catch {
                            return nil
                        }
                    }
                }

                for await entry in group {
                    guard let (fullName, pullRequests) = entry else { continue }

                    result[fullName] = pullRequests
                }
            }
        }

        return result
    }

    private static func notification(
        for event: GitHubPullRequestNotificationEvent,
        clickAction: GitHubPullRequestNotificationClickAction
    ) -> RepoBarNotification {
        RepoBarNotification(
            identifier: event.id,
            title: self.notificationTitle(for: event),
            body: self.notificationBody(for: event),
            url: event.url,
            clickAction: clickAction,
            issueNavigatorMatch: self.issueNavigatorMatch(for: event)
        )
    }

    private static func issueNavigatorMatch(for event: GitHubPullRequestNotificationEvent) -> GitHubReferenceMatch {
        GitHubReferenceMatch(
            query: .repositoryIssueNumber(
                repositoryFullName: event.repositoryFullName,
                number: event.pullRequestNumber
            ),
            title: event.title,
            url: event.url,
            repositoryFullName: event.repositoryFullName,
            kind: .pullRequest,
            state: nil,
            createdAt: nil,
            updatedAt: Date()
        )
    }

    private static func notificationTitle(for event: GitHubPullRequestNotificationEvent) -> String {
        switch event.kind {
        case .newPullRequest:
            "New PR in \(event.repositoryFullName)"
        case .pullRequestUpdated:
            "PR updated in \(event.repositoryFullName)"
        case .reviewRequested:
            "Review requested in \(event.repositoryFullName)"
        case .newComment:
            "New comment in \(event.repositoryFullName)"
        }
    }

    private static func notificationBody(for event: GitHubPullRequestNotificationEvent) -> String {
        let title = "#\(event.pullRequestNumber) \(event.title)"
        guard let detail = event.detail, detail.isEmpty == false else {
            return title
        }

        return "\(title)\n\(detail)"
    }

    private nonisolated static func uniqueRepositoryFullNames(_ fullNames: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for fullName in fullNames {
            let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard trimmed.isEmpty == false, seen.insert(key).inserted else { continue }

            result.append(trimmed)
        }
        return result
    }

    private nonisolated static func repositoryParts(from fullName: String) -> (owner: String, name: String)? {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].isEmpty == false, parts[1].isEmpty == false else { return nil }

        return (parts[0], parts[1])
    }
}
