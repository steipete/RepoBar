import AppKit

@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()
    private var openHandler: (() -> Void)?

    private init() {}

    func configure(open: (() -> Void)?) {
        self.openHandler = open
    }

    func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let openHandler {
            openHandler()
            return
        }
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
