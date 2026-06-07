import Commander
import Foundation
import RepoBarCore

@MainActor
struct ArchivesListCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "archives-list"

    @OptionGroup
    var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List configured GitHub archives")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
    }

    mutating func run() async throws {
        let settings = cliSettingsStore().load()
        if self.output.jsonOutput {
            try printJSON(settings.githubArchives)
            return
        }

        let sources = settings.githubArchives.sources
        if sources.isEmpty {
            print("No GitHub archives configured.")
            return
        }

        for source in sources {
            let state = source.enabled ? "enabled" : "disabled"
            let repo = source.localRepositoryPath.map(PathFormatter.displayString) ?? "-"
            let remote = source.remoteURL ?? "-"
            let db = PathFormatter.displayString(source.importedDatabasePath)
            print("\(source.name) (\(state))")
            print("  repo: \(repo)")
            print("  remote: \(remote)")
            print("  branch: \(source.branch)")
            print("  db: \(db)")
        }
    }
}

@MainActor
struct ArchivesStatusCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "archives-status"

    @OptionGroup
    var output: OutputOptions

    private var name: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Show GitHub archive source status")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one archive name can be specified")
        }
        self.name = values.positional.first
    }

    mutating func run() async throws {
        let settings = cliSettingsStore().load()
        let statuses = try GitHubArchiveStore.statuses(settings: settings.githubArchives, name: self.name)
        let payload = GitHubArchiveStatusOutput(sources: statuses)
        if self.output.jsonOutput {
            try printJSON(payload)
            return
        }

        if statuses.isEmpty {
            print("No GitHub archives configured.")
            return
        }
        for status in statuses {
            print("\(status.name): \(status.readyForRead ? "ready" : "not ready")")
            print("  enabled: \(status.enabled ? "yes" : "no")")
            print("  repo: \(status.localRepositoryPath ?? "-")")
            print("  manifest: \(status.manifestExists ? "yes" : "no")")
            print("  db: \(status.databaseExists ? "yes" : "no")")
            if let importedRowCount = status.importedRowCount {
                print("  rows: \(importedRowCount)")
            }
            if let lastImportAt = status.lastImportAt {
                print("  last import: \(GitHubArchiveStore.archiveDateString(lastImportAt))")
            }
            if status.issues.isEmpty == false {
                print("  issues: \(status.issues.joined(separator: "; "))")
            }
        }
    }
}

@MainActor
struct ArchivesValidateCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "archives-validate"

    @OptionGroup
    var output: OutputOptions

    private var name: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Validate GitHub archive sources")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one archive name can be specified")
        }
        self.name = values.positional.first
    }

    mutating func run() async throws {
        let settings = cliSettingsStore().load()
        let statuses = try GitHubArchiveStore.statuses(settings: settings.githubArchives, name: self.name)
        let payload = GitHubArchiveStatusOutput(sources: statuses)
        if self.output.jsonOutput {
            try printJSON(payload)
        } else if statuses.isEmpty {
            print("No GitHub archives configured.")
        } else {
            for status in statuses {
                print("\(status.name): \(status.configValid ? "valid" : "invalid")")
            }
        }

        let invalid = statuses.filter { !$0.configValid }
        if invalid.isEmpty == false {
            let names = invalid.map(\.name).joined(separator: ", ")
            throw ValidationError("Invalid archive configuration: \(names)")
        }
    }
}

@MainActor
struct ArchivesUpdateCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "archives-update"

    @OptionGroup
    var output: OutputOptions

    private var name: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Pull and import a GitHub archive snapshot")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one archive name can be specified")
        }
        self.name = values.positional.first
    }

    mutating func run() async throws {
        let name = try GitHubArchiveStore.requireName(self.name)
        let store = cliSettingsStore()
        var settings = store.load()
        guard let index = settings.githubArchives.sources.firstIndex(where: { $0.name.equalsCaseInsensitive(name) || $0.id == name }) else {
            throw ValidationError("Archive not found: \(name)")
        }

        let update = try GitHubArchiveStore.update(source: settings.githubArchives.sources[index])
        if update.source != settings.githubArchives.sources[index] {
            settings.githubArchives.sources[index] = update.source
            store.save(settings)
        }

        let result = update.importResult

        if self.output.jsonOutput {
            try printJSON(update)
            return
        }

        print("Updated archive \(update.source.name)")
        print("repo: \(PathFormatter.displayString(result.snapshotPath))")
        print("db: \(PathFormatter.displayString(result.databasePath))")
        print("tables: \(result.tables.count)")
        print("rows: \(result.totalRows)")
        if let generatedAt = result.generatedAt {
            print("snapshot: \(GitHubArchiveStore.archiveDateString(generatedAt))")
        }
    }
}

