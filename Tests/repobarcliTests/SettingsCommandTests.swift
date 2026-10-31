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
        settings.aiSummaries.model = AISummarySettings.defaultModel

        let lines = settingsSummaryLines(settings: settings)

        #expect(lines.contains("GitHub reference monitor: on"))
        #expect(lines.contains("PR notifications: on"))
        #expect(lines.contains("PR notification events: new pull requests, updates, review requests, comments"))
        #expect(lines.contains("PR notification click: Issue Navigator"))
        #expect(lines.contains("AI summaries: on"))
        #expect(lines.contains("AI summary model: \(AISummarySettings.defaultModel)"))
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

        #expect(try applySetting(.aiSummaryModel, value: "custom-model", settings: &settings) == AISummarySettings.defaultModel)
        #expect(settings.aiSummaries.model == AISummarySettings.defaultModel)
    }

    @Test
    func `settings set supports OpenAI-compatible AI summary endpoints`() throws {
        var settings = UserSettings()

        #expect(SettingsKey(argument: "ai-provider") == .aiSummaryProvider)
        #expect(try applySetting(.aiSummaryProvider, value: "OpenAI-Compatible", settings: &settings) == "openai-compatible")
        #expect(try applySetting(.aiSummaryBaseURL, value: "https://gateway.example/v1/", settings: &settings) == "https://gateway.example/v1")
        #expect(try applySetting(.aiSummaryCompatibleModel, value: " deepseek-flash ", settings: &settings) == "deepseek-flash")

        #expect(settings.aiSummaries.provider == .openAICompatible)
        #expect(settings.aiSummaries.compatibleBaseURL == "https://gateway.example/v1")
        #expect(settings.aiSummaries.compatibleModel == "deepseek-flash")
        let lines = settingsSummaryLines(settings: settings)
        #expect(lines.contains("AI summary provider: openai-compatible"))
        #expect(lines.contains("AI summary base URL: https://gateway.example/v1"))
        #expect(lines.contains("AI summary compatible model: deepseek-flash"))
    }

    @Test
    func `settings set rejects invalid AI summary endpoint values`() {
        var settings = UserSettings()

        #expect(throws: ValidationError.self) {
            try applySetting(.aiSummaryProvider, value: "anthropic", settings: &settings)
        }
        #expect(throws: ValidationError.self) {
            try applySetting(.aiSummaryBaseURL, value: "http://gateway.example/v1", settings: &settings)
        }
        #expect(throws: ValidationError.self) {
            try applySetting(.aiSummaryCompatibleModel, value: "  ", settings: &settings)
        }
        #expect(settings.aiSummaries == AISummarySettings())
    }

    @Test
    func `settings set supports color scheme and aliases`() throws {
        var settings = UserSettings()

        #expect(SettingsKey(argument: "color-scheme") == .colorScheme)
        #expect(SettingsKey(argument: "appearance") == .colorScheme)
        #expect(SettingsKey(argument: "theme") == .colorScheme)

        #expect(try applySetting(.colorScheme, value: "Dark", settings: &settings) == "dark")
        #expect(settings.appearance.colorScheme == .dark)
        #expect(settingsSummaryLines(settings: settings).contains("Color scheme: dark"))

        #expect(try applySetting(.colorScheme, value: "light", settings: &settings) == "light")
        #expect(settings.appearance.colorScheme == .light)

        #expect(try applySetting(.colorScheme, value: "default", settings: &settings) == "system")
        #expect(settings.appearance.colorScheme == .system)
    }

    @Test
    func `color scheme setting rejects unknown values`() {
        var settings = UserSettings()

        #expect(throws: ValidationError.self) {
            _ = try applySetting(.colorScheme, value: "sepia", settings: &settings)
        }
    }

    @Test
    func `notification click setting rejects unknown values`() {
        var settings = UserSettings()

        #expect(throws: ValidationError.self) {
            _ = try applySetting(.pullRequestNotificationClick, value: "sidebar", settings: &settings)
        }
    }
}
