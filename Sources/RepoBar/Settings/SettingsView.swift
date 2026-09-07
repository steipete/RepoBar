import AppKit
import RepoBarCore
import SwiftUI

struct SettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var contentWidth = SettingsTab.general.preferredWidth
    @State private var contentHeight = SettingsTab.general.preferredHeight

    var body: some View {
        TabView(selection: self.$session.settingsSelectedTab) {
            GeneralSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            DisplaySettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Display", systemImage: "rectangle.3.group") }
                .tag(SettingsTab.display)
            RepoSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Repositories", systemImage: "tray.full") }
                .tag(SettingsTab.repositories)
            AccountSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            NotificationSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
                .tag(SettingsTab.notifications)
            AdvancedSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)
            #if DEBUG
                if self.session.settings.debugPaneEnabled {
                    DebugSettingsView(session: self.session, appState: self.appState)
                        .tabItem { Label("Debug", systemImage: "ant.fill") }
                        .tag(SettingsTab.debug)
                }
            #endif
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .tabViewStyle(.automatic)
        .frame(
            minWidth: SettingsTab.minimumContentSize.width,
            idealWidth: self.contentWidth,
            maxWidth: .infinity,
            minHeight: SettingsTab.minimumContentSize.height,
            idealHeight: self.contentHeight,
            maxHeight: .infinity
        )
        .onAppear {
            self.updateLayout(for: self.session.settingsSelectedTab, animate: false)
        }
        .onChange(of: self.session.settingsSelectedTab) { _, newValue in
            self.updateLayout(for: newValue, animate: true)
        }
        .onChange(of: self.session.settings.debugPaneEnabled) { _, enabled in
            #if DEBUG
                if !enabled, self.session.settingsSelectedTab == .debug {
                    self.session.settingsSelectedTab = .general
                }
            #endif
        }
    }

    private func updateLayout(for tab: SettingsTab, animate: Bool) {
        let desiredContentSize = NSSize(width: tab.preferredWidth, height: tab.preferredHeight)
        let contentSize = Self.clampedSettingsContentSize(
            desired: desiredContentSize
        )
        let previousTopEdge = Self.settingsWindow?.frame.maxY
        self.contentWidth = contentSize.width
        self.contentHeight = contentSize.height

        // Let SwiftUI finish resizing its Settings window before applying AppKit bounds or
        // repositioning it. Mutating the frame during that constraint pass can crash AppKit.
        Task { @MainActor in
            await Task.yield()
            if animate {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard self.session.settingsSelectedTab == tab else { return }

            Self.configureSettingsWindow(contentSize: contentSize, previousTopEdge: previousTopEdge)
        }
    }

    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"

    private static var knownTabTitles: Set<String> {
        var titles = [
            SettingsTab.general.title,
            SettingsTab.display.title,
            SettingsTab.repositories.title,
            SettingsTab.accounts.title,
            SettingsTab.notifications.title,
            SettingsTab.advanced.title,
            SettingsTab.about.title
        ]
        #if DEBUG
            titles.append(SettingsTab.debug.title)
        #endif
        return Set(titles + titles.map { AppLocalizer().string($0) })
    }

    private static var settingsWindow: NSWindow? {
        NSApp.windows.first(where: {
            $0.identifier?.rawValue == self.settingsWindowIdentifier
                || self.knownTabTitles.contains($0.title)
        })
    }

    private static func clampedSettingsContentSize(desired: NSSize) -> NSSize {
        guard let window = self.settingsWindow else { return desired }

        return SettingsWindowSizing.clampedContentSize(
            desired: desired,
            visibleFrame: (window.screen ?? NSScreen.main)?.visibleFrame,
            chrome: self.settingsWindowChrome(for: window)
        )
    }

    private static func configureSettingsWindow(contentSize: NSSize, previousTopEdge: CGFloat?) {
        guard let window = self.settingsWindow else { return }

        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
        let chrome = self.settingsWindowChrome(for: window)

        // Establish resizability bounds once, derived from the actual chrome so the user
        // can drag the window edge to a sensible size but never past the screen.
        if let visibleFrame {
            let maximumContentSize = SettingsWindowSizing.maximumContentSize(
                for: visibleFrame,
                chrome: chrome
            )
            window.contentMinSize = SettingsWindowSizing.minimumContentSize(
                for: SettingsTab.minimumContentSize,
                maximum: maximumContentSize
            )
            window.contentMaxSize = maximumContentSize
        } else {
            window.contentMinSize = SettingsWindowSizing.minimumContentSize(
                for: SettingsTab.minimumContentSize
            )
        }

        var frame = window.frame
        frame.size = NSSize(
            width: contentSize.width + chrome.width,
            height: contentSize.height + chrome.height
        )
        if let visibleFrame {
            frame.origin.x = SettingsWindowSizing.clampedWindowOriginX(
                proposedOriginX: frame.origin.x,
                windowWidth: frame.width,
                visibleFrame: visibleFrame
            )
            frame.origin.y = SettingsWindowSizing.clampedWindowOriginY(
                proposedOriginY: previousTopEdge.map { $0 - frame.height } ?? frame.origin.y,
                windowHeight: frame.height,
                visibleFrame: visibleFrame
            )
        }
        window.setFrame(frame, display: true, animate: false)
    }

    private static func settingsWindowChrome(for window: NSWindow) -> NSSize {
        NSSize(
            width: max(0, window.frame.width - window.contentLayoutRect.width),
            height: max(0, window.frame.height - window.contentLayoutRect.height)
        )
    }
}

