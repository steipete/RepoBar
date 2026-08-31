import Commander
@testable import repobarcli
import Testing

struct CLIParsingTests {
    @Test
    func `parse repo name splits owner and name`() throws {
        let result = try parseRepoName("steipete/RepoBar")
        #expect(result.owner == "steipete")
        #expect(result.name == "RepoBar")
    }

    @Test
    func `parse repo name trims whitespace and git suffix`() throws {
        let result = try parseRepoName("  steipete/RepoBar.git  ")
        #expect(result.owner == "steipete")
        #expect(result.name == "RepoBar")
    }

    @Test
    func `parse repo name accepts GitHub HTTPS URLs`() throws {
        let result = try parseRepoName("https://github.com/steipete/RepoBar")
        #expect(result.owner == "steipete")
        #expect(result.name == "RepoBar")
    }

    @Test
    func `parse repo name accepts GitHub URL subpages`() throws {
        let result = try parseRepoName("https://github.com/steipete/RepoBar/issues/1")
        #expect(result.owner == "steipete")
        #expect(result.name == "RepoBar")
    }

    @Test
    func `parse repo name accepts SSH remotes`() throws {
        let result = try parseRepoName("git@github.com:steipete/RepoBar.git")
        #expect(result.owner == "steipete")
        #expect(result.name == "RepoBar")
    }

    @Test
    func `parse repo name rejects missing slash`() {
        #expect(throws: ValidationError.self) {
            _ = try parseRepoName("RepoBar")
        }
    }

    @Test
    func `parse repo name rejects extra raw path components`() {
        #expect(throws: ValidationError.self) {
            _ = try parseRepoName("steipete/RepoBar/issues/1")
        }
    }

    @Test
    @MainActor
    func test_localResetYesFlagBindsAssumeYes() throws {
        let defaultCommand = try parseCommand(LocalResetCommand.self, arguments: ["local-reset"])
        let flaggedCommand = try parseCommand(LocalResetCommand.self, arguments: ["local-reset", "--yes"])

        #expect(defaultCommand.assumeYes == false)
        #expect(flaggedCommand.assumeYes)
    }

    @Test
    @MainActor
    func test_checkoutOpenFlagBindsOpenAfter() throws {
        let defaultCommand = try parseCommand(CheckoutCommand.self, arguments: ["checkout"])
        let flaggedCommand = try parseCommand(CheckoutCommand.self, arguments: ["checkout", "--open"])

        #expect(defaultCommand.openAfter == false)
        #expect(flaggedCommand.openAfter)
    }

    @Test
    @MainActor
    func test_repoTrafficFlagBindsIncludeTraffic() throws {
        let defaultCommand = try parseCommand(RepoCommand.self, arguments: ["repo"])
        let flaggedCommand = try parseCommand(RepoCommand.self, arguments: ["repo", "--traffic"])

        #expect(defaultCommand.includeTraffic == false)
        #expect(flaggedCommand.includeTraffic)
    }

    @Test
    @MainActor
    func test_repoHeatmapFlagBindsIncludeHeatmap() throws {
        let defaultCommand = try parseCommand(RepoCommand.self, arguments: ["repo"])
        let flaggedCommand = try parseCommand(RepoCommand.self, arguments: ["repo", "--heatmap"])

        #expect(defaultCommand.includeHeatmap == false)
        #expect(flaggedCommand.includeHeatmap)
    }

    @Test
    @MainActor
    func test_repoReleaseFlagBindsIncludeRelease() throws {
        let defaultCommand = try parseCommand(RepoCommand.self, arguments: ["repo"])
        let flaggedCommand = try parseCommand(RepoCommand.self, arguments: ["repo", "--release"])

        #expect(defaultCommand.includeRelease == false)
        #expect(flaggedCommand.includeRelease)
    }
}

@MainActor
private func parseCommand<T: CommanderRunnableCommand>(
    _: T.Type,
    arguments: [String]
) throws -> T {
    let argv = CLIArgumentNormalizer.normalize(["repobar"] + arguments)
    let program = Program(descriptors: [RepoBarRoot.descriptor()])
    let invocation = try program.resolve(argv: argv)
    return try #require(RepoBarCLI.makeCommand(from: invocation) as? T)
}
