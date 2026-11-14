import AppKit
import Foundation
@testable import RepoBar
@testable import RepoBarCore
import Testing

@MainActor
struct LocalBranchMenuTests {
    @Test
    func `local branch menu item wires switch action and payload`() throws {
        let (appState, cleanup) = try Self.makeIsolatedAppState()
        defer { cleanup() }
        let manager = StatusBarMenuManager(appState: appState)
        let item = manager.makeLocalBranchMenuItemForTesting(
            Self.branchModel(named: "feature"),
            repoPath: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
            fullName: "owner/repo"
        )

        #expect(item.target === manager)
        #expect(item.action == #selector(StatusBarMenuManager.switchLocalBranch(_:)))
        #expect(item.view is MenuItemHostingView)
        #expect(manager.localBranchNameForTesting(item) == "feature")
    }

    @Test
    func `activating a local branch row switches the checkout`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("repobar-local-branch-menu-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try runGit(["init"], in: root)
        try runGit(["switch", "-c", "main"], in: root)
        try runGit(["config", "user.email", "repobar-tests@example.com"], in: root)
        try runGit(["config", "user.name", "RepoBar Tests"], in: root)
        try "hello".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: root)
        try runGit(["commit", "-m", "init"], in: root)
        try runGit(["branch", "feature"], in: root)

        let (appState, cleanup) = try Self.makeIsolatedAppState()
        defer { cleanup() }
        let manager = StatusBarMenuManager(appState: appState)
        let item = manager.makeLocalBranchMenuItemForTesting(
            Self.branchModel(named: "feature"),
            repoPath: root,
            fullName: "owner/repo"
        )
        let menu = NSMenu()
        menu.addItem(item)
        let activation = MenuItemActivation()
        activation.item = item

        activation.perform()

        let deadline = Date().addingTimeInterval(10)
        var head = try Self.currentBranch(in: root)
        while head != "feature", Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            head = try Self.currentBranch(in: root)
        }
        #expect(head == "feature")
    }

    private static func makeIsolatedAppState() throws -> (AppState, () -> Void) {
        let suiteName = "com.steipete.repobar.local-branch-menu-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let appState = AppState(settingsStore: SettingsStore(defaults: defaults))
        return (appState, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private static func branchModel(named name: String) -> LocalRefMenuRowViewModel {
        LocalRefMenuRowViewModel(
            kind: .branch,
            title: name,
            detail: nil,
            isCurrent: false,
            isDetached: false,
            upstream: nil,
            aheadCount: nil,
            behindCount: nil,
            lastCommitDate: nil,
            lastCommitAuthor: nil,
            dirtySummary: nil
        )
    }

    private static func currentBranch(in repo: URL) throws -> String {
        try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
