import Foundation

public enum RepositorySortKey: String, Sendable, CaseIterable, Codable {
    case activity
    case issues
    case pulls
    case stars
    case name
    case event
}

public enum RepositorySort {
    public static func sorted(
        _ repos: [Repository],
        sortKey: RepositorySortKey = .activity
    ) -> [Repository] {
        repos.sorted { self.isOrderedBefore($0, $1, sortKey: sortKey) }
    }

    public static func isOrderedBefore(
        _ lhs: Repository,
        _ rhs: Repository,
        sortKey: RepositorySortKey
    ) -> Bool {
        if let preferred = compare(lhs, rhs, sortKey: sortKey) {
            return preferred
        }
        if let preferred = compare(lhs, rhs, sortKey: .activity) {
            return preferred
        }
        if let preferred = compare(lhs, rhs, sortKey: .issues) {
            return preferred
        }
        if let preferred = compare(lhs, rhs, sortKey: .pulls) {
            return preferred
        }
        if let preferred = compare(lhs, rhs, sortKey: .stars) {
            return preferred
        }
        return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
    }

    private static func compare(
        _ lhs: Repository,
        _ rhs: Repository,
        sortKey: RepositorySortKey
    ) -> Bool? {
        switch sortKey {
        case .activity:
            let leftDate = lhs.activityDate ?? .distantPast
            let rightDate = rhs.activityDate ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return nil
        case .issues:
            if lhs.stats.openIssues != rhs.stats.openIssues {
                return lhs.stats.openIssues > rhs.stats.openIssues
            }
            return nil
        case .pulls:
            if lhs.stats.openPulls != rhs.stats.openPulls {
                return lhs.stats.openPulls > rhs.stats.openPulls
            }
            return nil
        case .stars:
            if lhs.stats.stars != rhs.stats.stars {
                return lhs.stats.stars > rhs.stats.stars
            }
            return nil
        case .name:
            let order = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName)
            if order != .orderedSame {
                return order == .orderedAscending
            }
            return nil
        case .event:
            let left = lhs.activityLine(fallbackToPush: true) ?? ""
            let right = rhs.activityLine(fallbackToPush: true) ?? ""
            if left != right {
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
            return nil
        }
    }
}