@MainActor
struct ArchivesAddCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "archives-add"

    @Option(name: .customLong("repo"), help: "Repository shorthand, remote URL, or local Git snapshot repository path")
    var repoPath: String?

    @Option(name: .customLong("remote"), help: "Git snapshot remote URL")
    var remoteURL: String?

    @Option(name: .customLong("branch"), help: "Git snapshot branch")
    var branch: String = "main"

    @Option(name: .customLong("db"), help: "Imported SQLite database path")
    var databasePath: String?

    @OptionGroup
    var output: OutputOptions

    private var repository: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Add a GitHub archive source")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one archive repository can be specified")
        }
        self.repository = values.positional.first
        self.repoPath = try values.decodeOption("repoPath") ?? values.decodeOption("repo")
        self.remoteURL = try values.decodeOption("remoteURL") ?? values.decodeOption("remote")
        self.branch = try values.decodeOption("branch") ?? "main"
        self.databasePath = try values.decodeOption("databasePath") ?? values.decodeOption("db")
    }

    mutating func run() async throws {
        let store = cliSettingsStore()
        var settings = store.load()
        let source = try Self.archiveSource(
            repository: self.repository,
            repoPath: self.repoPath,
            remoteURL: self.remoteURL,
            branch: self.branch,
            databasePath: self.databasePath
        )
        if settings.githubArchives.sources.contains(where: { $0.name.equalsCaseInsensitive(source.name) }) {
            throw ValidationError("Archive already exists: \(source.name)")
        }
        if settings.githubArchives.sources.contains(where: { GitHubArchiveStore.sameArchiveLocation($0, source) }) {
            throw ValidationError("Archive source already exists for this repository")
        }

        settings.githubArchives.sources.append(source)
        store.save(settings)
        try self.render(action: "Added", source: source, settings: settings)
    }

    private func render(action: String, source: GitHubArchiveSource, settings: UserSettings) throws {
        if self.output.jsonOutput {
            try printJSON(settings.githubArchives)
            return
        }

        print("\(action) archive \(source.name)")
        print("db: \(PathFormatter.displayString(source.importedDatabasePath))")
    }

    nonisolated static func archiveSource(
        repository: String?,
        repoPath: String?,
        remoteURL: String?,
        branch: String,
        databasePath: String?,
        fileManager: FileManager = .default
    ) throws -> GitHubArchiveSource {
        let sourceText = repository?.trimmingCharacters(in: .whitespacesAndNewlines)
        let repoText = repoPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteText = remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasExplicitLocation = repoText?.isEmpty == false || remoteText?.isEmpty == false
        let baseRepository = (hasExplicitLocation ? [remoteText, repoText] : [sourceText])
            .compactMap { value in value?.isEmpty == false ? value : nil }
            .first
        guard let baseRepository else {
            throw ValidationError("Missing archive repository")
        }
        guard var source = GitHubArchiveStore.source(repository: baseRepository) else {
            throw ValidationError("Invalid archive repository: \(baseRepository)")
        }

        let usesCustomName = hasExplicitLocation && sourceText?.isEmpty == false
        if usesCustomName, let sourceText {
            source.name = sourceText
        }

        if let repoText, repoText.isEmpty == false {
            if remoteText?.isEmpty == false || GitHubArchiveStore.normalizedRemoteURL(repository: repoText) == nil {
                source.localRepositoryPath = PathFormatter.expandTilde(repoText)
            }
        }
        if let remoteText, remoteText.isEmpty == false {
            source.remoteURL = try self.validatedRemote(remoteText)
        }
        source.branch = branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : branch
        if let databasePath, databasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            source.importedDatabasePath = PathFormatter.expandTilde(databasePath)
        } else if usesCustomName {
            source.importedDatabasePath = GitHubArchiveStore.defaultDatabasePath(
                name: source.name,
                repositoryIdentifier: source.remoteURL ?? source.localRepositoryPath
            )
        }

        if let localRepositoryPath = source.localRepositoryPath {
            try self.validateLocalRepositoryPath(
                localRepositoryPath,
                allowRemoteCloneTarget: source.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                fileManager: fileManager
            )
        }
        if let remoteURL = source.remoteURL {
            _ = try self.validatedRemote(remoteURL)
        }
        return source
    }

    private nonisolated static func validateLocalRepositoryPath(
        _ path: String,
        allowRemoteCloneTarget: Bool,
        fileManager: FileManager
    ) throws {
        let expanded = PathFormatter.expandTilde(path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
            if allowRemoteCloneTarget {
                return
            }
            throw ValidationError("Archive repository path does not exist: \(PathFormatter.displayString(expanded))")
        }

        let gitPath = URL(fileURLWithPath: expanded).appending(path: ".git").path
        guard allowRemoteCloneTarget || fileManager.fileExists(atPath: gitPath) else {
            throw ValidationError("Archive repository path is not a Git working tree: \(PathFormatter.displayString(expanded))")
        }
    }

    private nonisolated static func validatedRemote(_ remote: String) throws -> String {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ValidationError("Archive remote URL is empty")
        }

        if trimmed.hasPrefix("git@"), trimmed.contains(":") {
            return trimmed
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["https", "http", "ssh", "git"].contains(scheme),
              url.host?.isEmpty == false
        else {
            throw ValidationError("Invalid archive remote URL: \(remote)")
        }

        return trimmed
    }
}

