import Commander
import Foundation
import RepoBarCore

@MainActor
struct ReferenceTranslateCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "reference-translate"

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var text: String?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Translate copied text into GitHub reference queries"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        self.text = values.positional.joined(separator: " ")
    }

    mutating func run() async throws {
        guard let text, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ValidationError(cliText("Missing reference text"))
        }

        let repositoryFullName = await GitHubReferenceLocalContext.repositoryFullName(in: text)
        let queries = GitHubReferenceTranslator.queries(
            from: text,
            repositoryContextOverride: repositoryFullName
        )
        let result = ReferenceTranslationOutput(input: text, queries: queries)
        if self.output.jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            if let json = String(data: data, encoding: .utf8) {
                Swift.print(json)
            }
            return
        }

        guard result.matched else {
            cliPrint("No GitHub reference")
            return
        }

        cliPrint("query: \(result.query ?? "-")")
        cliPrint("display: \(result.displayText ?? "-")")
        if let repositoryFullName = result.repositoryFullName {
            cliPrint("repo: \(repositoryFullName)")
        }
        if let repositoryName = result.repositoryName {
            cliPrint("repo-name: \(repositoryName)")
        }
        if let number = result.number {
            cliPrint("number: \(number)")
        }
        if let hash = result.hash {
            cliPrint("hash: \(hash)")
        }
        if let runID = result.runID {
            cliPrint("run: \(runID)")
        }
        if result.matches.count > 1 {
            cliPrint("matches: \(result.matches.count)")
            for match in result.matches {
                cliPrint("- \(match.displayText)")
            }
        }
    }
}

struct ReferenceTranslationOutput: Codable, Equatable {
    struct Match: Codable, Equatable {
        let query: String
        let displayText: String
        let repositoryFullName: String?
        let repositoryName: String?
        let number: Int?
        let hash: String?
        let runID: Int64?

        init(query: GitHubReferenceQuery) {
            self.query = ReferenceTranslationOutput.queryName(query)
            self.displayText = query.displayText
            self.repositoryFullName = query.repositoryFullName
            self.repositoryName = query.repositoryName
            self.number = ReferenceTranslationOutput.number(query)
            self.hash = ReferenceTranslationOutput.hash(query)
            self.runID = ReferenceTranslationOutput.runID(query)
        }
    }

    let input: String
    let matched: Bool
    let query: String?
    let displayText: String?
    let repositoryFullName: String?
    let repositoryName: String?
    let number: Int?
    let hash: String?
    let runID: Int64?
    let matches: [Match]

    init(input: String, query: GitHubReferenceQuery?) {
        self.init(input: input, queries: query.map { [$0] } ?? [])
    }

    init(input: String, queries: [GitHubReferenceQuery]) {
        self.input = input
        let primaryQuery = queries.first
        self.matched = primaryQuery != nil
        self.query = primaryQuery.map(Self.queryName)
        self.displayText = primaryQuery?.displayText
        self.repositoryFullName = primaryQuery?.repositoryFullName
        self.repositoryName = primaryQuery?.repositoryName
        self.number = primaryQuery.flatMap(Self.number)
        self.hash = primaryQuery.flatMap(Self.hash)
        self.runID = primaryQuery.flatMap(Self.runID)
        self.matches = queries.map(Match.init)
    }

    private static func queryName(_ query: GitHubReferenceQuery) -> String {
        switch query {
        case .issueNumber:
            "issueNumber"
        case .repositoryNameIssueNumber:
            "repositoryNameIssueNumber"
        case .repositoryIssueNumber:
            "repositoryIssueNumber"
        case .commitHash:
            "commitHash"
        case .repositoryCommitHash:
            "repositoryCommitHash"
        case .repositoryWorkflowRun:
            "repositoryWorkflowRun"
        }
    }

    private static func number(_ query: GitHubReferenceQuery) -> Int? {
        switch query {
        case let .issueNumber(number),
             let .repositoryNameIssueNumber(_, number),
             let .repositoryIssueNumber(_, number):
            number
        case .commitHash, .repositoryCommitHash, .repositoryWorkflowRun:
            nil
        }
    }

    private static func hash(_ query: GitHubReferenceQuery) -> String? {
        switch query {
        case .issueNumber, .repositoryNameIssueNumber, .repositoryIssueNumber, .repositoryWorkflowRun:
            nil
        case let .commitHash(hash), let .repositoryCommitHash(_, hash):
            hash
        }
    }

    private static func runID(_ query: GitHubReferenceQuery) -> Int64? {
        switch query {
        case .issueNumber, .repositoryNameIssueNumber, .repositoryIssueNumber, .commitHash, .repositoryCommitHash:
            nil
        case let .repositoryWorkflowRun(_, runID):
            runID
        }
    }
}
