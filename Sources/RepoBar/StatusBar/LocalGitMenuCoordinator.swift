import AppKit
import Foundation
import RepoBarCore
import SwiftUI

@MainActor
final class LocalGitMenuCoordinator {
    private unowned let actionHandler: StatusBarMenuManager
    private let appState: AppState
    private let menuBuilder: StatusBarMenuBuilder
    private let menuItemFactory: MenuItemViewFactory
    private let recentMenuService: RecentMenuService
    private var localBranchMenus: [ObjectIdentifier: LocalGitMenuEntry] = [:]
    private var localWorktreeMenus: [ObjectIdentifier: LocalGitMenuEntry] = [:]
    private var webURLBuilder: RepoWebURLBuilder {
        RepoWebURLBuilder(host: self.appState.session.settings.githubHost)
    }

    init(
        appState: AppState,
        menuBuilder: StatusBarMenuBuilder,
        menuItemFactory: MenuItemViewFactory,
        recentMenuService: RecentMenuService,
        actionHandler: StatusBarMenuManager
    ) {
        self.appState = appState
        self.menuBuilder = menuBuilder
        self.menuItemFactory = menuItemFactory
        self.recentMenuService = recentMenuService
        self.actionHandler = actionHandler
    }

    func registerLocalBranchMenu(_ menu: NSMenu, repoPath: URL, fullName: String, localStatus: LocalRepoStatus) {
        self.localBranchMenus[ObjectIdentifier(menu)] = LocalGitMenuEntry(
            menu: menu,
            repoPath: repoPath,
            fullName: fullName,
            localStatus: localStatus,
            includesRemoteBranches: false
        )
    }

    func registerCombinedBranchMenu(_ menu: NSMenu, repoPath: URL, fullName: String, localStatus: LocalRepoStatus) {
        self.localBranchMenus[ObjectIdentifier(menu)] = LocalGitMenuEntry(
            menu: menu,
            repoPath: repoPath,
            fullName: fullName,
            localStatus: localStatus,
            includesRemoteBranches: true
        )
    }

    func registerLocalWorktreeMenu(_ menu: NSMenu, repoPath: URL, fullName: String) {
        self.localWorktreeMenus[ObjectIdentifier(menu)] = LocalGitMenuEntry(
            menu: menu,
            repoPath: repoPath,
            fullName: fullName,
            localStatus: nil,
            includesRemoteBranches: false
        )
    }

    func pruneMenus() {
        self.localBranchMenus = self.localBranchMenus.filter { $0.value.menu != nil }
        self.localWorktreeMenus = self.localWorktreeMenus.filter { $0.value.menu != nil }
    }

    func handleMenuWillOpen(_ menu: NSMenu) -> Bool {
        if let entry = self.localBranchMenus[ObjectIdentifier(menu)] {
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            Task { @MainActor [weak self] in
                guard let self else { return }

                if entry.includesRemoteBranches {
                    await self.refreshCombinedBranchMenu(menu: menu, entry: entry)
                } else {
                    await self.refreshLocalBranchMenu(menu: menu, entry: entry)
                }
            }
            return true
        }
        if let entry = self.localWorktreeMenus[ObjectIdentifier(menu)] {
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            Task { @MainActor [weak self] in
                await self?.refreshLocalWorktreeMenu(menu: menu, entry: entry)
            }
            return true
        }
        return false
    }

    func syncLocalRepo(_ status: LocalRepoStatus) {
        self.runLocalGitTask(
            title: "Sync failed",
            status: status,
            notifyOnSuccess: true,
            action: .sync(status.path)
        )
    }

    func rebaseLocalRepo(_ status: LocalRepoStatus) {
        self.runLocalGitTask(
            title: "Rebase failed",
            status: status,
            notifyOnSuccess: false,
            action: .rebase(status.path)
        )
    }

