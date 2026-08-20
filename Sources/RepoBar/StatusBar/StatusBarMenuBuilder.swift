import AppKit
import OSLog
import RepoBarCore
import SwiftUI

@MainActor
final class StatusBarMenuBuilder {
    private static let menuFixedWidth: CGFloat = 360

    let appState: AppState
    unowned let target: StatusBarMenuManager
    let signposter = OSSignposter(subsystem: "com.steipete.repobar", category: "menu")
    var repoMenuItemsByID: [AccountScopedCacheKey: NSMenuItem] = [:]
    var repoSubmenusByFullName: [AccountScopedCacheKey: RepoSubmenuCacheEntry] = [:]
    var systemImageCache: [String: NSImage] = [:]
    let menuItemFactory = MenuItemViewFactory()

    init(appState: AppState, target: StatusBarMenuManager) {
        self.appState = appState
        self.target = target
    }

    func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self.target
        menu.appearance = nil
        return menu
    }

    func mainMenuPlan(now: Date = Date()) -> MainMenuPlan {
        let session = self.appState.session
        let settings = session.settings
        let repos = self.orderedViewModels(now: now)
        let signature = MenuBuildSignature(
            account: AccountSignature(session.account),
            settings: MenuSettingsSignature(settings: settings, selection: session.menuRepoSelection),
            hasLoadedRepositories: session.hasLoadedRepositories,
            rateLimitReset: session.rateLimitReset,
            rateLimits: RateLimitMenuSignature(session.rateLimitDisplayState),
            lastError: session.lastError,
            contribution: ContributionSignature(
                user: session.contributionUser,
                error: session.contributionError,
                heatmapCount: session.contributionHeatmap.count
            ),
            globalActivity: ActivitySignature(
                events: session.globalActivityEvents,
                error: session.globalActivityError
            ),
            globalCommits: CommitSignature(
                commits: session.globalCommitEvents,
                error: session.globalCommitError
            ),
            heatmapRangeStart: session.heatmapRange.start.timeIntervalSinceReferenceDate,
            heatmapRangeEnd: session.heatmapRange.end.timeIntervalSinceReferenceDate,
            reposDigest: RepoSignature.digest(for: repos),
            actionsDigest: ActionsSnapshotSignature.digest(for: session.actionsOrgSnapshots),
            timeBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )
        return MainMenuPlan(repos: repos, signature: signature)
    }

    func populateMainMenu(_ menu: NSMenu, repos: [RepositoryDisplayModel]) {
        let signpost = self.signposter.beginInterval("populateMainMenu")
        defer { self.signposter.endInterval("populateMainMenu", signpost) }
        menu.removeAllItems()
        let session = self.appState.session
        let settings = session.settings
        let customization = settings.menuCustomization.normalized()
        let blocks = self.mainMenuBlocks(repos: repos, settings: settings, customization: customization)
        self.flattenMainMenuBlocks(blocks).forEach { menu.addItem($0) }
    }

    private struct MainMenuBlock {
        let group: MainMenuItemGroup
        let items: [NSMenuItem]
    }

    private func mainMenuBlocks(
        repos: [RepositoryDisplayModel],
        settings: UserSettings,
        customization: MenuCustomization
    ) -> [MainMenuBlock] {
        let session = self.appState.session
        var blocks: [MainMenuBlock] = []
        for itemID in customization.mainMenuOrder {
            if customization.hiddenMainMenuItems.contains(itemID), !itemID.isRequired {
                continue
            }
            let items = self.mainMenuItems(for: itemID, repos: repos, settings: settings, session: session)
            if items.isEmpty {
                continue
            }
            blocks.append(MainMenuBlock(group: itemID.group, items: items))
        }
        return blocks
    }

    private func mainMenuItems(
        for itemID: MainMenuItemID,
        repos: [RepositoryDisplayModel],
        settings: UserSettings,
        session: Session
    ) -> [NSMenuItem] {
        switch itemID {
        case .loggedOutPrompt:
            switch session.account {
            case .loggedOut, .loggingIn:
                let loggedOut = MenuLoggedOutView()
                    .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                    .padding(.vertical, MenuStyle.sectionVerticalPadding)
                return [self.viewItem(for: loggedOut, enabled: false)]
            case .loggedIn:
                return []
            }
        case .signInAction:
            switch session.account {
            case .loggedOut:
                return [self.actionItem(title: "Sign in to GitHub", action: #selector(self.target.signIn))]
            case .loggingIn:
                let signInItem = self.actionItem(title: "Signing in…", action: #selector(self.target.signIn))
                signInItem.isEnabled = false
                return [signInItem]
            case .loggedIn:
                return []
            }
        case .contributionHeader:
            guard case .loggedIn = session.account else { return [] }

            let hasContributionHeatmap = session.contributionHeatmap.isEmpty == false
            let shouldShowContributionHeader = settings.appearance.showContributionHeader
                && (hasContributionHeatmap || session.contributionError == nil)
            let username = self.currentUsername()
            let displayName = self.currentDisplayName()
            guard shouldShowContributionHeader, let username, let displayName else { return [] }

            let header = ContributionHeaderView(
                username: username,
                displayName: displayName,
                session: session,
                appState: self.appState
            )
            .padding(.horizontal, MenuStyle.headerHorizontalPadding)
            .padding(.top, MenuStyle.headerTopPadding)
            .padding(.bottom, MenuStyle.headerBottomPadding)
            let submenu = self.contributionSubmenu(username: username, displayName: displayName)
            return [self.viewItem(for: header, enabled: true, submenu: submenu)]
        case .statusBanner:
            guard case .loggedIn = session.account else { return [] }

            if let reset = session.rateLimitReset {
                let banner = RateLimitBanner(reset: reset)
                    .padding(.horizontal, MenuStyle.bannerHorizontalPadding)
                    .padding(.vertical, MenuStyle.bannerVerticalPadding)
                return [self.viewItem(for: banner, enabled: false)]
            }
            if let error = session.lastError {
                let banner = ErrorBanner(message: error)
                    .padding(.horizontal, MenuStyle.bannerHorizontalPadding)
                    .padding(.vertical, MenuStyle.bannerVerticalPadding)
                return [self.viewItem(for: banner, enabled: false)]
            }
            return []
        case .rateLimits:
            guard case .loggedIn = session.account else { return [] }

            return [self.rateLimitsStatusMenuItem()]
        case .actionsLimits:
            guard case .loggedIn = session.account else { return [] }

            return [self.actionsLimitsStatusMenuItem()]
        case .filters:
            let isLoggedIn = session.account.isLoggedIn
            let hasLocalFolder = session.settings.localProjects.rootPath?.isEmpty == false
            // Show filters if logged in with repos, OR if local folder is configured
            guard isLoggedIn ? session.hasLoadedRepositories : hasLocalFolder else { return [] }
            guard isLoggedIn else { return [] }

            let filters = MenuRepoFiltersView(session: session)
                .padding(.horizontal, 0)
                .padding(.vertical, 0)
            return [self.viewItem(for: filters, enabled: true)]
        case .repoList:
            let isLoggedIn = session.account.isLoggedIn
            let isLocalScope = session.menuRepoSelection.isLocalScope
            let uniqueRepos = self.uniqueDisplayModels(repos)
            // Allow repo list for logged in users, or for local scope when logged out
            guard isLoggedIn || isLocalScope else { return [] }

            if isLoggedIn, !session.hasLoadedRepositories {
                let loading = MenuLoadingRowView()
                    .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                    .padding(.vertical, MenuStyle.sectionVerticalPadding)
                return [self.viewItem(for: loading, enabled: false)]
            }
            if uniqueRepos.isEmpty {
                let (title, subtitle) = self.emptyStateMessage(for: session)
                let emptyState = MenuEmptyStateView(title: title, subtitle: subtitle)
                    .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                    .padding(.vertical, MenuStyle.sectionVerticalPadding)
                return [self.viewItem(for: emptyState, enabled: false)]
            }
            var items: [NSMenuItem] = []
            let accountID = settings.resolvedActiveAccount()?.id ?? "legacy"
            var usedRepoIDs: Set<AccountScopedCacheKey> = []
            var usedRepoFullNames: Set<AccountScopedCacheKey> = []
            for (index, repo) in uniqueRepos.enumerated() {
                let isPinned = self.appState.activePinnedRepositories.contains {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(repo.title) == .orderedSame
                }
                let item = self.repoMenuItem(for: repo, isPinned: isPinned)
                item.representedObject = repo.title
                items.append(item)
                if index < uniqueRepos.count - 1 {
                    items.append(self.repoCardSeparator())
                }
                usedRepoIDs.insert(AccountScopedCacheKey(accountID: accountID, key: repo.id))
                usedRepoFullNames.insert(AccountScopedCacheKey(accountID: accountID, key: repo.title))
            }
            self.repoMenuItemsByID = self.repoMenuItemsByID.filter { usedRepoIDs.contains($0.key) }
            self.repoSubmenusByFullName = self.repoSubmenusByFullName.filter { usedRepoFullNames.contains($0.key) }
            return items
        case .issueNavigator:
            guard case .loggedIn = session.account else { return [] }

            return [self.actionItem(
                title: "Issue Navigator…",
                action: #selector(self.target.openIssueNavigator),
                keyEquivalent: "f",
                systemImage: "rectangle.and.text.magnifyingglass"
            )]
        case .preferences:
            return [self.actionItem(title: "Preferences…", action: #selector(self.target.openPreferences), keyEquivalent: ",")]
        case .about:
            return [self.actionItem(title: "About RepoBar", action: #selector(self.target.openAbout))]
        case .restartToUpdate:
            guard case .loggedIn = session.account else { return [] }
            guard SparkleController.shared.updateStatus.isUpdateReady else { return [] }

            return [self.actionItem(title: "Restart to update", action: #selector(self.target.checkForUpdates))]
        case .quit:
            return [self.actionItem(title: "Quit RepoBar", action: #selector(self.target.quitApp), keyEquivalent: "q")]
        }
    }

    private func uniqueDisplayModels(_ repos: [RepositoryDisplayModel]) -> [RepositoryDisplayModel] {
        var seen: Set<String> = []
        return repos.filter { repo in
            seen.insert(repo.title.lowercased()).inserted
        }
    }

    private func flattenMainMenuBlocks(_ blocks: [MainMenuBlock]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        var lastGroup: MainMenuItemGroup?
        for block in blocks {
            guard block.items.isEmpty == false else { continue }

            if let lastGroup, lastGroup != block.group, items.isEmpty == false {
                let separator: NSMenuItem = block.group == .footer ? self.paddedSeparator() : .separator()
                items.append(separator)
            }
            items.append(contentsOf: block.items)
            lastGroup = block.group
        }
        return items
    }

    func refreshMenuViewHeights(in menu: NSMenu) {
        let signpost = self.signposter.beginInterval("refreshMenuViewHeights")
        defer { self.signposter.endInterval("refreshMenuViewHeights", signpost) }
        self.refreshMenuViewHeights(in: menu, width: self.menuWidth(for: menu))
    }

    func refreshMenuViewHeights(in menu: NSMenu, width: CGFloat) {
        let signpost = self.signposter.beginInterval("refreshMenuViewHeightsWidth")
        defer { self.signposter.endInterval("refreshMenuViewHeightsWidth", signpost) }
        for item in menu.items {
            guard let view = item.view,
                  let measuring = view as? MenuItemMeasuring else { continue }

            let height = measuring.measuredHeight(width: width)
            if abs(view.frame.size.height - height) > 0.5 || view.frame.size.width != width {
                view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            }
        }
    }

    func clearHighlights(in menu: NSMenu) {
        for item in menu.items {
            (item.view as? MenuItemHighlighting)?.setHighlighted(false)
        }
    }

    func menuWidth(for menu: NSMenu) -> CGFloat {
        let signpost = self.signposter.beginInterval("menuWidth")
        defer { self.signposter.endInterval("menuWidth", signpost) }
        if let view = menu.items.compactMap(\.view).first {
            if let contentWidth = view.window?.contentView?.bounds.width, contentWidth > 0 {
                return max(contentWidth, Self.menuFixedWidth)
            }
            if let windowWidth = view.window?.frame.width, windowWidth > 0 {
                return max(windowWidth, Self.menuFixedWidth)
            }
        }
        let menuWidth = menu.size.width
        if menuWidth > 0 {
            return max(menuWidth, Self.menuFixedWidth)
        }
        return Self.menuFixedWidth
    }

    private func orderedViewModels(now: Date) -> [RepositoryDisplayModel] {
        let session = self.appState.session
        let selection = session.menuRepoSelection
        let settings = session.settings

        if selection.isLocalScope {
            return self.localScopeViewModels(session: session, settings: settings, now: now)
        }

        let scope: RepositoryScope = selection.isPinnedScope ? .pinned : .all
        let pinned = self.appState.activePinnedRepositories
        let hidden = self.appState.activeHiddenRepositories
        let query = RepositoryQuery(
            scope: scope,
            onlyWith: selection.onlyWith,
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            sortKey: settings.repoList.menuSortKey,
            limit: settings.repoList.displayLimit,
            pinned: pinned,
            hidden: Set(hidden),
            pinPriority: true
        )
        let baseRepos = session.repositories.isEmpty
            ? (session.menuSnapshot?.repositories ?? [])
            : session.repositories
        let sorted = RepositoryPipeline.apply(baseRepos, query: query)
        let displayIndex = session.menuDisplayIndex
        return sorted.map { repo in
            displayIndex[repo.fullName.lowercased()]
                ?? RepositoryDisplayModel(
                    repo: repo,
                    localStatus: session.localRepoIndex.status(for: repo, host: settings.githubHost),
                    now: now
                )
        }
    }

    func localScopeViewModels(
        session: Session,
        settings: UserSettings,
        now: Date
    ) -> [RepositoryDisplayModel] {
        // Filter out worktrees - they appear in parent repo's "Switch Worktree" submenu
        let localRepos = session.localRepoIndex.all.filter { $0.worktreeName == nil }
        let displayIndex = session.menuDisplayIndex

        var models: [RepositoryDisplayModel] = []
        for localStatus in localRepos {
            guard let fullName = localStatus.fullName?.lowercased(),
                  let existingModel = displayIndex[fullName],
                  localStatus.matches(host: settings.githubHost)
            else {
                let model = RepositoryDisplayModel(localStatus: localStatus, now: now)
                models.append(model)
                continue
            }

            models.append(existingModel)
        }

        let limit = settings.repoList.displayLimit
        if limit > 0, models.count > limit {
            return Array(models.prefix(limit))
        }
        return models
    }

    private func emptyStateMessage(for session: Session) -> (String, String) {
        let hasPinned = !session.settings.repoList.pinnedRepositories.isEmpty
        let isPinnedScope = session.menuRepoSelection.isPinnedScope
        let isLocalScope = session.menuRepoSelection.isLocalScope
        let hasFilter = session.menuRepoSelection.onlyWith.isActive
        if isLocalScope {
            return ("No local repositories", "Clone a repository or set your projects folder in Settings.")
        }
        if isPinnedScope, !hasPinned {
            return ("No pinned repositories", "Pin a repository to see activity here.")
        }
        if isPinnedScope || hasFilter {
            return ("No repositories match this filter", "Try All or a different filter.")
        }
        return ("No repositories yet", "Pin a repository to see activity here.")
    }

    private func currentUsername() -> String? {
        if case let .loggedIn(user) = self.appState.session.account {
            return user.username
        }
        return nil
    }

    private func currentDisplayName() -> String? {
        if case let .loggedIn(user) = self.appState.session.account {
            return user.username
        }
        return nil
    }

    var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }
}
