import Foundation
import RepoBarCore

extension AppState {
    func fetchGlobalActivityEvents(
        username: String,
        scope: GlobalActivityScope,
        repos: [Repository]
    ) async -> GlobalActivityResult {
        let repoEvents = GlobalActivityMerger.repositoryEvents(from: repos)
        async let activityResult: Result<[ActivityEvent], Error> = self.capture {
            try await self.github.userActivityEvents(
                username: username,
                scope: scope,
                limit: AppLimits.GlobalActivity.limit
            )
        }
        async let commitResult: Result<[RepoCommitSummary], Error> = self.capture {
            try await self.github.userCommitEvents(
                username: username,
                scope: scope,
                limit: AppLimits.GlobalCommits.limit
            )
        }

        let activityEvents: [ActivityEvent]
        let activityError: String?
        switch await activityResult {
        case let .success(events):
            activityEvents = events
            activityError = nil
        case let .failure(error):
            activityEvents = []
            activityError = error.userFacingMessage
        }

        let commitEvents: [RepoCommitSummary]
        let commitError: String?
        switch await commitResult {
        case let .success(commits):
            commitEvents = commits
            commitError = nil
        case let .failure(error):
            commitEvents = []
            commitError = error.userFacingMessage
        }

        let merged = GlobalActivityMerger.merge(
            userEvents: activityEvents,
            repoEvents: repoEvents,
            scope: scope,
            username: username,
            limit: AppLimits.GlobalActivity.limit
        )

        return GlobalActivityResult(
            events: merged,
            commits: commitEvents,
            error: activityError,
            commitError: commitError
        )
    }

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }
}
