import Commander
import Foundation
import RepoBarCore

func cliSettingsStore() -> SettingsStore {
    SettingsStore(defaults: SettingsStore.mainAppDefaults())
}

enum SettingsKey: String, CaseIterable {
    case refreshInterval = "refresh-interval"
    case repoLimit = "repo-limit"
    case showForks = "show-forks"
    case showArchived = "show-archived"
    case menuSort = "menu-sort"
    case showContributionHeader = "show-contribution-header"
    case showRateLimitMeter = "show-rate-limit-meter"
    case showActionsMenu = "show-actions-menu"
    case actionsPlanTier = "actions-plan-tier"
    case monitoredOwners = "monitored-owners"
    case gitHubReferenceMonitor = "github-reference-monitor"
    case pullRequestNotifications = "pull-request-notifications"
    case pullRequestNotificationNew = "pull-request-notification-new"
    case pullRequestNotificationUpdates = "pull-request-notification-updates"
    case pullRequestNotificationReviews = "pull-request-notification-reviews"
    case pullRequestNotificationComments = "pull-request-notification-comments"
    case pullRequestNotificationClick = "pull-request-notification-click"
    case cardDensity = "card-density"
    case accentTone = "accent-tone"
    case activityScope = "activity-scope"
    case heatmapDisplay = "heatmap-display"
    case heatmapSpan = "heatmap-span"
    case localRoot = "local-root"
    case localAutoSync = "local-auto-sync"
    case localFetchInterval = "local-fetch-interval"
    case localWorktreeFolder = "local-worktree-folder"
    case localPreferredTerminal = "local-preferred-terminal"
    case localGhosttyMode = "local-ghostty-mode"
    case localShowDirtyFiles = "local-show-dirty-files"
    case aiSummaries = "ai-summaries"
    case aiSummaryModel = "ai-summary-model"
    case launchAtLogin = "launch-at-login"

    init?(argument: String) {
        let key = argument.lowercased()
        switch key {
        case "refresh-interval", "refresh", "interval":
            self = .refreshInterval
        case "repo-limit", "limit":
            self = .repoLimit
        case "show-forks":
            self = .showForks
        case "show-archived":
            self = .showArchived
        case "menu-sort", "sort":
            self = .menuSort
        case "show-contribution-header", "contribution-header":
            self = .showContributionHeader
        case "show-rate-limit-meter", "rate-limit-meter", "menu-bar-rate-limit-meter":
            self = .showRateLimitMeter
        case "show-actions-menu", "actions-menu", "actions":
            self = .showActionsMenu
        case "actions-plan-tier", "actions-plan", "plan-tier":
            self = .actionsPlanTier
        case "monitored-owners", "actions-owners", "actions-owner-filter", "owners":
            self = .monitoredOwners
        case "github-reference-monitor", "reference-monitor", "watch-references", "references":
            self = .gitHubReferenceMonitor
        case "pull-request-notifications", "pr-notifications", "github-pr-notifications", "notifications":
            self = .pullRequestNotifications
        case "pull-request-notification-new", "pr-notification-new", "new-pr-notifications":
            self = .pullRequestNotificationNew
        case "pull-request-notification-updates", "pr-notification-updates", "pr-update-notifications":
            self = .pullRequestNotificationUpdates
        case "pull-request-notification-reviews", "pr-notification-reviews", "review-request-notifications":
            self = .pullRequestNotificationReviews
        case "pull-request-notification-comments", "pr-notification-comments", "comment-notifications":
            self = .pullRequestNotificationComments
        case "pull-request-notification-click", "pr-notification-click", "notification-click":
            self = .pullRequestNotificationClick
        case "card-density", "density":
            self = .cardDensity
        case "accent-tone", "accent":
            self = .accentTone
        case "activity-scope", "scope":
            self = .activityScope
        case "heatmap-display", "heatmap":
            self = .heatmapDisplay
        case "heatmap-span", "heatmap-range":
            self = .heatmapSpan
        case "local-root", "local-root-path":
            self = .localRoot
        case "local-auto-sync", "local-sync":
            self = .localAutoSync
        case "local-fetch-interval", "local-fetch":
            self = .localFetchInterval
        case "local-worktree-folder", "worktree-folder":
            self = .localWorktreeFolder
        case "local-preferred-terminal", "preferred-terminal":
            self = .localPreferredTerminal
        case "local-ghostty-mode", "ghostty-mode":
            self = .localGhosttyMode
        case "local-show-dirty-files", "show-dirty-files":
            self = .localShowDirtyFiles
        case "ai-summaries", "ai-summary", "pr-summaries", "pr-summary":
            self = .aiSummaries
        case "ai-summary-model", "ai-model", "summary-model":
            self = .aiSummaryModel
        case "launch-at-login":
            self = .launchAtLogin
        default:
            return nil
        }
    }
}

