import Commander
import Foundation
import RepoBarCore

@MainActor
struct ContributionsCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "contributions"

    @Option(name: .customLong("login"), help: "GitHub login (defaults to current user)")
    var login: String?

    @OptionGroup
    var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Fetch contribution heatmap for a user"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.login = try values.decodeOption("login")
        self.output.bind(values)
    }

    mutating func run() async throws {
        let context = try await makeAuthenticatedClient()
        let client = context.client
        let resolvedLogin: String

        if let login, login.isEmpty == false {
            resolvedLogin = login
        } else {
            let user = try await client.currentUser()
            resolvedLogin = user.username
        }

        let cells = try await client.userContributionHeatmap(login: resolvedLogin)
        let total = cells.map(\.count).reduce(0, +)
        let maxCount = cells.map(\.count).max() ?? 0

        if self.output.jsonOutput {
            let output = ContributionsOutput(
                login: resolvedLogin,
                total: total,
                max: maxCount,
                days: cells.count,
                cells: cells
            )
            try printJSON(output)
        } else {
            print("User: \(resolvedLogin)")
            print("Days: \(cells.count)")
            print("Total contributions: \(total)")
            print("Max in a day: \(maxCount)")
        }
    }
}

@MainActor
struct RepoCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "repo"

    @Flag(names: [.customLong("traffic")], help: "Include traffic stats")
    var includeTraffic: Bool = false

    @Flag(names: [.customLong("heatmap")], help: "Include commit activity heatmap")
    var includeHeatmap: Bool = false

    @Flag(names: [.customLong("release")], help: "Include latest release data")
    var includeRelease: Bool = false

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Fetch a repository summary"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.includeTraffic = values.flag("includeTraffic")
        self.includeHeatmap = values.flag("includeHeatmap")
        self.includeRelease = values.flag("includeRelease")
        self.output.bind(values)

        if values.positional.count > 1 {
            throw ValidationError("Only one repository can be specified")
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        let repoID = try requireRepoIdentifier(self.repoName)

        let context = try await makeAuthenticatedClient()
        let client = context.client
        let repo = try await client.fullRepository(owner: repoID.owner, name: repoID.name)

        if self.output.jsonOutput {
            let output = RepoDetailOutput(
                fullName: repo.fullName,
                ciStatus: repo.ciStatus.description,
                ciRunCount: repo.ciRunCount,
                issues: repo.stats.openIssues,
                pulls: repo.stats.openPulls,
                latestRelease: self.includeRelease ? repo.latestRelease : nil,
                traffic: self.includeTraffic ? repo.traffic : nil,
                heatmap: self.includeHeatmap ? repo.heatmap : nil,
                activity: repo.latestActivity,
                error: repo.error,
                rateLimitedUntil: repo.rateLimitedUntil
            )
            try printJSON(output)
            return
        }

        let ciSuffix = repo.ciRunCount.map { " (\($0))" } ?? ""
        print("Repository: \(repo.fullName)")
        print("CI: \(repo.ciStatus.description)\(ciSuffix)")
        print("Issues: \(repo.stats.openIssues)")
        print("PRs: \(repo.stats.openPulls)")

        if self.includeRelease {
            if let release = repo.latestRelease {
                let dateText = RelativeFormatter.string(from: release.publishedAt, relativeTo: Date())
                print("Release: \(release.name) (\(dateText))")
            } else {
                print("Release: none")
            }
        }

        if self.includeTraffic {
            if let traffic = repo.traffic {
                print("Traffic: \(traffic.uniqueVisitors) visitors, \(traffic.uniqueCloners) cloners")
            } else {
                print("Traffic: unavailable")
            }
        }

        if self.includeHeatmap {
            let maxCount = repo.heatmap.map(\.count).max() ?? 0
            print("Heatmap days: \(repo.heatmap.count), max \(maxCount)")
        }

        if let activity = repo.latestActivity {
            let when = RelativeFormatter.string(from: activity.date, relativeTo: Date())
            print("Activity: \(activity.title.singleLine) (\(when))")
        }

        if let error = repo.error {
            print("Error: \(error)")
        }
        if let limit = repo.rateLimitedUntil {
            print("Rate limited until \(RelativeFormatter.string(from: limit, relativeTo: Date()))")
        }
    }
}

@MainActor
struct IssuesCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "issues"

    @Option(name: .customLong("limit"), help: "Max issues to fetch (default: 20)")
    var limit: Int = 20

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "List open issues by recently updated"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.output.bind(values)

        if values.positional.count > 1 {
            throw ValidationError("Only one repository can be specified")
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError("--limit must be greater than 0")
        }
        let repoID = try requireRepoIdentifier(self.repoName)

        let context = try await makeAuthenticatedClient()
        let client = context.client
        let issues = try await client.recentIssues(owner: repoID.owner, name: repoID.name, limit: self.limit)

        if self.output.jsonOutput {
            try printJSON(RepoIssuesOutput(
                repo: repoID.webURL(baseHost: context.host),
                count: issues.count,
                issues: issues.map {
                    IssueOutput(
                        number: $0.number,
                        title: $0.title,
                        url: $0.url,
                        updatedAt: $0.updatedAt,
                        author: $0.authorLogin
                    )
                }
            ))
            return
        }

        if self.output.plain == false, self.output.useColor {
            print("Issues: \(repoID.fullName)")
        }
        let lines = issuesTableLines(
            issues,
            useColor: self.output.useColor,
            includeURL: self.output.plain == false,
            now: Date()
        )
        for line in lines {
            print(line)
        }
    }
}

