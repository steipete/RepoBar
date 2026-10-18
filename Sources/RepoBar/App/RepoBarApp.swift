import AppKit
import Kingfisher
import RepoBarCore
import SwiftUI
import UserNotifications

@main
struct RepoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @State private var appState: AppState
    private let menuManager: StatusBarMenuManager

    init() {
        let appState = AppState()
        let menuManager = StatusBarMenuManager(appState: appState)
        self._appState = State(wrappedValue: appState)
        self.menuManager = menuManager
        self.appDelegate.configure(menuManager: menuManager)
    }

    @SceneBuilder
    var body: some Scene {
        WindowGroup("RepoBarLifecycleKeepalive") {
            RepoBarLifecycleKeepaliveView()
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(session: self.appState.session, appState: self.appState)
        }
        .defaultSize(width: SettingsTab.general.preferredWidth, height: SettingsTab.general.preferredHeight)
        // Use contentMinSize (not contentSize) so the window uses the per-tab preferred
        // size from `resizeSettingsWindow` as its initial size and only grows if the user
        // drags it. Without this, an unbounded table (Repositories tab) would expand the
        // window to fill the entire screen.
        .windowResizability(.contentMinSize)
    }
}

private struct RepoBarLifecycleKeepaliveView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onAppear {
                SettingsOpener.shared.configure {
                    self.openSettings()
                }
                if let window = NSApp.windows.first(where: { $0.title == "RepoBarLifecycleKeepalive" }) {
                    window.styleMask = [.borderless]
                    window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
                    window.isExcludedFromWindowsMenu = true
                    window.level = .floating
                    window.isOpaque = false
                    window.alphaValue = 0
                    window.backgroundColor = .clear
                    window.hasShadow = false
                    window.ignoresMouseEvents = true
                    window.canHide = false
                    window.setContentSize(NSSize(width: 1, height: 1))
                    window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
                }
            }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuManager: StatusBarMenuManager?
    private var suppressIssueNavigatorReopenUntil: Date?
    private var isTerminating = false

    func configure(menuManager: StatusBarMenuManager) {
        self.menuManager = menuManager
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        configureImagePipeline()
        self.menuManager?.appState.applyColorScheme()
        self.menuManager?.appState.start()
        UNUserNotificationCenter.current().delegate = RepoBarNotificationResponseHandler.shared
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.notificationBrowserOpenRequested),
            name: .notificationBrowserOpenRequested,
            object: nil
        )
        self.menuManager?.ensureStatusItems()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !self.isTerminating else { return .terminateLater }

        self.isTerminating = true
        self.menuManager?.appState.shutdown()
        Task {
            await self.menuManager?.appState.github.flushRepoDetailCache()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_: Notification) {
        self.menuManager?.appState.shutdown()
        self.menuManager?.tearDownStatusItems()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        if let suppressIssueNavigatorReopenUntil, Date() < suppressIssueNavigatorReopenUntil {
            return true
        }
        self.suppressIssueNavigatorReopenUntil = nil
        self.menuManager?.openIssueNavigator()
        return true
    }

    @objc private func notificationBrowserOpenRequested() {
        self.suppressIssueNavigatorReopenUntil = Date().addingTimeInterval(2)
    }
}

extension AppDelegate {
    /// Prevent multiple instances when LS UI flag is unavailable under SwiftPM.
    private func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }

        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && !$0.isEqual(NSRunningApplication.current)
        }
        return others.isEmpty
    }

    private func configureImagePipeline() {
        let cache = ImageCache(name: "RepoBarAvatars")
        cache.memoryStorage.config.totalCostLimit = 64 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 64 * 1024 * 1024
        KingfisherManager.shared.cache = cache
    }
}
