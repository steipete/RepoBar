import RepoBarCore

extension AppState {
    func processGitHubPullRequestNotifications() async {
        await self.gitHubPullRequestNotificationRunner.process(
            settings: self.session.settings.gitHubPullRequestNotifications,
            pinnedRepositories: self.session.settings.repoList.pinnedRepositories,
            github: self.github,
            concurrencyLimit: self.hydrateConcurrencyLimit
        )
    }

    func resetGitHubPullRequestNotificationSnapshots() {
        self.gitHubPullRequestNotificationRunner.resetSnapshots()
    }
}