    func resetLocalRepo(_ status: LocalRepoStatus) {
        let confirmed = self.confirmHardReset(for: status)
        guard confirmed else { return }

        self.runLocalGitTask(
            title: "Reset failed",
            status: status,
            notifyOnSuccess: false,
            action: .reset(status.path)
        )
    }

    func switchLocalBranch(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? LocalBranchAction else { return }

        self.runLocalGitTask(
            title: "Switch branch failed",
            status: nil,
            notifyOnSuccess: false,
            action: .switchBranch(action.repoPath, action.branch)
        )
    }

    func switchLocalWorktree(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? LocalWorktreeAction else { return }

        self.switchLocalWorktree(path: action.path, fullName: action.fullName)
    }

    func createLocalBranch(_ sender: NSMenuItem) {
        guard let repoURL = sender.representedObject as? URL else { return }

        let name = self.promptForText(
            title: "Create branch",
            message: "Enter a new branch name."
        )
        guard let name, name.isEmpty == false else { return }

        self.runLocalGitTask(
            title: "Create branch failed",
            status: nil,
            notifyOnSuccess: false,
            action: .createBranch(repoURL, name)
        )
    }

    func createLocalWorktree(_ sender: NSMenuItem) {
        guard let repoURL = sender.representedObject as? URL else { return }

        let branchName = self.promptForText(
            title: "Create worktree",
            message: "Enter a branch name for the new worktree."
        )
        guard let branchName, branchName.isEmpty == false else { return }

        let folderName = self.appState.session.settings.localProjects.worktreeFolderName
        let defaultPath = repoURL
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(branchName, isDirectory: true)
        let pathText = self.promptForText(
            title: "Worktree folder",
            message: "Enter the folder path for the new worktree.",
            defaultValue: defaultPath.path
        )
        guard let pathText, pathText.isEmpty == false else { return }

        let worktreeURL = URL(fileURLWithPath: pathText, isDirectory: true)
        do {
            let parent = worktreeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            self.presentAlert(title: "Create worktree failed", message: error.userFacingMessage)
            return
        }
        self.runLocalGitTask(
            title: "Create worktree failed",
            status: nil,
            notifyOnSuccess: false,
            action: .createWorktree(repoURL, worktreeURL, branchName)
        )
    }

    private func refreshLocalBranchMenu(menu: NSMenu, entry: LocalGitMenuEntry) async {
        let repoPath = entry.repoPath
        let fullName = entry.fullName
        let result = await self.loadLocalBranchSnapshot(repoPath: repoPath)

        menu.removeAllItems()
        self.addLocalBranchMenuHeader(menu: menu, repoPath: repoPath)
        switch result {
        case let .success(snapshot):
            if snapshot.branches.isEmpty, snapshot.isDetachedHead == false {
                menu.addItem(self.menuBuilder.infoItem("No branches"))
                self.menuBuilder.refreshMenuViewHeights(in: menu)
                menu.update()
                return
            }
            if snapshot.isDetachedHead {
                let model = LocalRefMenuRowViewModel(
                    kind: .branch,
                    title: "Detached HEAD",
                    detail: nil,
                    isCurrent: true,
                    isDetached: true,
                    upstream: nil,
                    aheadCount: nil,
                    behindCount: nil,
                    lastCommitDate: snapshot.detachedCommitDate,
                    lastCommitAuthor: snapshot.detachedCommitAuthor,
                    dirtySummary: entry.localStatus?.dirtyCounts?.summary
                )
                menu.addItem(self.makeLocalBranchMenuItem(model, repoPath: repoPath, fullName: fullName, isCurrent: true))
            }
            for branch in snapshot.branches {
                let dirtySummary = branch.isCurrent ? entry.localStatus?.dirtyCounts?.summary : nil
                let model = LocalRefMenuRowViewModel(
                    kind: .branch,
                    title: branch.name,
                    detail: nil,
                    isCurrent: branch.isCurrent,
                    isDetached: false,
                    upstream: branch.upstream,
                    aheadCount: branch.aheadCount,
                    behindCount: branch.behindCount,
                    lastCommitDate: branch.lastCommitDate,
                    lastCommitAuthor: branch.lastCommitAuthor,
                    dirtySummary: dirtySummary
                )
                menu.addItem(self.makeLocalBranchMenuItem(model, repoPath: repoPath, fullName: fullName, isCurrent: branch.isCurrent))
            }
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        case let .failure(error):
            menu.addItem(self.menuBuilder.infoItem("Failed to load branches"))
            self.presentAlert(title: "Branch list failed", message: error.userFacingMessage)
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        }
    }

