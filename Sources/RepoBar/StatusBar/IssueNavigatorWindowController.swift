import AppKit
import RepoBarCore
import SwiftUI

@MainActor
final class IssueNavigatorWindowController: NSObject, NSWindowDelegate {
    private enum Metrics {
        static let baseContentSize = NSSize(width: 1600, height: 840)
        static let defaultContentScale = CGFloat(2).squareRoot()
        static let defaultContentSize = NSSize(
            width: Self.baseContentSize.width * Self.defaultContentScale,
            height: Self.baseContentSize.height * Self.defaultContentScale
        )
        static let minimumContentSize = NSSize(width: 1080, height: 620)
    }

    private let appState: AppState
    private var window: NSWindow?
    private var previousActivationPolicy: NSApplication.ActivationPolicy?
    private var closeCleanupTask: Task<Void, Never>?
    private var presentationID = UUID()
    private let browserStore = IssueNavigatorBrowserStore()

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func show(matches: [GitHubReferenceMatch] = []) {
        self.closeCleanupTask?.cancel()
        self.closeCleanupTask = nil
        self.presentationID = UUID()
        self.showDockIcon()

        if self.window == nil {
            let rootView = self.makeIssueNavigatorView(matches: matches)
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.title = "Issue Navigator"
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.toolbar = IssueNavigatorToolbar()
            window.setContentSize(Self.clampedContentSize(Metrics.defaultContentSize, for: window))
            window.contentMinSize = Self.clampedContentSize(Metrics.minimumContentSize, for: window)
            window.center()
            window.delegate = self
            self.window = window
        } else if matches.isEmpty == false {
            self.window?.contentViewController = NSHostingController(
                rootView: self.makeIssueNavigatorView(matches: matches)
            )
        }

        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func preloadFirstPreview(for matches: [GitHubReferenceMatch]) {
        let orderedMatches = matches.issueNavigatorOrderPreservingDeduped()
        guard orderedMatches.count > 1, let firstURL = orderedMatches.first?.url else { return }

        self.browserStore.preload(firstURL)
    }

    private func makeIssueNavigatorView(matches: [GitHubReferenceMatch]) -> IssueNavigatorView {
        IssueNavigatorView(
            appState: self.appState,
            initialMatches: matches,
            browserStore: self.browserStore
        )
    }

    private static func clampedContentSize(_ contentSize: NSSize, for window: NSWindow) -> NSSize {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return contentSize
        }

        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let chromeWidth = max(0, frameSize.width - contentSize.width)
        let chromeHeight = max(0, frameSize.height - contentSize.height)
        let maxContentWidth = max(1, visibleFrame.width - chromeWidth)
        let maxContentHeight = max(1, visibleFrame.height - chromeHeight)

        return NSSize(
            width: min(contentSize.width, maxContentWidth),
            height: min(contentSize.height, maxContentHeight)
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }

        let closingPresentationID = self.presentationID

        self.closeCleanupTask?.cancel()
        self.closeCleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            guard self.window === closingWindow else { return }
            guard self.presentationID == closingPresentationID else { return }
            guard !closingWindow.isVisible else { return }

            closingWindow.contentViewController = nil
            closingWindow.orderOut(nil)
            self.window = nil
            self.hideDockIcon()
            self.closeCleanupTask = nil
        }
    }

    private func showDockIcon() {
        if self.previousActivationPolicy == nil {
            self.previousActivationPolicy = NSApp.activationPolicy()
        }
        guard NSApp.activationPolicy() != .regular else { return }

        NSApp.setActivationPolicy(.regular)
    }

    private func hideDockIcon() {
        guard let previousActivationPolicy else { return }

        self.previousActivationPolicy = nil
        guard NSApp.activationPolicy() != previousActivationPolicy else { return }

        NSApp.setActivationPolicy(previousActivationPolicy)
    }
}

private final class IssueNavigatorToolbar: NSToolbar, NSToolbarDelegate {
    private enum ItemID {
        static let paste = NSToolbarItem.Identifier("IssueNavigatorPaste")
        static let refresh = NSToolbarItem.Identifier("IssueNavigatorRefresh")
        static let copy = NSToolbarItem.Identifier("IssueNavigatorCopy")
        static let open = NSToolbarItem.Identifier("IssueNavigatorOpen")
    }

    init() {
        super.init(identifier: "IssueNavigatorToolbar")
        self.displayMode = .iconOnly
        self.allowsUserCustomization = false
        self.delegate = self
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ItemID.paste, ItemID.refresh, ItemID.copy, ItemID.open]
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ItemID.paste, ItemID.refresh, ItemID.copy, ItemID.open]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ItemID.paste:
            self.buttonItem(
                itemIdentifier,
                label: "Use Clipboard",
                symbolName: "doc.on.clipboard",
                tooltip: "Search the current clipboard reference",
                action: #selector(self.useClipboard)
            )
        case ItemID.refresh:
            self.buttonItem(
                itemIdentifier,
                label: "Refresh",
                symbolName: "arrow.clockwise",
                tooltip: "Refresh results",
                action: #selector(self.refresh)
            )
        case ItemID.copy:
            self.buttonItem(
                itemIdentifier,
                label: "Copy",
                symbolName: "doc.on.doc",
                tooltip: "Copy selected result URL",
                action: #selector(self.copySelected)
            )
        case ItemID.open:
            self.buttonItem(
                itemIdentifier,
                label: "Open",
                symbolName: "safari",
                tooltip: "Open selected result in browser",
                action: #selector(self.open)
            )
        default:
            nil
        }
    }

    private func buttonItem(
        _ itemIdentifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        tooltip: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = tooltip
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
    }

    @objc private func useClipboard() {
        NotificationCenter.default.post(name: .issueNavigatorUseClipboard, object: nil)
    }

    @objc private func refresh() {
        NotificationCenter.default.post(name: .issueNavigatorRefresh, object: nil)
    }

    @objc private func copySelected() {
        NotificationCenter.default.post(name: .issueNavigatorCopy, object: nil)
    }

    @objc private func open() {
        NotificationCenter.default.post(name: .issueNavigatorOpen, object: nil)
    }
}
