import Commander
import Foundation
import RepoBarCore

/// Shared resolver used by every `accounts` subcommand and by `--account`
/// flags on other commands.
enum AccountResolver {
    /// Returns the matching `Account` for the given input.
    ///
    /// `input` may be either a full account ID (`github.com#alice`) or a
    /// `username@host` shorthand (`alice@github.com`). When `input` is `nil`
    /// the active account is returned, then the only configured account as a
    /// fallback. Otherwise a `ValidationError` describes the next user step.
    static func resolve(_ input: String?, settings: UserSettings) throws -> Account {
        if let input, input.isEmpty == false {
            if let direct = settings.accounts.first(where: { $0.id == input }) {
                return direct
            }
            if let shorthand = Self.matchShorthand(input, in: settings.accounts) {
                return shorthand
            }
            throw ValidationError("Unknown account: \(input). Run `repobar accounts list` to see configured accounts.")
        }
        if let active = settings.resolvedActiveAccount() {
            return active
        }
        if settings.accounts.isEmpty {
            throw ValidationError("No accounts configured. Run `repobar login` first.")
        }
        throw ValidationError("Multiple accounts configured. Pass --account <id> or run `repobar accounts use <id>`.")
    }

    static func matchShorthand(_ input: String, in accounts: [Account]) -> Account? {
        guard let at = input.firstIndex(of: "@") else { return nil }

        let user = input[..<at].lowercased()
        let host = input[input.index(after: at)...].lowercased()
        return accounts.first(where: {
            $0.username.lowercased() == user && Account.hostAuthority(for: $0.host) == host
        })
    }
}

@MainActor
struct AccountsListCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "accounts-list"

    @OptionGroup var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "List configured accounts")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
    }

    mutating func run() async throws {
        let settings = cliSettingsStore().load()
        let activeAccountID = settings.resolvedActiveAccount()?.id
        if self.output.jsonOutput {
            let payload = AccountListOutput(
                activeAccountID: activeAccountID,
                accounts: settings.accounts.map { AccountSummary(from: $0, active: $0.id == activeAccountID) }
            )
            try printJSON(payload)
            return
        }

        if settings.accounts.isEmpty {
            print("No accounts configured. Run `repobar login` first.")
            return
        }
        for account in settings.accounts {
            let marker = account.id == activeAccountID ? "*" : " "
            let method = account.authMethod.rawValue
            print("\(marker) \(account.id)  [\(method)]  \(account.host.host ?? "github.com")")
        }
    }
}

@MainActor
struct AccountsUseCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "accounts-use"

    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Set the active account (accepts <accountID> or username@host)")
    }

    mutating func bind(_ values: ParsedValues) throws {
        if values.positional.count > 1 {
            throw ValidationError("Only one account identifier can be specified")
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        let store = cliSettingsStore()
        var settings = store.load()
        let account = try AccountResolver.resolve(self.target, settings: settings)
        try mirrorAccountCredentialsToLegacy(account)
        settings.activeAccountID = account.id
        mirrorActiveAccountIntoSettings(account, settings: &settings)
        store.save(settings)
        print("Active account set to \(account.id).")
    }
}

@MainActor
struct AccountsRemoveCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "accounts-remove"

    private var target: String?

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Remove an account and its stored credentials")
    }

    mutating func bind(_ values: ParsedValues) throws {
        if values.positional.count > 1 {
            throw ValidationError("Only one account identifier can be specified")
        }
        self.target = values.positional.first
    }

    mutating func run() async throws {
        let store = cliSettingsStore()
        var settings = store.load()
        let account = try AccountResolver.resolve(self.target, settings: settings)
        TokenStore.shared.clear(accountID: account.id)
        settings.accounts.removeAll(where: { $0.id == account.id })
        if settings.activeAccountID == account.id {
            settings.activeAccountID = settings.accounts.first?.id
        }
        mirrorResolvedActiveAccount(settings: &settings)
        settings.accountRepoLists.pinnedByAccount.removeValue(forKey: account.id)
        settings.accountRepoLists.hiddenByAccount.removeValue(forKey: account.id)
        store.save(settings)
        print("Removed account \(account.id).")
    }
}

// MARK: - JSON payloads

struct AccountSummary: Encodable {
    let id: String
    let username: String
    let host: String
    let apiHost: String
    let authMethod: String
    let active: Bool

    init(from account: Account, active: Bool) {
        self.id = account.id
        self.username = account.username
        self.host = account.host.absoluteString
        self.apiHost = account.apiHost.absoluteString
        self.authMethod = account.authMethod.rawValue
        self.active = active
    }
}

struct AccountListOutput: Encodable {
    let activeAccountID: String?
    let accounts: [AccountSummary]
}