    private func refreshCombinedBranchMenu(menu: NSMenu, entry: LocalGitMenuEntry) async {
        let repoPath = entry.repoPath
        let fullName = entry.fullName
        let localResult = await self.loadLocalBranchSnapshot(repoPath: repoPath)

        let now = Date()
        guard case .loggedIn = self.appState.session.account else {
            self.populateCombinedBranchMenu(
                menu: menu,
                entry: entry,
                localResult: localResult,
                remoteState: BranchesRemoteState(
                    branches: nil,
                    message: "Sign in to load branches",
                    emptyTitle: "No branches"
                )
            )
            return
        }
        guard let (owner, name) = self.ownerAndName(from: fullName) else {
            self.populateCombinedBranchMenu(
                menu: menu,
                entry: entry,
                localResult: localResult,
                remoteState: BranchesRemoteState(
                    branches: nil,
                    message: "Invalid repository name",
                    emptyTitle: "No branches"
                )
            )
            return
        }
        guard let descriptor = self.recentMenuService.descriptor(for: .branches) else { return }

        let cacheContext = self.recentMenuService.cacheContext(fullName: fullName)
        let cacheKey = cacheContext.key

        let cachedItems = descriptor.cached(cacheKey, now, self.recentMenuService.cacheTTL)
            ?? descriptor.stale(cacheKey)
        let cachedBranches = self.remoteBranches(from: cachedItems)
        let needsRefresh = descriptor.needsRefresh(cacheKey, now, self.recentMenuService.cacheTTL)
        let remoteMessage = cachedBranches == nil && needsRefresh ? "Loading…" : nil
        self.populateCombinedBranchMenu(
            menu: menu,
            entry: entry,
            localResult: localResult,
            remoteState: BranchesRemoteState(
                branches: cachedBranches,
                message: remoteMessage,
                emptyTitle: descriptor.emptyTitle
            )
        )

        guard needsRefresh else { return }

        do {
            let items = try await descriptor.load(cacheKey, owner, name, self.recentMenuService.listLimit, cacheContext.github)
            let branches = self.remoteBranches(from: items)
            self.populateCombinedBranchMenu(
                menu: menu,
                entry: entry,
                localResult: localResult,
                remoteState: BranchesRemoteState(
                    branches: branches,
                    message: nil,
                    emptyTitle: descriptor.emptyTitle
                )
            )
        } catch is AsyncTimeoutError {
            await DiagnosticsLogger.shared.message("Recent list timed out: branches \(fullName)")
            if cachedBranches == nil {
                self.populateCombinedBranchMenu(
                    menu: menu,
                    entry: entry,
                    localResult: localResult,
                    remoteState: BranchesRemoteState(
                        branches: nil,
                        message: "Timed out",
                        emptyTitle: descriptor.emptyTitle
                    )
                )
            }
        } catch {
            await DiagnosticsLogger.shared.message(
                "Recent list failed: branches \(fullName) error=\(error.localizedDescription)"
            )
            if cachedBranches == nil {
                self.populateCombinedBranchMenu(
                    menu: menu,
                    entry: entry,
                    localResult: localResult,
                    remoteState: BranchesRemoteState(
                        branches: nil,
                        message: "Failed to load",
                        emptyTitle: descriptor.emptyTitle
                    )
                )
            }
        }
    }

