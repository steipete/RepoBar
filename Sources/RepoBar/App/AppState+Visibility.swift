import Foundation
import RepoBarCore

extension AppState {
    func localMatchRepoNamesForLocalProjects(repos: [Repository], includePinned: Bool) -> Set<String> {
        var names = Set(repos.map(\.name))
        guard includePinned else { return names }

        let pinned = self.session.settings.repoList.pinnedRepositories
        for fullName in pinned {
            if let last = fullName.split(separator: "/").last {
                names.insert(String(last))
            }
        }
        return names
    }

    func applyVisibilityFilters(to repos: [Repository]) -> [Repository] {
        let options = AppState.VisibleSelectionOptions(
            pinned: self.session.settings.repoList.pinnedRepositories,
            hidden: Set(self.session.settings.repoList.hiddenRepositories),
            includeForks: self.session.settings.repoList.showForks,
            includeArchived: self.session.settings.repoList.showArchived,
            limit: Int.max,
            ownerFilter: self.session.settings.repoList.ownerFilter
        )
        return AppState.selectVisible(all: repos, options: options)
    }

    func selectMenuTargets(from repos: [Repository]) -> [Repository] {
        RepositoryPipeline.apply(repos, query: self.menuQuery())
    }

    private func menuQuery() -> RepositoryQuery {
        let selection = self.session.menuRepoSelection
        let settings = self.session.settings
        let scope: RepositoryScope = selection.isPinnedScope ? .pinned : .all
        let ageCutoff = RepositoryQueryDefaults.ageCutoff(
            scope: scope,
            ageDays: RepositoryQueryDefaults.defaultAgeDays
        )
        return RepositoryQuery(
            scope: scope,
            onlyWith: selection.onlyWith,
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            sortKey: settings.repoList.menuSortKey,
            limit: settings.repoList.displayLimit,
            ageCutoff: ageCutoff,
            pinned: settings.repoList.pinnedRepositories,
            hidden: Set(settings.repoList.hiddenRepositories),
            pinPriority: true,
            ownerFilter: settings.repoList.ownerFilter
        )
    }

    func applyPinnedOrder(to repos: [Repository]) -> [Repository] {
        let pinned = self.session.settings.repoList.pinnedRepositories
        let pinnedIndex = pinned.enumerated().reduce(into: [String: Int]()) { dict, entry in
            let key = self.normalizedFullName(entry.element)
            if dict[key] == nil { dict[key] = entry.offset }
        }
        return repos.map { repo in
            if let idx = pinnedIndex[self.normalizedFullName(repo.fullName)] {
                return repo.withOrder(idx)
            }
            return repo
        }
    }

    func addPinned(_ fullName: String) async {
        guard self.session.settings.repoList.pinRepository(fullName) else { return }

        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func removePinned(_ fullName: String) async {
        let normalized = self.normalizedFullName(fullName)
        self.session.settings.repoList.pinnedRepositories.removeAll {
            self.normalizedFullName($0) == normalized
        }
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func hide(_ fullName: String) async {
        let normalized = self.normalizedFullName(fullName)
        guard !self.session.settings.repoList.hiddenRepositories.contains(where: {
            self.normalizedFullName($0) == normalized
        }) else { return }

        self.session.settings.repoList.hiddenRepositories.append(fullName)
        // If hidden, also unpin to avoid stale pin list.
        self.session.settings.repoList.pinnedRepositories.removeAll {
            self.normalizedFullName($0) == normalized
        }
        self.settingsStore.save(self.session.settings)
        self.session.repositories.removeAll {
            self.normalizedFullName($0.fullName) == normalized
        }
        await self.refresh()
    }

    func unhide(_ fullName: String) async {
        let normalized = self.normalizedFullName(fullName)
        self.session.settings.repoList.hiddenRepositories.removeAll {
            self.normalizedFullName($0) == normalized
        }
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    /// Sets a repository's visibility in one place, keeping pinned/hidden arrays consistent.
    func setVisibility(for fullName: String, to visibility: RepoVisibility) async {
        // Always trim first to avoid storing whitespace variants.
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = self.normalizedFullName(trimmed)

        // Remove from both buckets before re-adding.
        self.session.settings.repoList.pinnedRepositories.removeAll {
            self.normalizedFullName($0) == normalized
        }
        self.session.settings.repoList.hiddenRepositories.removeAll {
            self.normalizedFullName($0) == normalized
        }

        switch visibility {
        case .pinned:
            self.session.settings.repoList.pinnedRepositories.append(trimmed)
        case .hidden:
            self.session.settings.repoList.hiddenRepositories.append(trimmed)
        case .visible:
            break
        }

        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    struct VisibleSelectionOptions {
        let pinned: [String]
        let hidden: Set<String>
        let includeForks: Bool
        let includeArchived: Bool
        let limit: Int
        let ownerFilter: [String]
    }

    nonisolated static func selectVisible(all repos: [Repository], options: VisibleSelectionOptions) -> [Repository] {
        let uniqueRepos = RepositoryUniquing.byFullName(repos)
        let pinnedSet = Set(options.pinned.map { $0.lowercased() })
        let hiddenSet = Set(options.hidden.map { $0.lowercased() })
        let filtered = uniqueRepos.filter {
            let key = $0.fullName.lowercased()
            return !hiddenSet.contains(key) || pinnedSet.contains(key)
        }
        let visible = RepositoryFilter.apply(
            filtered,
            includeForks: options.includeForks,
            includeArchived: options.includeArchived,
            pinned: pinnedSet,
            ownerFilter: options.ownerFilter
        )
        let limited = Array(visible.prefix(max(options.limit, 0)))
        return limited.sorted { lhs, rhs in
            let lhsIndex = options.pinned.firstIndex { $0.caseInsensitiveCompare(lhs.fullName) == .orderedSame }
            let rhsIndex = options.pinned.firstIndex { $0.caseInsensitiveCompare(rhs.fullName) == .orderedSame }
            switch (lhsIndex, rhsIndex) {
            case let (l?, r?):
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return false
            }
        }
    }

    private func normalizedFullName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension RepoListSettings {
    @discardableResult
    mutating func pinRepository(_ fullName: String) -> Bool {
        let normalized = Self.normalizedFullName(fullName)
        let alreadyPinned = self.pinnedRepositories.contains {
            Self.normalizedFullName($0) == normalized
        }
        let isHidden = self.hiddenRepositories.contains {
            Self.normalizedFullName($0) == normalized
        }
        // Nothing to do only when it is already pinned and not hidden. If it is
        // already pinned but somehow still hidden, fall through to repair that.
        guard !alreadyPinned || isHidden else { return false }

        if !alreadyPinned {
            self.pinnedRepositories.append(fullName)
        }
        // If pinned, also unhide to keep pinned and hidden mutually exclusive.
        // This mirrors hide(), which removes the repo from the pinned list.
        self.hiddenRepositories.removeAll {
            Self.normalizedFullName($0) == normalized
        }
        return true
    }

    private static func normalizedFullName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
