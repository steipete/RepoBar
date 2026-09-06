import Commander
import Foundation
import RepoBarCore

@MainActor
struct CacheStatusCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "cache-status"

    @Option(name: .customLong("limit"), help: "Number of recent cache rows to include")
    var limit: Int = 10

    @OptionGroup
    var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Show persistent cache status")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        self.limit = try values.decodeOption("limit") ?? 10
    }

    mutating func run() async throws {
        if self.limit < 0 {
            throw ValidationError(cliText("--limit must be >= 0"))
        }

        let summary = try RepoBarPersistentCache.summary(limit: self.limit)
        if self.output.jsonOutput {
            try printJSON(summary)
            return
        }

        cliPrint("Cache DB: \(PathFormatter.displayString(summary.databasePath))")
        cliPrint("Exists: \(summary.exists ? "yes" : "no")")
        cliPrint("API responses: \(summary.apiResponseCount)")
        cliPrint("GraphQL responses: \(summary.graphQLResponseCount)")
        cliPrint("Rate limits: \(summary.rateLimitCount)")
        if summary.latestResponses.isEmpty == false {
            cliPrint("Recent responses:")
            for response in summary.latestResponses {
                let status = response.statusCode.map(String.init) ?? "-"
                let etag = response.hasETag ? "etag" : "no-etag"
                cliPrint("  \(status) \(etag) \(response.url)")
            }
        }
    }
}

@MainActor
struct CacheClearCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "cache-clear"

    @OptionGroup
    var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Clear persistent cache")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
    }

    mutating func run() async throws {
        let summary = try RepoBarPersistentCache.clear()
        if self.output.jsonOutput {
            try printJSON(summary)
            return
        }

        cliPrint("Cleared cache: \(PathFormatter.displayString(summary.databasePath))")
    }
}

@MainActor
struct RateLimitsCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "rate-limits"

    @Option(name: .customLong("limit"), help: "Number of recent cache rows to inspect")
    var limit: Int = 100

    @OptionGroup
    var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(commandName: commandName, abstract: "Show GitHub rate-limit state")
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        self.limit = try values.decodeOption("limit") ?? 100
    }

    mutating func run() async throws {
        if self.limit < 0 {
            throw ValidationError(cliText("--limit must be >= 0"))
        }

        let summary = try RepoBarPersistentCache.summary(limit: self.limit)
        let diagnostics = DiagnosticsSummary.empty
        let sections = RateLimitStatusFormatter.sections(
            diagnostics: diagnostics,
            cacheSummary: summary
        )

        if self.output.jsonOutput {
            try printJSON(RateLimitsOutput(
                databasePath: summary.databasePath,
                exists: summary.exists,
                apiResponseCount: summary.apiResponseCount,
                graphQLResponseCount: summary.graphQLResponseCount,
                rateLimitCount: summary.rateLimitCount,
                compactSummary: RateLimitStatusFormatter.compactSummary(
                    diagnostics: diagnostics,
                    cacheSummary: summary
                ),
                sections: sections
            ))
            return
        }

        cliPrint("GitHub API Status")
        cliPrint("Cache DB: \(PathFormatter.displayString(summary.databasePath))")
        for (index, section) in sections.enumerated() {
            if index > 0 {
                cliPrint("")
            }
            if let title = section.title {
                Swift.print(title)
            }
            for row in section.rows {
                cliPrint("  \(row)")
            }
        }
    }
}

private struct RateLimitsOutput: Encodable {
    let databasePath: String
    let exists: Bool
    let apiResponseCount: Int
    let graphQLResponseCount: Int
    let rateLimitCount: Int
    let compactSummary: String
    let sections: [RateLimitDisplaySection]
}
