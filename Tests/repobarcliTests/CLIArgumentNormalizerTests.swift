import Commander
@testable import repobarcli
import RepoBarCore
import Testing

struct CLIArgumentNormalizerTests {
    @Test
    func `normalizes binary name to repobar`() {
        let argv = CLIArgumentNormalizer.normalize(["/Applications/RepoBar.app/Contents/MacOS/repobarcli", "status"])
        #expect(argv.first == RepoBarRoot.commandName)
        #expect(argv.dropFirst().first == "status")
    }

    @Test
    @MainActor
    func `normalized args resolve to status command`() throws {
        let argv = CLIArgumentNormalizer.normalize(["/Applications/RepoBar.app/Contents/MacOS/repobarcli", "status"])
        let program = Program(descriptors: [RepoBarRoot.descriptor()])
        let invocation = try program.resolve(arguments: argv)
        #expect(invocation.path.last == StatusCommand.commandName)
    }

    @Test
    @MainActor
    func `normalized empty invocation resolves to default repos command`() throws {
        let argv = CLIArgumentNormalizer.normalize(["/usr/local/bin/repobar"])
        let program = Program(descriptors: [RepoBarRoot.descriptor()])
        let invocation = try program.resolve(arguments: argv)
        #expect(invocation.path == [RepoBarRoot.commandName, ReposCommand.commandName])
    }

    @Test
    func `normalizes legacy aliases`() {
        #expect(CLIArgumentNormalizer.normalize(["repobar", "list"]).dropFirst().first == "repos")
        #expect(CLIArgumentNormalizer.normalize(["repobar", "pr"]).dropFirst().first == "pulls")
        #expect(CLIArgumentNormalizer.normalize(["repobar", "prs"]).dropFirst().first == "pulls")
        #expect(CLIArgumentNormalizer.normalize(["repobar", "runs"]).dropFirst().first == "ci")
    }

    @Test
    func `normalizes local subcommands`() {
        let syncArgs = CLIArgumentNormalizer.normalize(["repobar", "local", "sync", "RepoBar"])
        #expect(syncArgs[1] == "local-sync")
        #expect(syncArgs.dropFirst(2).first == "RepoBar")

        let branchesArgs = CLIArgumentNormalizer.normalize(["repobar", "local", "branches", "RepoBar"])
        #expect(branchesArgs[1] == "local-branches")

        let worktreesArgs = CLIArgumentNormalizer.normalize(["repobar", "local", "worktrees", "RepoBar"])
        #expect(worktreesArgs[1] == "worktrees")
    }

    @Test
    func `normalizes settings subcommands`() {
        let showArgs = CLIArgumentNormalizer.normalize(["repobar", "settings", "show"])
        #expect(showArgs[1] == "settings-show")

        let setArgs = CLIArgumentNormalizer.normalize(["repobar", "settings", "set", "refresh-interval", "5m"])
        #expect(setArgs[1] == "settings-set")
    }

    @Test
    func `normalizes account subcommands`() {
        let listArgs = CLIArgumentNormalizer.normalize(["repobar", "accounts", "list"])
        #expect(listArgs[1] == "accounts-list")

        let useArgs = CLIArgumentNormalizer.normalize(["repobar", "accounts", "use", "alice@github.com"])
        #expect(useArgs[1] == "accounts-use")
        #expect(useArgs.dropFirst(2).first == "alice@github.com")

        let removeArgs = CLIArgumentNormalizer.normalize(["repobar", "accounts", "remove", "github.com#alice"])
        #expect(removeArgs[1] == "accounts-remove")
        #expect(removeArgs.dropFirst(2).first == "github.com#alice")
    }

    @Test
    func `normalizes archive subcommands`() {
        let listArgs = CLIArgumentNormalizer.normalize(["repobar", "archives", "list"])
        #expect(listArgs[1] == "archives-list")

        let statusArgs = CLIArgumentNormalizer.normalize(["repobar", "archives", "status", "openclaw"])
        #expect(statusArgs[1] == "archives-status")
        #expect(statusArgs.dropFirst(2).first == "openclaw")

        let validateArgs = CLIArgumentNormalizer.normalize(["repobar", "archives", "validate"])
        #expect(validateArgs[1] == "archives-validate")

        let updateArgs = CLIArgumentNormalizer.normalize(["repobar", "archives", "update", "openclaw"])
        #expect(updateArgs[1] == "archives-update")
        #expect(updateArgs.dropFirst(2).first == "openclaw")

        let addArgs = CLIArgumentNormalizer.normalize(["repobar", "archives", "add", "openclaw", "--repo", "~/backup"])
        #expect(addArgs[1] == "archives-add")
        #expect(addArgs.dropFirst(2).first == "openclaw")
    }

