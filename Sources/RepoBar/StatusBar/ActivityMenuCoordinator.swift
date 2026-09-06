import AppKit
import RepoBarCore
import SwiftUI

@MainActor
final class ActivityMenuCoordinator {
    private unowned let actionHandler: StatusBarMenuManager
    private let appState: AppState
    private let menuBuilder: StatusBarMenuBuilder

    init(appState: AppState, menuBuilder: StatusBarMenuBuilder, actionHandler: StatusBarMenuManager) {
        self.appState = appState
        self.menuBuilder = menuBuilder
        self.actionHandler = actionHandler
    }

    func contributionSubmenu(username: String, displayName: String) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self.actionHandler

        var hasHeaderItem = false
        if let profileURL = self.profileURL(for: username) {
            menu.addItem(self.menuBuilder.actionItem(
                title: "Open \(displayName) in GitHub",
                action: #selector(StatusBarMenuManager.openURLItem(_:)),
                represented: profileURL,
                systemImage: "person.crop.circle"
            ))
            hasHeaderItem = true
        }

        if hasHeaderItem {
            menu.addItem(.separator())
        }
        menu.addItem(self.menuBuilder.rateLimitsStatusMenuItem())

        let commitEvents = self.appState.session.globalCommitEvents
        let activityEvents = self.appState.session.globalActivityEvents
        let commitPreview = Array(commitEvents.prefix(AppLimits.GlobalCommits.previewLimit))
        let commitRemainder = Array(commitEvents.dropFirst(commitPreview.count))
        let activityPreview = Array(activityEvents.prefix(AppLimits.GlobalActivity.previewLimit))
        let activityRemainder = Array(activityEvents.dropFirst(activityPreview.count))

        if commitPreview.isEmpty == false {
            menu.addItem(self.menuBuilder.infoItem("Commits"))
            commitPreview.forEach { menu.addItem(self.commitMenuItem(for: $0)) }
            if commitRemainder.isEmpty == false {
                menu.addItem(self.moreCommitsMenuItem(commits: commitRemainder))
            }
        } else if let error = self.appState.session.globalCommitError {
            menu.addItem(self.menuBuilder.infoMessageItem(error))
        }

        if activityPreview.isEmpty == false {
            menu.addItem(.separator())
            menu.addItem(self.menuBuilder.infoItem("Activity"))
            activityPreview.forEach { menu.addItem(self.activityMenuItem(for: $0)) }
            if activityRemainder.isEmpty == false {
                menu.addItem(self.moreActivityMenuItem(events: activityRemainder))
            }
        } else if let error = self.appState.session.globalActivityError {
            menu.addItem(.separator())
            menu.addItem(self.menuBuilder.infoMessageItem(error))
        } else if commitPreview.isEmpty {
            let title = self.appState.session.hasLoadedRepositories ? "No recent activity" : "Loading…"
            menu.addItem(.separator())
            menu.addItem(self.menuBuilder.infoItem(title))
        }

        return menu
    }

    func activityMenuItem(for event: ActivityEvent) -> NSMenuItem {
        let view = ActivityMenuItemView(event: event, symbolName: self.activitySymbolName(for: event)) { [weak self] in
            self?.actionHandler.open(url: event.url)
        }
        return self.menuBuilder.viewItem(for: view, enabled: true, highlightable: true)
    }

    func commitMenuItem(for commit: RepoCommitSummary) -> NSMenuItem {
        let view = CommitMenuItemView(summary: commit) { [weak self] in
            self?.actionHandler.open(url: commit.url)
        }
        return self.menuBuilder.viewItem(for: view, enabled: true, highlightable: true)
    }

    func activitySymbolName(for event: ActivityEvent) -> String {
        guard let type = event.eventTypeEnum else { return "clock" }

        switch type {
        case .pullRequest: return "arrow.triangle.branch"
        case .pullRequestReview: return "checkmark.bubble"
        case .pullRequestReviewComment: return "text.bubble"
        case .pullRequestReviewThread: return "text.bubble"
        case .issueComment: return "text.bubble"
        case .issues: return "exclamationmark.circle"
        case .push: return "arrow.up.circle"
        case .release: return "tag"
        case .watch: return "star"
        case .fork: return "doc.on.doc"
        case .create: return "plus"
        case .delete: return "trash"
        case .member: return "person.badge.plus"
        case .public: return "globe"
        case .gollum: return "book"
        case .commitComment: return "text.bubble"
        case .discussion: return "bubble.left.and.bubble.right"
        case .sponsorship: return "heart"
        }
    }

    private func moreCommitsMenuItem(commits: [RepoCommitSummary]) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.actionHandler
        commits.prefix(AppLimits.MoreMenus.limit).forEach { submenu.addItem(self.commitMenuItem(for: $0)) }
        let item = NSMenuItem(title: AppLocalizer().string("More Commits…"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        if let image = self.menuBuilder.cachedSystemImage(named: "ellipsis") {
            item.image = image
        }
        return item
    }

    private func moreActivityMenuItem(events: [ActivityEvent]) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.actionHandler
        events.prefix(AppLimits.MoreMenus.limit).forEach { submenu.addItem(self.activityMenuItem(for: $0)) }
        let item = NSMenuItem(title: AppLocalizer().string("More Activity…"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        if let image = self.menuBuilder.cachedSystemImage(named: "ellipsis") {
            item.image = image
        }
        return item
    }

    private func profileURL(for username: String) -> URL? {
        guard username.isEmpty == false else { return nil }

        var host = self.appState.session.settings.githubHost
        host.appendPathComponent(username)
        return host
    }
}