    private func populateCombinedBranchMenu(
        menu: NSMenu,
        entry: LocalGitMenuEntry,
        localResult: Result<LocalGitBranchSnapshot, Error>,
        remoteState: BranchesRemoteState
    ) {
        menu.removeAllItems()
        self.addLocalBranchMenuHeader(menu: menu, repoPath: entry.repoPath)
        switch localResult {
        case let .success(snapshot):
            if snapshot.branches.isEmpty, snapshot.isDetachedHead == false {
                menu.addItem(self.menuBuilder.infoItem("No local branches"))
            }
            if snapshot.isDetachedHead {
                let model = LocalRefMenuRowViewModel(
                    kind: .branch,
                    title: "Detached HEAD",
                    detail: nil,
                    isCurrent: true,
                    isDetached: true,
                    upstream: nil,
                    aheadCount: nil,
                    behindCount: nil,
                    lastCommitDate: snapshot.detachedCommitDate,
                    lastCommitAuthor: snapshot.detachedCommitAuthor,
                    dirtySummary: entry.localStatus?.dirtyCounts?.summary
                )
                menu.addItem(self.makeLocalBranchMenuItem(model, repoPath: entry.repoPath, fullName: entry.fullName, isCurrent: true))
            }
            for branch in snapshot.branches {
                let dirtySummary = branch.isCurrent ? entry.localStatus?.dirtyCounts?.summary : nil
                let model = LocalRefMenuRowViewModel(
                    kind: .branch,
                    title: branch.name,
                    detail: nil,
                    isCurrent: branch.isCurrent,
                    isDetached: false,
                    upstream: branch.upstream,
                    aheadCount: branch.aheadCount,
                    behindCount: branch.behindCount,
                    lastCommitDate: branch.lastCommitDate,
                    lastCommitAuthor: branch.lastCommitAuthor,
                    dirtySummary: dirtySummary
                )
                menu.addItem(self.makeLocalBranchMenuItem(model, repoPath: entry.repoPath, fullName: entry.fullName, isCurrent: branch.isCurrent))
            }
        case let .failure(error):
            menu.addItem(self.menuBuilder.infoItem("Failed to load local branches"))
            self.presentAlert(title: "Branch list failed", message: error.userFacingMessage)
        }

        menu.addItem(.separator())
        menu.addItem(self.menuBuilder.actionItem(
            title: "Open Branches",
            action: #selector(StatusBarMenuManager.openBranches(_:)),
            represented: entry.fullName,
            systemImage: "point.topleft.down.curvedto.point.bottomright.up"
        ))
        menu.addItem(.separator())

        if let remoteMessage = remoteState.message {
            menu.addItem(self.menuBuilder.infoItem(remoteMessage))
        } else if let remoteBranches = remoteState.branches {
            if remoteBranches.isEmpty {
                menu.addItem(self.menuBuilder.infoItem(remoteState.emptyTitle))
            } else {
                for branch in remoteBranches {
                    self.addRemoteBranchMenuItem(branch, repoFullName: entry.fullName, to: menu)
                }
            }
        } else {
            menu.addItem(self.menuBuilder.infoItem(remoteState.emptyTitle))
        }

        self.menuBuilder.refreshMenuViewHeights(in: menu)
        menu.update()
    }

