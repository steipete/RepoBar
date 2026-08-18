import AppKit
import OSLog
import RepoBarCore
import SwiftUI

enum RepoSubmenuRowKind: String, Hashable {
    case changelog
}

struct RepoSubmenuRowIdentifier: Hashable {
    let accountID: String
    let fullName: String
    let kind: RepoSubmenuRowKind
}

@MainActor
struct RepoSubmenuBuilder {
    let menuBuilder: StatusBarMenuBuilder

    private var appState: AppState {
        self.menuBuilder.appState
    }

    private var target: StatusBarMenuManager {
        self.menuBuilder.target
    }

    private var signposter: OSSignposter {
        self.menuBuilder.signposter
    }

    func makeRepoSubmenu(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenu {
        let signpost = self.signposter.beginInterval("makeRepoSubmenu")
        defer { self.signposter.endInterval("makeRepoSubmenu", signpost) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self.target
        let settings = self.appState.session.settings
        let customization = settings.menuCustomization.normalized()
        let blocks = self.repoSubmenuBlocks(repo: repo, isPinned: isPinned, customization: customization)
        self.flattenRepoSubmenuBlocks(blocks).forEach { menu.addItem($0) }
        return menu
    }

    private struct RepoSubmenuBlock {
        let group: RepoSubmenuItemGroup
        let items: [NSMenuItem]
    }

    private func repoSubmenuBlocks(
        repo: RepositoryDisplayModel,
        isPinned: Bool,
        customization: MenuCustomization
    ) -> [RepoSubmenuBlock] {
        var blocks: [RepoSubmenuBlock] = []
        for itemID in customization.repoSubmenuOrder {
            if customization.hiddenRepoSubmenuItems.contains(itemID) {
                continue
            }
            let items = self.repoSubmenuItems(for: itemID, repo: repo, isPinned: isPinned)
            if items.isEmpty {
                continue
            }
            blocks.append(RepoSubmenuBlock(group: itemID.group, items: items))
        }
        return blocks
    }

    private func flattenRepoSubmenuBlocks(_ blocks: [RepoSubmenuBlock]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        var lastGroup: RepoSubmenuItemGroup?
        for block in blocks {
            guard block.items.isEmpty == false else { continue }

            if let lastGroup, lastGroup != block.group, items.isEmpty == false {
                items.append(.separator())
            }
            items.append(contentsOf: block.items)
            lastGroup = block.group
        }
        return items
    }

    private func repoSubmenuItems(
        for itemID: RepoSubmenuItemID,
        repo: RepositoryDisplayModel,
        isPinned: Bool
    ) -> [NSMenuItem] {
        let settings = self.appState.session.settings
        let local = repo.localStatus
        switch itemID {
        case .openOnGitHub:
            let openRow = RecentListSubmenuRowView(
                title: "Open \(repo.title) in GitHub",
                systemImage: "arrow.up.right.square",
                badgeText: nil,
                onOpen: { [weak target] in
                    target?.openRepoFromMenu(fullName: repo.title)
                }
            )
            return [self.menuBuilder.viewItem(for: openRow, enabled: true, highlightable: true)]
        case .openInFinder:
            guard let local else { return [] }

            return [self.menuBuilder.actionItem(
                title: "Open in Finder",
                action: #selector(StatusBarMenuManager.openLocalFinder(_:)),
                represented: local.path,
                systemImage: "folder"
            )]
        case .openInTerminal:
            guard let local else { return [] }

            return [self.menuBuilder.actionItem(
                title: "Open in Terminal",
                action: #selector(StatusBarMenuManager.openLocalTerminal(_:)),
                represented: local.path,
                systemImage: "terminal"
            )]
        case .checkoutRepo:
            guard local == nil else { return [] }

            return [self.menuBuilder.actionItem(
                title: "Checkout Repo",
                action: #selector(self.target.checkoutRepoFromMenu),
                represented: repo.title,
                systemImage: "arrow.down.to.line"
            )]
        case .localState:
            guard let local else { return [] }

            let stateView = LocalRepoStateMenuView(
                status: local,
                onSync: { [weak target] in target?.syncLocalRepo(local) },
                onRebase: { [weak target] in target?.rebaseLocalRepo(local) },
                onReset: { [weak target] in target?.resetLocalRepo(local) }
            )
            return [self.menuBuilder.viewItem(for: stateView, enabled: true)]
        case .worktrees:
            guard let local else { return [] }

            return [self.localWorktreesSubmenuItem(for: local, fullName: repo.title)]
        case .issues:
            return [self.recentListSubmenuItem(RecentListConfig(
                title: "Issues",
                systemImage: "exclamationmark.circle",
                fullName: repo.title,
                kind: .issues,
                openTitle: "Open Issues",
                openAction: #selector(self.target.openIssues),
                badgeText: StatValueFormatter.compact(repo.issues)
            ))]
        case .pulls:
            return [self.recentListSubmenuItem(RecentListConfig(
                title: "Pull Requests",
                systemImage: "arrow.triangle.branch",
                fullName: repo.title,
                kind: .pullRequests,
                openTitle: "Open Pull Requests",
                openAction: #selector(self.target.openPulls),
                badgeText: StatValueFormatter.compact(repo.pulls)
            ))]
        case .releases:
            let latestReleaseName = repo.source.latestRelease?.name
            let badgeAccessibilityLabel: String? = {
                let name = latestReleaseName.flatMap { $0.isEmpty == false ? $0 : nil }
                switch name {
                case let name?:
                    return "Latest release \(name)."
                case nil:
                    return nil
                }
            }()
            return [self.recentListSubmenuItem(RecentListConfig(
                title: "Releases",
                systemImage: "tag",
                fullName: repo.title,
                kind: .releases,
                openTitle: "Open Releases",
                openAction: #selector(self.target.openReleases),
                badgePrefixText: latestReleaseName,
                badgeText: nil,
                badgeAccessibilityLabel: badgeAccessibilityLabel
            ))]
        case .changelog:
            let presentation = self.target.cachedChangelogPresentation(
                fullName: repo.title,
                releaseTag: repo.source.latestRelease?.tag
            )
            return [self.changelogSubmenuItem(
                fullName: repo.title,
                localStatus: local,
                presentation: presentation
            )]
        case .ciRuns:
            let runBadge = repo.ciRunCount.flatMap { $0 > 0 ? String($0) : nil }
            return [self.recentListSubmenuItem(RecentListConfig(
                title: "CI Runs",
                systemImage: "bolt",
                fullName: repo.title,
                kind: .ciRuns,
                openTitle: "Open Actions",
                openAction: #selector(self.target.openActions),
                badgeText: runBadge
            ))]
        case .discussions:
            if repo.source.discussionsEnabled == false {
                return []
            }
            return [self.recentListSubmenuItem(RecentListConfig(
                title: "Discussions",
                systemImage: "bubble.left.and.bubble.right",
                fullName: repo.title,
                kind: .discussions,
                openTitle: "Open Discussions",
                openAction: #selector(self.target.openDiscussions),
                badgeText: nil
            ))]
        case .tags:
            return [self.recentListSubmenuItem(RecentListConfig(
                title: "Tags",
                systemImage: "tag",
                fullName: repo.title,
                kind: .tags,
                openTitle: "Open Tags",
                openAction: #selector(self.target.openTags),
                badgeText: nil
            ))]
        case .branches:
            if let local {
                return [self.branchesSubmenuItem(for: local, fullName: repo.title, badgeText: nil)]
            }
            return [self.recentListSubmenuItem(RecentListConfig(
                title: "Branches",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                fullName: repo.title,
                kind: .branches,
                openTitle: "Open Branches",
                openAction: #selector(self.target.openBranches),
                badgeText: nil
            ))]
        case .contributors:
            return [self.recentListSubmenuItem(RecentListConfig(
                title: "Contributors",
                systemImage: "person.2",
                fullName: repo.title,
                kind: .contributors,
                openTitle: "Open Contributors",
                openAction: #selector(self.target.openContributors),
                badgeText: nil
            ))]
        case .heatmap:
            guard settings.heatmap.display == .submenu, !repo.heatmap.isEmpty else { return [] }

            let filtered = HeatmapFilter.filter(repo.heatmap, range: self.appState.session.heatmapRange)
            let heatmap = VStack(spacing: 4) {
                HeatmapView(
                    cells: filtered,
                    accentTone: settings.appearance.accentTone,
                    height: MenuStyle.heatmapSubmenuHeight
                )
                HeatmapAxisLabelsView(range: self.appState.session.heatmapRange, foregroundStyle: Color.secondary)
            }
            .padding(.horizontal, MenuStyle.cardHorizontalPadding)
            .padding(.vertical, MenuStyle.cardVerticalPadding)
            return [self.menuBuilder.viewItem(for: heatmap, enabled: false)]
        case .commits:
            let cachedCommits = self.target.recentMenuService.cachedCommits(fullName: repo.title)
            let commitCount = self.target.cachedRecentCommitCount(fullName: repo.title)
            let commits = Array((cachedCommits ?? []).prefix(AppLimits.RepoCommits.totalLimit))
            let commitPreview = Array(commits.prefix(AppLimits.RepoCommits.previewLimit))
            let commitRemainder = Array(commits.dropFirst(commitPreview.count))
            var items: [NSMenuItem] = []
            items.append(self.menuBuilder.actionItem(
                title: "Open Commits",
                action: #selector(self.target.openCommits),
                represented: repo.title,
                systemImage: "arrow.turn.down.right"
            ))
            if commitPreview.isEmpty {
                let message = commitCount == 0 ? "No commits" : "Loading…"
                items.append(self.menuBuilder.infoItem(message))
            } else {
                commitPreview.forEach { items.append(self.menuBuilder.commitMenuItem(for: $0)) }
                if commitRemainder.isEmpty == false {
                    items.append(self.repoCommitsMoreMenuItem(commits: commitRemainder))
                }
            }
            return items
        case .activity:
            let events = Array(repo.activityEvents.prefix(AppLimits.RepoActivity.limit))
            let activityPreview = Array(events.prefix(AppLimits.RepoActivity.previewLimit))
            let activityRemainder = Array(events.dropFirst(activityPreview.count))
            let hasActivityLink = repo.activityURL != nil
            guard hasActivityLink || activityPreview.isEmpty == false else { return [] }

            var items: [NSMenuItem] = []
            if hasActivityLink {
                items.append(self.menuBuilder.actionItem(
                    title: "Open Activity",
                    action: #selector(self.target.openActivity),
                    represented: repo.title,
                    systemImage: "clock.arrow.circlepath"
                ))
            }
            if activityPreview.isEmpty == false {
                activityPreview.forEach { items.append(self.menuBuilder.activityMenuItem(for: $0)) }
                if activityRemainder.isEmpty == false {
                    items.append(self.repoActivityMoreMenuItem(events: activityRemainder))
                }
            }
            return items
        case .pinToggle:
            if isPinned {
                return [self.menuBuilder.actionItem(
                    title: "Unpin",
                    action: #selector(self.target.unpinRepo),
                    represented: repo.title,
                    systemImage: "pin.slash"
                )]
            }
            return [self.menuBuilder.actionItem(
                title: "Pin",
                action: #selector(self.target.pinRepo),
                represented: repo.title,
                systemImage: "pin"
            )]
        case .hideRepo:
            return [self.menuBuilder.actionItem(
                title: "Hide",
                action: #selector(self.target.hideRepo),
                represented: repo.title,
                systemImage: "eye.slash"
            )]
        case .moveUp:
            return []
        case .moveDown:
            return []
        }
    }

    private func branchesSubmenuItem(for local: LocalRepoStatus, fullName: String, badgeText: String?) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        self.target.registerCombinedBranchMenu(submenu, repoPath: local.path, fullName: fullName, localStatus: local)
        submenu.addItem(self.menuBuilder.actionItem(
            title: "Create Branch…",
            action: #selector(self.target.createLocalBranch),
            represented: local.path,
            systemImage: "plus"
        ))
        submenu.addItem(.separator())
        submenu.addItem(self.menuBuilder.actionItem(
            title: "Open Branches",
            action: #selector(self.target.openBranches),
            represented: fullName,
            systemImage: "point.topleft.down.curvedto.point.bottomright.up"
        ))
        submenu.addItem(.separator())
        submenu.addItem(self.loadingItem())

        let row = RecentListSubmenuRowView(
            title: "Branches",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            badgeText: badgeText
        )
        return self.menuBuilder.viewItem(for: row, enabled: true, highlightable: true, submenu: submenu)
    }

    private func localWorktreesSubmenuItem(for local: LocalRepoStatus, fullName: String) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        self.target.registerLocalWorktreeMenu(submenu, repoPath: local.path, fullName: fullName)
        submenu.addItem(self.menuBuilder.actionItem(
            title: "Create Worktree…",
            action: #selector(self.target.createLocalWorktree),
            represented: local.path,
            systemImage: "plus"
        ))
        submenu.addItem(.separator())
        submenu.addItem(self.loadingItem())

        let row = RecentListSubmenuRowView(
            title: "Switch Worktree",
            systemImage: "square.stack.3d.down.right",
            badgeText: nil,
            detailText: local.worktreeName
        )
        return self.menuBuilder.viewItem(for: row, enabled: true, highlightable: true, submenu: submenu)
    }

