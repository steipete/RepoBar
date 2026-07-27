import Foundation
import Observation
import RepoBarCore

@Observable
final class Session {
    var account: AccountState = .loggedOut
    var hasStoredTokens = false
    var accessibleRepositories: [Repository] = []
    var repositories: [Repository] = []
    var menuSnapshot: MenuSnapshot?
    var menuDisplayIndex: [String: RepositoryDisplayModel] = [:]
    var hasLoadedRepositories = false
    var settings = UserSettings()
    var settingsSelectedTab: SettingsTab = .general
    var settingsAPIUsageExpanded = false
    var rateLimitReset: Date?
    var rateLimitDiagnostics: DiagnosticsSummary = .empty
    var rateLimitCacheSummary: RepoBarCacheSummary?
    var lastError: String?
    var contributionHeatmap: [HeatmapCell] = []
    var contributionUser: String?
    var contributionError: String?
    var contributionIsLoading = false
    var globalActivityEvents: [ActivityEvent] = []
    var globalActivityError: String?
    var globalCommitEvents: [RepoCommitSummary] = []
    var globalCommitError: String?
    var heatmapRange: HeatmapRange = HeatmapFilter.range(span: .twelveMonths, now: Date(), alignToWeek: true)
    var menuRepoSelection: MenuRepoSelection = .all
    var recentIssueScope: RecentIssueScope = .all
    var recentIssueLabelSelection: Set<String> = []
    var recentPullRequestScope: RecentPullRequestScope = .all
    var recentPullRequestEngagement: RecentPullRequestEngagement = .all
    var localRepoIndex: LocalRepoIndex = .empty
    var localDiscoveredRepoCount = 0
    var localProjectsScanInProgress = false
    var localProjectsAccessDenied = false
    var gitHubReferenceMatches: [GitHubReferenceMatch] = []
    var gitHubReferenceMatch: GitHubReferenceMatch?
    var actionsOrgSnapshots: [ActionsOrgSnapshot] = []
    var actionsPlanTier: GitHubPlanTier = .free
    // Multi-account state. Populated by AccountManager during bootstrap.
    // The aggregate `repositories` / `accessibleRepositories` above remain
    // authoritative for the existing single-account menu rendering.
    var accountSessions: [AccountSession] = []
    var activeAccountID: String?
    var aggregatedRepositories: [TaggedRepo] = []

    var rateLimitDisplayState: RateLimitDisplayState {
        RateLimitDisplayState(
            diagnostics: self.rateLimitDiagnostics,
            cacheSummary: self.rateLimitCacheSummary,
            authMethod: self.settings.authMethod
        )
    }
}

enum AccountState: Equatable {
    case loggedOut
    case loggingIn
    case loggedIn(UserIdentity)

    var isLoggedIn: Bool {
        if case .loggedIn = self {
            return true
        }
        return false
    }
}
