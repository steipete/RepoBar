import AppKit
import Foundation
import RepoBarCore

@MainActor
final class RecentListMenuCoordinator {
    unowned let actionHandler: StatusBarMenuManager
    let appState: AppState
    let menuBuilder: StatusBarMenuBuilder
    let menuItemFactory: MenuItemViewFactory
    private let menuService: RecentMenuService
    private let logger = RepoBarLogging.logger("recent-list")
    private var recentListMenus: [ObjectIdentifier: RecentListMenuEntry] = [:]
    let issueLabelChipLimit = AppLimits.RecentLists.issueLabelChipLimit

    var webURLBuilder: RepoWebURLBuilder {
        RepoWebURLBuilder(host: self.appState.session.settings.githubHost)
    }

    init(
        appState: AppState,
        menuBuilder: StatusBarMenuBuilder,
        menuItemFactory: MenuItemViewFactory,
        menuService: RecentMenuService,
        actionHandler: StatusBarMenuManager
    ) {
        self.appState = appState
        self.menuBuilder = menuBuilder
        self.menuItemFactory = menuItemFactory
        self.menuService = menuService
        self.actionHandler = actionHandler
    }

    func registerRecentListMenu(_ menu: NSMenu, context: RepoRecentMenuContext) {
        self.recentListMenus[ObjectIdentifier(menu)] = RecentListMenuEntry(menu: menu, context: context)
    }

    func cachedRecentCommitCount(fullName: String) -> Int? {
        self.menuService.cachedRecentCommitCount(fullName: fullName)
    }

    func pruneMenus() {
        self.recentListMenus = self.recentListMenus.filter { $0.value.menu != nil }
    }

    func handleMenuWillOpen(_ menu: NSMenu) -> Bool {
        guard let entry = self.recentListMenus[ObjectIdentifier(menu)] else { return false }

        self.menuBuilder.refreshMenuViewHeights(in: menu)
        Task { @MainActor [weak self] in
            await self?.refreshRecentListMenu(menu: menu, context: entry.context)
        }
        return true
    }

    func handleFilterChanges() {
        self.pruneMenus()
        for entry in self.recentListMenus.values {
            guard entry.context.kind == .pullRequests || entry.context.kind == .issues,
                  let menu = entry.menu
            else { continue }

            Task { @MainActor [weak self] in
                await self?.refreshRecentListMenu(menu: menu, context: entry.context)
            }
        }
    }

    func toggleIssueLabelFilter(label: String) {
        var selection = self.appState.session.recentIssueLabelSelection
        if selection.contains(label) {
            selection.remove(label)
        } else {
            selection.insert(label)
        }
        self.appState.session.recentIssueLabelSelection = selection
        NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
    }

    func clearIssueLabelFilters() {
        self.appState.session.recentIssueLabelSelection.removeAll()
        NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
    }

    func prefetchRecentLists(fullNames: Set<String>) {
        guard case .loggedIn = self.appState.session.account else { return }
        guard fullNames.isEmpty == false else { return }
        guard let accountID = self.appState.session.settings.resolvedActiveAccount()?.id else {
            self.logger.error("Skipping recent-list prefetch because no active account is resolved")
            return
        }

        let kinds = self.menuService.descriptors().keys
        for fullName in fullNames {
            for kind in kinds {
                self.prefetchRecentList(accountID: accountID, fullName: fullName, kind: kind)
            }
        }
    }

    func prefetchRecentList(fullName: String, kind: RepoRecentMenuKind) {
        guard let accountID = self.appState.session.settings.resolvedActiveAccount()?.id else {
            self.logger.error("Skipping recent-list prefetch because no active account is resolved")
            return
        }

        self.prefetchRecentList(accountID: accountID, fullName: fullName, kind: kind)
    }

