import AppKit
import RepoBarCore

@MainActor
final class GitHubReferenceStatusCoordinator: NSObject, NSMenuDelegate {
    private static let hiddenItemLength: CGFloat = 0
    private static let maxItemLength: CGFloat = 360
    private static let repositoryTitleLimit = 30
    private static let summaryTitleLimit = 28

    private let appState: AppState
    private let statusBar: NSStatusBar
    private let openIssueNavigator: ([GitHubReferenceMatch]) -> Void
    private let preloadIssueNavigator: ([GitHubReferenceMatch]) -> Void
    private let log: (String) -> Void
    private var menuMatches: [GitHubReferenceMatch] = []
    private var syncTask: Task<Void, Never>?

    private(set) var statusItem: NSStatusItem?
    private(set) var menu: NSMenu?

    init(
        appState: AppState,
        statusBar: NSStatusBar,
        openIssueNavigator: @escaping ([GitHubReferenceMatch]) -> Void,
        preloadIssueNavigator: @escaping ([GitHubReferenceMatch]) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.appState = appState
        self.statusBar = statusBar
        self.openIssueNavigator = openIssueNavigator
        self.preloadIssueNavigator = preloadIssueNavigator
        self.log = log
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.matchesDidChange),
            name: .gitHubReferenceMatchDidChange,
            object: nil
        )
    }

    func sync() {
        let matches = self.appState.session.gitHubReferenceMatches
        guard self.appState.session.gitHubReferenceMatch != nil, matches.isEmpty == false else {
            self.hide()
            return
        }

        let item = self.makeStatusItemIfNeeded()
        self.populate(self.makeMenuIfNeeded(), matches: matches)
        item.length = NSStatusItem.variableLength
        if let button = item.button {
            button.isHidden = false
            button.isEnabled = true
            button.image = NSImage(
                systemSymbolName: self.systemImage(for: matches),
                accessibilityDescription: self.accessibilityDescription(for: matches)
            )
            button.image?.isTemplate = true
            button.imageScaling = .scaleNone
            (button.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
            self.setButtonTitle(self.title(for: matches), for: button)
            button.toolTip = self.menuTitle(for: matches)
            button.target = self
            button.action = #selector(self.statusItemClicked(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            self.clampLength(item, button: button)
        }
        item.menu = nil
        item.isVisible = true
        self.audit("sync visible")
    }

    func tearDown() {
        self.syncTask?.cancel()
        self.syncTask = nil
        self.menu = nil
        self.menuMatches = []
        guard let item = self.statusItem else { return }

        self.collapse(item)
        self.statusItem = nil
        self.statusBar.removeStatusItem(item)
        self.audit("removed")
    }

    func populate(_ menu: NSMenu, matches: [GitHubReferenceMatch]) {
        guard self.menuMatches != matches else { return }

        menu.removeAllItems()
        self.menuMatches = matches
        if matches.count == 1, let match = matches.first {
            self.addPreview(to: menu, match: match)
            return
        }

        for match in matches {
            let item = NSMenuItem(title: self.title(for: match), action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: self.systemImage(for: match), accessibilityDescription: match.kind.label)
            item.image?.isTemplate = true
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            self.addPreview(to: submenu, match: match)
            item.submenu = submenu
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let item = NSMenuItem(
            title: "Open \(matches.count) refs in Issue Navigator…",
            action: #selector(self.openCurrentMatchesInNavigator),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(systemSymbolName: "rectangle.and.text.magnifyingglass", accessibilityDescription: "Issue Navigator")
        item.image?.isTemplate = true
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) {
        self.log("menuWillOpen gitHubReferenceMenu items=\(menu.items.count)")
        if self.appState.session.gitHubReferenceMatches.isEmpty == false {
            self.populate(menu, matches: self.appState.session.gitHubReferenceMatches)
        }
        self.preloadPreviews(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        self.unloadPreviews(menu)
        self.statusItem?.menu = nil
    }

    @objc func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let shouldShowMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard shouldShowMenu == false else {
            self.showMenu(from: sender)
            return
        }

        let matches = self.appState.session.gitHubReferenceMatches
        guard matches.count > 1 else {
            self.showMenu(from: sender)
            return
        }

        self.openIssueNavigator(matches)
    }

    @objc private func matchesDidChange() {
        self.syncTask?.cancel()
        self.syncTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }

            self.syncTask = nil
            let matches = self.appState.session.gitHubReferenceMatches
            self.preloadIssueNavigator(matches)
            self.sync()
        }
    }

    @objc private func openCurrentMatchesInNavigator() {
        self.openIssueNavigator(self.appState.session.gitHubReferenceMatches)
    }

    private func makeMenuIfNeeded() -> NSMenu {
        if let menu {
            return menu
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        self.menu = menu
        return menu
    }

    private func makeStatusItemIfNeeded() -> NSStatusItem {
        if let statusItem {
            return statusItem
        }

        let item = self.statusBar.statusItem(withLength: Self.hiddenItemLength)
        item.autosaveName = "repobar-github-reference"
        item.button?.imageScaling = .scaleNone
        self.statusItem = item
        self.collapse(item)
        self.audit("created collapsed")
        return item
    }

    private func hide() {
        guard let item = self.statusItem else { return }

        self.menu = nil
        self.menuMatches = []
        self.collapse(item)
        self.audit("hidden")
    }

    private func collapse(_ item: NSStatusItem) {
        item.menu = nil
        item.length = Self.hiddenItemLength
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

    private func showMenu(from sender: Any?) {
        guard let item = self.statusItem,
              let button = sender as? NSStatusBarButton ?? item.button
        else { return }

        item.menu = self.makeMenuIfNeeded()
        button.performClick(nil)
    }

    private func addPreview(to menu: NSMenu, match: GitHubReferenceMatch) {
        let browserItem = NSMenuItem()
        browserItem.view = GitHubReferenceBrowserMenuItemView(match: match)
        browserItem.toolTip = self.menuTitle(for: match)
        menu.addItem(browserItem)
    }

    private func preloadPreviews(_ menu: NSMenu) {
        var remaining = min(
            AppLimits.GitHubReferenceMonitor.menuWebPreviewPreloadLimit,
            max(1, self.appState.session.gitHubReferenceMatches.count)
        )
        self.preloadPreviews(in: menu, remaining: &remaining)
    }

    private func preloadPreviews(in menu: NSMenu, remaining: inout Int) {
        guard remaining > 0 else { return }

        for item in menu.items {
            if let browserView = item.view as? GitHubReferenceBrowserMenuItemView {
                browserView.preload()
                remaining -= 1
                if remaining <= 0 {
                    return
                }
            }
            if let submenu = item.submenu {
                self.preloadPreviews(in: submenu, remaining: &remaining)
                if remaining <= 0 {
                    return
                }
            }
        }
    }

    private func unloadPreviews(_ menu: NSMenu) {
        for item in menu.items {
            (item.view as? GitHubReferenceBrowserMenuItemView)?.unload()
            if let submenu = item.submenu {
                self.unloadPreviews(submenu)
            }
        }
    }

    private func menuTitle(for match: GitHubReferenceMatch) -> String {
        let state = match.state.map { "\($0.label) " } ?? ""
        return "\(state)\(match.kind.label): \(match.title)"
    }

    private func menuTitle(for matches: [GitHubReferenceMatch]) -> String {
        if matches.count == 1, let match = matches.first {
            return self.menuTitle(for: match)
        }
        if let repo = self.commonRepository(in: matches) {
            return "\(matches.count) GitHub references in \(repo)"
        }
        return "\(matches.count) GitHub references"
    }

    private func systemImage(for match: GitHubReferenceMatch) -> String {
        switch match.kind {
        case .issue: match.state == .closed ? "checkmark.circle" : "exclamationmark.circle"
        case .pullRequest:
            switch match.state {
            case .merged: "arrow.triangle.merge"
            case .closed: "xmark.circle"
            case .open, nil: "arrow.triangle.branch.circle"
            }
        case .commit: "number.square"
        case .workflowRun: "play.circle"
        }
    }

    private func systemImage(for matches: [GitHubReferenceMatch]) -> String {
        guard matches.count != 1, let first = matches.first else {
            return matches.first.map(self.systemImage(for:)) ?? "number.square"
        }

        return matches.allSatisfy { $0.kind == first.kind } ? self.systemImage(for: first) : "list.bullet.rectangle"
    }

    private func accessibilityDescription(for matches: [GitHubReferenceMatch]) -> String {
        if matches.count == 1, let match = matches.first {
            return match.kind.label
        }
        return "\(matches.count) GitHub References"
    }

    private func title(for matches: [GitHubReferenceMatch]) -> String {
        guard matches.count != 1 else { return matches.first.map(self.title(for:)) ?? "" }

        let suffix = self.commonRepository(in: matches)
            .map { " " + Self.truncatedMiddle($0, maxCharacters: Self.repositoryTitleLimit) } ?? ""
        return "\(matches.count) GitHub refs\(suffix)"
    }

    private func title(for match: GitHubReferenceMatch) -> String {
        var parts = [self.referenceText(for: match)]
        if let state = match.state?.label {
            parts.append(state)
        }
        parts.append(Self.truncatedMiddle(match.repositoryFullName, maxCharacters: Self.repositoryTitleLimit))
        let title = Self.truncatedTail(match.title, maxCharacters: Self.summaryTitleLimit)
        return "\(parts.joined(separator: " ")): \(title)"
    }

    private func referenceText(for match: GitHubReferenceMatch) -> String {
        switch match.query {
        case let .issueNumber(number), let .repositoryNameIssueNumber(_, number), let .repositoryIssueNumber(_, number):
            "#\(number)"
        case let .commitHash(hash), let .repositoryCommitHash(_, hash):
            String(hash.prefix(10))
        case let .repositoryWorkflowRun(_, runID):
            "Run \(runID)"
        }
    }

    private func commonRepository(in matches: [GitHubReferenceMatch]) -> String? {
        guard let first = matches.first?.repositoryFullName else { return nil }

        return matches.allSatisfy { $0.repositoryFullName.caseInsensitiveCompare(first) == .orderedSame } ? first : nil
    }

    private func clampLength(_ item: NSStatusItem, button: NSStatusBarButton) {
        let fitted = button.fittingSize.width
        let desired = fitted.isFinite && fitted > 0 ? ceil(fitted + 6) : Self.maxItemLength
        item.length = min(desired, Self.maxItemLength)
    }

    private func setButtonTitle(_ title: String?, for button: NSStatusBarButton) {
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

    private func audit(_ context: String) {
        #if DEBUG
            let identifier = self.statusItem.map { String(ObjectIdentifier($0).hashValue) } ?? "nil"
            self.log("reference status item audit \(context) item=\(identifier)")
        #endif
    }

    private static func truncatedTail(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters, maxCharacters > 3 else { return value }

        return "\(value.prefix(maxCharacters - 3))..."
    }

    private static func truncatedMiddle(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters, maxCharacters > 5 else { return value }

        let available = maxCharacters - 3
        let headCount = available / 2
        return "\(value.prefix(headCount))...\(value.suffix(available - headCount))"
    }
}
