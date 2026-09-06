import Commander
import Foundation
import RepoBarCore

@MainActor
struct ReleasesCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "releases"

    @Option(name: .customLong("limit"), help: "Max releases to fetch (default: 20)")
    var limit: Int = 20

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List recent releases")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one repository can be specified"))
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError(cliText("--limit must be greater than 0"))
        }
        let repo = try requireRepoIdentifier(self.repoName)

        let context = try await makeAuthenticatedClient()
        let releases = try await context.client.recentReleases(owner: repo.owner, name: repo.name, limit: self.limit)

        if self.output.jsonOutput {
            let output = RepoReleasesOutput(
                repo: repo.webURL(baseHost: context.host),
                count: releases.count,
                releases: releases.map(ReleaseOutput.init)
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            cliPrint("Releases: \(repo.fullName)")
        }
        for line in releasesTableLines(releases, useColor: self.output.useColor, includeURL: self.output.plain == false, now: Date()) {
            Swift.print(line)
        }
    }
}

@MainActor
struct CICommand: CommanderRunnableCommand {
    nonisolated static let commandName = "ci"

    @Option(name: .customLong("limit"), help: "Max workflow runs to fetch (default: 20)")
    var limit: Int = 20

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List recent workflow runs")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one repository can be specified"))
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError(cliText("--limit must be greater than 0"))
        }
        let repo = try requireRepoIdentifier(self.repoName)

        let context = try await makeAuthenticatedClient()
        let runs = try await context.client.recentWorkflowRuns(owner: repo.owner, name: repo.name, limit: self.limit)

        if self.output.jsonOutput {
            let output = RepoWorkflowRunsOutput(
                repo: repo.webURL(baseHost: context.host),
                count: runs.count,
                runs: runs.map(WorkflowRunOutput.init)
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            cliPrint("CI Runs: \(repo.fullName)")
        }
        for line in workflowRunsTableLines(runs, useColor: self.output.useColor, includeURL: self.output.plain == false, now: Date()) {
            Swift.print(line)
        }
    }
}

@MainActor
struct DiscussionsCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "discussions"

    @Option(name: .customLong("limit"), help: "Max discussions to fetch (default: 20)")
    var limit: Int = 20

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List recent discussions")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one repository can be specified"))
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError(cliText("--limit must be greater than 0"))
        }
        let repo = try requireRepoIdentifier(self.repoName)

        let context = try await makeAuthenticatedClient()
        let discussions = try await context.client.recentDiscussions(owner: repo.owner, name: repo.name, limit: self.limit)

        if self.output.jsonOutput {
            let output = RepoDiscussionsOutput(
                repo: repo.webURL(baseHost: context.host),
                count: discussions.count,
                discussions: discussions.map(DiscussionOutput.init)
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            cliPrint("Discussions: \(repo.fullName)")
        }
        for line in discussionsTableLines(discussions, useColor: self.output.useColor, includeURL: self.output.plain == false, now: Date()) {
            Swift.print(line)
        }
    }
}

@MainActor
struct TagsCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "tags"

    @Option(name: .customLong("limit"), help: "Max tags to fetch (default: 20)")
    var limit: Int = 20

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List recent tags")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one repository can be specified"))
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError(cliText("--limit must be greater than 0"))
        }
        let repo = try requireRepoIdentifier(self.repoName)

        let context = try await makeAuthenticatedClient()
        let tags = try await context.client.recentTags(owner: repo.owner, name: repo.name, limit: self.limit)

        if self.output.jsonOutput {
            let output = RepoTagsOutput(
                repo: repo.webURL(baseHost: context.host),
                count: tags.count,
                tags: tags.map(TagOutput.init)
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            cliPrint("Tags: \(repo.fullName)")
        }
        for line in tagsTableLines(tags, useColor: self.output.useColor, includeURL: self.output.plain == false) {
            Swift.print(line)
        }
    }
}