    private func refreshLocalWorktreeMenu(menu: NSMenu, entry: LocalGitMenuEntry) async {
        let repoPath = entry.repoPath
        let fullName = entry.fullName
        let result = await Task.detached { () -> Result<[LocalGitWorktree], Error> in
            Result { try LocalGitService().worktrees(at: repoPath) }
        }.value

        menu.removeAllItems()
        self.addLocalWorktreeMenuHeader(menu: menu, repoPath: repoPath)
        switch result {
        case let .success(worktrees):
            if worktrees.isEmpty {
                menu.addItem(self.menuBuilder.infoItem("No worktrees"))
                self.menuBuilder.refreshMenuViewHeights(in: menu)
                menu.update()
                return
            }
            for worktree in worktrees {
                let branch = worktree.branch ?? "Detached"
                let displayPath = PathFormatter.displayString(worktree.path.path)
                let model = LocalRefMenuRowViewModel(
                    kind: .worktree,
                    title: displayPath,
                    detail: branch,
                    isCurrent: worktree.isCurrent,
                    isDetached: false,
                    upstream: worktree.upstream,
                    aheadCount: worktree.aheadCount,
                    behindCount: worktree.behindCount,
                    lastCommitDate: worktree.lastCommitDate,
                    lastCommitAuthor: worktree.lastCommitAuthor,
                    dirtySummary: worktree.dirtyCounts?.summary
                )
                menu.addItem(self.makeLocalWorktreeMenuItem(model, path: worktree.path, fullName: fullName))
            }
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        case let .failure(error):
            menu.addItem(self.menuBuilder.infoItem("Failed to load worktrees"))
            self.presentAlert(title: "Worktree list failed", message: error.userFacingMessage)
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        }
    }

    private func makeLocalWorktreeMenuItem(
        _ model: LocalRefMenuRowViewModel,
        path: URL,
        fullName: String
    ) -> NSMenuItem {
        let row = LocalWorktreeMenuRowView(model: model)
        let item = self.menuItemFactory.makeItem(for: row, enabled: true, highlightable: true)
        item.target = self.actionHandler
        item.action = #selector(StatusBarMenuManager.switchLocalWorktree(_:))
        item.representedObject = LocalWorktreeAction(path: path, fullName: fullName)
        return item
    }

    private func makeLocalBranchMenuItem(
        _ model: LocalRefMenuRowViewModel,
        repoPath: URL,
        fullName: String,
        isCurrent: Bool
    ) -> NSMenuItem {
        let row = LocalBranchMenuRowView(model: model)
        let item = self.menuItemFactory.makeItem(for: row, enabled: true, highlightable: true)
        item.target = self.actionHandler
        item.action = #selector(StatusBarMenuManager.switchLocalBranch(_:))
        item.representedObject = LocalBranchAction(
            repoPath: repoPath,
            branch: model.title,
            fullName: fullName
        )
        item.state = isCurrent ? .on : .off
        return item
    }

    private func addRemoteBranchMenuItem(_ summary: RepoBranchSummary, repoFullName: String, to menu: NSMenu) {
        let view = BranchMenuItemView(summary: summary) { [weak self] in
            guard let self, let url = self.webURLBuilder.branchURL(fullName: repoFullName, branch: summary.name) else { return }

            self.actionHandler.open(url: url)
        }
        let item = self.menuItemFactory.makeItem(for: view, enabled: true, highlightable: true)
        item.toolTip = "\(summary.name)\n\(summary.commitSHA)"
        menu.addItem(item)
    }

    private func addLocalBranchMenuHeader(menu: NSMenu, repoPath: URL) {
        menu.addItem(self.menuBuilder.actionItem(
            title: "Create Branch…",
            action: #selector(StatusBarMenuManager.createLocalBranch(_:)),
            represented: repoPath,
            systemImage: "plus"
        ))
        menu.addItem(.separator())
    }

    private func addLocalWorktreeMenuHeader(menu: NSMenu, repoPath: URL) {
        menu.addItem(self.menuBuilder.actionItem(
            title: "Create Worktree…",
            action: #selector(StatusBarMenuManager.createLocalWorktree(_:)),
            represented: repoPath,
            systemImage: "plus"
        ))
        menu.addItem(.separator())
    }

    private func loadLocalBranchSnapshot(repoPath: URL) async -> Result<LocalGitBranchSnapshot, Error> {
        await Task.detached { () -> Result<LocalGitBranchSnapshot, Error> in
            Result { try LocalGitService().branchDetails(at: repoPath) }
        }.value
    }

    private func ownerAndName(from fullName: String) -> (String, String)? {
        let parts = fullName.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        return (String(parts[0]), String(parts[1]))
    }

    private func remoteBranches(from items: RecentMenuItems?) -> [RepoBranchSummary]? {
        guard case let .branches(branches) = items else { return nil }

        return branches
    }