    @Test
    func `normalizes cache subcommands`() {
        let statusArgs = CLIArgumentNormalizer.normalize(["repobar", "cache", "status"])
        #expect(statusArgs[1] == "cache-status")

        let clearArgs = CLIArgumentNormalizer.normalize(["repobar", "cache", "clear"])
        #expect(clearArgs[1] == "cache-clear")

        let rateLimitArgs = CLIArgumentNormalizer.normalize(["repobar", "cache", "rate-limits"])
        #expect(rateLimitArgs[1] == "rate-limits")

        let directArgs = CLIArgumentNormalizer.normalize(["repobar", "limits"])
        #expect(directArgs[1] == "rate-limits")
    }

    @Test
    @MainActor
    func `normalized archive args resolve`() throws {
        let argv = CLIArgumentNormalizer.normalize(["repobar", "archives", "list"])
        let program = Program(descriptors: [RepoBarRoot.descriptor()])
        let invocation = try program.resolve(arguments: argv)
        #expect(invocation.path.last == ArchivesListCommand.commandName)
    }

    @Test
    @MainActor
    func `normalized rate limit args resolve`() throws {
        let argv = CLIArgumentNormalizer.normalize(["repobar", "cache", "rate-limits"])
        let program = Program(descriptors: [RepoBarRoot.descriptor()])
        let invocation = try program.resolve(arguments: argv)
        #expect(invocation.path.last == RateLimitsCommand.commandName)
        #expect(try RepoBarCLI.makeCommand(from: invocation) is RateLimitsCommand)
    }

    @Test
    @MainActor
    func `normalized account args resolve`() throws {
        let argv = CLIArgumentNormalizer.normalize(["repobar", "accounts", "list"])
        let program = Program(descriptors: [RepoBarRoot.descriptor()])
        let invocation = try program.resolve(arguments: argv)
        #expect(invocation.path.last == AccountsListCommand.commandName)
        #expect(try RepoBarCLI.makeCommand(from: invocation) is AccountsListCommand)
    }

    @Test
    @MainActor
    func `archive add binds custom options`() throws {
        let argv = CLIArgumentNormalizer.normalize([
            "repobar",
            "archives",
            "add",
            "openclaw",
            "--repo",
            "/tmp/repo",
            "--remote",
            "https://github.com/example/archive.git",
            "--db",
            "/tmp/archive.sqlite"
        ])
        let program = Program(descriptors: [RepoBarRoot.descriptor()])
        let invocation = try program.resolve(arguments: argv)
        let command = try #require(RepoBarCLI.makeCommand(from: invocation) as? ArchivesAddCommand)

        #expect(command.repoPath == "/tmp/repo")
        #expect(command.remoteURL == "https://github.com/example/archive.git")
        #expect(command.databasePath == "/tmp/archive.sqlite")
    }

    @Test
    @MainActor
    func `archive add binds attached long option values`() throws {
        let argv = CLIArgumentNormalizer.normalize([
            "repobar", "archives", "add", "example", "--repo=/tmp/repo"
        ])
        let program = Program(descriptors: [RepoBarRoot.descriptor()])
        let invocation = try program.resolve(arguments: argv)
        let command = try #require(RepoBarCLI.makeCommand(from: invocation) as? ArchivesAddCommand)
        #expect(command.repoPath == "/tmp/repo")
    }

    @Test
    @MainActor
    func `commands without positional arguments reject stray input`() throws {
        let argv = CLIArgumentNormalizer.normalize(["repobar", "status", "unexpected"])
        let program = Program(descriptors: [RepoBarRoot.descriptor()])

        #expect(throws: CommanderProgramError.self) {
            _ = try program.resolve(arguments: argv)
        }
    }

    @Test
    func `normalizes open subcommands`() {
        let finderArgs = CLIArgumentNormalizer.normalize(["repobar", "open", "finder", "~/Projects"])
        #expect(finderArgs[1] == "open-finder")

        let terminalArgs = CLIArgumentNormalizer.normalize(["repobar", "open", "terminal", "~/Projects"])
        #expect(terminalArgs[1] == "open-terminal")
    }

    @Test
    func `help targets resolve nested command paths`() {
        #expect(HelpTarget.from(argv: ["repobar", "help", "archives", "add"]) == .archivesAdd)
        #expect(HelpTarget.from(argv: ["repobar", "help", "cache", "status"]) == .cacheStatus)
        #expect(HelpTarget.from(argv: ["repobar", "help", "settings", "set"]) == .settingsSet)
        #expect(HelpTarget.from(argv: ["repobar", "help", "local", "worktrees"]) == .worktrees)
    }

    @Test
    func `help targets resolve command aliases`() {
        #expect(HelpTarget.from(argv: ["repobar", "help", "pr"]) == .pulls)
        #expect(HelpTarget.from(argv: ["repobar", "help", "runs"]) == .ci)
        #expect(HelpTarget.from(argv: ["repobar", "help", "rate-limit"]) == .rateLimits)
    }
}
