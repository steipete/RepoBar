import Foundation

public struct RepositoryOnlyWith: Sendable, Equatable {
    public var requireIssues: Bool
    public var requirePRs: Bool

    public init(requireIssues: Bool = false, requirePRs: Bool = false) {
        self.requireIssues = requireIssues
        self.requirePRs = requirePRs
    }

    public static let none = RepositoryOnlyWith()

    public var isActive: Bool {
        self.requireIssues || self.requirePRs
    }

    public func matches(_ repo: Repository) -> Bool {
        let hasIssues = repo.stats.openIssues > 0
        let hasPRs = repo.stats.openPulls > 0

        var ok = false
        if self.requireIssues {
            ok = ok || hasIssues
        }
        if self.requirePRs {
            ok = ok || hasPRs
        }
        return ok
    }
}
