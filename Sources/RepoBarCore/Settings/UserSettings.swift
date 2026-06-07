import Foundation

public struct UserSettings: Equatable, Codable {
    public var appearance = AppearanceSettings()
    public var heatmap = HeatmapSettings()
    public var repoList = RepoListSettings()
    public var localProjects = LocalProjectsSettings()
    public var gitHubReferenceMonitor = GitHubReferenceMonitorSettings()
    public var aiSummaries = AISummarySettings()
    public var gitHubPullRequestNotifications = GitHubPullRequestNotificationSettings()
    public var githubArchives = GitHubArchiveSettings()
    public var menuCustomization = MenuCustomization()
    public var refreshInterval: RefreshInterval = .fiveMinutes
    public var launchAtLogin = false
    public var debugPaneEnabled: Bool = false
    public var diagnosticsEnabled: Bool = false
    public var loggingVerbosity: LogVerbosity = .info
    public var fileLoggingEnabled: Bool = false
    public var githubHost: URL = .init(string: "https://github.com")!
    public var enterpriseHost: URL?
    public var loopbackPort: Int = 53682
    public var authMethod: AuthMethod = .oauth
    public var monitoredOwners: [String] = []
    public var actions = ActionsSettings()
    // Multi-account fields (Phase 2+). Old single-account fields above are kept as
    // compatibility shims and continue to mirror the active account.
    public var accounts: [Account] = []
    public var activeAccountID: String?
    public var accountSelection: AccountSelection = .all
    public var accountRepoLists: AccountScopedRepositoryLists = .init()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case appearance
        case heatmap
        case repoList
        case localProjects
        case gitHubReferenceMonitor
        case aiSummaries
        case gitHubPullRequestNotifications
        case legacyIssueNumberMonitor = "issueNumberMonitor"
        case githubArchives
        case menuCustomization
        case refreshInterval
        case launchAtLogin
        case debugPaneEnabled
        case diagnosticsEnabled
        case loggingVerbosity
        case fileLoggingEnabled
        case githubHost
        case enterpriseHost
        case loopbackPort
        case authMethod
        case monitoredOwners
        case actions
        case accounts
        case activeAccountID
        case accountSelection
        case accountRepoLists
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? AppearanceSettings()
        self.heatmap = try container.decodeIfPresent(HeatmapSettings.self, forKey: .heatmap) ?? HeatmapSettings()
        self.repoList = try container.decodeIfPresent(RepoListSettings.self, forKey: .repoList) ?? RepoListSettings()
        self.localProjects = try container.decodeIfPresent(LocalProjectsSettings.self, forKey: .localProjects) ?? LocalProjectsSettings()
        self.gitHubReferenceMonitor = try container.decodeIfPresent(GitHubReferenceMonitorSettings.self, forKey: .gitHubReferenceMonitor)
            ?? container.decodeIfPresent(GitHubReferenceMonitorSettings.self, forKey: .legacyIssueNumberMonitor)
            ?? GitHubReferenceMonitorSettings()
        self.aiSummaries = try container.decodeIfPresent(AISummarySettings.self, forKey: .aiSummaries) ?? AISummarySettings()
        self.gitHubPullRequestNotifications = try container.decodeIfPresent(
            GitHubPullRequestNotificationSettings.self,
            forKey: .gitHubPullRequestNotifications
        ) ?? GitHubPullRequestNotificationSettings()
        self.githubArchives = try container.decodeIfPresent(GitHubArchiveSettings.self, forKey: .githubArchives) ?? GitHubArchiveSettings()
        self.menuCustomization = try container.decodeIfPresent(MenuCustomization.self, forKey: .menuCustomization) ?? MenuCustomization()
        self.refreshInterval = try container.decodeIfPresent(RefreshInterval.self, forKey: .refreshInterval) ?? .fiveMinutes
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.debugPaneEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugPaneEnabled) ?? false
        self.diagnosticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? false
        self.loggingVerbosity = try container.decodeIfPresent(LogVerbosity.self, forKey: .loggingVerbosity) ?? .info
        self.fileLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .fileLoggingEnabled) ?? false
        self.githubHost = try container.decodeIfPresent(URL.self, forKey: .githubHost) ?? URL(string: "https://github.com")!
        self.enterpriseHost = try container.decodeIfPresent(URL.self, forKey: .enterpriseHost)
        self.loopbackPort = try container.decodeIfPresent(Int.self, forKey: .loopbackPort) ?? 53682
        self.authMethod = try container.decodeIfPresent(AuthMethod.self, forKey: .authMethod) ?? .oauth
        let hasActionsSettings = container.contains(.actions)
        self.actions = try container.decodeIfPresent(ActionsSettings.self, forKey: .actions) ?? ActionsSettings()
        if container.contains(.monitoredOwners) {
            let decodedOwners = try container.decodeIfPresent([String].self, forKey: .monitoredOwners) ?? []
            self.monitoredOwners = OwnerFilter.normalize(decodedOwners)
        } else {
            self.monitoredOwners = OwnerFilter.normalize(self.actions.ownerFilter)
        }
        if hasActionsSettings, self.actions.showActionsInMenu {
            self.menuCustomization.hiddenMainMenuItems.remove(.actionsLimits)
        } else {
            self.menuCustomization.hiddenMainMenuItems.insert(.actionsLimits)
        }
        self.accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        self.activeAccountID = try container.decodeIfPresent(String.self, forKey: .activeAccountID)
        self.accountSelection = try container.decodeIfPresent(AccountSelection.self, forKey: .accountSelection) ?? .all
        self.accountRepoLists = try container.decodeIfPresent(
            AccountScopedRepositoryLists.self,
            forKey: .accountRepoLists
        ) ?? AccountScopedRepositoryLists()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.appearance, forKey: .appearance)
        try container.encode(self.heatmap, forKey: .heatmap)
        try container.encode(self.repoList, forKey: .repoList)
        try container.encode(self.localProjects, forKey: .localProjects)
        try container.encode(self.gitHubReferenceMonitor, forKey: .gitHubReferenceMonitor)
        try container.encode(self.aiSummaries, forKey: .aiSummaries)
        try container.encode(self.gitHubPullRequestNotifications, forKey: .gitHubPullRequestNotifications)
        try container.encode(self.githubArchives, forKey: .githubArchives)
        try container.encode(self.menuCustomization, forKey: .menuCustomization)
        try container.encode(self.refreshInterval, forKey: .refreshInterval)
        try container.encode(self.launchAtLogin, forKey: .launchAtLogin)
        try container.encode(self.debugPaneEnabled, forKey: .debugPaneEnabled)
        try container.encode(self.diagnosticsEnabled, forKey: .diagnosticsEnabled)
        try container.encode(self.loggingVerbosity, forKey: .loggingVerbosity)
        try container.encode(self.fileLoggingEnabled, forKey: .fileLoggingEnabled)
        try container.encode(self.githubHost, forKey: .githubHost)
        try container.encodeIfPresent(self.enterpriseHost, forKey: .enterpriseHost)
        try container.encode(self.loopbackPort, forKey: .loopbackPort)
        try container.encode(self.authMethod, forKey: .authMethod)
        try container.encode(OwnerFilter.normalize(self.monitoredOwners), forKey: .monitoredOwners)
        var actions = self.actions
        actions.ownerFilter = OwnerFilter.normalize(self.monitoredOwners)
        actions.monitoredOrg = nil
        try container.encode(actions, forKey: .actions)
        if self.accounts.isEmpty == false {
            try container.encode(self.accounts, forKey: .accounts)
        }
        try container.encodeIfPresent(self.activeAccountID, forKey: .activeAccountID)
        if case .all = self.accountSelection {
            // Default: omit so legacy reads stay clean.
        } else {
            try container.encode(self.accountSelection, forKey: .accountSelection)
        }
        if self.accountRepoLists.isEmpty == false {
            try container.encode(self.accountRepoLists, forKey: .accountRepoLists)
        }
    }

    // MARK: - Multi-account helpers

    /// Resolves the active account, falling back to the only configured account.
    public func resolvedActiveAccount() -> Account? {
        if let activeAccountID {
            if let account = self.accounts.first(where: { $0.id == activeAccountID }) {
                return account
            }
        }
        if self.accounts.count == 1 {
            return self.accounts.first
        }
        return nil
    }

    /// Account IDs that should contribute repositories to the menu.
    public var visibleAccountIDs: [String] {
        let ids = self.accounts.map(\.id)
        switch self.accountSelection {
        case .all:
            return ids
        case let .only(selected):
            return ids.filter { selected.contains($0) }
        }
    }
}

