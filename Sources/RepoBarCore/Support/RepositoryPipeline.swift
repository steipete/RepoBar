import Foundation

public enum RepositoryScope: String, CaseIterable, Codable, Sendable {
    case all
    case pinned
    case hidden
}

public struct RepositoryQuery: Equatable, Sendable {
    public var scope: RepositoryScope
    public var onlyWith: RepositoryOnlyWith
    public var includeForks: Bool
    public var includeArchived: Bool
    public var sortKey: RepositorySortKey
    public var limit: Int?
    public var ageCutoff: Date?
    public var pinned: [String]
    public var hidden: Set<String>
    public var pinPriority: Bool
    public var ownerFilter: [String]

    public init(
        scope: RepositoryScope = .all,
        onlyWith: RepositoryOnlyWith = .none,
        includeForks: Bool = false,
        includeArchived: Bool = false,
        sortKey: RepositorySortKey = .activity,
        limit: Int? = nil,
        ageCutoff: Date? = nil,
        pinned: [String] = [],
        hidden: Set<String> = [],
        pinPriority: Bool = false,
        ownerFilter: [String] = []
    ) {
        self.scope = scope
        self.onlyWith = onlyWith
        self.includeForks = includeForks
        self.includeArchived = includeArchived
        self.sortKey = sortKey
        self.limit = limit
        self.ageCutoff = ageCutoff
        self.pinned = pinned
        self.hidden = hidden
        self.pinPriority = pinPriority
        self.ownerFilter = OwnerFilter.normalize(ownerFilter)
    }
}

public enum RepositoryQueryDefaults {
    public static let defaultAgeDays = 365

    public static func ageCutoff(
        now: Date = Date(),
        scope: RepositoryScope,
        ageDays: Int = defaultAgeDays
    ) -> Date? {
        guard scope == .all, ageDays > 0 else { return nil }

        return Calendar.current.date(byAdding: .day, value: -ageDays, to: now)
    }
}

public enum RepositoryPipeline {
    public static func apply(_ repos: [Repository], query: RepositoryQuery) -> [Repository] {
        var filtered = RepositoryUniquing.byFullName(repos)
        let pinnedSet = Set(query.pinned.map { $0.lowercased() })
        let hiddenSet = Set(query.hidden.map { $0.lowercased() })

        switch query.scope {
        case .hidden:
            filtered = filtered.filter {
                let key = $0.fullName.lowercased()
                return hiddenSet.contains(key) && !pinnedSet.contains(key)
            }
        case .all, .pinned:
            if !hiddenSet.isEmpty {
                filtered = filtered.filter {
                    let key = $0.fullName.lowercased()
                    return !hiddenSet.contains(key) || pinnedSet.contains(key)
                }
            }
        }

        filtered = RepositoryFilter.apply(
            filtered,
            includeForks: query.includeForks,
            includeArchived: query.includeArchived,
            pinned: pinnedSet,
            ownerFilter: query.ownerFilter
        )

        if let cutoff = query.ageCutoff {
            filtered = filtered.filter { ($0.activityDate ?? .distantPast) >= cutoff }
        }

        if query.scope == .pinned {
            filtered = filtered.filter { pinnedSet.contains($0.fullName.lowercased()) }
        }

        if query.onlyWith.isActive {
            filtered = filtered.filter { query.onlyWith.matches($0) }
        }

        var sorted: [Repository]
        if query.pinPriority, !query.pinned.isEmpty {
            let pinnedIndex = query.pinned.enumerated().reduce(into: [String: Int]()) { dict, entry in
                let key = entry.element.lowercased()
                if dict[key] == nil { dict[key] = entry.offset }
            }
            sorted = filtered.sorted { lhs, rhs in
                let leftIndex = pinnedIndex[lhs.fullName.lowercased()]
                let rightIndex = pinnedIndex[rhs.fullName.lowercased()]
                switch (leftIndex, rightIndex) {
                case let (left?, right?):
                    if left != right { return left < right }
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
                return RepositorySort.isOrderedBefore(lhs, rhs, sortKey: query.sortKey)
            }
        } else {
            sorted = RepositorySort.sorted(filtered, sortKey: query.sortKey)
        }

        if let limit = query.limit {
            return Array(sorted.prefix(max(limit, 0)))
        }
        return sorted
    }
}
