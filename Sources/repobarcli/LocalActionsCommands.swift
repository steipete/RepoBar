import Commander
import Foundation
import RepoBarCore

@MainActor
struct LocalSyncCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "local-sync"

    @OptionGroup
    var output: OutputOptions

    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Sync a local repository (fetch/rebase/push)")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one repository or path can be specified")
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        let target = try requireLocalTarget(self.target)
        let settings = cliSettingsStore().load()
        let resolved = try await resolveLocalRepoTarget(target, settings: settings)
        let result = try LocalGitService().smartSync(at: resolved.path)

        if self.output.jsonOutput {
            let output = LocalActionOutput(
                action: "sync",
                path: resolved.path.path,
                fullName: resolved.status?.fullName,
                success: true,
                didFetch: result.didFetch,
                didPull: result.didPull,
                didPush: result.didPush
            )
            try printJSON(output)
            return
        }

        let display = resolved.displayName
        print("Synced \(display)")
        print("Fetch: \(result.didFetch ? "yes" : "no")")
        print("Pull: \(result.didPull ? "yes" : "no")")
        print("Push: \(result.didPush ? "yes" : "no")")
    }
}

@MainActor
struct LocalRebaseCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "local-rebase"

    @OptionGroup
    var output: OutputOptions

    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Rebase a local repository onto upstream")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one repository or path can be specified")
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        let target = try requireLocalTarget(self.target)
        let settings = cliSettingsStore().load()
        let resolved = try await resolveLocalRepoTarget(target, settings: settings)
        try LocalGitService().rebaseOntoUpstream(at: resolved.path)

        if self.output.jsonOutput {
            let output = LocalActionOutput(
                action: "rebase",
                path: resolved.path.path,
                fullName: resolved.status?.fullName,
                success: true,
                didFetch: nil,
                didPull: nil,
                didPush: nil
            )
            try printJSON(output)
            return
        }

        print("Rebased \(resolved.displayName)")
    }
}

@MainActor
struct LocalResetCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "local-reset"

    @Flag(names: [.customLong("yes")], help: "Skip confirmation prompt")
    var assumeYes: Bool = false

    @OptionGroup
    var output: OutputOptions

    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Hard reset a local repository to upstream")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        self.assumeYes = values.flag("yes")
        if values.positional.count > 1 {
            throw ValidationError("Only one repository or path can be specified")
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        let target = try requireLocalTarget(self.target)
        let settings = cliSettingsStore().load()
        let resolved = try await resolveLocalRepoTarget(target, settings: settings)

        if self.assumeYes == false {
            try confirmHardReset(path: resolved.displayName)
        }

        try LocalGitService().hardResetToUpstream(at: resolved.path)

        if self.output.jsonOutput {
            let output = LocalActionOutput(
                action: "reset",
                path: resolved.path.path,
                fullName: resolved.status?.fullName,
                success: true,
                didFetch: nil,
                didPull: nil,
                didPush: nil
            )
            try printJSON(output)
            return
        }

        print("Reset \(resolved.displayName)")
    }
}

@MainActor
struct LocalBranchesCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "local-branches"

    @OptionGroup
    var output: OutputOptions

    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List local branches")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one repository or path can be specified")
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        let target = try requireLocalTarget(self.target)
        let settings = cliSettingsStore().load()
        let resolved = try await resolveLocalRepoTarget(target, settings: settings)
        let snapshot = try LocalGitService().branchDetails(at: resolved.path)

        if self.output.jsonOutput {
            let output = LocalBranchesOutput(
                path: resolved.path.path,
                fullName: resolved.status?.fullName,
                detached: snapshot.isDetachedHead,
                branches: snapshot.branches.map(LocalBranchOutput.init)
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            print("Branches: \(resolved.displayName)")
        }
        for line in localBranchesTableLines(snapshot, useColor: self.output.useColor, now: Date()) {
            print(line)
        }
    }
}

