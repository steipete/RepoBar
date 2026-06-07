import Foundation
import Tachikoma

public struct PullRequestAISummarizer: Sendable {
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
            system: "You write compact pull request sidebar summaries. Return one sentence, no markdown, no labels.",
            maxTokens: 80,
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
        parts.append("Summarize what this pull request appears to change and why it matters.")
        return parts.joined(separator: "\n")
    }

    private static func clean(_ raw: String) -> String? {
        let summary = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        guard summary.isEmpty == false else { return nil }

        if summary.count <= 220 { return summary }
        return "\(summary.prefix(217))..."
    }
}