public struct ActionsSettings: Equatable, Codable {
    public var planTier: GitHubPlanTier = .free
    public var showActionsInMenu = false
    public var ownerFilter: [String] = []
    public var monitoredOrg: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case planTier
        case showActionsInMenu
        case ownerFilter
        case monitoredOrg
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.planTier = try container.decodeIfPresent(GitHubPlanTier.self, forKey: .planTier) ?? .free
        self.showActionsInMenu = try container.decodeIfPresent(Bool.self, forKey: .showActionsInMenu) ?? false
        let owners = try container.decodeIfPresent([String].self, forKey: .ownerFilter) ?? []
        if !owners.isEmpty {
            self.ownerFilter = OwnerFilter.normalize(owners)
        } else if let monitoredOrg = try container.decodeIfPresent(String.self, forKey: .monitoredOrg) {
            self.ownerFilter = OwnerFilter.normalize([monitoredOrg])
        } else {
            self.ownerFilter = []
        }
        self.monitoredOrg = try container.decodeIfPresent(String.self, forKey: .monitoredOrg)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.planTier, forKey: .planTier)
        try container.encode(self.showActionsInMenu, forKey: .showActionsInMenu)
        try container.encode(OwnerFilter.normalize(self.ownerFilter), forKey: .ownerFilter)
        try container.encodeIfPresent(self.monitoredOrg, forKey: .monitoredOrg)
    }
}