@MainActor
struct BranchesCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "branches"

    @Option(name: .customLong("limit"), help: "Max branches to fetch (default: 20)")
    var limit: Int = 20

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List recent branches")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one repository can be specified"))
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError(cliText("--limit must be greater than 0"))
        }
        let repo = try requireRepoIdentifier(self.repoName)

        let context = try await makeAuthenticatedClient()
        let branches = try await context.client.recentBranches(owner: repo.owner, name: repo.name, limit: self.limit)

        if self.output.jsonOutput {
            let output = RepoBranchesOutput(
                repo: repo.webURL(baseHost: context.host),
                count: branches.count,
                branches: branches.map(BranchOutput.init)
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            cliPrint("Branches: \(repo.fullName)")
        }
        for line in branchesTableLines(branches, useColor: self.output.useColor, includeURL: self.output.plain == false) {
            Swift.print(line)
        }
    }
}

@MainActor
struct ContributorsCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "contributors"

    @Option(name: .customLong("limit"), help: "Max contributors to fetch (default: 20)")
    var limit: Int = 20

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List top contributors")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one repository can be specified"))
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError(cliText("--limit must be greater than 0"))
        }
        let repo = try requireRepoIdentifier(self.repoName)

        let context = try await makeAuthenticatedClient()
        let contributors = try await context.client.topContributors(owner: repo.owner, name: repo.name, limit: self.limit)

        if self.output.jsonOutput {
            let output = RepoContributorsOutput(
                repo: repo.webURL(baseHost: context.host),
                count: contributors.count,
                contributors: contributors.map(ContributorOutput.init)
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            cliPrint("Contributors: \(repo.fullName)")
        }
        for line in contributorsTableLines(contributors, useColor: self.output.useColor, includeURL: self.output.plain == false) {
            Swift.print(line)
        }
    }
}

@MainActor
struct CommitsCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "commits"

    @Option(name: .customLong("limit"), help: "Max commits to fetch (default: 20)")
    var limit: Int = 20

    @Option(name: .customLong("login"), help: "GitHub login for global commits")
    var login: String?

    @Option(name: .customLong("scope"), help: "Activity scope (values: all, my)")
    var scope: GlobalActivityScope?

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List recent commits (repo or global)")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.login = try values.decodeOption("login")
        self.scope = try values.decodeOption("scope")
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one repository or login can be specified"))
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError(cliText("--limit must be greater than 0"))
        }
        let context = try await makeAuthenticatedClient()

        if let target, target.contains("/") {
            let repo = try parseRepoName(target)
            let commits = try await context.client.recentCommits(owner: repo.owner, name: repo.name, limit: self.limit)

            if self.output.jsonOutput {
                let output = RepoCommitsOutput(
                    repo: repo.webURL(baseHost: context.host),
                    count: commits.items.count,
                    totalCount: commits.totalCount,
                    commits: commits.items.map(CommitOutput.init)
                )
                try printJSON(output)
                return
            }

            if self.output.plain == false, self.output.useColor {
                cliPrint("Commits: \(repo.fullName)")
            }
            for line in commitsTableLines(commits.items, useColor: self.output.useColor, includeURL: self.output.plain == false, now: Date()) {
                Swift.print(line)
            }
            return
        }

        let scope = self.scope ?? context.settings.appearance.activityScope
        let login: String = if let resolved = self.login ?? target {
            resolved
        } else {
            try await context.client.currentUser().username
        }
        let commits = try await context.client.userCommitEvents(username: login, scope: scope, limit: self.limit)

        if self.output.jsonOutput {
            let output = GlobalCommitsOutput(
                login: login,
                scope: scope.rawValue,
                count: commits.count,
                commits: commits.map(CommitOutput.init)
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            cliPrint("Commits: \(login)")
        }
        for line in globalCommitsTableLines(commits, useColor: self.output.useColor, includeURL: self.output.plain == false, now: Date()) {
            Swift.print(line)
        }
    }
}