    private func runLocalGitTask(
        title: String,
        status: LocalRepoStatus?,
        notifyOnSuccess: Bool,
        action: LocalGitAction
    ) {
        let rootBookmark = self.appState.session.settings.localProjects.rootBookmarkData
        Task.detached { [weak self] in
            guard let self else { return }

            let result = Result {
                var capturedError: Error?
                SecurityScopedBookmark.withAccess(to: action.repoURL, rootBookmarkData: rootBookmark) {
                    do {
                        try Self.performLocalGitAction(action)
                    } catch {
                        capturedError = error
                    }
                }
                if let capturedError {
                    throw capturedError
                }
            }
            await MainActor.run {
                switch result {
                case .success:
                    self.appState.refreshLocalProjects()
                    if notifyOnSuccess, let status {
                        Task { await LocalSyncNotifier.shared.notifySync(for: status) }
                    }
                case let .failure(error):
                    self.presentAlert(title: title, message: error.userFacingMessage)
                }
            }
        }
    }

    private nonisolated static func performLocalGitAction(_ action: LocalGitAction) throws {
        let service = LocalGitService()
        switch action {
        case let .sync(url):
            _ = try service.smartSync(at: url)
        case let .rebase(url):
            try service.rebaseOntoUpstream(at: url)
        case let .reset(url):
            try service.hardResetToUpstream(at: url)
        case let .switchBranch(url, branch):
            try service.switchBranch(at: url, branch: branch)
        case let .createBranch(url, name):
            try service.createBranch(at: url, name: name)
        case let .createWorktree(url, path, branch):
            try service.createWorktree(at: url, path: path, branch: branch)
        }
    }

    private func promptForText(title: String, message: String, defaultValue: String? = nil) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        field.stringValue = defaultValue ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func switchLocalWorktree(path: URL, fullName: String) {
        let pathString = path.path
        guard FileManager.default.fileExists(atPath: pathString) else {
            self.presentAlert(title: "Worktree missing", message: "Could not find \(pathString).")
            return
        }

        self.appState.session.settings.localProjects.preferredLocalPathsByFullName[fullName] = pathString
        self.appState.persistSettings()
        self.appState.refreshLocalProjects()
    }

    private func confirmHardReset(for status: LocalRepoStatus) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Hard reset \(status.displayName)?"
        alert.informativeText = "This will discard uncommitted changes and reset to \(status.upstreamBranch ?? "upstream")."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private enum LocalGitAction {
    case sync(URL)
    case rebase(URL)
    case reset(URL)
    case switchBranch(URL, String)
    case createBranch(URL, String)
    case createWorktree(URL, URL, String)

    var repoURL: URL {
        switch self {
        case let .sync(url),
             let .rebase(url),
             let .reset(url),
             let .switchBranch(url, _),
             let .createBranch(url, _),
             let .createWorktree(url, _, _):
            url
        }
    }
}

private struct LocalGitMenuEntry {
    weak var menu: NSMenu?
    let repoPath: URL
    let fullName: String
    let localStatus: LocalRepoStatus?
    let includesRemoteBranches: Bool
}

private struct BranchesRemoteState {
    let branches: [RepoBranchSummary]?
    let message: String?
    let emptyTitle: String
}

private struct LocalBranchAction {
    let repoPath: URL
    let branch: String
    let fullName: String
}

private struct LocalWorktreeAction {
    let path: URL
    let fullName: String
}

#if DEBUG
    extension LocalGitMenuCoordinator {
        func makeLocalWorktreeMenuItemForTesting(
            _ model: LocalRefMenuRowViewModel,
            path: URL,
            fullName: String
        ) -> NSMenuItem {
            self.makeLocalWorktreeMenuItem(model, path: path, fullName: fullName)
        }

        func isWorktreeMenuItemForTesting(_ item: NSMenuItem) -> Bool {
            item.representedObject is LocalWorktreeAction
        }
    }
#endif