    private func changelogSubmenuItem(
        fullName: String,
        localStatus: LocalRepoStatus?,
        presentation: ChangelogRowPresentation?
    ) -> NSMenuItem {
        guard let accountID = self.appState.session.settings.resolvedActiveAccount()?.id else {
            return self.menuBuilder.infoItem("No active account")
        }

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        self.target.registerChangelogMenu(submenu, fullName: fullName, localStatus: localStatus)
        submenu.addItem(self.menuBuilder.infoItem("Loading…"))

        let headline = self.target.cachedChangelogHeadline(fullName: fullName)
        let title = headline == nil ? (presentation?.title ?? "Changelog") : "Changelog"
        let badgeText = headline ?? presentation?.badgeText
        let detailText = headline == nil ? presentation?.detailText : nil
        let row = RecentListSubmenuRowView(
            title: title,
            systemImage: "doc.text",
            badgeText: badgeText,
            detailText: detailText
        )
        let item = self.menuBuilder.viewItem(for: row, enabled: true, highlightable: true, submenu: submenu)
        item.representedObject = RepoSubmenuRowIdentifier(
            accountID: accountID,
            fullName: fullName,
            kind: .changelog
        )
        return item
    }

    private func loadingItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private struct RecentListConfig {
        let title: String
        let systemImage: String
        let fullName: String
        let kind: RepoRecentMenuKind
        let openTitle: String
        let openAction: Selector
        let badgePrefixText: String?
        let badgeText: String?
        let badgeAccessibilityLabel: String?

        init(
            title: String,
            systemImage: String,
            fullName: String,
            kind: RepoRecentMenuKind,
            openTitle: String,
            openAction: Selector,
            badgePrefixText: String? = nil,
            badgeText: String?,
            badgeAccessibilityLabel: String? = nil
        ) {
            self.title = title
            self.systemImage = systemImage
            self.fullName = fullName
            self.kind = kind
            self.openTitle = openTitle
            self.openAction = openAction
            self.badgePrefixText = badgePrefixText
            self.badgeText = badgeText
            self.badgeAccessibilityLabel = badgeAccessibilityLabel
        }
    }