func applySetting(_ key: SettingsKey, value: String, settings: inout UserSettings) throws -> String {
    switch key {
    case .refreshInterval:
        let interval = try parseRefreshInterval(value)
        settings.refreshInterval = interval
        return intervalLabel(interval)
    case .repoLimit:
        let limit = try parsePositiveInt(value, label: key.rawValue)
        settings.repoList.displayLimit = limit
        return String(limit)
    case .showForks:
        let flag = try parseBool(value)
        settings.repoList.showForks = flag
        return flag ? "on" : "off"
    case .showArchived:
        let flag = try parseBool(value)
        settings.repoList.showArchived = flag
        return flag ? "on" : "off"
    case .menuSort:
        guard let sort = RepositorySortKey(argument: value) else {
            throw ValidationError("Invalid menu-sort value: \(value)")
        }

        settings.repoList.menuSortKey = sort
        return sort.rawValue
    case .showContributionHeader:
        let flag = try parseBool(value)
        settings.appearance.showContributionHeader = flag
        return flag ? "on" : "off"
    case .showRateLimitMeter:
        let flag = try parseBool(value)
        settings.appearance.showRateLimitMeterInMenuBar = flag
        return flag ? "on" : "off"
    case .showActionsMenu:
        let flag = try parseBool(value)
        settings.actions.showActionsInMenu = flag
        if flag {
            settings.menuCustomization.hiddenMainMenuItems.remove(.actionsLimits)
        } else {
            settings.menuCustomization.hiddenMainMenuItems.insert(.actionsLimits)
        }
        return flag ? "on" : "off"
    case .actionsPlanTier:
        guard let tier = GitHubPlanTier(argument: value) else {
            throw ValidationError("Invalid actions-plan-tier value: \(value)")
        }

        settings.actions.planTier = tier
        return tier.rawValue
    case .monitoredOwners:
        let owners = parseOwnerList(value)
        settings.monitoredOwners = owners
        return owners.isEmpty ? "auto" : owners.joined(separator: ", ")
    case .gitHubReferenceMonitor:
        let flag = try parseBool(value)
        settings.gitHubReferenceMonitor.enabled = flag
        return flag ? "on" : "off"
    case .pullRequestNotifications:
        let flag = try parseBool(value)
        settings.gitHubPullRequestNotifications.enabled = flag
        return flag ? "on" : "off"
    case .pullRequestNotificationNew:
        let flag = try parseBool(value)
        settings.gitHubPullRequestNotifications.newPullRequests = flag
        return flag ? "on" : "off"
    case .pullRequestNotificationUpdates:
        let flag = try parseBool(value)
        settings.gitHubPullRequestNotifications.pullRequestUpdates = flag
        return flag ? "on" : "off"
    case .pullRequestNotificationReviews:
        let flag = try parseBool(value)
        settings.gitHubPullRequestNotifications.reviewRequests = flag
        return flag ? "on" : "off"
    case .pullRequestNotificationComments:
        let flag = try parseBool(value)
        settings.gitHubPullRequestNotifications.comments = flag
        return flag ? "on" : "off"
    case .pullRequestNotificationClick:
        let action = try parsePullRequestNotificationClickAction(value)
        settings.gitHubPullRequestNotifications.clickAction = action
        return action.label
    case .cardDensity:
        guard let density = CardDensity(rawValue: value.lowercased()) else {
            throw ValidationError("Invalid card-density value: \(value)")
        }

        settings.appearance.cardDensity = density
        return density.rawValue
    case .accentTone:
        let lowered = value.lowercased()
        let tone: AccentTone
        switch lowered {
        case "system": tone = .system
        case "github", "github-green", "githubgreen", "green": tone = .githubGreen
        default:
            throw ValidationError("Invalid accent-tone value: \(value)")
        }
        settings.appearance.accentTone = tone
        return tone.rawValue
    case .activityScope:
        guard let scope = GlobalActivityScope(argument: value) else {
            throw ValidationError("Invalid activity-scope value: \(value)")
        }

        settings.appearance.activityScope = scope
        return scope.rawValue
    case .heatmapDisplay:
        guard let display = HeatmapDisplay(rawValue: value.lowercased()) else {
            throw ValidationError("Invalid heatmap-display value: \(value)")
        }

        settings.heatmap.display = display
        return display.rawValue
    case .heatmapSpan:
        let span = try parseHeatmapSpan(value)
        settings.heatmap.span = span
        return "\(span.months)m"
    case .localRoot:
        settings.localProjects.rootPath = value
        return PathFormatter.displayString(value)
    case .localAutoSync:
        let flag = try parseBool(value)
        settings.localProjects.autoSyncEnabled = flag
        return flag ? "on" : "off"
    case .localFetchInterval:
        let interval = try parseLocalFetchInterval(value)
        settings.localProjects.fetchInterval = interval
        return interval.label
    case .localWorktreeFolder:
        settings.localProjects.worktreeFolderName = value
        return value
    case .localPreferredTerminal:
        settings.localProjects.preferredTerminal = value
        return value
    case .localGhosttyMode:
        let mode: GhosttyOpenMode
        switch value.lowercased() {
        case "tab": mode = .tab
        case "new-window", "newwindow", "window": mode = .newWindow
        default:
            throw ValidationError("Invalid local-ghostty-mode value: \(value)")
        }
        settings.localProjects.ghosttyOpenMode = mode
        return mode.rawValue
    case .localShowDirtyFiles:
        let flag = try parseBool(value)
        settings.localProjects.showDirtyFilesInMenu = flag
        return flag ? "on" : "off"
    case .aiSummaries:
        let flag = try parseBool(value)
        settings.aiSummaries.enabled = flag
        return flag ? "on" : "off"
    case .aiSummaryModel:
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.aiSummaries.model = trimmed.isEmpty ? AISummarySettings.defaultModel : trimmed
        return settings.aiSummaries.model
    case .launchAtLogin:
        let flag = try parseBool(value)
        settings.launchAtLogin = flag
        return flag ? "on" : "off"
    }
}

