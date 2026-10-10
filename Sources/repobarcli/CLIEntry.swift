import Commander
import Foundation
import RepoBarCore

@main
@MainActor
enum RepoBarCLI {
    static func main() async {
        let argv = CLIArgumentNormalizer.normalize(CommandLine.arguments)
        if let helpTarget = HelpTarget.from(argv: argv) {
            printHelp(helpTarget)
            return
        }

        do {
            let program = Program(descriptors: [RepoBarRoot.descriptor()])
            let invocation = try program.resolve(arguments: argv)
            var command = try makeCommand(from: invocation)
            try await command.run()
        } catch {
            self.handleError(error)
        }
    }

    static func makeCommand(from invocation: CommandInvocation) throws -> any CommanderRunnableCommand {
        guard let name = invocation.path.last else {
            throw CLIError.unknownCommand("repobar")
        }
        guard let type = commandRegistry[name] else {
            throw CLIError.unknownCommand(name)
        }

        var command = type.init()
        try command.bind(invocation.parsedValues)
        return command
    }

    private static let commandRegistry: [String: CommanderRunnableCommand.Type] = [
        ReposCommand.commandName: ReposCommand.self,
        RepoCommand.commandName: RepoCommand.self,
        IssuesCommand.commandName: IssuesCommand.self,
        PullsCommand.commandName: PullsCommand.self,
        ReleasesCommand.commandName: ReleasesCommand.self,
        CICommand.commandName: CICommand.self,
        DiscussionsCommand.commandName: DiscussionsCommand.self,
        TagsCommand.commandName: TagsCommand.self,
        BranchesCommand.commandName: BranchesCommand.self,
        ContributorsCommand.commandName: ContributorsCommand.self,
        CommitsCommand.commandName: CommitsCommand.self,
        ActivityCommand.commandName: ActivityCommand.self,
        LocalProjectsCommand.commandName: LocalProjectsCommand.self,
        LocalSyncCommand.commandName: LocalSyncCommand.self,
        LocalRebaseCommand.commandName: LocalRebaseCommand.self,
        LocalResetCommand.commandName: LocalResetCommand.self,
        LocalBranchesCommand.commandName: LocalBranchesCommand.self,
        WorktreesCommand.commandName: WorktreesCommand.self,
        OpenFinderCommand.commandName: OpenFinderCommand.self,
        OpenTerminalCommand.commandName: OpenTerminalCommand.self,
        CheckoutCommand.commandName: CheckoutCommand.self,
        RefreshCommand.commandName: RefreshCommand.self,
        ContributionsCommand.commandName: ContributionsCommand.self,
        ChangelogCommand.commandName: ChangelogCommand.self,
        MarkdownCommand.commandName: MarkdownCommand.self,
        PinCommand.commandName: PinCommand.self,
        UnpinCommand.commandName: UnpinCommand.self,
        HideCommand.commandName: HideCommand.self,
        ShowCommand.commandName: ShowCommand.self,
        ArchivesListCommand.commandName: ArchivesListCommand.self,
        ArchivesStatusCommand.commandName: ArchivesStatusCommand.self,
        ArchivesValidateCommand.commandName: ArchivesValidateCommand.self,
        ArchivesUpdateCommand.commandName: ArchivesUpdateCommand.self,
        ArchivesAddCommand.commandName: ArchivesAddCommand.self,
        ArchivesRemoveCommand.commandName: ArchivesRemoveCommand.self,
        ArchivesEnableCommand.commandName: ArchivesEnableCommand.self,
        ArchivesDisableCommand.commandName: ArchivesDisableCommand.self,
        RateLimitsCommand.commandName: RateLimitsCommand.self,
        ReferenceTranslateCommand.commandName: ReferenceTranslateCommand.self,
        CacheStatusCommand.commandName: CacheStatusCommand.self,
        CacheClearCommand.commandName: CacheClearCommand.self,
        SettingsShowCommand.commandName: SettingsShowCommand.self,
        SettingsSetCommand.commandName: SettingsSetCommand.self,
        LoginCommand.commandName: LoginCommand.self,
        LogoutCommand.commandName: LogoutCommand.self,
        ImportGHTokenCommand.commandName: ImportGHTokenCommand.self,
        StatusCommand.commandName: StatusCommand.self,
        AccountsListCommand.commandName: AccountsListCommand.self,
        AccountsUseCommand.commandName: AccountsUseCommand.self,
        AccountsRemoveCommand.commandName: AccountsRemoveCommand.self
    ]

    private static func handleError(_ error: Error) {
        let message: String = switch error {
        case let error as CLIError:
            error.message
        case let error as CommanderProgramError:
            error.description
        case let error as ValidationError:
            error.description
        default:
            error.userFacingMessage
        }
        printError(message)
        exit(1)
    }
}