@MainActor
struct PullsCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "pulls"

    @Option(name: .customLong("limit"), help: "Max PRs to fetch (default: 20)")
    var limit: Int = 20

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "List open pull requests by recently updated"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.output.bind(values)

        if values.positional.count > 1 {
            throw ValidationError("Only one repository can be specified")
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError("--limit must be greater than 0")
        }
        let repoID = try requireRepoIdentifier(self.repoName)

        let context = try await makeAuthenticatedClient()
        let client = context.client
        let pulls = try await client.recentPullRequests(owner: repoID.owner, name: repoID.name, limit: self.limit)

        if self.output.jsonOutput {
            try printJSON(RepoPullsOutput(
                repo: repoID.webURL(baseHost: context.host),
                count: pulls.count,
                pulls: pulls.map {
                    PullRequestOutput(
                        number: $0.number,
                        title: $0.title,
                        url: $0.url,
                        updatedAt: $0.updatedAt,
                        author: $0.authorLogin,
                        draft: $0.isDraft
                    )
                }
            ))
            return
        }

        if self.output.plain == false, self.output.useColor {
            print("Pull Requests: \(repoID.fullName)")
        }
        let lines = pullsTableLines(
            pulls,
            useColor: self.output.useColor,
            includeURL: self.output.plain == false,
            now: Date()
        )
        for line in lines {
            print(line)
        }
    }
}

@MainActor
struct RefreshCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "refresh"

    @OptionGroup
    var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Refresh pinned repositories using current settings"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
    }

    mutating func run() async throws {
        let context = try await makeAuthenticatedClient()
        let hidden = Set(context.settings.repoList.hiddenRepositories)
        let pinned = context.settings.repoList.pinnedRepositories.filter { !hidden.contains($0) }

        guard pinned.isEmpty == false else {
            if self.output.jsonOutput {
                try printJSON(RefreshOutput(count: 0, repositories: []))
            } else {
                print("No pinned repositories to refresh.")
            }
            return
        }

        let results = try await refreshPinned(pinned, client: context.client)

        if self.output.jsonOutput {
            try printJSON(RefreshOutput(count: results.count, repositories: results))
        } else {
            print("Refreshed \(results.count) repositories:")
            for result in results {
                if let error = result.error {
                    print("- \(result.fullName): \(error)")
                } else {
                    print("- \(result.fullName)")
                }
            }
        }
    }
}

private func refreshPinned(_ pinned: [String], client: GitHubClient) async throws -> [RefreshRepositoryOutput] {
    try await withThrowingTaskGroup(of: RefreshRepositoryOutput.self) { group in
        for name in pinned {
            group.addTask {
                let parsed: RepoIdentifier
                do {
                    parsed = try parseRepoName(name)
                } catch {
                    return RefreshRepositoryOutput(fullName: name, error: "Invalid repository name", rateLimitedUntil: nil)
                }

                do {
                    let repo = try await client.fullRepository(owner: parsed.owner, name: parsed.name)
                    return RefreshRepositoryOutput(
                        fullName: repo.fullName,
                        error: repo.error,
                        rateLimitedUntil: repo.rateLimitedUntil
                    )
                } catch {
                    return RefreshRepositoryOutput(
                        fullName: name,
                        error: error.userFacingMessage,
                        rateLimitedUntil: nil
                    )
                }
            }
        }

        var results: [RefreshRepositoryOutput] = []
        for try await result in group {
            results.append(result)
        }
        return results.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }
}

private struct RepoIssuesOutput: Encodable {
    let repo: URL
    let count: Int
    let issues: [IssueOutput]
}

private struct IssueOutput: Encodable {
    let number: Int
    let title: String
    let url: URL
    let updatedAt: Date
    let author: String?
}

private struct RepoPullsOutput: Encodable {
    let repo: URL
    let count: Int
    let pulls: [PullRequestOutput]
}

private struct PullRequestOutput: Encodable {
    let number: Int
    let title: String
    let url: URL
    let updatedAt: Date
    let author: String?
    let draft: Bool
}

private struct ContributionsOutput: Encodable {
    let login: String
    let total: Int
    let max: Int
    let days: Int
    let cells: [HeatmapCell]
}

private struct RepoDetailOutput: Encodable {
    let fullName: String
    let ciStatus: String
    let ciRunCount: Int?
    let issues: Int
    let pulls: Int
    let latestRelease: Release?
    let traffic: TrafficStats?
    let heatmap: [HeatmapCell]?
    let activity: ActivityEvent?
    let error: String?
    let rateLimitedUntil: Date?
}

private struct RefreshOutput: Encodable {
    let count: Int
    let repositories: [RefreshRepositoryOutput]
}

private struct RefreshRepositoryOutput: Encodable {
    let fullName: String
    let error: String?
    let rateLimitedUntil: Date?
}

private extension CIStatus {
    var description: String {
        switch self {
        case .passing: "passing"
        case .failing: "failing"
        case .pending: "pending"
        case .unknown: "unknown"
        }
    }
}
