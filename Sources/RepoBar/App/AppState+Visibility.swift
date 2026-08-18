import Foundation
import RepoBarCore

extension AppState {
    func localMatchRepoNamesForLocalProjects(repos: [Repository], includePinned: Bool) -> Set<String> {
        var names = Set(repos.map(\.name))
        guard includePinned else { return names }

        let pinned = self.activePinnedRepositories
        for fullName in pinned {
            if let last = fullName.split(separator: "/").last {
                names.insert(String(last))
            }
        }
        return names
    }

    func applyVisibilityFilters(to repos: [Repository]) -> [Repository] {
        guard let accountID = self.resolvedActiveRepositoryAccountID else {
            return self.applyLegacyVisibilityFilters(to: repos)
        }

        return self.applyVisibilityFilters(to: repos, accountID: accountID)
    }

    func applyVisibilityFilters(to repos: [Repository], accountID: String) -> [Repository] {
        let preferences = self.repositoryPreferences(for: accountID)
        let options = AppState.VisibleSelectionOptions(
            pinned: preferences.pinned,
            hidden: preferences.hidden,
            includeForks: preferences.includeForks,
            includeArchived: preferences.includeArchived,
            limit: Int.max,
            ownerFilter: preferences.ownerFilter
        )
        return AppState.selectVisible(all: repos, options: options)
    }

    func selectMenuTargets(from repos: [Repository]) -> [Repository] {
        RepositoryPipeline.apply(repos, query: self.menuQuery())
    }

