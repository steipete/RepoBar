import AppKit
import OSLog
import RepoBarCore

extension StatusBarMenuManager {
    private static let minimumMainMenuItems = 3

    func menuWillOpen(_ menu: NSMenu) {
        let signpost = self.signposter.beginInterval("menuWillOpen")
        defer { self.signposter.endInterval("menuWillOpen", signpost) }
        if menu === self.mainMenu {
            self.appState.checkBundleReplacement()
        }
        self.prepareMenuAppearance(menu)
        if self.recentListCoordinator.handleMenuWillOpen(menu) {
            return
        }
        if self.localGitMenuCoordinator.handleMenuWillOpen(menu) {
            return
        }
        if self.changelogMenuCoordinator.handleMenuWillOpen(menu) {
            return
        }
        self.prefetchChangelogIfNeeded(for: menu)
        if menu === self.mainMenu {
            self.prepareMainMenuWillOpen(menu)
        } else {
            self.prepareSubmenuWillOpen(menu)
        }
    }

    private func prepareMenuAppearance(_ menu: NSMenu) {
        if menu === self.mainMenu {
            self.logMenuEvent("menuWillOpen mainMenu items=\(menu.items.count)")
        } else {
            self.logMenuEvent("menuWillOpen submenu items=\(menu.items.count)")
        }
        if let app = NSApp {
            menu.appearance = app.effectiveAppearance
        }
    }

    private func prefetchChangelogIfNeeded(for menu: NSMenu) {
        guard let fullName = self.menuBuilder.repoFullName(for: menu) else { return }

        let localPath = self.appState.session.localRepoIndex.status(forFullName: fullName)?.path
        let releaseTag = self.appState.session.repositories
            .first(where: { $0.fullName == fullName })?
            .latestRelease?
            .tag
        self.changelogMenuCoordinator.prefetchChangelog(
            fullName: fullName,
            localPath: localPath,
            releaseTag: releaseTag
        )
    }

    private func prepareMainMenuWillOpen(_ menu: NSMenu) {
        self.appState.reloadRateLimitCacheSummary()
        if menu.delegate == nil {
            menu.delegate = self
        }
        let plan = self.menuBuilder.mainMenuPlan()
        self.recentListCoordinator.pruneMenus()
        self.localGitMenuCoordinator.pruneMenus()
        self.changelogMenuCoordinator.pruneMenus()
        if self.appState.session.settings.appearance.showContributionHeader {
            if case let .loggedIn(user) = self.appState.session.account {
                Task { await self.appState.loadContributionHeatmapIfNeeded(for: user.username) }
            }
        }
        self.appState.refreshIfNeededForMenu()
        let isMenuTooSmall = menu.items.count < Self.minimumMainMenuItems
        if isMenuTooSmall {
            self.logMenuEvent("menuWillOpen mainMenu invalidating cache: items=\(menu.items.count)")
            self.lastMainMenuSignature = nil
        }
        let planDidRebuild = self.rebuildMainMenuIfNeeded(menu, plan: plan, isMenuTooSmall: isMenuTooSmall)
        let repoFullNames = Set(menu.items.compactMap { $0.representedObject as? String }.filter { $0.contains("/") })
        self.recentListCoordinator.prefetchRecentLists(fullNames: repoFullNames)
        self.refreshMainMenuMetricsAfterOpen(menu, plan: plan, didRebuildMenu: planDidRebuild)
    }

    private func rebuildMainMenuIfNeeded(_ menu: NSMenu, plan: MainMenuPlan, isMenuTooSmall: Bool) -> Bool {
        var didRebuildMenu = false
        if self.lastMainMenuSignature != plan.signature || menu.items.isEmpty || isMenuTooSmall {
            self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
            self.lastMainMenuSignature = plan.signature
            didRebuildMenu = true
        }
        if didRebuildMenu {
            if let cachedWidth = self.lastMainMenuWidth {
                self.menuBuilder.refreshMenuViewHeights(in: menu, width: cachedWidth)
            } else {
                self.menuBuilder.refreshMenuViewHeights(in: menu)
            }
        }
        return didRebuildMenu
    }

    private func refreshMainMenuMetricsAfterOpen(_ menu: NSMenu, plan: MainMenuPlan, didRebuildMenu: Bool) {
        let shouldRecomputeWidth = self.lastMainMenuWidth == nil || self.lastMainMenuWidthSignature != plan.signature
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if shouldRecomputeWidth {
                let measuredWidth = self.menuBuilder.menuWidth(for: menu)
                let priorWidth = self.lastMainMenuWidth
                let shouldRemeasure = priorWidth == nil || abs(measuredWidth - (priorWidth ?? 0)) > 0.5
                self.lastMainMenuWidth = measuredWidth
                self.lastMainMenuWidthSignature = plan.signature
                if shouldRemeasure, didRebuildMenu {
                    self.menuBuilder.refreshMenuViewHeights(in: menu, width: measuredWidth)
                }
            }
            self.menuBuilder.clearHighlights(in: menu)
            self.startObservingMenuResize(for: menu)
        }
    }

    private func prepareSubmenuWillOpen(_ menu: NSMenu) {
        self.menuBuilder.refreshMenuViewHeights(in: menu)
        let submenuFullName = menu.supermenu?.items.first(where: { $0.submenu === menu })?.representedObject as? String
        if let fullName = submenuFullName, fullName.contains("/") {
            // Repo submenu opened; prefetch so nested recent lists appear instantly.
            self.recentListCoordinator.prefetchRecentLists(fullNames: [fullName])
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === self.mainMenu {
            let shouldReopen = self.pendingMenuReopen
            self.pendingMenuReopen = false
            self.menuBuilder.clearHighlights(in: menu)
            self.stopObservingMenuResize()
            self.logMenuEvent("menuDidClose mainMenu")
            if shouldReopen {
                self.reopenMainMenu()
            }
        }
    }

    private func reopenMainMenu() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            self.statusItem?.button?.performClick(nil)
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            guard let view = menuItem.view as? MenuItemHighlighting else { continue }

            let highlighted = menuItem == item && menuItem.isEnabled
            view.setHighlighted(highlighted)
        }
    }

    private func startObservingMenuResize(for menu: NSMenu) {
        self.stopObservingMenuResize()
        guard let window = menu.items.compactMap(\.view).first?.window else { return }

        self.menuResizeWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuWindowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    private func stopObservingMenuResize() {
        guard let window = self.menuResizeWindow else { return }

        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: window)
        self.menuResizeWindow = nil
    }

    @objc private func menuWindowDidResize(_: Notification) {
        guard let menu = self.mainMenu else { return }

        let width = self.menuBuilder.menuWidth(for: menu)
        self.lastMainMenuWidth = width
        self.menuBuilder.refreshMenuViewHeights(in: menu, width: width)
        menu.update()
    }

    func logMenuEvent(_ message: String) {
        self.logger.info("\(message)")
        Task { await DiagnosticsLogger.shared.message(message) }
    }

    func prepareMainMenuIfNeeded(_ menu: NSMenu) {
        let isMenuTooSmall = menu.items.count < Self.minimumMainMenuItems
        if self.lastMainMenuSignature == nil || menu.items.isEmpty || isMenuTooSmall {
            self.appState.reloadRateLimitCacheSummary()
            let plan = self.menuBuilder.mainMenuPlan()
            self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
            self.lastMainMenuSignature = plan.signature
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        }
    }

    func objectID(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }

        return String(ObjectIdentifier(object).hashValue)
    }
}
