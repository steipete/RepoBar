import AppKit
import Logging
import RepoBarCore

enum TerminalApp: String, CaseIterable {
    case terminal = "Terminal"
    case iTerm2
    case ghostty = "Ghostty"
    case warp = "Warp"
    case alacritty = "Alacritty"
    case hyper = "Hyper"
    case wezterm = "WezTerm"
    case kitty = "Kitty"

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm2: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .warp: "dev.warp.Warp-Stable"
        case .alacritty: "org.alacritty"
        case .hyper: "co.zeit.hyper"
        case .wezterm: "com.github.wez.wezterm"
        case .kitty: "net.kovidgoyal.kitty"
        }
    }

    var displayName: String {
        self.rawValue
    }

    private static let logger = RepoBarLogging.logger("terminal")

    var isInstalled: Bool {
        if self == .terminal {
            return true
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: self.bundleIdentifier) != nil
    }

    var appIcon: NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: self.bundleIdentifier) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    static var installed: [TerminalApp] {
        allCases.filter(\.isInstalled)
    }

    static var defaultPreferred: TerminalApp {
        if let ghostty = installed.first(where: { $0 == .ghostty }) {
            return ghostty
        }
        return .terminal
    }

    static func resolve(_ rawValue: String?) -> TerminalApp {
        guard let rawValue, let match = TerminalApp(rawValue: rawValue), match.isInstalled else {
            return TerminalApp.defaultPreferred
        }

        return match
    }

    func open(at url: URL, rootBookmarkData: Data?, ghosttyOpenMode: GhosttyOpenMode = .tab) {
        Self.logger.info("Open terminal: \(self.displayName) mode=\(ghosttyOpenMode.rawValue) path=\(url.path)")
        if self == .ghostty, ghosttyOpenMode == .newWindow {
            if self.openGhosttyNewWindow(at: url, rootBookmarkData: rootBookmarkData) {
                return
            }
        }
        if self == .ghostty, ghosttyOpenMode == .newWindow {
            Self.logger.warning("Ghostty new-window script failed; falling back to standard open.")
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: self.bundleIdentifier) else {
            SecurityScopedBookmark.withAccess(to: url, rootBookmarkData: rootBookmarkData) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        SecurityScopedBookmark.withAccess(to: url, rootBookmarkData: rootBookmarkData) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
    }

    private func openGhosttyNewWindow(at url: URL, rootBookmarkData: Data?) -> Bool {
        var didOpen = false
        SecurityScopedBookmark.withAccess(to: url, rootBookmarkData: rootBookmarkData) {
            let filePath = (url as NSURL).filePathURL?.path ?? url.path
            let script = Self.ghosttyNewWindowScript(for: filePath)
            Self.logger.debug("Running Ghostty AppleScript for new window.")
            didOpen = Self.runAppleScript(script)
            if didOpen {
                Self.logger.debug("Ghostty AppleScript succeeded.")
            }
        }
        return didOpen
    }

    private static func ghosttyNewWindowScript(for path: String) -> String {
        let escapedPath = Self.escapeAppleScriptString(path)
        return """
        on run
            set targetPath to "\(escapedPath)"
            tell application "Ghostty" to activate
            tell application "System Events"
                repeat until exists process "Ghostty"
                    delay 0.05
                end repeat
                tell process "Ghostty"
                    set frontmost to true
                    click menu item "New Window" of menu "File" of menu bar 1
                end tell
            end tell
            delay 0.2
            tell application "System Events"
                set cmd to "cd " & quoted form of targetPath
                keystroke cmd
                key code 36
            end tell
        end run
        """
    }

    private static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            Self.logger.error("Failed to run osascript: \(error.localizedDescription)")
            return false
        }
        process.waitUntilExit()
        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            if stderr.isEmpty == false {
                Self.logger.error("osascript failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                Self.logger.error("osascript failed with status \(process.terminationStatus).")
            }
            if stdout.isEmpty == false {
                Self.logger.debug("osascript stdout: \(stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return false
        }
        if stderr.isEmpty == false {
            Self.logger.debug("osascript stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return true
    }
}