@MainActor
struct WorktreesCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "worktrees"

    @OptionGroup
    var output: OutputOptions

    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List local worktrees")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one repository or path can be specified")
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        let target = try requireLocalTarget(self.target)
        let settings = cliSettingsStore().load()
        let resolved = try await resolveLocalRepoTarget(target, settings: settings)
        let worktrees = try LocalGitService().worktrees(at: resolved.path)

        if self.output.jsonOutput {
            let output = LocalWorktreesOutput(
                path: resolved.path.path,
                fullName: resolved.status?.fullName,
                worktrees: worktrees.map(LocalWorktreeOutput.init)
            )
            try printJSON(output)
            return
        }

        if self.output.plain == false, self.output.useColor {
            print("Worktrees: \(resolved.displayName)")
        }
        for line in localWorktreesTableLines(worktrees, useColor: self.output.useColor, now: Date()) {
            print(line)
        }
    }
}

@MainActor
struct OpenFinderCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "open-finder"

    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Open a local repository in Finder")
    }

    mutating func bind(_ values: ParsedValues) throws {
        if values.positional.count > 1 {
            throw ValidationError("Only one repository or path can be specified")
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        let target = try requireLocalTarget(self.target)
        let settings = cliSettingsStore().load()
        let resolved = try await resolveLocalRepoTarget(target, settings: settings)
        try openPath(resolved.path.path)
        print("Opened Finder at \(resolved.displayName)")
    }
}

@MainActor
struct OpenTerminalCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "open-terminal"

    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Open a local repository in Terminal")
    }

    mutating func bind(_ values: ParsedValues) throws {
        if values.positional.count > 1 {
            throw ValidationError("Only one repository or path can be specified")
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        let target = try requireLocalTarget(self.target)
        let settings = cliSettingsStore().load()
        let resolved = try await resolveLocalRepoTarget(target, settings: settings)
        try openTerminal(at: resolved.path, settings: settings)
        print("Opened terminal at \(resolved.displayName)")
    }
}

@MainActor
struct CheckoutCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "checkout"

    @Option(name: .customLong("root"), help: "Root folder to clone into (defaults to Local Projects root)")
    var root: String?

    @Option(name: .customLong("destination"), help: "Explicit destination folder")
    var destination: String?

    @Flag(names: [.customLong("open")], help: "Open Finder after checkout")
    var openAfter: Bool = false

    @OptionGroup
    var output: OutputOptions

    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Clone a repository into the local projects folder")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        self.root = try values.decodeOption("root")
        self.destination = try values.decodeOption("destination")
        self.openAfter = values.flag("open")
        if values.positional.count > 1 {
            throw ValidationError("Only one repository can be specified")
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        let repo = try requireRepoIdentifier(self.repoName)
        let settingsStore = cliSettingsStore()
        var settings = settingsStore.load()
        let host = settings.enterpriseHost ?? settings.githubHost

        let rootPath = self.destination == nil ? (self.root ?? settings.localProjects.rootPath) : nil
        if self.destination == nil, rootPath?.isEmpty ?? true {
            throw ValidationError("Set a Local Projects root in Settings or pass --root")
        }

        let destinationURL: URL
        if let destination {
            destinationURL = URL(fileURLWithPath: PathFormatter.expandTilde(destination), isDirectory: true)
        } else {
            let expandedRoot = PathFormatter.expandTilde(rootPath ?? "")
            let rootURL = URL(fileURLWithPath: expandedRoot, isDirectory: true)
            destinationURL = rootURL.appendingPathComponent(repo.name, isDirectory: true)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            throw ValidationError("Destination already exists: \(PathFormatter.displayString(destinationURL.path))")
        }

        var remoteURL = host.appendingPathComponent(repo.fullName)
        remoteURL.appendPathExtension("git")

        try LocalGitService().cloneRepo(remoteURL: remoteURL, to: destinationURL)

        settings.localProjects.preferredLocalPathsByFullName[repo.fullName] = destinationURL.path
        settingsStore.save(settings)

        if self.openAfter {
            try openPath(destinationURL.path)
        }

        if self.output.jsonOutput {
            let output = CheckoutOutput(
                repo: repo.fullName,
                destination: destinationURL.path,
                opened: self.openAfter
            )
            try printJSON(output)
            return
        }

        print("Checked out \(repo.fullName) → \(PathFormatter.displayString(destinationURL.path))")
    }
}
