import Foundation
import RepoBarCore
import Testing

struct SettingsStoreCoverageTests {
    @Test
    func `load returns defaults when missing`() throws {
        let suiteName = "SettingsStoreCoverageTests.missing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        let settings = store.load()
        #expect(settings == UserSettings())
    }

    @Test
    func `save and load round trips`() throws {
        let suiteName = "SettingsStoreCoverageTests.roundtrip.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        var settings = UserSettings()
        settings.repoList.displayLimit = 9
        settings.gitHubReferenceMonitor.enabled = true
        settings.gitHubPullRequestNotifications.enabled = true
        settings.gitHubPullRequestNotifications.reviewRequests = true
        settings.gitHubPullRequestNotifications.clickAction = .openIssueNavigator
        settings.aiSummaries.enabled = true
        settings.aiSummaries.model = "chat-latest"
        settings.githubHost = try #require(URL(string: "https://github.example.com"))
        settings.githubArchives.sources = [
            GitHubArchiveSource(
                name: "openclaw",
                localRepositoryPath: "~/Backups/openclaw",
                remoteURL: "https://github.com/example/openclaw-backup.git",
                importedDatabasePath: "/tmp/openclaw.sqlite"
            )
        ]
        store.save(settings)

        let loaded = store.load()
        #expect(loaded.repoList.displayLimit == 9)
        #expect(loaded.gitHubReferenceMonitor.enabled)
        #expect(loaded.gitHubPullRequestNotifications.enabled)
        #expect(loaded.gitHubPullRequestNotifications.reviewRequests)
        #expect(loaded.gitHubPullRequestNotifications.clickAction == .openIssueNavigator)
        #expect(loaded.aiSummaries.enabled)
        #expect(loaded.aiSummaries.model == "chat-latest")
        #expect(loaded.githubHost == URL(string: "https://github.example.com")!)
        #expect(loaded.githubArchives.sources.first?.name == "openclaw")
        #expect(loaded.githubArchives.sources.first?.format == .discrawlSnapshot)
    }

    @Test
    func `load migrates older envelope and persists current version`() throws {
        let suiteName = "SettingsStoreCoverageTests.migrate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        struct TestEnvelope: Codable {
            let version: Int
            let settings: UserSettings
        }

        var original = UserSettings()
        original.repoList.showForks = true
        let data = try JSONEncoder().encode(TestEnvelope(version: 1, settings: original))
        defaults.set(data, forKey: "com.steipete.repobar.settings")

        let store = SettingsStore(defaults: defaults)
        let loaded = store.load()
        #expect(loaded.repoList.showForks == true)

        let stored = defaults.data(forKey: "com.steipete.repobar.settings")
        let decoded = try JSONDecoder().decode(TestEnvelope.self, from: #require(stored))
        #expect(decoded.version == 3)
    }

    @Test
    func `load invalid data falls back to defaults`() throws {
        let suiteName = "SettingsStoreCoverageTests.invalid.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: "com.steipete.repobar.settings")
        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == UserSettings())
    }

    @Test
    func `load older settings missing archive config`() throws {
        var original = UserSettings()
        original.repoList.displayLimit = 4
        let data = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "githubArchives")
        object.removeValue(forKey: "gitHubReferenceMonitor")
        object.removeValue(forKey: "gitHubPullRequestNotifications")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)
        #expect(loaded.repoList.displayLimit == 4)
        #expect(loaded.gitHubReferenceMonitor == GitHubReferenceMonitorSettings())
        #expect(loaded.actions == ActionsSettings())
        #expect(loaded.gitHubPullRequestNotifications == GitHubPullRequestNotificationSettings())
        #expect(loaded.githubArchives == GitHubArchiveSettings())
    }

    @Test
    func `load older action settings defaults to hidden`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "actions")
        var customization = try #require(object["menuCustomization"] as? [String: Any])
        customization["hiddenMainMenuItems"] = []
        object["menuCustomization"] = customization
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.actions.showActionsInMenu == false)
        #expect(loaded.menuCustomization.hiddenMainMenuItems.contains(.actionsLimits))
    }

    @Test
    func `load legacy monitored action org as monitored owners`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "monitoredOwners")
        object["actions"] = [
            "showActionsInMenu": true,
            "planTier": "Free",
            "monitoredOrg": "OpenClaw"
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.actions.showActionsInMenu)
        #expect(loaded.monitoredOwners == ["openclaw"])
        #expect(!loaded.menuCustomization.hiddenMainMenuItems.contains(.actionsLimits))
    }

    @Test
    func `load explicit empty monitored owners does not revive legacy action owner filter`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["monitoredOwners"] = []
        object["actions"] = [
            "showActionsInMenu": true,
            "planTier": "Free",
            "monitoredOrg": "OpenClaw"
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.monitoredOwners.isEmpty)
        #expect(loaded.actions.ownerFilter == ["openclaw"])
        #expect(!loaded.menuCustomization.hiddenMainMenuItems.contains(.actionsLimits))
    }

    @Test
    func `encode syncs legacy action owner filter from monitored owners`() throws {
        var settings = UserSettings()
        settings.monitoredOwners = []
        settings.actions.ownerFilter = ["openclaw"]
        settings.actions.monitoredOrg = "OpenClaw"

        let data = try JSONEncoder().encode(settings)
        let loaded = try JSONDecoder().decode(UserSettings.self, from: data)

        #expect(loaded.monitoredOwners.isEmpty)
        #expect(loaded.actions.ownerFilter.isEmpty)
        #expect(loaded.actions.monitoredOrg == nil)
    }

    @Test
    func `load older issue number monitor setting as github reference monitor`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "gitHubReferenceMonitor")
        object["issueNumberMonitor"] = ["enabled": true]
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.gitHubReferenceMonitor.enabled)
    }

    @Test
    func `load older pull request notification settings defaults click action`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var notifications = try #require(object["gitHubPullRequestNotifications"] as? [String: Any])
        notifications["enabled"] = true
        notifications["reviewRequests"] = true
        notifications.removeValue(forKey: "clickAction")
        object["gitHubPullRequestNotifications"] = notifications
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.gitHubPullRequestNotifications.enabled)
        #expect(loaded.gitHubPullRequestNotifications.reviewRequests)
        #expect(loaded.gitHubPullRequestNotifications.clickAction == .openInBrowser)
    }

    @Test
    func `load older appearance settings enables rate-limit meter`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var appearance = try #require(object["appearance"] as? [String: Any])
        appearance.removeValue(forKey: "showRateLimitMeterInMenuBar")
        object["appearance"] = appearance
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(UserSettings.self, from: legacyData)

        #expect(loaded.appearance.showRateLimitMeterInMenuBar)
    }
}