@MainActor
struct ActivityCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "activity"

    @Option(name: .customLong("limit"), help: "Max events to fetch (default: 20)")
    var limit: Int = 20

    @Option(name: .customLong("login"), help: "GitHub login for global activity")
    var login: String?

    @Option(name: .customLong("scope"), help: "Activity scope (values: all, my)")
    var scope: GlobalActivityScope?

    @Flag(names: [.customLong("include-repos")], help: "Merge cached repository activity like the menu profile submenu")
    var includeRepos: Bool = false

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List recent activity (repo or global)")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.limit = try values.decodeOption("limit") ?? 20
        self.login = try values.decodeOption("login")
        self.scope = try values.decodeOption("scope")
        self.includeRepos = values.flag("includeRepos")
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one repository or login can be specified"))
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        if self.limit <= 0 {
            throw ValidationError(cliText("--limit must be greater than 0"))
        }
        let context = try await makeAuthenticatedClient()

        if let target, target.contains("/") {
            if self.includeRepos {
                throw ValidationError(cliText("--include-repos is only available for global activity"))
            }
            let repoID = try parseRepoName(target)
            let repo = try await context.client.fullRepository(owner: repoID.owner, name: repoID.name)
            let events = Array(repo.activityEvents.prefix(self.limit))

            if self.output.jsonOutput {
                let output = RepoActivityOutput(
                    repo: repoID.webURL(baseHost: context.host),
                    count: events.count,
                    events: events
                )
                try printJSON(output)
                return
            }

            if self.output.plain == false, self.output.useColor {
                cliPrint("Activity: \(repoID.fullName)")
            }
            for line in activityTableLines(events, useColor: self.output.useColor, includeURL: self.output.plain == false, now: Date()) {
                Swift.print(line)
            }
            return
        }

        let scope = self.scope ?? context.settings.appearance.activityScope
        let login: String = if let resolved = self.login ?? target {
            resolved
        } else {
            try await context.client.currentUser().username
        }
        let userEvents = try await context.client.userActivityEvents(username: login, scope: scope, limit: self.limit)
        let events: [ActivityEvent]
        if self.includeRepos {
            let repositories = await (try? context.client.cachedRepositoryList(limit: nil)) ?? []
            events = GlobalActivityMerger.merge(
                userEvents: userEvents,
                repoEvents: GlobalActivityMerger.repositoryEvents(from: repositories),
                scope: scope,
                username: login,
                limit: self.limit
            )
        } else {
            events = userEvents
        }

        if self.output.jsonOutput {
            let output = GlobalActivityOutput(
                login: login,
                scope: scope.rawValue,
                count: events.count,
                events: events
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            cliPrint("Activity: \(login)")
        }
        let host = context.host
        for line in globalActivityTableLines(
            events,
            useColor: self.output.useColor,
            includeURL: self.output.plain == false,
            now: Date(),
            repoHost: host
        ) {
            Swift.print(line)
        }
    }
}

private struct RepoReleasesOutput: Encodable {
    let repo: URL
    let count: Int
    let releases: [ReleaseOutput]
}

private struct RepoWorkflowRunsOutput: Encodable {
    let repo: URL
    let count: Int
    let runs: [WorkflowRunOutput]
}

private struct RepoDiscussionsOutput: Encodable {
    let repo: URL
    let count: Int
    let discussions: [DiscussionOutput]
}

private struct RepoTagsOutput: Encodable {
    let repo: URL
    let count: Int
    let tags: [TagOutput]
}

private struct RepoBranchesOutput: Encodable {
    let repo: URL
    let count: Int
    let branches: [BranchOutput]
}

private struct RepoContributorsOutput: Encodable {
    let repo: URL
    let count: Int
    let contributors: [ContributorOutput]
}

private struct RepoCommitsOutput: Encodable {
    let repo: URL
    let count: Int
    let totalCount: Int?
    let commits: [CommitOutput]
}

private struct RepoActivityOutput: Encodable {
    let repo: URL
    let count: Int
    let events: [ActivityEvent]
}

private struct GlobalActivityOutput: Encodable {
    let login: String
    let scope: String
    let count: Int
    let events: [ActivityEvent]
}

private struct GlobalCommitsOutput: Encodable {
    let login: String
    let scope: String
    let count: Int
    let commits: [CommitOutput]
}