func settingsSummaryLines(settings: UserSettings) -> [String] {
    let pinned = settings.repoList.pinnedRepositories
    let hidden = settings.repoList.hiddenRepositories
    let localRoot = settings.localProjects.rootPath.map(PathFormatter.displayString) ?? "-"
    let archives = settings.githubArchives.sources
    return [
        "Refresh interval: \(intervalLabel(settings.refreshInterval))",
        "Repo limit: \(settings.repoList.displayLimit)",
        "Show forks: \(settings.repoList.showForks ? "on" : "off")",
        "Show archived: \(settings.repoList.showArchived ? "on" : "off")",
        "Menu sort: \(settings.repoList.menuSortKey.rawValue)",
        "Contribution header: \(settings.appearance.showContributionHeader ? "on" : "off")",
        "Rate-limit menu bar meter: \(settings.appearance.showRateLimitMeterInMenuBar ? "on" : "off")",
        "Actions menu: \(settings.menuCustomization.hiddenMainMenuItems.contains(.actionsLimits) ? "off" : "on")",
        "Actions plan tier: \(settings.actions.planTier.rawValue)",
        "Monitored owners: \(settings.monitoredOwners.isEmpty ? "auto" : settings.monitoredOwners.joined(separator: ", "))",
        "GitHub reference monitor: \(settings.gitHubReferenceMonitor.enabled ? "on" : "off")",
        "PR notifications: \(settings.gitHubPullRequestNotifications.enabled ? "on" : "off")",
        "PR notification events: \(pullRequestNotificationEventsLabel(settings.gitHubPullRequestNotifications))",
        "PR notification click: \(settings.gitHubPullRequestNotifications.clickAction.label)",
        "Card density: \(settings.appearance.cardDensity.rawValue)",
        "Accent tone: \(settings.appearance.accentTone.rawValue)",
        "Activity scope: \(settings.appearance.activityScope.rawValue)",
        "Heatmap display: \(settings.heatmap.display.rawValue)",
        "Heatmap span: \(settings.heatmap.span.months)m",
        "Local root: \(localRoot)",
        "Local auto-sync: \(settings.localProjects.autoSyncEnabled ? "on" : "off")",
        "Local fetch interval: \(settings.localProjects.fetchInterval.label)",
        "Local worktree folder: \(settings.localProjects.worktreeFolderName)",
        "Local preferred terminal: \(settings.localProjects.preferredTerminal ?? "-")",
        "Local Ghostty mode: \(settings.localProjects.ghosttyOpenMode.rawValue)",
        "Local show dirty files: \(settings.localProjects.showDirtyFilesInMenu ? "on" : "off")",
        "AI summaries: \(settings.aiSummaries.enabled ? "on" : "off")",
        "AI summary model: \(settings.aiSummaries.model)",
        "GitHub archives: \(archives.isEmpty ? "-" : archives.map(\.name).joined(separator: ", "))",
        "Archive fallback on rate limit: \(settings.githubArchives.preferArchiveWhenRateLimited ? "on" : "off")",
        "Launch at login: \(settings.launchAtLogin ? "on" : "off")",
        "Pinned repositories: \(pinned.isEmpty ? "-" : pinned.joined(separator: ", "))",
        "Hidden repositories: \(hidden.isEmpty ? "-" : hidden.joined(separator: ", "))"
    ]
}

