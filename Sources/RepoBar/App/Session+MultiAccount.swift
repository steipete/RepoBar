import Foundation
import RepoBarCore

/// Per-account session snapshot. Populated by `AccountManager` and consumed by
/// `Session` to expose a multi-account view while keeping the existing
/// single-account fast path source compatible.
struct AccountSession: Identifiable {
    let id: String
    var account: Account
    var state: AccountState
    var repositories: [Repository]
    var accessibleRepositories: [Repository]
    var rateLimitReset: Date?
    var diagnostics: DiagnosticsSummary?
    var cacheSummary: RepoBarCacheSummary?
    var lastAttemptAt: Date?
    var lastSuccessfulRefreshAt: Date?
    var isStale: Bool
    var lastError: String?

    init(
        account: Account,
        state: AccountState = .loggedOut,
        repositories: [Repository] = [],
        accessibleRepositories: [Repository] = [],
        rateLimitReset: Date? = nil,
        diagnostics: DiagnosticsSummary? = nil,
        cacheSummary: RepoBarCacheSummary? = nil,
        lastAttemptAt: Date? = nil,
        lastSuccessfulRefreshAt: Date? = nil,
        isStale: Bool = false,
        lastError: String? = nil
    ) {
        self.id = account.id
        self.account = account
        self.state = state
        self.repositories = repositories
        self.accessibleRepositories = accessibleRepositories
        self.rateLimitReset = rateLimitReset
        self.diagnostics = diagnostics
        self.cacheSummary = cacheSummary
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.isStale = isStale
        self.lastError = lastError
    }
}

/// Collision-safe wrapper for repositories that originate from a specific
/// account. Used by the menu fan-out path so the same `Repository.id` can
/// appear under multiple accounts without clobbering Swift collection
/// identity (e.g. SwiftUI list diffing).
struct TaggedRepo: Identifiable, Equatable {
    var repo: Repository
    let accountID: String

    var id: String {
        "\(self.accountID)|\(self.repo.id)"
    }
}

extension Session {
    /// Helper for callers that want a tagged view of the current single-account
    /// repository list during the transition window. When fan-out across
    /// accounts is wired up, callers should prefer `aggregatedRepositories`.
    func taggedRepositoriesForCurrentAccount() -> [TaggedRepo] {
        let accountID = self.activeAccountID ?? self.settings.resolvedActiveAccount()?.id
        guard let accountID else { return [] }

        return self.repositories.map { TaggedRepo(repo: $0, accountID: accountID) }
    }
}
