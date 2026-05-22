import Foundation
import RepoBarCore

struct RepoBrowserRow: Identifiable, Hashable {
    let id: String
    let fullName: String
    let owner: String
    let name: String
    let visibility: RepoVisibility
    let isFork: Bool
    let isArchived: Bool
    let isManual: Bool
    let openIssues: Int?
    let openPulls: Int?
    let stars: Int?
    let pushedAt: Date?
    let updatedLabel: String

    var issueLabel: String {
        self.openIssues.map(String.init) ?? "-"
    }

    var pullRequestLabel: String {
        self.openPulls.map(String.init) ?? "-"
    }

    var starLabel: String {
        self.stars.map(String.init) ?? "-"
    }

    // MARK: - Sortable keys

    //
    // KeyPathComparator needs concrete Comparable values, so optional stats are
    // folded to sentinels that sink unknown rows to the "low" end of the order.

    var visibilitySortKey: Int {
        self.visibility.sortPriority
    }

    var sortableIssues: Int {
        self.openIssues ?? -1
    }

    var sortablePulls: Int {
        self.openPulls ?? -1
    }

    var sortableStars: Int {
        self.stars ?? -1
    }

    var sortablePushedAt: Date {
        self.pushedAt ?? .distantPast
    }

    func matches(_ query: String) -> Bool {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
        guard !terms.isEmpty else { return true }

        let haystack = [
            self.fullName,
            self.owner,
            self.name,
            self.visibility.label,
            self.isFork ? "fork" : "",
            self.isArchived ? "archived" : "",
            self.isManual ? "manual" : ""
        ]
        .joined(separator: " ")
        .lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }
}

enum RepoBrowserRows {
    static func make(
        repositories: [Repository],
        pinnedRepositories: [String],
        hiddenRepositories: [String],
        now: Date
    ) -> [RepoBrowserRow] {
        let pinnedSet = Set(pinnedRepositories.map(Self.normalized))
        let hiddenSet = Set(hiddenRepositories.map(Self.normalized))
        let uniqueRepos = RepositoryUniquing.byFullName(repositories)

        var rows = uniqueRepos.map { repo in
            let key = Self.normalized(repo.fullName)
            let visibility: RepoVisibility = if hiddenSet.contains(key) {
                .hidden
            } else if pinnedSet.contains(key) {
                .pinned
            } else {
                .visible
            }
            return RepoBrowserRow(
                id: key,
                fullName: repo.fullName,
                owner: repo.owner,
                name: repo.name,
                visibility: visibility,
                isFork: repo.isFork,
                isArchived: repo.isArchived,
                isManual: false,
                openIssues: repo.stats.openIssues,
                openPulls: repo.stats.openPulls,
                stars: repo.stats.stars,
                pushedAt: repo.stats.pushedAt,
                updatedLabel: repo.stats.pushedAt.map { RelativeFormatter.string(from: $0, relativeTo: now) } ?? "-"
            )
        }

        let loadedKeys = Set(rows.map(\.id))
        for name in pinnedRepositories where !loadedKeys.contains(Self.normalized(name)) {
            rows.append(Self.manualRow(fullName: name, visibility: .pinned))
        }
        for name in hiddenRepositories where !loadedKeys.contains(Self.normalized(name)) {
            rows.append(Self.manualRow(fullName: name, visibility: .hidden))
        }

        return rows.sorted { lhs, rhs in
            if lhs.visibility.sortPriority != rhs.visibility.sortPriority {
                return lhs.visibility.sortPriority < rhs.visibility.sortPriority
            }
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
    }

    static func filter(_ rows: [RepoBrowserRow], query: String) -> [RepoBrowserRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }

        return rows.filter { $0.matches(trimmed) }
    }

    static func statusLine(allRows: [RepoBrowserRow], filteredRows: [RepoBrowserRow]) -> String {
        let total = allRows.count
        let visible = filteredRows.count
        let loaded = allRows.count(where: { !$0.isManual })
        let pinned = allRows.count(where: { $0.visibility == .pinned })
        let hidden = allRows.count(where: { $0.visibility == .hidden })
        if visible == total {
            return "\(total) repositories, \(loaded) loaded, \(pinned) pinned, \(hidden) hidden"
        }
        return "\(visible) of \(total) repositories, \(pinned) pinned, \(hidden) hidden"
    }

    private static func manualRow(fullName: String, visibility: RepoVisibility) -> RepoBrowserRow {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
        let owner = parts.count == 2 ? parts[0] : ""
        let name = parts.count == 2 ? parts[1] : trimmed
        return RepoBrowserRow(
            id: Self.normalized(trimmed),
            fullName: trimmed,
            owner: owner,
            name: name,
            visibility: visibility,
            isFork: false,
            isArchived: false,
            isManual: true,
            openIssues: nil,
            openPulls: nil,
            stars: nil,
            pushedAt: nil,
            updatedLabel: "-"
        )
    }

    private static func normalized(_ fullName: String) -> String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension RepoVisibility {
    var sortPriority: Int {
        switch self {
        case .pinned: 0
        case .visible: 1
        case .hidden: 2
        }
    }
}
