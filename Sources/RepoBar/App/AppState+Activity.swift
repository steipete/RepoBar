import Foundation
import RepoBarCore

extension AppState {
    func fetchActivityRepos() async throws -> [Repository] {
        let repos = try await self.github.repositoryList(limit: nil)
        let pinned = self.session.settings.repoList.pinnedRepositories
        return await self.mergePinnedRepositories(into: repos, pinned: pinned)
    }

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

    private func mergePinnedRepositories(
        into repos: [Repository],
        pinned: [String]
    ) async -> [Repository] {
        guard !pinned.isEmpty else { return repos }

        let existing = Set(repos.map { $0.fullName.lowercased() })
        let targets = self.pinnedRepoTargets(from: pinned, excluding: existing)
        guard !targets.isEmpty else { return repos }

        let fetched = await withTaskGroup(of: Repository?.self) { group in
            for target in targets {
                group.addTask { [github] in
                    do {
                        return try await github.fullRepository(owner: target.owner, name: target.name)
                    } catch {
                        let rateLimitedUntil = (error as? GitHubAPIError)?.rateLimitedUntil
                        return Self.placeholderRepository(
                            owner: target.owner,
                            name: target.name,
                            error: error.userFacingMessage,
                            rateLimitedUntil: rateLimitedUntil
                        )
                    }
                }
            }
            var out: [Repository] = []
            for await repo in group {
                if let repo {
                    out.append(repo)
                }
            }
            return out
        }

        return repos + fetched
    }

    private struct PinnedRepoTarget: Hashable {
        let owner: String
        let name: String

        var fullName: String {
            "\(self.owner)/\(self.name)"
        }
    }

    private func pinnedRepoTargets(
        from pinned: [String],
        excluding existing: Set<String>
    ) -> [PinnedRepoTarget] {
        var seen: Set<String> = []
        var targets: [PinnedRepoTarget] = []
        for raw in pinned {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let owner = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !owner.isEmpty, !name.isEmpty else { continue }

            let fullName = "\(owner)/\(name)"
            let normalized = fullName.lowercased()
            guard !existing.contains(normalized) else { continue }
            guard seen.insert(normalized).inserted else { continue }

            targets.append(PinnedRepoTarget(owner: owner, name: name))
        }
        return targets
    }

    private nonisolated static func placeholderRepository(
        owner: String,
        name: String,
        error: String?,
        rateLimitedUntil: Date?
    ) -> Repository {
        Repository(
            id: "\(owner)/\(name)",
            name: name,
            owner: owner,
            sortOrder: nil,
            error: error,
            rateLimitedUntil: rateLimitedUntil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            forks: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
    }
}