public enum AuthMethod: String, CaseIterable, Equatable, Codable, Sendable {
    case oauth
    case pat

    public var label: String {
        switch self {
        case .oauth: "OAuth"
        case .pat: "Personal Access Token"
        }
    }
}

public struct HeatmapSettings: Equatable, Codable {
    public var display: HeatmapDisplay = .inline
    public var span: HeatmapSpan = .twelveMonths

    public init() {}
}

public struct RepoListSettings: Equatable, Codable {
    public var displayLimit: Int = 6
    public var showForks = false
    public var showArchived = false
    public var menuSortKey: RepositorySortKey = .activity
    public var pinnedRepositories: [String] = [] // owner/name
    public var hiddenRepositories: [String] = [] // owner/name
    public var ownerFilter: [String] = [] // owner names to include (empty = show all)

    public init() {}
}

public struct AppearanceSettings: Equatable, Codable {
    public var showContributionHeader = true
    public var showRateLimitMeterInMenuBar = true
    public var cardDensity: CardDensity = .comfortable
    public var accentTone: AccentTone = .githubGreen
    public var activityScope: GlobalActivityScope = .myActivity

    public init() {}

    enum CodingKeys: String, CodingKey {
        case showContributionHeader
        case showRateLimitMeterInMenuBar
        case cardDensity
        case accentTone
        case activityScope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showContributionHeader = try container.decodeIfPresent(Bool.self, forKey: .showContributionHeader) ?? true
        self.showRateLimitMeterInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showRateLimitMeterInMenuBar) ?? true
        self.cardDensity = try container.decodeIfPresent(CardDensity.self, forKey: .cardDensity) ?? .comfortable
        self.accentTone = try container.decodeIfPresent(AccentTone.self, forKey: .accentTone) ?? .githubGreen
        self.activityScope = try container.decodeIfPresent(GlobalActivityScope.self, forKey: .activityScope) ?? .myActivity
    }
}

public struct LocalProjectsSettings: Equatable, Codable {
    public var rootPath: String?
    public var rootBookmarkData: Data?
    public var autoSyncEnabled: Bool = true
    public var showDirtyFilesInMenu: Bool = false
    public var fetchInterval: LocalProjectsRefreshInterval = .fiveMinutes
    public var maxDepth: Int = LocalProjectsConstants.defaultMaxDepth
    public var worktreeFolderName: String = ".work"
    public var preferredTerminal: String?
    public var ghosttyOpenMode: GhosttyOpenMode = .tab
    public var preferredLocalPathsByFullName: [String: String] = [:]

    public init() {
        #if DEBUG
            self.rootPath = "~/Projects"
        #endif
    }
}

public struct GitHubReferenceMonitorSettings: Equatable, Codable, Sendable {
    public var enabled = false

    public init() {}
}

public struct AISummarySettings: Equatable, Codable, Sendable {
    public static let defaultModel = "chat-latest"
    public static let modelOptions: [AISummaryModelOption] = [
        AISummaryModelOption(id: "chat-latest", label: "Chat latest"),
        AISummaryModelOption(id: "gpt-5.5", label: "GPT-5.5"),
        AISummaryModelOption(id: "gpt-5.4", label: "GPT-5.4"),
        AISummaryModelOption(id: "gpt-5.4-mini", label: "GPT-5.4 mini")
    ]

    public var enabled = false
    public var model = defaultModel
    public var scope = AISummaryScope.allItems

    public init() {}