    private func recentListSubmenuItem(_ config: RecentListConfig) -> NSMenuItem {
        guard let accountID = self.appState.session.settings.resolvedActiveAccount()?.id else {
            return self.menuBuilder.infoItem("No active account")
        }

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        self.target.registerRecentListMenu(
            submenu,
            context: RepoRecentMenuContext(accountID: accountID, fullName: config.fullName, kind: config.kind)
        )

        submenu.addItem(self.menuBuilder.actionItem(
            title: config.openTitle,
            action: config.openAction,
            represented: config.fullName,
            systemImage: config.systemImage
        ))
        submenu.addItem(.separator())
        let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        loading.isEnabled = false
        submenu.addItem(loading)

        let row = RecentListSubmenuRowView(
            title: config.title,
            systemImage: config.systemImage,
            badgePrefixText: config.badgePrefixText,
            badgeText: config.badgeText,
            badgeAccessibilityLabel: config.badgeAccessibilityLabel
        )
        return self.menuBuilder.viewItem(for: row, enabled: true, highlightable: true, submenu: submenu)
    }

    private func repoActivityMoreMenuItem(events: [ActivityEvent]) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        events.prefix(AppLimits.MoreMenus.limit).forEach { submenu.addItem(self.menuBuilder.activityMenuItem(for: $0)) }
        let item = NSMenuItem(title: "More Activity…", action: nil, keyEquivalent: "")
        item.submenu = submenu
        if let image = self.menuBuilder.cachedSystemImage(named: "ellipsis") {
            item.image = image
        }
        return item
    }

    private func repoCommitsMoreMenuItem(commits: [RepoCommitSummary]) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        commits.prefix(AppLimits.MoreMenus.limit).forEach { submenu.addItem(self.menuBuilder.commitMenuItem(for: $0)) }
        let item = NSMenuItem(title: "More Commits…", action: nil, keyEquivalent: "")
        item.submenu = submenu
        if let image = self.menuBuilder.cachedSystemImage(named: "ellipsis") {
            item.image = image
        }
        return item
    }
}
