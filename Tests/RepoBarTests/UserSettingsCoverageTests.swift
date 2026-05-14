import Foundation
import RepoBarCore
import Testing

struct UserSettingsCoverageTests {
    @Test
    func `labels and seconds cover enum switches`() {
        #expect(LocalProjectsRefreshInterval.oneMinute.seconds == 60)
        #expect(LocalProjectsRefreshInterval.fifteenMinutes.seconds == 900)
        #expect(LocalProjectsRefreshInterval.twoMinutes.label == "2 minutes")
        #expect(LocalProjectsSettings().maxDepth == LocalProjectsConstants.defaultMaxDepth)

        #expect(GhosttyOpenMode.newWindow.label == "New Window")
        #expect(GhosttyOpenMode.tab.label == "Tab")

        #expect(RefreshInterval.oneMinute.seconds == 60)
        #expect(RefreshInterval.fifteenMinutes.seconds == 900)

        #expect(HeatmapDisplay.inline.label == "Inline")
        #expect(HeatmapDisplay.submenu.label == "Submenu")

        #expect(CardDensity.comfortable.label == "Comfortable")
        #expect(CardDensity.compact.label == "Compact")

        #expect(AccentTone.system.label == "System accent")
        #expect(AccentTone.githubGreen.label == "GitHub greens")
        #expect(AppearanceSettings().showRateLimitMeterInMenuBar)
        #expect(GitHubReferenceMonitorSettings().enabled == false)
        #expect(ActionsSettings().showActionsInMenu == false)
        #expect(ActionsSettings().planTier == .free)
        #expect(ActionsSettings().ownerFilter.isEmpty)
        #expect(UserSettings().monitoredOwners.isEmpty)
        #expect(GitHubPlanTier.free.includedMinutesPerMonth == 2000)
        #expect(GitHubPlanTier.enterprise.concurrentJobs == 500)
        #expect(GitHubPullRequestNotificationSettings().enabled == false)
        #expect(GitHubPullRequestNotificationSettings().newPullRequests)
        #expect(GitHubPullRequestNotificationSettings().pullRequestUpdates)
        #expect(GitHubPullRequestNotificationSettings().reviewRequests == false)
        #expect(GitHubPullRequestNotificationSettings().comments == false)
        #expect(GitHubPullRequestNotificationSettings().clickAction == .openInBrowser)
        #expect(GitHubPullRequestNotificationClickAction.openInBrowser.label == "Default browser")
        #expect(GitHubPullRequestNotificationClickAction.openIssueNavigator.label == "Issue Navigator")

        #expect(GlobalActivityScope.allActivity.label == "All activity")
        #expect(GlobalActivityScope.myActivity.label == "My activity")

        #expect(GitHubArchiveSettings().preferArchiveWhenRateLimited)
        #expect(GitHubArchiveFormat.discrawlSnapshot.label == "Discrawl snapshot")
    }

    @Test
    func `menu normalization keeps rate limits above filters`() throws {
        var customization = MenuCustomization()
        customization.mainMenuOrder = [
            .loggedOutPrompt,
            .signInAction,
            .contributionHeader,
            .statusBanner,
            .filters,
            .repoList,
            .issueNavigator,
            .preferences,
            .about,
            .restartToUpdate,
            .quit
        ]

        customization.normalize()

        let statusIndex = try #require(customization.mainMenuOrder.firstIndex(of: .statusBanner))
        let rateIndex = try #require(customization.mainMenuOrder.firstIndex(of: .rateLimits))
        let filterIndex = try #require(customization.mainMenuOrder.firstIndex(of: .filters))
        #expect(statusIndex < rateIndex)
        #expect(rateIndex < filterIndex)
    }

    @Test
    func `menu normalization keeps actions after rate limits`() throws {
        var customization = MenuCustomization()
        customization.mainMenuOrder.removeAll { $0 == .actionsLimits }

        customization.normalize()

        let rateIndex = try #require(customization.mainMenuOrder.firstIndex(of: .rateLimits))
        let actionsIndex = try #require(customization.mainMenuOrder.firstIndex(of: .actionsLimits))
        let filterIndex = try #require(customization.mainMenuOrder.firstIndex(of: .filters))
        #expect(rateIndex < actionsIndex)
        #expect(actionsIndex < filterIndex)
    }

    @Test
    func `archive source derives internal fields from repo`() throws {
        let shorthand = try #require(GitHubArchiveStore.source(repository: "openclaw/archive"))
        #expect(shorthand.name == "openclaw/archive")
        #expect(shorthand.remoteURL == "https://github.com/openclaw/archive.git")
        #expect(shorthand.localRepositoryPath == nil)
        #expect(shorthand.importedDatabasePath.contains("/RepoBar/Archives/openclaw-archive-"))
        #expect(shorthand.importedDatabasePath.hasSuffix(".sqlite"))

        let ssh = try #require(GitHubArchiveStore.source(repository: "git@github.com:steipete/RepoBar.git"))
        #expect(ssh.name == "steipete/RepoBar")
        #expect(ssh.remoteURL == "git@github.com:steipete/RepoBar.git")

        let local = try #require(GitHubArchiveStore.source(repository: "/tmp/RepoBarArchive.git/"))
        #expect(local.name == "RepoBarArchive")
        #expect(local.remoteURL == nil)
        #expect(local.localRepositoryPath == "/tmp/RepoBarArchive.git")

        let colliding = try #require(GitHubArchiveStore.source(repository: "/tmp/openclaw-archive"))
        #expect(colliding.name == "openclaw-archive")
        #expect(colliding.importedDatabasePath != shorthand.importedDatabasePath)
    }

    @Test
    func `archive location matching ignores nil optionals`() throws {
        let firstRemote = try #require(GitHubArchiveStore.source(repository: "openclaw/archive"))
        let secondRemote = try #require(GitHubArchiveStore.source(repository: "steipete/RepoBar"))
        let firstLocal = try #require(GitHubArchiveStore.source(repository: "/tmp/archive-one"))
        let secondLocal = try #require(GitHubArchiveStore.source(repository: "/tmp/archive-two"))
        let sameLeafLocal = try #require(GitHubArchiveStore.source(repository: "/Volumes/backup/archive-one"))

        #expect(GitHubArchiveStore.sameArchiveLocation(firstRemote, firstRemote))
        #expect(GitHubArchiveStore.sameArchiveLocation(firstRemote, secondRemote) == false)
        #expect(GitHubArchiveStore.sameArchiveLocation(firstLocal, secondLocal) == false)
        #expect(GitHubArchiveStore.sameArchiveLocation(firstLocal, sameLeafLocal) == false)
    }
}
