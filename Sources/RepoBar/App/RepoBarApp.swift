import AppKit
import Kingfisher
import Logging
import MenuBarExtraAccess
import RepoBarCore
import SwiftUI

@main
struct RepoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @State private var appState = AppState()
    @State private var isMenuPresented = false
    @State private var menuManager: StatusBarMenuManager?
    private let logger = RepoBarLogging.logger("menu-state")

    @SceneBuilder
    var body: some Scene {
        MenuBarExtra {
            EmptyView()
        } label: {
            StatusItemLabelView(session: self.appState.session)
                .task {
                    await self.ensureStatusItemAttached()
                }
        }
        .menuBarExtraAccess(isPresented: self.$isMenuPresented) { item in
            self.logMenuEvent("menuBarExtraAccess statusItem=\(self.objectID(item)) menuManager=\(self.menuManager != nil)")
            if self.menuManager == nil {
                self.menuManager = StatusBarMenuManager(appState: self.appState)
            }
            self.menuManager?.attachMainMenu(to: item)
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: self.isMenuPresented) { _, newValue in
            self.logMenuEvent("isMenuPresented=\(newValue)")
        }

        Settings {
            SettingsView(session: self.appState.session, appState: self.appState)
        }
        .defaultSize(width: 540, height: 420)
        .windowResizability(.contentSize)
    }

    @MainActor
    private func ensureStatusItemAttached() async {
        if self.menuManager == nil {
            self.menuManager = StatusBarMenuManager(appState: self.appState)
        }
        guard let menuManager = self.menuManager, menuManager.isAttached == false else { return }
        for _ in 0 ..< 10 {
            if let statusItem = StatusItemLocator.locate() {
                self.logMenuEvent("statusItem fallback attach")
                menuManager.attachMainMenu(to: statusItem)
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        self.logMenuEvent("statusItem fallback attach failed")
    }

    private func logMenuEvent(_ message: String) {
        self.logger.info("\(message)")
        Task { await DiagnosticsLogger.shared.message(message) }
    }

    private func objectID(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }
        return String(ObjectIdentifier(object).hashValue)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        configureImagePipeline()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
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