func pullRequestNotificationEventsLabel(_ settings: GitHubPullRequestNotificationSettings) -> String {
    var labels: [String] = []
    if settings.newPullRequests {
        labels.append("new pull requests")
    }
    if settings.pullRequestUpdates {
        labels.append("updates")
    }
    if settings.reviewRequests {
        labels.append("review requests")
    }
    if settings.comments {
        labels.append("comments")
    }
    return labels.isEmpty ? "-" : labels.joined(separator: ", ")
}

extension GitHubPlanTier {
    init?(argument: String) {
        switch argument.lowercased() {
        case "free":
            self = .free
        case "pro", "developer":
            self = .pro
        case "team":
            self = .team
        case "enterprise", "ent":
            self = .enterprise
        default:
            return nil
        }
    }
}

func parseBool(_ raw: String) throws -> Bool {
    switch raw.lowercased() {
    case "1", "true", "yes", "y", "on":
        return true
    case "0", "false", "no", "n", "off":
        return false
    default:
        throw ValidationError("Invalid boolean value: \(raw)")
    }
}

func parsePullRequestNotificationClickAction(_ raw: String) throws -> GitHubPullRequestNotificationClickAction {
    switch raw.lowercased() {
    case "browser", "default-browser", "open-in-browser", "openinbrowser":
        return .openInBrowser
    case "issue-navigator", "navigator", "issue", "issues", "open-issue-navigator", "openissuenavigator":
        return .openIssueNavigator
    default:
        throw ValidationError("Invalid pull-request-notification-click value: \(raw)")
    }
}

func parseOwnerList(_ raw: String) -> [String] {
    let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard lowered != "auto", lowered != "all", lowered != "-" else { return [] }

    return OwnerFilter.normalize(raw.split { separator in
        separator == "," || separator == " " || separator == "\n" || separator == "\t"
    }.map(String.init))
}

func parsePositiveInt(_ raw: String, label: String) throws -> Int {
    guard let value = Int(raw), value > 0 else {
        throw ValidationError("Invalid \(label) value: \(raw)")
    }

    return value
}

func parseRefreshInterval(_ raw: String) throws -> RefreshInterval {
    switch raw.lowercased() {
    case "1", "1m", "one", "one-minute", "oneminute":
        return .oneMinute
    case "2", "2m", "two", "two-minute", "twominute":
        return .twoMinutes
    case "5", "5m", "five", "five-minute", "fiveminute":
        return .fiveMinutes
    case "15", "15m", "fifteen", "fifteen-minute", "fifteenminute":
        return .fifteenMinutes
    default:
        throw ValidationError("Invalid refresh-interval value: \(raw)")
    }
}

func parseLocalFetchInterval(_ raw: String) throws -> LocalProjectsRefreshInterval {
    switch raw.lowercased() {
    case "1", "1m", "one", "one-minute", "oneminute":
        return .oneMinute
    case "2", "2m", "two", "two-minute", "twominute":
        return .twoMinutes
    case "5", "5m", "five", "five-minute", "fiveminute":
        return .fiveMinutes
    case "15", "15m", "fifteen", "fifteen-minute", "fifteenminute":
        return .fifteenMinutes
    default:
        throw ValidationError("Invalid local-fetch-interval value: \(raw)")
    }
}

func parseHeatmapSpan(_ raw: String) throws -> HeatmapSpan {
    switch raw.lowercased() {
    case "1", "1m", "one", "one-month", "onemonth":
        return .oneMonth
    case "3", "3m", "three", "three-month", "threemonth":
        return .threeMonths
    case "6", "6m", "six", "six-month", "sixmonth":
        return .sixMonths
    case "12", "12m", "twelve", "twelve-month", "twelvemonth", "year", "1y":
        return .twelveMonths
    default:
        throw ValidationError("Invalid heatmap-span value: \(raw)")
    }
}

func intervalLabel(_ interval: RefreshInterval) -> String {
    switch interval {
    case .oneMinute: "1m"
    case .twoMinutes: "2m"
    case .fiveMinutes: "5m"
    case .fifteenMinutes: "15m"
    }
}

func normalizeRepoFullName(_ raw: String) throws -> String {
    try parseRepoName(raw).fullName
}

func renderRepoListUpdate(action: String, repoName: String, settings: UserSettings, output: OutputOptions) throws {
    if output.jsonOutput {
        let payload = RepoListOutput(
            action: action.lowercased(),
            repo: repoName,
            pinned: settings.repoList.pinnedRepositories,
            hidden: settings.repoList.hiddenRepositories
        )
        try printJSON(payload)
        return
    }
    print("\(action) \(repoName)")
}

struct RepoListOutput: Encodable {
    let action: String
    let repo: String
    let pinned: [String]
    let hidden: [String]
}

extension String {
    func equalsCaseInsensitive(_ other: String) -> Bool {
        self.caseInsensitiveCompare(other) == .orderedSame
    }
}