    func prefetchRecentList(accountID: String, fullName: String, kind: RepoRecentMenuKind) {
        guard let (owner, name) = self.ownerAndName(from: fullName) else { return }

        let now = Date()
        guard let descriptor = self.menuService.descriptor(for: kind) else { return }

        let cacheContext: (key: AccountScopedCacheKey, github: GitHubClient)
        do {
            cacheContext = try self.menuService.cacheContext(accountID: accountID, fullName: fullName)
        } catch {
            self.logger.error(
                "Recent-list client resolution failed account=\(accountID) repo=\(fullName) error=\(error.userFacingMessage)"
            )
            return
        }
        let cacheKey = cacheContext.key
        guard descriptor.needsRefresh(cacheKey, now, self.menuService.cacheTTL) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                self.logger.debug("Prefetch start kind=\(String(describing: kind)) repo=\(fullName)")
                _ = try await descriptor.load(cacheKey, owner, name, self.menuService.listLimit, cacheContext.github)
                self.logger.debug("Prefetch ok kind=\(String(describing: kind)) repo=\(fullName)")
            } catch {
                self.logger.warning(
                    "Prefetch failed kind=\(String(describing: kind)) repo=\(fullName) error=\(error.userFacingMessage)"
                )
                await DiagnosticsLogger.shared.message(
                    "Prefetch failed: \(String(describing: kind)) \(fullName) error=\(error.localizedDescription)"
                )
            }
        }
    }

    #if DEBUG
        func containsMenuForTesting(_ menu: NSMenu) -> Bool {
            self.recentListMenus[ObjectIdentifier(menu)] != nil
        }
    #endif

    private func refreshRecentListMenu(menu: NSMenu, context: RepoRecentMenuContext) async {
        guard case .loggedIn = self.appState.session.account else {
            let header = RecentMenuHeader(title: "Sign in to view", action: nil, fullName: context.fullName, systemImage: nil)
            self.populateRecentListMenu(menu, header: header, content: .signedOut)
            menu.update()
            return
        }
        guard let (owner, name) = self.ownerAndName(from: context.fullName) else {
            let header = RecentMenuHeader(
                title: "Open on GitHub",
                action: #selector(StatusBarMenuManager.openRepo(_:)),
                fullName: context.fullName,
                systemImage: "folder"
            )
            self.populateRecentListMenu(menu, header: header, content: .message("Invalid repository name"))
            menu.update()
            return
        }

        let now = Date()
        guard let descriptor = self.menuService.descriptor(for: context.kind) else { return }

        let header = RecentMenuHeader(
            title: descriptor.headerTitle,
            action: self.openAction(for: context.kind),
            fullName: context.fullName,
            systemImage: descriptor.headerIcon
        )
        let actions = self.actions(for: context.kind, fullName: context.fullName)
        let cacheContext: (key: AccountScopedCacheKey, github: GitHubClient)
        do {
            cacheContext = try self.menuService.cacheContext(
                accountID: context.accountID,
                fullName: context.fullName
            )
        } catch {
            self.populateRecentListMenu(
                menu,
                header: header,
                actions: actions,
                content: .message(Self.failureMessage(for: error))
            )
            menu.update()
            return
        }
        let cacheKey = cacheContext.key
        let cached = descriptor.cached(cacheKey, now, self.menuService.cacheTTL)
        let stale = cached ?? descriptor.stale(cacheKey)
        let staleExtras = self.recentListExtras(for: context, items: stale)
        let cachedCount = cached?.count.description ?? "nil"
        let staleCount = stale?.count.description ?? "nil"
        self.logger.info(
            "Recent list open kind=\(String(describing: context.kind)) repo=\(context.fullName) cached=\(cachedCount) stale=\(staleCount)"
        )
        if let stale {
            self.populateRecentListMenu(
                menu,
                header: header,
                actions: actions,
                extras: staleExtras,
                content: .items(stale, emptyTitle: descriptor.emptyTitle, render: { menu, items in
                    self.renderRecentItems(items, for: context.kind, repoFullName: context.fullName, menu: menu)
                })
            )
        } else {
            self.populateRecentListMenu(menu, header: header, actions: actions, extras: staleExtras, content: .loading)
        }
        menu.update()

        guard descriptor.needsRefresh(cacheKey, now, self.menuService.cacheTTL) else {
            self.logger.debug("Recent list cache hit kind=\(String(describing: context.kind)) repo=\(context.fullName)")
            return
        }

        let startedAt = Date()
        self.logger.info("Recent list refresh start kind=\(String(describing: context.kind)) repo=\(context.fullName)")
        do {
            let items = try await descriptor.load(cacheKey, owner, name, self.menuService.listLimit, cacheContext.github)
            self.logger.info(
                "Recent list refresh ok kind=\(String(describing: context.kind)) repo=\(context.fullName) count=\(items.count) dur=\(Self.formatDuration(since: startedAt))"
            )
            let rateLimitExtras = await self.currentRateLimitExtras(github: cacheContext.github)
            self.populateRecentListMenu(
                menu,
                header: header,
                actions: actions,
                extras: rateLimitExtras + self.recentListExtras(for: context, items: items),
                content: .items(items, emptyTitle: descriptor.emptyTitle, render: { menu, items in
                    self.renderRecentItems(items, for: context.kind, repoFullName: context.fullName, menu: menu)
                })
            )
        } catch is AsyncTimeoutError {
            self.logger.warning(
                "Recent list timed out kind=\(String(describing: context.kind)) repo=\(context.fullName) timeout=\(self.menuService.loadTimeout)s"
            )
            await DiagnosticsLogger.shared.message(
                "Recent list timed out: \(String(describing: context.kind)) \(context.fullName)"
            )
            if stale == nil {
                self.populateRecentListMenu(
                    menu,
                    header: header,
                    actions: actions,
                    extras: staleExtras,
                    content: .message(Self.timeoutMessage(timeout: self.menuService.loadTimeout))
                )
            }
        } catch {
            let message = error.userFacingMessage
            let errorType = String(describing: type(of: error))
            let duration = Self.formatDuration(since: startedAt)
            let rateLimitMessage = Self.rateLimitMessage(for: error)
            self.recordRateLimitIfNeeded(error)
            self.logger.warning(
                "Recent list failed kind=\(String(describing: context.kind)) repo=\(context.fullName) error=\(message) type=\(errorType) dur=\(duration)"
            )
            await DiagnosticsLogger.shared.message(
                "Recent list failed: \(String(describing: context.kind)) \(context.fullName) error=\(error.localizedDescription)"
            )
            if stale == nil {
                self.populateRecentListMenu(
                    menu,
                    header: header,
                    actions: actions,
                    extras: staleExtras,
                    content: .message(Self.failureMessage(for: error))
                )
            } else if let stale, let rateLimitMessage {
                self.populateRecentListMenu(
                    menu,
                    header: header,
                    actions: actions,
                    extras: self.rateLimitExtras(message: rateLimitMessage) + staleExtras,
                    content: .items(stale, emptyTitle: descriptor.emptyTitle, render: { menu, items in
                        self.renderRecentItems(items, for: context.kind, repoFullName: context.fullName, menu: menu)
                    })
                )
            }
        }
        menu.update()
    }

    static func timeoutMessage(timeout: TimeInterval) -> String {
        "Timed out after \(Int(timeout.rounded()))s"
    }

    static func failureMessage(for error: Error) -> String {
        let message = error.userFacingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return "Failed to load" }

        return "Failed: \(message)"
    }

    static func rateLimitMessage(for error: Error) -> String? {
        guard let reset = (error as? GitHubAPIError)?.rateLimitedUntil else { return nil }

        return "GitHub rate limited; resets \(RelativeFormatter.string(from: reset, relativeTo: Date()))."
    }

    private static func formatDuration(since start: Date) -> String {
        let milliseconds = Int((Date().timeIntervalSince(start) * 1000).rounded())
        return "\(milliseconds)ms"
    }

    private func recordRateLimitIfNeeded(_ error: Error) {
        guard let reset = (error as? GitHubAPIError)?.rateLimitedUntil else { return }

        self.appState.session.rateLimitReset = reset
        self.appState.session.lastError = error.userFacingMessage
    }

    private func currentRateLimitExtras(github: GitHubClient) async -> [NSMenuItem] {
        guard let reset = await github.rateLimitReset(now: Date()) else { return [] }

        self.appState.session.rateLimitReset = reset
        return self.rateLimitExtras(
            message: "GitHub rate limited; resets \(RelativeFormatter.string(from: reset, relativeTo: Date()))."
        )
    }

    private func rateLimitExtras(message: String) -> [NSMenuItem] {
        [
            self.makeListItem(
                title: message,
                action: nil,
                representedObject: nil,
                systemImage: "exclamationmark.triangle",
                isEnabled: false
            ),
            .separator()
        ]
    }

    private func renderRecentItems(_ items: RecentMenuItems, for _: RepoRecentMenuKind, repoFullName: String, menu: NSMenu) {
        switch items {
        case let .issues(issueItems):
            let filtered = self.filteredIssues(issueItems)
            if filtered.isEmpty {
                self.addEmptyListItem("No matching issues", to: menu)
                return
            }
            for issue in filtered.prefix(self.menuService.listLimit) {
                self.addIssueMenuItem(issue, to: menu)
            }
        case let .pullRequests(pullRequestItems):
            let filtered = self.filteredPullRequests(pullRequestItems)
            if filtered.isEmpty {
                self.addEmptyListItem("No matching pull requests", to: menu)
                return
            }
            for pullRequest in filtered.prefix(self.menuService.listLimit) {
                self.addPullRequestMenuItem(pullRequest, to: menu)
            }
        case let .releases(releases):
            for release in releases.prefix(self.menuService.listLimit) {
                self.addReleaseMenuItem(release, to: menu)
            }
        case let .workflowRuns(runs):
            for run in runs.prefix(self.menuService.listLimit) {
                self.addWorkflowRunMenuItem(run, to: menu)
            }
        case let .discussions(discussions):
            for discussion in discussions.prefix(self.menuService.listLimit) {
                self.addDiscussionMenuItem(discussion, to: menu)
            }
        case let .commits(commits):
            for commit in commits.prefix(self.menuService.previewLimit) {
                self.addCommitMenuItem(commit, to: menu)
            }
            if commits.count > self.menuService.previewLimit {
                menu.addItem(self.moreCommitsMenuItem(items: commits))
            }
        case let .tags(tags):
            for tag in tags.prefix(self.menuService.listLimit) {
                self.addTagMenuItem(tag, repoFullName: repoFullName, to: menu)
            }
        case let .branches(branches):
            for branch in branches.prefix(self.menuService.listLimit) {
                self.addBranchMenuItem(branch, repoFullName: repoFullName, to: menu)
            }
        case let .contributors(contributors):
            for contributor in contributors.prefix(self.menuService.listLimit) {
                self.addContributorMenuItem(contributor, to: menu)
            }
        }
    }

    private func actions(for kind: RepoRecentMenuKind, fullName: String) -> [RecentMenuAction] {
        switch kind {
        case .releases:
            let hasLatestRelease = self.appState.session.repositories
                .first(where: { $0.fullName == fullName })?
                .latestRelease != nil
            guard hasLatestRelease else { return [] }

            return [
                RecentMenuAction(
                    title: "Open Latest Release",
                    action: #selector(StatusBarMenuManager.openLatestRelease(_:)),
                    systemImage: "tag.fill",
                    representedObject: fullName,
                    isEnabled: true
                )
            ]
        default:
            return []
        }
    }

    private func openAction(for kind: RepoRecentMenuKind) -> Selector {
        switch kind {
        case .commits: #selector(StatusBarMenuManager.openCommits(_:))
        case .issues: #selector(StatusBarMenuManager.openIssues(_:))
        case .pullRequests: #selector(StatusBarMenuManager.openPulls(_:))
        case .releases: #selector(StatusBarMenuManager.openReleases(_:))
        case .ciRuns: #selector(StatusBarMenuManager.openActions(_:))
        case .discussions: #selector(StatusBarMenuManager.openDiscussions(_:))
        case .tags: #selector(StatusBarMenuManager.openTags(_:))
        case .branches: #selector(StatusBarMenuManager.openBranches(_:))
        case .contributors: #selector(StatusBarMenuManager.openContributors(_:))
        }
    }

    private func filteredPullRequests(_ items: [RepoPullRequestSummary]) -> [RepoPullRequestSummary] {
        var filtered = items
        let scope = self.appState.session.recentPullRequestScope
        if scope == .mine {
            guard case let .loggedIn(user) = self.appState.session.account else { return [] }

            filtered = filtered.filter { pullRequest in
                guard let author = pullRequest.authorLogin else { return false }

                return author.caseInsensitiveCompare(user.username) == .orderedSame
            }
        }

        switch self.appState.session.recentPullRequestEngagement {
        case .all:
            break
        case .commented:
            filtered = filtered.filter { $0.commentCount > 0 }
        case .reviewed:
            filtered = filtered.filter { $0.reviewCommentCount > 0 }
        }

        return filtered
    }

    private func filteredIssues(_ items: [RepoIssueSummary]) -> [RepoIssueSummary] {
        var filtered = items
        let scope = self.appState.session.recentIssueScope
        if scope == .mine {
            guard case let .loggedIn(user) = self.appState.session.account else { return [] }

            let username = user.username.lowercased()
            filtered = filtered.filter { issue in
                if let author = issue.authorLogin?.lowercased(), author == username {
                    return true
                }
                return issue.assigneeLogins.contains(where: { $0.lowercased() == username })
            }
        }

        let selectedLabels = self.appState.session.recentIssueLabelSelection
        if !selectedLabels.isEmpty {
            let lowered = Set(selectedLabels.map { $0.lowercased() })
            filtered = filtered.filter { issue in
                issue.labels.contains { lowered.contains($0.name.lowercased()) }
            }
        }

        return filtered
    }
}