@MainActor
struct ArchivesRemoveCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "archives-remove"

    @OptionGroup
    var output: OutputOptions

    private var name: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Remove a GitHub archive source")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one archive name can be specified")
        }
        self.name = values.positional.first
    }

    mutating func run() async throws {
        let name = try GitHubArchiveStore.requireName(self.name)
        let store = cliSettingsStore()
        var settings = store.load()
        let before = settings.githubArchives.sources.count
        settings.githubArchives.sources.removeAll { $0.name.equalsCaseInsensitive(name) || $0.id == name }
        guard settings.githubArchives.sources.count != before else {
            throw ValidationError("Archive not found: \(name)")
        }

        store.save(settings)
        if self.output.jsonOutput {
            try printJSON(settings.githubArchives)
        } else {
            print("Removed archive \(name)")
        }
    }
}

@MainActor
struct ArchivesEnableCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "archives-enable"

    @OptionGroup
    var output: OutputOptions

    private var name: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Enable a GitHub archive source")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one archive name can be specified")
        }
        self.name = values.positional.first
    }

    mutating func run() async throws {
        try self.update(enabled: true)
    }

    private func update(enabled: Bool) throws {
        let name = try GitHubArchiveStore.requireName(self.name)
        let store = cliSettingsStore()
        var settings = store.load()
        guard let index = settings.githubArchives.sources.firstIndex(where: { $0.name.equalsCaseInsensitive(name) || $0.id == name }) else {
            throw ValidationError("Archive not found: \(name)")
        }

        settings.githubArchives.sources[index].enabled = enabled
        store.save(settings)
        if self.output.jsonOutput {
            try printJSON(settings.githubArchives)
        } else {
            print("\(enabled ? "Enabled" : "Disabled") archive \(settings.githubArchives.sources[index].name)")
        }
    }
}

@MainActor
struct ArchivesDisableCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "archives-disable"

    @OptionGroup
    var output: OutputOptions

    private var name: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Disable a GitHub archive source")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one archive name can be specified")
        }
        self.name = values.positional.first
    }

    mutating func run() async throws {
        let name = try GitHubArchiveStore.requireName(self.name)
        let store = cliSettingsStore()
        var settings = store.load()
        guard let index = settings.githubArchives.sources.firstIndex(where: { $0.name.equalsCaseInsensitive(name) || $0.id == name }) else {
            throw ValidationError("Archive not found: \(name)")
        }

        settings.githubArchives.sources[index].enabled = false
        store.save(settings)
        if self.output.jsonOutput {
            try printJSON(settings.githubArchives)
        } else {
            print("Disabled archive \(settings.githubArchives.sources[index].name)")
        }
    }
}
