import Foundation
import Tachikoma

public struct PullRequestAISummarizer: Sendable {
    static let maximumSummaryCharacters = 280
    private static let systemPrompt = [
        "You write GitHub item summaries for a macOS sidebar.",
        "Return one complete sentence, 24-34 words, no more than 280 characters, ending with punctuation.",
        "Use no markdown and no labels.",
        "Prefer concrete implementation details over generic phrasing."
    ].joined(separator: " ")

    private let keyStore: OpenAIAPIKeyStore

    public init(keyStore: OpenAIAPIKeyStore = OpenAIAPIKeyStore()) {
        self.keyStore = keyStore
    }

    public func summarize(_ match: GitHubReferenceMatch, settings: AISummarySettings, apiKeyOverride: String? = nil) async throws -> String? {
        guard settings.enabled, match.isResolved else { return nil }
        guard let key = Self.resolvedAPIKey(apiKeyOverride: apiKeyOverride, keyStore: self.keyStore) else { return nil }

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

    public func test(settings: AISummarySettings, apiKeyOverride: String? = nil) async throws -> String {
        guard let key = Self.resolvedAPIKey(apiKeyOverride: apiKeyOverride, keyStore: self.keyStore) else {
            throw AISummaryTestError.missingAPIKey
        }

        let model = Self.openAIModel(from: settings.model)
        let configuration = TachikomaConfiguration(loadFromEnvironment: false)
        configuration.setAPIKey(key, for: .openai)

        let rawSummary = try await generate(
            "Return one short sentence confirming RepoBar AI summaries are ready.",
            using: model,
            system: "You test a macOS app AI summary connection. Return one plain sentence, no markdown.",
            maxTokens: 60,
            configuration: configuration
        )

        guard let summary = Self.clean(rawSummary) else {
            throw AISummaryTestError.missingSummary
        }

        return summary
    }

    private static func openAIModel(from modelID: String) -> LanguageModel {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return .openai(.chatLatest) }

        if case let .openai(model)? = LanguageModel.parse(from: trimmed) {
            return .openai(model)
        }

        return .openai(.custom(trimmed))
    }

    private static func resolvedAPIKey(apiKeyOverride: String?, keyStore: OpenAIAPIKeyStore) -> String? {
        let override = apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, override.isEmpty == false {
            return override
        }

        return keyStore.resolve().key
    }

    private static func prompt(for match: GitHubReferenceMatch) -> String {
        var parts = [
            "Repository: \(match.repositoryFullName)",
            "Kind: \(match.kind.label)",
            "Item: \(match.query.displayText)",
            "Title: \(match.title)"
        ]
        if let author = match.authorLogin, author.isEmpty == false {
            parts.append("Author: \(author)")
        }
        if let body = match.bodyPreview, body.isEmpty == false {
            parts.append("Body preview: \(body)")
        }
        parts.append("Summarize what this GitHub item changes, reports, or shows in one sidebar-sized sentence.")
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

enum AISummaryTestError: LocalizedError {
    case missingAPIKey
    case missingSummary

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No OpenAI API key configured."
        case .missingSummary:
            "The model did not return a summary."
        }
    }
}
