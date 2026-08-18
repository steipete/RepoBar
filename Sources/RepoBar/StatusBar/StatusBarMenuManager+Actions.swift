import AppKit
import RepoBarCore

extension StatusBarMenuManager {
    @objc func openAPIUsage() {
        self.appState.session.settingsSelectedTab = .accounts
        self.appState.session.settingsAPIUsageExpanded = true
        SettingsOpener.shared.open()
    }

    @objc func logOut() {
        Task { @MainActor in
            await self.appState.logoutCurrentMethod()
            self.appState.session.repositories = []
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func signIn() {
        Task { await self.appState.quickLogin() }
    }

    @objc func openRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender),
              let url = self.webURLBuilder.repoURL(fullName: fullName) else { return }

        self.open(url: url)
    }

    func openRepoFromMenu(fullName: String) {
        guard let url = self.webURLBuilder.repoURL(fullName: fullName) else { return }

        self.open(url: url)
    }

    @objc func openIssues(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "issues")
    }

    @objc func openPulls(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "pulls")
    }

    @objc func openActions(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "actions")
    }

    @objc func openDiscussions(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "discussions")
    }

    @objc func openTags(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "tags")
    }

    @objc func openBranches(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "branches")
    }

    @objc func openCommits(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "commits")
    }

    func cachedRecentCommitDigest(fullName: String) -> Int? {
        self.recentMenuService.cachedCommitDigest(fullName: fullName)
    }

    @objc func openContributors(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "graphs/contributors")
    }

    @objc func openReleases(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "releases")
    }

    @objc func openLatestRelease(_ sender: NSMenuItem) {
        guard let repo = self.repoModel(from: sender),
              let url = repo.source.latestRelease?.url else { return }

        self.open(url: url)
    }

    @objc func openActivity(_ sender: NSMenuItem) {
        guard let repo = self.repoModel(from: sender),
              let url = repo.activityURL else { return }

        self.open(url: url)
    }

    @objc func openURLItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }

        self.open(url: url)
    }

    @objc func openLocalFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }

        self.openLocalFinder(at: url)
    }

    func openLocalFinder(at url: URL) {
        self.open(url: url)
    }

    @objc func openLocalTerminal(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }

        self.openLocalTerminal(at: url)
    }

    func openLocalTerminal(at url: URL) {
        let preferred = self.appState.session.settings.localProjects.preferredTerminal
        let terminal = TerminalApp.resolve(preferred)
        terminal.open(
            at: url,
            rootBookmarkData: self.appState.session.settings.localProjects.rootBookmarkData,
            ghosttyOpenMode: self.appState.session.settings.localProjects.ghosttyOpenMode
        )
    }

    func syncLocalRepo(_ status: LocalRepoStatus) {
        self.localGitMenuCoordinator.syncLocalRepo(status)
    }

    func rebaseLocalRepo(_ status: LocalRepoStatus) {
        self.localGitMenuCoordinator.rebaseLocalRepo(status)
    }

    func resetLocalRepo(_ status: LocalRepoStatus) {
        self.localGitMenuCoordinator.resetLocalRepo(status)
    }

    @objc func switchLocalBranch(_ sender: NSMenuItem) {
        self.localGitMenuCoordinator.switchLocalBranch(sender)
    }

    @objc func switchLocalWorktree(_ sender: NSMenuItem) {
        self.localGitMenuCoordinator.switchLocalWorktree(sender)
    }

    @objc func createLocalBranch(_ sender: NSMenuItem) {
        self.localGitMenuCoordinator.createLocalBranch(sender)
    }

    @objc func createLocalWorktree(_ sender: NSMenuItem) {
        self.localGitMenuCoordinator.createLocalWorktree(sender)
    }

    @objc func checkoutRepoFromMenu(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }

        let settings = self.appState.session.settings.localProjects
        guard let rootPath = settings.rootPath, rootPath.isEmpty == false else {
            let alert = NSAlert()
            alert.messageText = "Set a local projects folder"
            alert.informativeText = "Choose a Local Projects folder in Settings to enable checkout."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                self.openPreferences()
            }
            return
        }
        guard let remoteURL = self.cloneURL(for: fullName) else {
            self.presentAlert(title: "Checkout failed", message: "Invalid repository URL.")
            return
        }

        let repoName = fullName.split(separator: "/").last.map(String.init) ?? fullName
        let destination = URL(fileURLWithPath: PathFormatter.expandTilde(rootPath), isDirectory: true)
            .appendingPathComponent(repoName, isDirectory: true)

        if FileManager.default.fileExists(atPath: destination.path) {
            self.presentAlert(title: "Folder exists", message: "\(destination.path) already exists.")
            return
        }

        self.showCheckoutProgress(fullName: fullName, destination: destination)
        let rootBookmark = settings.rootBookmarkData
        Task.detached { [weak self] in
            guard let self else { return }

            let result = Result {
                var capturedError: Error?
                SecurityScopedBookmark.withAccess(to: destination, rootBookmarkData: rootBookmark) {
                    do {
                        try LocalGitService().cloneRepo(remoteURL: remoteURL, to: destination)
                    } catch {
                        capturedError = error
                    }
                }
                if let capturedError {
                    throw capturedError
                }
            }
            await MainActor.run {
                self.closeCheckoutProgress()
                switch result {
                case .success:
                    self.appState.session.settings.localProjects.preferredLocalPathsByFullName[fullName] = destination.path
                    self.appState.persistSettings()
                    self.appState.refreshLocalProjects()
                    self.openLocalFinder(at: destination)
                case let .failure(error):
                    self.presentAlert(title: "Checkout failed", message: error.userFacingMessage)
                }
            }
        }
    }

    @objc func copyRepoName(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(fullName, forType: .string)
    }

    @objc func copyRepoURL(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender),
              let url = self.webURLBuilder.repoURL(fullName: fullName) else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    @objc func pinRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }

        self.requestMenuReopenAfterClose()
        Task { await self.appState.addPinned(fullName) }
    }

    @objc func unpinRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }

        self.requestMenuReopenAfterClose()
        Task { await self.appState.removePinned(fullName) }
    }

    @objc func hideRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }

        self.requestMenuReopenAfterClose()
        Task { await self.appState.hide(fullName) }
    }

    @objc func moveRepoUp(_ sender: NSMenuItem) {
        self.requestMenuReopenAfterClose()
        self.moveRepo(sender: sender, direction: -1)
    }

    @objc func moveRepoDown(_ sender: NSMenuItem) {
        self.requestMenuReopenAfterClose()
        self.moveRepo(sender: sender, direction: 1)
    }

    private func moveRepo(sender: NSMenuItem, direction: Int) {
        guard let fullName = self.repoFullName(from: sender) else { return }

        Task { await self.appState.movePinned(fullName, direction: direction) }
    }
}
