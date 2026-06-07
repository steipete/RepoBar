import Commander
import Foundation
import RepoBarCore

@MainActor
struct PinCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "pin"

    @OptionGroup
    var output: OutputOptions

    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Pin a repository")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one repository can be specified")
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        let repoName = try requireRepoName(self.repoName)
        let normalized = try normalizeRepoFullName(repoName)
        let store = cliSettingsStore()
        var settings = store.load()

        settings.repoList.hiddenRepositories.removeAll { $0.equalsCaseInsensitive(normalized) }
        if settings.repoList.pinnedRepositories.contains(where: { $0.equalsCaseInsensitive(normalized) }) == false {
            settings.repoList.pinnedRepositories.append(normalized)
        }
        store.save(settings)

        try renderRepoListUpdate(
            action: "Pinned",
            repoName: normalized,
            settings: settings,
            output: self.output
        )
    }
}

@MainActor
struct UnpinCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "unpin"

    @OptionGroup
    var output: OutputOptions

    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Unpin a repository")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one repository can be specified")
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        let repoName = try requireRepoName(self.repoName)
        let normalized = try normalizeRepoFullName(repoName)
        let store = cliSettingsStore()
        var settings = store.load()

        settings.repoList.pinnedRepositories.removeAll { $0.equalsCaseInsensitive(normalized) }
        store.save(settings)

        try renderRepoListUpdate(
            action: "Unpinned",
            repoName: normalized,
            settings: settings,
            output: self.output
        )
    }
}

@MainActor
struct HideCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "hide"

    @OptionGroup
    var output: OutputOptions

    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Hide a repository")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one repository can be specified")
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        let repoName = try requireRepoName(self.repoName)
        let normalized = try normalizeRepoFullName(repoName)
        let store = cliSettingsStore()
        var settings = store.load()

        settings.repoList.pinnedRepositories.removeAll { $0.equalsCaseInsensitive(normalized) }
        if settings.repoList.hiddenRepositories.contains(where: { $0.equalsCaseInsensitive(normalized) }) == false {
            settings.repoList.hiddenRepositories.append(normalized)
        }
        store.save(settings)

        try renderRepoListUpdate(
            action: "Hidden",
            repoName: normalized,
            settings: settings,
            output: self.output
        )
    }
}

@MainActor
struct ShowCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "show"

    @OptionGroup
    var output: OutputOptions

    private var repoName: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Show a hidden repository")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 1 {
            throw ValidationError("Only one repository can be specified")
        }
        self.repoName = values.positional.first
    }

    mutating func run() async throws {
        let repoName = try requireRepoName(self.repoName)
        let normalized = try normalizeRepoFullName(repoName)
        let store = cliSettingsStore()
        var settings = store.load()

        settings.repoList.hiddenRepositories.removeAll { $0.equalsCaseInsensitive(normalized) }
        store.save(settings)

        try renderRepoListUpdate(
            action: "Shown",
            repoName: normalized,
            settings: settings,
            output: self.output
        )
    }
}

@MainActor
struct SettingsShowCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "settings-show"

    @OptionGroup
    var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Show current settings")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
    }

    mutating func run() async throws {
        var settings = cliSettingsStore().load()
        settings.menuCustomization.normalize()
        if self.output.jsonOutput {
            try printJSON(settings)
            return
        }

        for line in settingsSummaryLines(settings: settings) {
            print(line)
        }
    }
}

@MainActor
struct SettingsSetCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "settings-set"

    @OptionGroup
    var output: OutputOptions

    private var key: String?
    private var value: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Update a settings value")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        if values.positional.count > 2 {
            throw ValidationError("Expected a setting key and value")
        }
        self.key = values.positional.first
        self.value = values.positional.dropFirst().first
    }

    mutating func run() async throws {
        guard let key, key.isEmpty == false else {
            throw ValidationError("Missing settings key")
        }
        guard let value, value.isEmpty == false else {
            throw ValidationError("Missing settings value")
        }
        guard let settingKey = SettingsKey(argument: key) else {
            throw ValidationError("Unknown settings key: \(key)")
        }

        let store = cliSettingsStore()
        var settings = store.load()
        let summary = try applySetting(settingKey, value: value, settings: &settings)
        store.save(settings)

        if self.output.jsonOutput {
            try printJSON(settings)
            return
        }

        print("Updated \(settingKey.rawValue): \(summary)")
    }
}
