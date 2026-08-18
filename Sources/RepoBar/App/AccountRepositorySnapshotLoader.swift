import Foundation
import RepoBarCore

struct AccountRepositoryPreferences {
    let pinned: [String]
    let hidden: Set<String>
    let includeForks: Bool
    let includeArchived: Bool
    let ownerFilter: [String]
}

struct AccountRepositorySnapshotRequest {
    let account: Account
    let client: GitHubClient
    let preferences: AccountRepositoryPreferences
    let now: Date
}

struct AccountRepositorySnapshot {
    let account: Account
    let accessibleRepositories: [Repository]
    let repositories: [Repository]
    let capturedAt: Date
    let diagnostics: DiagnosticsSummary
    let cacheSummary: RepoBarCacheSummary?
}

protocol AccountRepositorySnapshotLoading: Sendable {
    func cachedSnapshot(for request: AccountRepositorySnapshotRequest) async throws -> AccountRepositorySnapshot?
    func snapshot(for request: AccountRepositorySnapshotRequest) async throws -> AccountRepositorySnapshot
}

struct AccountRepositorySnapshotLoader: AccountRepositorySnapshotLoading {
    func cachedSnapshot(for request: AccountRepositorySnapshotRequest) async throws -> AccountRepositorySnapshot? {
        let repos = try await request.client.cachedRepositoryList(limit: nil)
        guard repos.isEmpty == false else { return nil }

        return await self.makeSnapshot(repositories: repos, request: request)
    }

    func snapshot(for request: AccountRepositorySnapshotRequest) async throws -> AccountRepositorySnapshot {
        let repos = try await request.client.repositoryList(limit: nil)
        let withPinned = await self.mergePinnedRepositories(
            into: repos,
            pinned: request.preferences.pinned,
            client: request.client
        )
        return await self.makeSnapshot(repositories: withPinned, request: request)
    }

    private func makeSnapshot(
        repositories: [Repository],
        request: AccountRepositorySnapshotRequest
    ) async -> AccountRepositorySnapshot {
        let accessible = RepositoryUniquing.byFullName(repositories)
        let visible = AppState.selectVisible(
            all: accessible,
            options: AppState.VisibleSelectionOptions(
                pinned: request.preferences.pinned,
                hidden: request.preferences.hidden,
                includeForks: request.preferences.includeForks,
                includeArchived: request.preferences.includeArchived,
                limit: Int.max,
                ownerFilter: request.preferences.ownerFilter
            )
        )
        let ordered = AppState.applyPinnedOrder(to: visible, pinned: request.preferences.pinned)
        let diagnostics = await request.client.diagnostics()
        let cacheSummary = try? RepoBarPersistentCache.summary(accountID: request.account.id, limit: 100)
        return AccountRepositorySnapshot(
            account: request.account,
            accessibleRepositories: accessible,
            repositories: ordered,
            capturedAt: request.now,
            diagnostics: diagnostics,
            cacheSummary: cacheSummary
        )
    }

    private func mergePinnedRepositories(
        into repos: [Repository],
        pinned: [String],
        client: GitHubClient
    ) async -> [Repository] {
        guard pinned.isEmpty == false else { return repos }

        let existing = Set(repos.map { $0.fullName.lowercased() })
        let targets = Self.pinnedRepoTargets(from: pinned, excluding: existing)
        guard targets.isEmpty == false else { return repos }

        let fetched = await withTaskGroup(of: Repository?.self) { group in
            for target in targets {
                group.addTask {
                    do {
                        return try await client.fullRepository(owner: target.owner, name: target.name)
                    } catch {
                        return Self.placeholderRepository(
                            owner: target.owner,
                            name: target.name,
                            error: error.userFacingMessage,
                            rateLimitedUntil: (error as? GitHubAPIError)?.rateLimitedUntil
                        )
                    }
                }
            }
            var output: [Repository] = []
            for await repo in group {
                if let repo {
                    output.append(repo)
                }
            }
            return output
        }
        return repos + fetched
    }

    private static func pinnedRepoTargets(
        from pinned: [String],
        excluding existing: Set<String>
    ) -> [PinnedRepoTarget] {
        var seen: Set<String> = []
        var targets: [PinnedRepoTarget] = []
        for raw in pinned {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let owner = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard owner.isEmpty == false, name.isEmpty == false else { continue }

            let normalized = "\(owner)/\(name)".lowercased()
            guard existing.contains(normalized) == false, seen.insert(normalized).inserted else { continue }

            targets.append(PinnedRepoTarget(owner: owner, name: name))
        }
        return targets
    }

    private static func placeholderRepository(
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

    private struct PinnedRepoTarget {
        let owner: String
        let name: String
    }
}
