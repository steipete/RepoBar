import Commander
@testable import repobarcli
import RepoBarCore
import Testing

struct SettingsCommandTests {
    @Test
    func `settings summary includes reference and notification settings`() {
        var settings = UserSettings()
        settings.gitHubReferenceMonitor.enabled = true
        settings.gitHubPullRequestNotifications.enabled = true
        settings.gitHubPullRequestNotifications.reviewRequests = true
        settings.gitHubPullRequestNotifications.comments = true
        settings.gitHubPullRequestNotifications.clickAction = .openIssueNavigator
        settings.aiSummaries.enabled = true
        settings.aiSummaries.model = "chat-latest"

        let lines = settingsSummaryLines(settings: settings)

        #expect(lines.contains("GitHub reference monitor: on"))
        #expect(lines.contains("PR notifications: on"))
        #expect(lines.contains("PR notification events: new pull requests, updates, review requests, comments"))
        #expect(lines.contains("PR notification click: Issue Navigator"))
        #expect(lines.contains("AI summaries: on"))
        #expect(lines.contains("AI summary model: chat-latest"))
    }

    @Test
    func `settings set supports reference monitor and notification settings`() throws {
        var settings = UserSettings()

        #expect(try applySetting(.gitHubReferenceMonitor, value: "on", settings: &settings) == "on")
        #expect(try applySetting(.pullRequestNotifications, value: "on", settings: &settings) == "on")
        #expect(try applySetting(.pullRequestNotificationNew, value: "off", settings: &settings) == "off")
        #expect(try applySetting(.pullRequestNotificationUpdates, value: "off", settings: &settings) == "off")
        #expect(try applySetting(.pullRequestNotificationReviews, value: "on", settings: &settings) == "on")
        #expect(try applySetting(.pullRequestNotificationComments, value: "on", settings: &settings) == "on")
        #expect(try applySetting(.pullRequestNotificationClick, value: "issue-navigator", settings: &settings) == "Issue Navigator")

        #expect(settings.gitHubReferenceMonitor.enabled)
        #expect(settings.gitHubPullRequestNotifications.enabled)
        #expect(settings.gitHubPullRequestNotifications.newPullRequests == false)
        #expect(settings.gitHubPullRequestNotifications.pullRequestUpdates == false)
        #expect(settings.gitHubPullRequestNotifications.reviewRequests)
        #expect(settings.gitHubPullRequestNotifications.comments)
        #expect(settings.gitHubPullRequestNotifications.clickAction == .openIssueNavigator)
    }

    @Test
    func `settings set supports AI summary settings`() throws {
        var settings = UserSettings()

        #expect(try applySetting(.aiSummaries, value: "on", settings: &settings) == "on")
        #expect(try applySetting(.aiSummaryModel, value: "gpt-5.5", settings: &settings) == "gpt-5.5")

        #expect(settings.aiSummaries.enabled)
        #expect(settings.aiSummaries.model == "gpt-5.5")
    }

    @Test
    func `AI summary model setting normalizes unsupported values`() throws {
        var settings = UserSettings()

        #expect(try applySetting(.aiSummaryModel, value: "custom-model", settings: &settings) == "chat-latest")
        #expect(settings.aiSummaries.model == AISummarySettings.defaultModel)
    }

    @Test
    func `notification click setting rejects unknown values`() {
        var settings = UserSettings()

        #expect(throws: ValidationError.self) {
            _ = try applySetting(.pullRequestNotificationClick, value: "sidebar", settings: &settings)
        }
    }
}
