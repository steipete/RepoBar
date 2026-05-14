import AppKit
import Logging
import OSLog
import RepoBarCore

@MainActor
final class StatusBarMenuManager: NSObject, NSMenuDelegate {
    private static let minimumMainMenuItems = 3
    private static let hiddenGitHubReferenceItemLength: CGFloat = 0
    private static let gitHubReferenceMaxStatusItemLength: CGFloat = 360
    private static let gitHubReferenceRepositoryTitleLimit = 30
    private static let gitHubReferenceSummaryTitleLimit = 28
    let appState: AppState
    private let statusBar: NSStatusBar
    private var mainMenu: NSMenu?
    var statusItem: NSStatusItem?
    var gitHubReferenceStatusItem: NSStatusItem?
    private var gitHubReferenceMenu: NSMenu?
    private lazy var menuBuilder = StatusBarMenuBuilder(appState: self.appState, target: self)
    private let menuItemFactory = MenuItemViewFactory()
    lazy var recentMenuService = RecentMenuService(github: self.appState.github)
    private lazy var recentListCoordinator = RecentListMenuCoordinator(
        appState: self.appState,
        menuBuilder: self.menuBuilder,
        menuItemFactory: self.menuItemFactory,
        menuService: self.recentMenuService,
        actionHandler: self
    )
    lazy var localGitMenuCoordinator = LocalGitMenuCoordinator(
        appState: self.appState,
        menuBuilder: self.menuBuilder,
        menuItemFactory: self.menuItemFactory,
        recentMenuService: self.recentMenuService,
        actionHandler: self
    )
    lazy var changelogMenuCoordinator = ChangelogMenuCoordinator(
        appState: self.appState,
        menuBuilder: self.menuBuilder,
        menuItemFactory: self.menuItemFactory
    )
    lazy var activityMenuCoordinator = ActivityMenuCoordinator(
        appState: self.appState,
        menuBuilder: self.menuBuilder,
        actionHandler: self
    )
    private let signposter = OSSignposter(subsystem: "com.steipete.repobar", category: "menu")
    private let logger = RepoBarLogging.logger("menu-state")
    private weak var menuResizeWindow: NSWindow?
    private var lastMainMenuWidth: CGFloat?
    private var lastMainMenuSignature: MenuBuildSignature?
    private var lastMainMenuWidthSignature: MenuBuildSignature?
    private var pendingMenuReopen = false
    private var gitHubReferenceSyncTask: Task<Void, Never>?
    private var gitHubReferenceMenuMatches: [GitHubReferenceMatch] = []
    private lazy var issueNavigatorWindowController = IssueNavigatorWindowController(appState: self.appState)
    var webURLBuilder: RepoWebURLBuilder {
        RepoWebURLBuilder(host: self.appState.session.settings.githubHost)
    }

    private weak var checkoutProgressWindow: NSWindow?

