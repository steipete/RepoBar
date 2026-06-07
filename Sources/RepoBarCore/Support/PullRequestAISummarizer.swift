import Foundation
import Tachikoma

public struct PullRequestAISummarizer: Sendable {
    static let maximumSummaryCharacters = 280
    private static let systemPrompt = [
        "You write pull request summaries for a macOS sidebar.",
        "Return one complete sentence, 24-34 words, no more than 280 characters, ending with punctuation.",
        "Use no markdown and no labels.",
        "Prefer concrete implementation details over generic phrasing."
    ].joined(separator: " ")

    private let keyStore: OpenAIAPIKeyStore

    public init(keyStore: OpenAIAPIKeyStore = OpenAIAPIKeyStore()) {
        self.keyStore = keyStore
    }

    public func summarize(_ match: GitHubReferenceMatch, settings: AISummarySettings) async throws -> String? {
        guard settings.enabled, match.kind == .pullRequest else { return nil }
        guard let key = self.keyStore.resolve().key else { return nil }

        let model = Self.openAIModel(from: settings.model)
        let configuration = TachikomaConfiguration(loadFromEnvironment: false)
        configuration.setAPIKey(key, for: .openai)

        let summary = try await generate(
            Self.prompt(for: match),
            using: model,
            system: Self.systemPrompt,
            maxTokens: 120,
            configuration: configuration
        )

        return Self.clean(summary)
    }

    private static func openAIModel(from modelID: String) -> LanguageModel {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return .openai(.chatLatest) }

        if case let .openai(model)? = LanguageModel.parse(from: trimmed) {
            return .openai(model)
        }

        return .openai(.custom(trimmed))
    }

    private static func prompt(for match: GitHubReferenceMatch) -> String {
        var parts = [
            "Repository: \(match.repositoryFullName)",
            "PR: \(match.query.displayText)",
            "Title: \(match.title)"
        ]
        if let author = match.authorLogin, author.isEmpty == false {
            parts.append("Author: \(author)")
        }
        if let body = match.bodyPreview, body.isEmpty == false {
            parts.append("Body preview: \(body)")
        }
        parts.append("Summarize what this pull request changes and why it matters in one sidebar-sized sentence.")
        return parts.joined(separator: "\n")
    }

    static func clean(_ raw: String) -> String? {
        let summary = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        guard summary.isEmpty == false else { return nil }

        if summary.count <= Self.maximumSummaryCharacters { return summary }

        let prefix = String(summary.prefix(Self.maximumSummaryCharacters - 3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastSpace = prefix.lastIndex(where: \.isWhitespace) {
            let cutIndex = prefix.distance(from: prefix.startIndex, to: lastSpace)
            if cutIndex > Self.maximumSummaryCharacters / 2 {
                return "\(prefix[..<lastSpace])..."
            }
        }
        return "\(prefix)..."
    }
}
