import AppKit
import Logging
import OSLog
import RepoBarCore

@MainActor
final class StatusBarMenuManager: NSObject, NSMenuDelegate {
    let appState: AppState
    private let statusBar: NSStatusBar
    var mainMenu: NSMenu?
    var statusItem: NSStatusItem?
    lazy var menuBuilder = StatusBarMenuBuilder(appState: self.appState, target: self)
    private let menuItemFactory = MenuItemViewFactory()
    lazy var recentMenuService = RecentMenuService(appState: self.appState)
    lazy var recentListCoordinator = RecentListMenuCoordinator(
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
    let signposter = OSSignposter(subsystem: "com.steipete.repobar", category: "menu")
    let logger = RepoBarLogging.logger("menu-state")
    weak var menuResizeWindow: NSWindow?
    var lastMainMenuWidth: CGFloat?
    var lastMainMenuSignature: MenuBuildSignature?
    var lastMainMenuWidthSignature: MenuBuildSignature?
    var pendingMenuReopen = false
    private var appAppearanceObservation: NSKeyValueObservation?
    private lazy var issueNavigatorWindowController = IssueNavigatorWindowController(appState: self.appState)
    private lazy var gitHubReferenceStatusCoordinator = GitHubReferenceStatusCoordinator(
        appState: self.appState,
        statusBar: self.statusBar,
        openIssueNavigator: { [weak self] matches in
            self?.openIssueNavigator(matches: matches)
        },
        preloadIssueNavigator: { [weak self] matches in
            self?.issueNavigatorWindowController.preloadFirstPreview(for: matches)
        },
        log: { [weak self] message in
            self?.logMenuEvent(message)
        }
    )
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
            selector: #selector(self.openIssueNavigatorFromNotification(_:)),
            name: .issueNavigatorOpenRequested,
            object: nil
        )
    }

    func tearDownStatusItems() {
        self.gitHubReferenceStatusCoordinator.tearDown()
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

        self.gitHubReferenceStatusCoordinator.sync()
        self.auditStatusItems("ensureStatusItems")
    }

    func attachMainMenu(to statusItem: NSStatusItem) {
        let menu = self.mainMenu ?? self.menuBuilder.makeMainMenu()
        self.mainMenu = menu
        self.syncMainMenuAppearance()
        self.observeAppAppearanceIfNeeded()
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

    /// Covers both the RepoBar Appearance setting and macOS switching while RepoBar follows the system.
    private func observeAppAppearanceIfNeeded() {
        guard self.appAppearanceObservation == nil, let app = NSApp else { return }

        self.appAppearanceObservation = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncMainMenuAppearance()
            }
        }
    }

    /// Setting the appearance in `menuWillOpen` only affects the next open: AppKit has already laid out
    /// the menu window by then. Pin it up front (on attach and whenever the app appearance changes) so the
    /// current Light/Dark mode is correct on the first open.
    private func syncMainMenuAppearance() {
        guard let app = NSApp, let menu = self.mainMenu else { return }

        menu.appearance = app.effectiveAppearance
    }

    private func applyStatusItemAppearance() {
        guard let button = self.statusItem?.button else { return }

        let juice = RateLimitJuice(
            diagnostics: self.appState.session.rateLimitDiagnostics,
            cacheSummary: self.appState.session.rateLimitCacheSummary
        )
        guard self.appState.session.settings.appearance.showRateLimitMeterInMenuBar,
              juice.hasData
        else {
            self.setButtonImage(self.fallbackStatusImage(), for: button)
            self.setButtonTitle(nil, for: button)
            button.toolTip = "RepoBar"
            button.setAccessibilityLabel("RepoBar")
            button.imageScaling = .scaleProportionallyDown
            return
        }

        let image = RateLimitStatusIconRenderer.makeIcon(
            restText: juice.compactRestText ?? "?",
            graphQLText: juice.compactGraphQLText ?? "?"
        )
        self.setButtonImage(image, for: button)
        self.setButtonTitle(nil, for: button)
        button.toolTip = juice.menuBarTooltip
        button.setAccessibilityLabel(juice.menuBarTooltip)
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        button.imageScaling = .scaleNone
    }

    private func auditStatusItems(_ context: String) {
        #if DEBUG
            let main = self.statusItem.map { self.objectID($0) } ?? "nil"
            let watcher = self.gitHubReferenceStatusCoordinator.statusItem.map { self.objectID($0) } ?? "nil"
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
            self.gitHubReferenceStatusCoordinator.sync()
        }

        func gitHubReferenceStatusItemForTesting() -> NSStatusItem? {
            self.gitHubReferenceStatusCoordinator.statusItem
        }

        func gitHubReferenceMenuForTesting() -> NSMenu? {
            self.gitHubReferenceStatusCoordinator.menu
        }

        func populateGitHubReferenceMenuForTesting(_ menu: NSMenu, matches: [GitHubReferenceMatch]) {
            self.gitHubReferenceStatusCoordinator.populate(menu, matches: matches)
        }
    #endif
}

private extension StatusBarMenuManager {
    func fallbackStatusImage() -> NSImage {
        let symbolName = self.appState.session.account.isLoggedIn ? "tray.fill" : "tray"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "RepoBar")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    func setButtonImage(_ image: NSImage, for button: NSStatusBarButton) {
        if button.image === image {
            return
        }
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