/// Pure helpers for sizing the Settings window. Kept AppKit-free at the core so we can unit
/// test the clamping logic without standing up an `NSWindow` in tests.
enum SettingsWindowSizing {
    /// Clamp a desired content size so its enclosing frame (content + chrome) fits inside
    /// `visibleFrame` (i.e. the screen area not covered by the menu bar or Dock). Returns the
    /// desired size unchanged when no visible frame is available.
    static func clampedContentSize(
        desired: NSSize,
        visibleFrame: NSRect?,
        chrome: NSSize = .zero
    ) -> NSSize {
        guard let visibleFrame else { return desired }

        let chromeWidth = max(0, chrome.width)
        let chromeHeight = max(0, chrome.height)
        let maxWidth = max(1, visibleFrame.width - chromeWidth)
        let maxHeight = max(1, visibleFrame.height - chromeHeight)
        return NSSize(
            width: min(desired.width, maxWidth),
            height: min(desired.height, maxHeight)
        )
    }

    /// AppKit's `contentMinSize` is already expressed in content coordinates.
    static func minimumContentSize(for minimum: NSSize, maximum: NSSize? = nil) -> NSSize {
        let normalizedMinimum = NSSize(
            width: max(minimum.width, 1),
            height: max(minimum.height, 1)
        )
        guard let maximum else { return normalizedMinimum }

        return NSSize(
            width: min(normalizedMinimum.width, max(maximum.width, 1)),
            height: min(normalizedMinimum.height, max(maximum.height, 1))
        )
    }

    /// AppKit expects `contentMaxSize` in content coordinates, so remove the window chrome
    /// from the screen's visible frame before applying the resize limit.
    static func maximumContentSize(
        for visibleFrame: NSRect,
        chrome: NSSize
    ) -> NSSize {
        let chromeWidth = max(0, chrome.width)
        let chromeHeight = max(0, chrome.height)
        return NSSize(
            width: max(visibleFrame.width - chromeWidth, 1),
            height: max(visibleFrame.height - chromeHeight, 1)
        )
    }

    static func clampedWindowOriginX(
        proposedOriginX: CGFloat,
        windowWidth: CGFloat,
        visibleFrame: NSRect
    ) -> CGFloat {
        let minimumOriginX = visibleFrame.minX
        let maximumOriginX = max(minimumOriginX, visibleFrame.maxX - max(windowWidth, 0))
        return min(max(proposedOriginX, minimumOriginX), maximumOriginX)
    }

    static func clampedWindowOriginY(
        proposedOriginY: CGFloat,
        windowHeight: CGFloat,
        visibleFrame: NSRect
    ) -> CGFloat {
        let minimumOriginY = visibleFrame.minY
        let maximumOriginY = max(minimumOriginY, visibleFrame.maxY - max(windowHeight, 0))
        return min(max(proposedOriginY, minimumOriginY), maximumOriginY)
    }
}