    public static func normalizedModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return Self.defaultModel }

        return Self.modelOptions.first { $0.id == trimmed }?.id ?? Self.defaultModel
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case model
        case scope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let decodedModel = try container.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel
        self.model = Self.normalizedModel(decodedModel)
        self.scope = try container.decodeIfPresent(AISummaryScope.self, forKey: .scope) ?? (self.enabled ? .pullRequests : .allItems)
    }

    public func includes(kind: GitHubReferenceKind) -> Bool {
        switch self.scope {
        case .pullRequests:
            kind == .pullRequest
        case .allItems:
            true
        }
    }
}

public enum AISummaryScope: String, CaseIterable, Codable, Sendable {
    case pullRequests = "pull-requests"
    case allItems = "all-items"

    public var label: String {
        switch self {
        case .pullRequests:
            "Pull requests"
        case .allItems:
            "All items"
        }
    }
}

public struct AISummaryModelOption: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct GitHubPullRequestNotificationSettings: Equatable, Codable, Sendable {
    public var enabled = false
    public var newPullRequests = true
    public var pullRequestUpdates = true
    public var reviewRequests = false
    public var comments = false
    public var clickAction: GitHubPullRequestNotificationClickAction = .openInBrowser

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled
        case newPullRequests
        case pullRequestUpdates
        case reviewRequests
        case comments
        case clickAction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.newPullRequests = try container.decodeIfPresent(Bool.self, forKey: .newPullRequests) ?? true
        self.pullRequestUpdates = try container.decodeIfPresent(Bool.self, forKey: .pullRequestUpdates) ?? true
        self.reviewRequests = try container.decodeIfPresent(Bool.self, forKey: .reviewRequests) ?? false
        self.comments = try container.decodeIfPresent(Bool.self, forKey: .comments) ?? false
        self.clickAction = try container.decodeIfPresent(
            GitHubPullRequestNotificationClickAction.self,
            forKey: .clickAction
        ) ?? .openInBrowser
    }
}

public enum GitHubPullRequestNotificationClickAction: String, CaseIterable, Hashable, Codable, Sendable {
    case openInBrowser
    case openIssueNavigator

    public var label: String {
        switch self {
        case .openInBrowser: "Default browser"
        case .openIssueNavigator: "Issue Navigator"
        }
    }
}

public struct GitHubArchiveSettings: Equatable, Codable, Sendable {
    public var sources: [GitHubArchiveSource] = []
    public var preferArchiveWhenRateLimited = true
    public var staleAfterSeconds: TimeInterval = 15 * 60

    public init() {}
}

public struct GitHubArchiveSource: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var localRepositoryPath: String?
    public var remoteURL: String?
    public var branch: String
    public var importedDatabasePath: String
    public var format: GitHubArchiveFormat

    public init(
        id: String = UUID().uuidString,
        name: String,
        enabled: Bool = true,
        localRepositoryPath: String?,
        remoteURL: String?,
        branch: String = "main",
        importedDatabasePath: String,
        format: GitHubArchiveFormat = .discrawlSnapshot
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.localRepositoryPath = localRepositoryPath
        self.remoteURL = remoteURL
        self.branch = branch
        self.importedDatabasePath = importedDatabasePath
        self.format = format
    }
}

public enum GitHubArchiveFormat: String, Equatable, Codable, Sendable {
    case discrawlSnapshot

    public var label: String {
        switch self {
        case .discrawlSnapshot: "Discrawl snapshot"
        }
    }
}

public enum LocalProjectsRefreshInterval: String, CaseIterable, Equatable, Codable {
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }

    public var label: String {
        switch self {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }
}

public enum GhosttyOpenMode: String, CaseIterable, Equatable, Codable {
    case newWindow
    case tab

    public var label: String {
        switch self {
        case .newWindow: "New Window"
        case .tab: "Tab"
        }
    }
}

public enum RefreshInterval: CaseIterable, Equatable, Codable {
    case oneMinute, twoMinutes, fiveMinutes, fifteenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }
}

public enum HeatmapDisplay: String, CaseIterable, Equatable, Codable {
    case inline
    case submenu

    public var label: String {
        switch self {
        case .inline: "Inline"
        case .submenu: "Submenu"
        }
    }
}

public enum CardDensity: String, CaseIterable, Equatable, Codable {
    case comfortable
    case compact

    public var label: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }
}

public enum AccentTone: String, CaseIterable, Equatable, Codable {
    case system
    case githubGreen

    public var label: String {
        switch self {
        case .system: "System accent"
        case .githubGreen: "GitHub greens"
        }
    }
}

public enum GlobalActivityScope: String, CaseIterable, Equatable, Codable, Sendable {
    case allActivity
    case myActivity

    public var label: String {
        switch self {
        case .allActivity: "All activity"
        case .myActivity: "My activity"
        }
    }
}