    private func menuQuery() -> RepositoryQuery {
        let selection = self.session.menuRepoSelection
        let settings = self.session.settings
        let pinned = self.activePinnedRepositories
        let hidden = self.activeHiddenRepositories
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
            pinned: pinned,
            hidden: Set(hidden),
            pinPriority: true,
            ownerFilter: settings.repoList.ownerFilter
        )
    }

    func applyPinnedOrder(to repos: [Repository]) -> [Repository] {
        Self.applyPinnedOrder(to: repos, pinned: self.activePinnedRepositories)
    }

    func applyPinnedOrder(to repos: [Repository], accountID: String) -> [Repository] {
        Self.applyPinnedOrder(to: repos, pinned: self.session.settings.pinnedRepositories(for: accountID))
    }

    nonisolated static func applyPinnedOrder(to repos: [Repository], pinned: [String]) -> [Repository] {
        let pinnedIndex = pinned.enumerated().reduce(into: [String: Int]()) { dict, entry in
            let key = Self.normalizedFullName(entry.element)
            if dict[key] == nil {
                dict[key] = entry.offset
            }
        }
        return repos.map { repo in
            if let idx = pinnedIndex[Self.normalizedFullName(repo.fullName)] {
                return repo.withOrder(idx)
            }
            return repo
        }
    }

    func addPinned(_ fullName: String) async {
        guard let accountID = self.resolvedActiveRepositoryAccountID else {
            guard self.session.settings.repoList.pinRepository(fullName) else { return }

            self.persistSettings()
            await self.refresh()
            return
        }

        await self.addPinned(fullName, accountID: accountID)
    }

    func addPinned(_ fullName: String, accountID: String) async {
        let normalized = Self.normalizedFullName(fullName)
        guard normalized.isEmpty == false else { return }

        var pinned = self.session.settings.pinnedRepositories(for: accountID)
        var hidden = self.session.settings.hiddenRepositories(for: accountID)
        let alreadyPinned = pinned.contains { Self.normalizedFullName($0) == normalized }
        let wasHidden = hidden.contains { Self.normalizedFullName($0) == normalized }
        guard alreadyPinned == false || wasHidden else { return }

        if alreadyPinned == false {
            pinned.append(fullName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        hidden.removeAll { Self.normalizedFullName($0) == normalized }
        self.session.settings.setPinnedRepositories(pinned, for: accountID)
        self.session.settings.setHiddenRepositories(hidden, for: accountID)
        await self.finishRepositoryPreferenceMutation(accountID: accountID)
    }

    func removePinned(_ fullName: String) async {
        guard let accountID = self.resolvedActiveRepositoryAccountID else {
            let normalized = Self.normalizedFullName(fullName)
            self.session.settings.repoList.pinnedRepositories.removeAll {
                Self.normalizedFullName($0) == normalized
            }
            self.persistSettings()
            await self.refresh()
            return
        }

        await self.removePinned(fullName, accountID: accountID)
    }

    func removePinned(_ fullName: String, accountID: String) async {
        let normalized = Self.normalizedFullName(fullName)
        var pinned = self.session.settings.pinnedRepositories(for: accountID)
        let previousCount = pinned.count
        pinned.removeAll { Self.normalizedFullName($0) == normalized }
        guard pinned.count != previousCount else { return }

        self.session.settings.setPinnedRepositories(pinned, for: accountID)
        await self.finishRepositoryPreferenceMutation(accountID: accountID)
    }

    func hide(_ fullName: String) async {
        guard let accountID = self.resolvedActiveRepositoryAccountID else {
            let normalized = Self.normalizedFullName(fullName)
            guard !self.session.settings.repoList.hiddenRepositories.contains(where: {
                Self.normalizedFullName($0) == normalized
            }) else { return }

            self.session.settings.repoList.hiddenRepositories.append(fullName)
            self.session.settings.repoList.pinnedRepositories.removeAll {
                Self.normalizedFullName($0) == normalized
            }
            self.persistSettings()
            self.session.repositories.removeAll {
                Self.normalizedFullName($0.fullName) == normalized
            }
            await self.refresh()
            return
        }

        await self.hide(fullName, accountID: accountID)
    }

    func hide(_ fullName: String, accountID: String) async {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalizedFullName(trimmed)
        guard normalized.isEmpty == false else { return }

        var pinned = self.session.settings.pinnedRepositories(for: accountID)
        var hidden = self.session.settings.hiddenRepositories(for: accountID)
        let alreadyHidden = hidden.contains { Self.normalizedFullName($0) == normalized }
        let wasPinned = pinned.contains { Self.normalizedFullName($0) == normalized }
        guard alreadyHidden == false || wasPinned else { return }

        if alreadyHidden == false {
            hidden.append(trimmed)
        }
        pinned.removeAll { Self.normalizedFullName($0) == normalized }
        self.session.settings.setPinnedRepositories(pinned, for: accountID)
        self.session.settings.setHiddenRepositories(hidden, for: accountID)
        if self.isActiveRepositoryAccount(accountID) {
            self.session.repositories.removeAll {
                Self.normalizedFullName($0.fullName) == normalized
            }
        }
        await self.finishRepositoryPreferenceMutation(accountID: accountID)
    }

    func unhide(_ fullName: String) async {
        guard let accountID = self.resolvedActiveRepositoryAccountID else {
            let normalized = Self.normalizedFullName(fullName)
            self.session.settings.repoList.hiddenRepositories.removeAll {
                Self.normalizedFullName($0) == normalized
            }
            self.persistSettings()
            await self.refresh()
            return
        }

        await self.unhide(fullName, accountID: accountID)
    }

    func unhide(_ fullName: String, accountID: String) async {
        let normalized = Self.normalizedFullName(fullName)
        var hidden = self.session.settings.hiddenRepositories(for: accountID)
        let previousCount = hidden.count
        hidden.removeAll { Self.normalizedFullName($0) == normalized }
        guard hidden.count != previousCount else { return }

        self.session.settings.setHiddenRepositories(hidden, for: accountID)
        await self.finishRepositoryPreferenceMutation(accountID: accountID)
    }

    /// Sets a repository's visibility in one place, keeping pinned/hidden arrays consistent.
    func setVisibility(for fullName: String, to visibility: RepoVisibility) async {
        guard let accountID = self.resolvedActiveRepositoryAccountID else {
            await self.setLegacyVisibility(for: fullName, to: visibility)
            return
        }

        await self.setVisibility(for: fullName, to: visibility, accountID: accountID)
    }

    func setVisibility(for fullName: String, to visibility: RepoVisibility, accountID: String) async {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = Self.normalizedFullName(trimmed)
        var pinned = self.session.settings.pinnedRepositories(for: accountID)
        var hidden = self.session.settings.hiddenRepositories(for: accountID)
        pinned.removeAll { Self.normalizedFullName($0) == normalized }
        hidden.removeAll { Self.normalizedFullName($0) == normalized }

        switch visibility {
        case .pinned:
            pinned.append(trimmed)
        case .hidden:
            hidden.append(trimmed)
        case .visible:
            break
        }

        self.session.settings.setPinnedRepositories(pinned, for: accountID)
        self.session.settings.setHiddenRepositories(hidden, for: accountID)
        await self.finishRepositoryPreferenceMutation(accountID: accountID)
    }

    func movePinned(_ fullName: String, direction: Int) async {
        guard let accountID = self.resolvedActiveRepositoryAccountID else {
            var pinned = self.session.settings.repoList.pinnedRepositories
            guard Self.movePinned(fullName, direction: direction, in: &pinned) else { return }

            self.session.settings.repoList.pinnedRepositories = pinned
            self.persistSettings()
            self.requestRefresh(cancelInFlight: true)
            return
        }

        await self.movePinned(fullName, direction: direction, accountID: accountID)
    }

    func movePinned(_ fullName: String, direction: Int, accountID: String) async {
        var pinned = self.session.settings.pinnedRepositories(for: accountID)
        guard Self.movePinned(fullName, direction: direction, in: &pinned) else { return }

        self.session.settings.setPinnedRepositories(pinned, for: accountID)
        self.persistSettings()
        if self.isActiveRepositoryAccount(accountID) {
            self.requestRefresh(cancelInFlight: true)
        }
    }

    func repositoryPreferences(for accountID: String) -> AccountRepositoryPreferences {
        let settings = self.session.settings
        return AccountRepositoryPreferences(
            pinned: settings.pinnedRepositories(for: accountID),
            hidden: Set(settings.hiddenRepositories(for: accountID)),
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            ownerFilter: settings.repoList.ownerFilter
        )
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

    private var resolvedActiveRepositoryAccountID: String? {
        self.session.settings.resolvedActiveAccount()?.id
    }

    var activePinnedRepositories: [String] {
        guard let accountID = self.resolvedActiveRepositoryAccountID else {
            return self.session.settings.repoList.pinnedRepositories
        }

        return self.session.settings.pinnedRepositories(for: accountID)
    }

    var activeHiddenRepositories: [String] {
        guard let accountID = self.resolvedActiveRepositoryAccountID else {
            return self.session.settings.repoList.hiddenRepositories
        }

        return self.session.settings.hiddenRepositories(for: accountID)
    }

    private func isActiveRepositoryAccount(_ accountID: String) -> Bool {
        self.resolvedActiveRepositoryAccountID == accountID
    }

    private func applyLegacyVisibilityFilters(to repos: [Repository]) -> [Repository] {
        let settings = self.session.settings
        return Self.selectVisible(
            all: repos,
            options: VisibleSelectionOptions(
                pinned: settings.repoList.pinnedRepositories,
                hidden: Set(settings.repoList.hiddenRepositories),
                includeForks: settings.repoList.showForks,
                includeArchived: settings.repoList.showArchived,
                limit: Int.max,
                ownerFilter: settings.repoList.ownerFilter
            )
        )
    }

    private func setLegacyVisibility(for fullName: String, to visibility: RepoVisibility) async {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let normalized = Self.normalizedFullName(trimmed)
        self.session.settings.repoList.pinnedRepositories.removeAll {
            Self.normalizedFullName($0) == normalized
        }
        self.session.settings.repoList.hiddenRepositories.removeAll {
            Self.normalizedFullName($0) == normalized
        }
        switch visibility {
        case .pinned:
            self.session.settings.repoList.pinnedRepositories.append(trimmed)
        case .hidden:
            self.session.settings.repoList.hiddenRepositories.append(trimmed)
        case .visible:
            break
        }
        self.persistSettings()
        await self.refresh()
    }

    private func finishRepositoryPreferenceMutation(accountID: String) async {
        self.persistSettings()
        if self.isActiveRepositoryAccount(accountID) {
            await self.refresh()
        }
    }

    private nonisolated static func movePinned(_ fullName: String, direction: Int, in pinned: inout [String]) -> Bool {
        guard let currentIndex = pinned.firstIndex(where: {
            $0.caseInsensitiveCompare(fullName) == .orderedSame
        }) else { return false }

        let maxIndex = max(pinned.count - 1, 0)
        let target = max(0, min(maxIndex, currentIndex + direction))
        guard target != currentIndex else { return false }

        pinned.move(
            fromOffsets: IndexSet(integer: currentIndex),
            toOffset: target > currentIndex ? target + 1 : target
        )
        return true
    }

    private nonisolated static func normalizedFullName(_ value: String) -> String {
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