    init(appState: AppState, statusBar: NSStatusBar = .system) {
        self.appState = appState
        self.statusBar = statusBar
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuFiltersChanged),
            name: .menuFiltersDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuRepositoriesChanged),
            name: .menuRepositoriesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuRepositoriesChanged),
            name: .menuDiagnosticsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.recentListFiltersChanged),
            name: .recentListFiltersDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.gitHubReferenceMatchChanged),
            name: .gitHubReferenceMatchDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.openIssueNavigatorFromNotification(_:)),
            name: .issueNavigatorOpenRequested,
            object: nil
        )
    }

    func tearDownStatusItems() {
        self.gitHubReferenceSyncTask?.cancel()
        self.gitHubReferenceSyncTask = nil
        self.removeGitHubReferenceStatusItem()
        if let item = self.statusItem {
            item.menu = nil
            item.button?.image = nil
            item.button?.title = ""
            self.statusItem = nil
            self.statusBar.removeStatusItem(item)
        }
        self.mainMenu = nil
        self.auditStatusItems("tearDownStatusItems")
    }

    var isAttached: Bool {
        self.statusItem != nil
    }

    func ensureStatusItems() {
        if self.statusItem == nil {
            let item = self.statusBar.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "repobar-main"
            item.isVisible = true
            item.button?.imageScaling = .scaleNone
            self.attachMainMenu(to: item)
        }

        self.syncGitHubReferenceStatusItem()
        self.auditStatusItems("ensureStatusItems")
    }

    func attachMainMenu(to statusItem: NSStatusItem) {
        let menu = self.mainMenu ?? self.menuBuilder.makeMainMenu()
        self.mainMenu = menu
        menu.delegate = self
        self.statusItem = statusItem
        statusItem.length = NSStatusItem.variableLength
        statusItem.menu = menu
        if let button = statusItem.button {
            button.isEnabled = true
            button.target = nil
            button.action = nil
        }
        self.applyStatusItemAppearance()
        DispatchQueue.main.async { [weak self] in
            self?.applyStatusItemAppearance()
        }
        self.prepareMainMenuIfNeeded(menu)
        self.logMenuEvent("attachMainMenu statusItem=\(self.objectID(statusItem)) menuItems=\(menu.items.count)")
    }

    func requestMenuReopenAfterClose() {
        self.pendingMenuReopen = true
    }

    // MARK: - Menu actions

    @objc func refreshNow() {
        self.appState.requestRefresh(cancelInFlight: true)
    }

    @objc func openPreferences() {
        SettingsOpener.shared.open()
    }

    @objc func openIssueNavigator() {
        self.openIssueNavigator(matches: [])
    }

    @objc private func openIssueNavigatorFromNotification(_ notification: Notification) {
        let matches = notification.object as? [GitHubReferenceMatch] ?? []
        self.openIssueNavigator(matches: matches)
    }

    private func openIssueNavigator(matches: [GitHubReferenceMatch]) {
        guard self.appState.session.account.isLoggedIn else {
            self.signIn()
            return
        }

        self.issueNavigatorWindowController.show(matches: matches)
    }

    @objc func openAbout() {
        self.appState.session.settingsSelectedTab = .about
        SettingsOpener.shared.open()
    }

    @objc func checkForUpdates() {
        SparkleController.shared.checkForUpdates()
    }

    @objc func menuFiltersChanged() {
        guard let menu = self.mainMenu else { return }

        // Defer menu rebuild to next run loop to avoid modifying menu during layout
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.recentListCoordinator.pruneMenus()
            self.appState.persistSettings()
            let plan = self.menuBuilder.mainMenuPlan()
            self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
            self.lastMainMenuSignature = plan.signature
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        }
    }

    @objc private func recentListFiltersChanged() {
        self.recentListCoordinator.handleFilterChanges()
    }

    @objc private func gitHubReferenceMatchChanged() {
        self.gitHubReferenceSyncTask?.cancel()
        self.gitHubReferenceSyncTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }

            self?.gitHubReferenceSyncTask = nil
            self?.syncGitHubReferenceStatusItem()
        }
    }

    private func syncGitHubReferenceStatusItem() {
        let matches = self.appState.session.gitHubReferenceMatches
        guard self.appState.session.gitHubReferenceMatch != nil, matches.isEmpty == false else {
            self.hideGitHubReferenceStatusItem()
            return
        }

        let item = self.lazyGitHubReferenceStatusItem()
        let menu = self.lazyGitHubReferenceMenu()
        self.populateGitHubReferenceMenu(menu, matches: matches)
        item.length = NSStatusItem.variableLength
        if let button = item.button {
            button.isHidden = false
            button.isEnabled = true
            button.image = NSImage(
                systemSymbolName: self.gitHubReferenceSystemImage(for: matches),
                accessibilityDescription: self.gitHubReferenceAccessibilityDescription(for: matches)
            )
            button.image?.isTemplate = true
            button.imageScaling = .scaleNone
            (button.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
            self.setButtonTitle(self.gitHubReferenceTitle(for: matches), for: button)
            button.toolTip = self.gitHubReferenceMenuTitle(for: matches)
            button.target = nil
            button.action = nil
            self.clampGitHubReferenceStatusItemLength(item, button: button)
        }
        item.menu = menu
        item.isVisible = true
        self.auditStatusItems("syncGitHubReferenceStatusItem visible")
    }

    private func hideGitHubReferenceStatusItem() {
        guard let item = self.gitHubReferenceStatusItem else { return }

        self.gitHubReferenceMenu = nil
        self.gitHubReferenceMenuMatches = []
        self.collapseGitHubReferenceStatusItem(item)
        self.auditStatusItems("hideGitHubReferenceStatusItem")
    }

    private func collapseGitHubReferenceStatusItem(_ item: NSStatusItem) {
        item.menu = nil
        item.length = Self.hiddenGitHubReferenceItemLength
        if let button = item.button {
            button.isHidden = true
            button.isEnabled = false
            button.image = nil
            button.title = ""
            button.toolTip = nil
            button.imagePosition = .imageOnly
            button.target = nil
            button.action = nil
        }
        item.isVisible = true
    }

    private func lazyGitHubReferenceStatusItem() -> NSStatusItem {
        if let item = self.gitHubReferenceStatusItem {
            return item
        }

        let item = self.statusBar.statusItem(withLength: Self.hiddenGitHubReferenceItemLength)
        item.autosaveName = "repobar-github-reference"
        item.button?.imageScaling = .scaleNone
        self.gitHubReferenceStatusItem = item
        self.collapseGitHubReferenceStatusItem(item)
        self.auditStatusItems("lazyGitHubReferenceStatusItem created collapsed")
        return item
    }

    private func removeGitHubReferenceStatusItem() {
        self.gitHubReferenceMenu = nil
        self.gitHubReferenceMenuMatches = []
        guard let item = self.gitHubReferenceStatusItem else { return }

        self.collapseGitHubReferenceStatusItem(item)
        self.gitHubReferenceStatusItem = nil
        self.statusBar.removeStatusItem(item)
        self.auditStatusItems("removeGitHubReferenceStatusItem")
    }

    private func lazyGitHubReferenceMenu() -> NSMenu {
        if let menu = self.gitHubReferenceMenu {
            return menu
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        self.gitHubReferenceMenu = menu
        return menu
    }

    private func applyStatusItemAppearance() {
        guard let button = self.statusItem?.button else { return }

        let juice = RateLimitJuice(
            diagnostics: self.appState.session.rateLimitDiagnostics,
            cacheSummary: self.appState.session.rateLimitCacheSummary
        )
        guard self.appState.session.settings.appearance.showRateLimitMeterInMenuBar,
              juice.hasData,
              let text = juice.compactRestText
        else {
            self.setButtonImage(self.fallbackStatusImage(), for: button)
            self.setButtonTitle(nil, for: button)
            button.toolTip = "RepoBar"
            button.imageScaling = .scaleProportionallyDown
            return
        }

        let image = RateLimitStatusIconRenderer.makeIcon(
            restPercent: juice.displayRestPercent,
            graphQLPercent: juice.displayGraphQLPercent
        )
        self.setButtonImage(image, for: button)
        self.setButtonTitle(text, for: button)
        button.toolTip = self.rateLimitTooltip(juice: juice)
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        button.imageScaling = .scaleNone
    }

    private func auditStatusItems(_ context: String) {
        #if DEBUG
            let main = self.statusItem.map { self.objectID($0) } ?? "nil"
            let watcher = self.gitHubReferenceStatusItem.map { self.objectID($0) } ?? "nil"
            self.logMenuEvent("status item audit \(context) main=\(main) watcher=\(watcher)")
        #endif
    }

    @objc func toggleIssueLabelFilter(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String else { return }

        self.recentListCoordinator.toggleIssueLabelFilter(label: label)
    }

    @objc func clearIssueLabelFilters() {
        self.recentListCoordinator.clearIssueLabelFilters()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let signpost = self.signposter.beginInterval("menuWillOpen")
        defer { self.signposter.endInterval("menuWillOpen", signpost) }
        if self.prepareGitHubReferenceMenuIfNeeded(menu) { return }
        self.prepareMenuAppearance(menu)
        if self.recentListCoordinator.handleMenuWillOpen(menu) { return }
        if self.localGitMenuCoordinator.handleMenuWillOpen(menu) { return }
        if self.changelogMenuCoordinator.handleMenuWillOpen(menu) { return }
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

    private func prepareGitHubReferenceMenuIfNeeded(_ menu: NSMenu) -> Bool {
        guard menu === self.gitHubReferenceMenu else { return false }

        self.logMenuEvent("menuWillOpen gitHubReferenceMenu items=\(menu.items.count)")
        self.refreshGitHubReferenceMenuIfNeeded(menu)
        return true
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

    func registerLocalBranchMenu(_ menu: NSMenu, repoPath: URL, fullName: String, localStatus: LocalRepoStatus) {
        self.localGitMenuCoordinator.registerLocalBranchMenu(menu, repoPath: repoPath, fullName: fullName, localStatus: localStatus)
    }

    func registerCombinedBranchMenu(_ menu: NSMenu, repoPath: URL, fullName: String, localStatus: LocalRepoStatus) {
        self.localGitMenuCoordinator.registerCombinedBranchMenu(menu, repoPath: repoPath, fullName: fullName, localStatus: localStatus)
    }

    func registerLocalWorktreeMenu(_ menu: NSMenu, repoPath: URL, fullName: String) {
        self.localGitMenuCoordinator.registerLocalWorktreeMenu(menu, repoPath: repoPath, fullName: fullName)
    }

    func registerChangelogMenu(_ menu: NSMenu, fullName: String, localStatus: LocalRepoStatus?) {
        self.changelogMenuCoordinator.registerChangelogMenu(menu, fullName: fullName, localStatus: localStatus)
    }

    func cachedChangelogPresentation(fullName: String, releaseTag: String?) -> ChangelogRowPresentation? {
        self.changelogMenuCoordinator.cachedPresentation(fullName: fullName, releaseTag: releaseTag)
    }

    func cachedChangelogHeadline(fullName: String) -> String? {
        self.changelogMenuCoordinator.cachedHeadline(fullName: fullName)
    }

    func cloneURL(for fullName: String) -> URL? {
        let host = self.appState.session.settings.githubHost
        var url = host.appendingPathComponent(fullName)
        url.appendPathExtension("git")
        return url
    }

    func showCheckoutProgress(fullName: String, destination: URL) {
        self.closeCheckoutProgress()
        let alert = NSAlert()
        alert.messageText = "Checking out \(fullName)"
        alert.informativeText = PathFormatter.displayString(destination.path)

        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)

        let stack = NSStackView(views: [indicator])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        alert.accessoryView = stack

        let window = alert.window
        window.level = .floating
        self.checkoutProgressWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeCheckoutProgress() {
        self.checkoutProgressWindow?.close()
        self.checkoutProgressWindow = nil
    }

    func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

    private func logMenuEvent(_ message: String) {
        self.logger.info("\(message)")
        self.appendClickDiagnostic(message)
        Task { await DiagnosticsLogger.shared.message(message) }
    }

    private func appendClickDiagnostic(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let url = URL(fileURLWithPath: "/tmp/repobar-clicks.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
    }

    private func prepareMainMenuIfNeeded(_ menu: NSMenu) {
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

    private func objectID(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }

        return String(ObjectIdentifier(object).hashValue)
    }

    func registerRecentListMenu(_ menu: NSMenu, context: RepoRecentMenuContext) {
        self.recentListCoordinator.registerRecentListMenu(menu, context: context)
    }

    func cachedRecentCommitCount(fullName: String) -> Int? {
        self.recentListCoordinator.cachedRecentCommitCount(fullName: fullName)
    }

    func repoModel(from sender: NSMenuItem) -> RepositoryDisplayModel? {
        guard let fullName = self.repoFullName(from: sender) else { return nil }
        guard let repo = self.appState.session.repositories.first(where: { $0.fullName == fullName }) else { return nil }

        let local = self.appState.session.localRepoIndex.status(forFullName: fullName)
        return RepositoryDisplayModel(repo: repo, localStatus: local)
    }

    func repoFullName(from sender: NSMenuItem) -> String? {
        sender.representedObject as? String
    }

    func openRepoPath(sender: NSMenuItem, path: String) {
        guard let fullName = self.repoFullName(from: sender),
              let url = self.webURLBuilder.repoPathURL(fullName: fullName, path: path) else { return }

        self.open(url: url)
    }

    func open(url: URL) {
        SecurityScopedBookmark.withAccess(
            to: url,
            rootBookmarkData: self.appState.session.settings.localProjects.rootBookmarkData
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openGitHubReferenceMatch(_ sender: Any?) {
        let representedURL = (sender as? NSMenuItem)?.representedObject as? URL
        guard let url = representedURL ?? self.appState.session.gitHubReferenceMatch?.url else {
            self.logMenuEvent("GitHub reference click ignored: no URL")
            return
        }

        self.logMenuEvent("GitHub reference click open url=\(url.absoluteString)")
        self.open(url: url)
    }

    @objc func copyGitHubReferenceURL(_ sender: Any?) {
        let representedURL = (sender as? NSMenuItem)?.representedObject as? URL
        guard let url = representedURL ?? self.appState.session.gitHubReferenceMatch?.url else {
            self.logMenuEvent("GitHub reference copy ignored: no URL")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        self.logMenuEvent("GitHub reference copied url=\(url.absoluteString)")
    }

    @objc func menuItemNoOp(_: NSMenuItem) {}

    #if DEBUG
        func setMainMenuForTesting(_ menu: NSMenu) {
            self.mainMenu = menu
        }

        func makeLocalWorktreeMenuItemForTesting(
            _ model: LocalRefMenuRowViewModel,
            path: URL,
            fullName: String
        ) -> NSMenuItem {
            self.localGitMenuCoordinator.makeLocalWorktreeMenuItemForTesting(model, path: path, fullName: fullName)
        }

        func isWorktreeMenuItemForTesting(_ item: NSMenuItem) -> Bool {
            self.localGitMenuCoordinator.isWorktreeMenuItemForTesting(item)
        }

        func isRecentListMenu(_ menu: NSMenu) -> Bool {
            self.recentListCoordinator.containsMenuForTesting(menu)
        }

        func syncGitHubReferenceStatusItemForTesting() {
            self.syncGitHubReferenceStatusItem()
        }

        func gitHubReferenceStatusItemForTesting() -> NSStatusItem? {
            self.gitHubReferenceStatusItem
        }

        func gitHubReferenceMenuForTesting() -> NSMenu? {
            self.gitHubReferenceMenu
        }

        func populateGitHubReferenceMenuForTesting(_ menu: NSMenu, matches: [GitHubReferenceMatch]) {
            self.populateGitHubReferenceMenu(menu, matches: matches)
        }
    #endif
}

extension StatusBarMenuManager {
    @objc func openGitHubReferenceMatchesInIssueNavigator() {
        guard self.appState.session.account.isLoggedIn else {
            self.signIn()
            return
        }

        let matches = self.appState.session.gitHubReferenceMatches
        guard matches.isEmpty == false else {
            self.openIssueNavigator()
            return
        }

        self.openIssueNavigator(matches: matches)
    }
}

private extension StatusBarMenuManager {
    func populateGitHubReferenceMenu(_ menu: NSMenu, matches: [GitHubReferenceMatch]) {
        guard self.gitHubReferenceMenuMatches != matches else { return }

        menu.removeAllItems()
        self.gitHubReferenceMenuMatches = matches

        if matches.count == 1, let match = matches.first {
            self.addGitHubReferenceItems(to: menu, match: match, includeBrowserPreview: true)
            return
        }

        for match in matches {
            let item = NSMenuItem(title: self.gitHubReferenceTitle(for: match), action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: self.gitHubReferenceSystemImage(for: match), accessibilityDescription: match.kind.label)
            item.image?.isTemplate = true

            let submenu = NSMenu()
            submenu.autoenablesItems = false
            self.addGitHubReferenceItems(to: submenu, match: match, includeBrowserPreview: true)
            item.submenu = submenu
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let item = NSMenuItem(
            title: "Open \(matches.count) refs in Issue Navigator…",
            action: #selector(self.openGitHubReferenceMatchesInIssueNavigator),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(systemSymbolName: "rectangle.and.text.magnifyingglass", accessibilityDescription: "Issue Navigator")
        item.image?.isTemplate = true
        menu.addItem(item)
    }

    func addGitHubReferenceItems(to menu: NSMenu, match: GitHubReferenceMatch, includeBrowserPreview: Bool) {
        guard includeBrowserPreview else { return }

        let browserItem = NSMenuItem()
        let browserView = GitHubReferenceBrowserMenuItemView(match: match)
        if self.shouldPreloadGitHubReferenceBrowserPreview, self.appState.session.gitHubReferenceMatches.count <= 1 {
            browserView.preload()
        }
        browserItem.view = browserView
        browserItem.toolTip = self.gitHubReferenceMenuTitle(for: match)
        menu.addItem(browserItem)
    }

    func gitHubReferenceMenuTitle(for match: GitHubReferenceMatch) -> String {
        let state = match.state.map { "\($0.label) " } ?? ""
        let kind = match.kind.label
        return "\(state)\(kind): \(match.title)"
    }

    func gitHubReferenceMenuTitle(for matches: [GitHubReferenceMatch]) -> String {
        if matches.count == 1, let match = matches.first {
            return self.gitHubReferenceMenuTitle(for: match)
        }
        if let repo = self.commonRepositoryFullName(in: matches) {
            return "\(matches.count) GitHub references in \(repo)"
        }
        return "\(matches.count) GitHub references"
    }

    func refreshGitHubReferenceMenuIfNeeded(_ menu: NSMenu) {
        guard menu === self.gitHubReferenceMenu,
              self.appState.session.gitHubReferenceMatches.isEmpty == false
        else {
            return
        }

        self.populateGitHubReferenceMenu(menu, matches: self.appState.session.gitHubReferenceMatches)
    }

    var shouldPreloadGitHubReferenceBrowserPreview: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    func gitHubReferenceSystemImage(for match: GitHubReferenceMatch) -> String {
        switch match.kind {
        case .issue:
            match.state == .closed ? "checkmark.circle" : "exclamationmark.circle"
        case .pullRequest:
            switch match.state {
            case .merged:
                "arrow.triangle.merge"
            case .closed:
                "xmark.circle"
            case .open, nil:
                "arrow.triangle.branch.circle"
            }
        case .commit:
            "number.square"
        case .workflowRun:
            "play.circle"
        }
    }

    func gitHubReferenceSystemImage(for matches: [GitHubReferenceMatch]) -> String {
        guard matches.count != 1, let first = matches.first else {
            return matches.first.map(self.gitHubReferenceSystemImage(for:)) ?? "number.square"
        }

        if matches.allSatisfy({ $0.kind == first.kind }) {
            return self.gitHubReferenceSystemImage(for: first)
        }
        return "list.bullet.rectangle"
    }

    func gitHubReferenceAccessibilityDescription(for matches: [GitHubReferenceMatch]) -> String {
        if matches.count == 1, let match = matches.first {
            return match.kind.label
        }
        return "\(matches.count) GitHub References"
    }

    func gitHubReferenceTitle(for matches: [GitHubReferenceMatch]) -> String {
        guard matches.count != 1 else {
            return matches.first.map(self.gitHubReferenceTitle(for:)) ?? ""
        }

        let repoSuffix = self.commonRepositoryFullName(in: matches)
            .map { " " + Self.truncatedMiddle($0, maxCharacters: Self.gitHubReferenceRepositoryTitleLimit) }
            ?? ""
        return "\(matches.count) GitHub refs\(repoSuffix)"
    }

    func gitHubReferenceTitle(for match: GitHubReferenceMatch) -> String {
        var parts = [self.gitHubReferenceText(for: match)]
        if let state = match.state?.label {
            parts.append(state)
        }
        parts.append(Self.truncatedMiddle(match.repositoryFullName, maxCharacters: Self.gitHubReferenceRepositoryTitleLimit))
        let prefix = parts.joined(separator: " ")
        let title = Self.truncatedTail(match.title, maxCharacters: Self.gitHubReferenceSummaryTitleLimit)
        return "\(prefix): \(title)"
    }

    func gitHubReferenceText(for match: GitHubReferenceMatch) -> String {
        switch match.query {
        case let .issueNumber(number),
             let .repositoryNameIssueNumber(_, number),
             let .repositoryIssueNumber(_, number):
            "#\(number)"
        case let .commitHash(hash),
             let .repositoryCommitHash(_, hash):
            String(hash.prefix(10))
        case let .repositoryWorkflowRun(_, runID):
            "Run \(runID)"
        }
    }

    func commonRepositoryFullName(in matches: [GitHubReferenceMatch]) -> String? {
        guard let first = matches.first?.repositoryFullName else { return nil }

        return matches.allSatisfy { $0.repositoryFullName.caseInsensitiveCompare(first) == .orderedSame } ? first : nil
    }

    func clampGitHubReferenceStatusItemLength(_ item: NSStatusItem, button: NSStatusBarButton) {
        let fitted = button.fittingSize.width
        let desired = fitted.isFinite && fitted > 0
            ? ceil(fitted + 6)
            : Self.gitHubReferenceMaxStatusItemLength
        item.length = min(desired, Self.gitHubReferenceMaxStatusItemLength)
    }

    static func truncatedTail(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters, maxCharacters > 3 else {
            return value
        }

        return "\(value.prefix(maxCharacters - 3))..."
    }

    static func truncatedMiddle(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters, maxCharacters > 5 else {
            return value
        }

        let available = maxCharacters - 3
        let headCount = available / 2
        let tailCount = available - headCount
        return "\(value.prefix(headCount))...\(value.suffix(tailCount))"
    }

    func fallbackStatusImage() -> NSImage {
        let symbolName = self.appState.session.account.isLoggedIn ? "tray.fill" : "tray"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "RepoBar")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    func setButtonImage(_ image: NSImage, for button: NSStatusBarButton) {
        if button.image === image { return }
        button.image = image
    }

    func setButtonTitle(_ title: String?, for button: NSStatusBarButton) {
        let rawValue = title ?? ""
        let value = rawValue.isEmpty || button.image == nil ? rawValue : " \(rawValue)"
        if button.title != value {
            button.title = value
        }
        let position: NSControl.ImagePosition = value.isEmpty ? .imageOnly : .imageLeft
        if button.imagePosition != position {
            button.imagePosition = position
        }
    }

    func rateLimitTooltip(juice: RateLimitJuice) -> String {
        let rest = self.rateLimitTooltipPart(label: "REST", remaining: juice.restRemaining, limit: juice.restLimit)
        let graphQL = self.rateLimitTooltipPart(label: "GraphQL", remaining: juice.graphQLRemaining, limit: juice.graphQLLimit)
        return "RepoBar GitHub rate limits: \(rest), \(graphQL)"
    }

    func rateLimitTooltipPart(label: String, remaining: Int?, limit: Int?) -> String {
        if let remaining, let limit {
            return "\(label) \(remaining)/\(limit)"
        }
        if let remaining {
            return "\(label) \(remaining) left"
        }
        return "\(label) unknown"
    }
}

extension StatusBarMenuManager {
    @objc func menuRepositoriesChanged() {
        guard let menu = self.mainMenu else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.applyStatusItemAppearance()
            let plan = self.menuBuilder.mainMenuPlan()
            guard self.lastMainMenuSignature != plan.signature else { return }

            if menu.hasVisibleHostedViews {
                self.lastMainMenuSignature = nil
                return
            }

            self.recentListCoordinator.pruneMenus()
            self.localGitMenuCoordinator.pruneMenus()
            self.changelogMenuCoordinator.pruneMenus()
            self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
            self.lastMainMenuSignature = plan.signature
            self.lastMainMenuWidthSignature = nil
            if let width = self.lastMainMenuWidth {
                self.menuBuilder.refreshMenuViewHeights(in: menu, width: width)
            } else {
                self.menuBuilder.refreshMenuViewHeights(in: menu)
            }
            menu.update()
        }
    }
}

@MainActor
private extension NSMenu {
    var hasVisibleHostedViews: Bool {
        self.items.contains { $0.view?.window != nil }
    }
}
