import Foundation

public struct PullRequestAISummarizer: Sendable {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let maximumSummaryCharacters = 280
    private static let systemPrompt = [
        "You write GitHub item summaries for a macOS sidebar.",
        "Return one complete sentence, 24-34 words, no more than 280 characters, ending with punctuation.",
        "Use no markdown and no labels.",
        "Prefer concrete implementation details over generic phrasing."
    ].joined(separator: " ")

    private let keyStore: OpenAIAPIKeyStore
    private let dataLoader: DataLoader

    public init(keyStore: OpenAIAPIKeyStore = OpenAIAPIKeyStore()) {
        self.init(keyStore: keyStore) { request in
            try await URLSession.shared.data(for: request)
        }
    }

    init(keyStore: OpenAIAPIKeyStore = OpenAIAPIKeyStore(), dataLoader: @escaping DataLoader) {
        self.keyStore = keyStore
        self.dataLoader = dataLoader
    }

    public func summarize(_ match: GitHubReferenceMatch, settings: AISummarySettings, apiKeyOverride: String? = nil) async throws -> String? {
        guard settings.enabled, match.isResolved else { return nil }
        guard let key = Self.resolvedAPIKey(apiKeyOverride: apiKeyOverride, keyStore: self.keyStore) else { return nil }

        let summary = try await self.generate(
            input: Self.prompt(for: match),
            model: AISummarySettings.normalizedModel(settings.model),
            system: Self.systemPrompt,
            maxTokens: 1024,
            apiKey: key
        )

        return Self.clean(summary)
    }

    public func test(settings: AISummarySettings, apiKeyOverride: String? = nil) async throws -> String {
        guard let key = Self.resolvedAPIKey(apiKeyOverride: apiKeyOverride, keyStore: self.keyStore) else {
            throw AISummaryTestError.missingAPIKey
        }

        let rawSummary = try await self.generate(
            input: "Return one short sentence confirming RepoBar AI summaries are ready.",
            model: AISummarySettings.normalizedModel(settings.model),
            system: "You test a macOS app AI summary connection. Return one plain sentence, no markdown.",
            maxTokens: 1024,
            apiKey: key
        )

        guard let summary = Self.clean(rawSummary) else {
            throw AISummaryTestError.missingSummary
        }

        return summary
    }

    private func generate(input: String, model: String, system: String, maxTokens: Int, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIResponseRequest(
            model: model,
            instructions: system,
            input: input,
            maxOutputTokens: maxTokens
        ))

        let (data, response) = try await self.dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AISummaryServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data).error.message
            throw AISummaryServiceError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        guard let text = decoded.text else {
            throw AISummaryTestError.missingSummary
        }

        return text
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

        if summary.count <= Self.maximumSummaryCharacters {
            return summary
        }

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

private struct OpenAIResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let maxOutputTokens: Int
    let reasoning = Reasoning(effort: "low")

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case maxOutputTokens = "max_output_tokens"
        case reasoning
    }

    struct Reasoning: Encodable {
        let effort: String
    }
}

private struct OpenAIResponseEnvelope: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    var text: String? {
        if let outputText, outputText.isEmpty == false {
            return outputText
        }
        return self.output?
            .flatMap(\.content)
            .compactMap(\.text)
            .first { $0.isEmpty == false }
    }

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    struct OutputItem: Decodable {
        let content: [ContentItem]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.content = try container.decodeIfPresent([ContentItem].self, forKey: .content) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case content
        }
    }

    struct ContentItem: Decodable {
        let text: String?
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

private enum AISummaryServiceError: LocalizedError {
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "OpenAI returned an invalid response."
        case let .requestFailed(statusCode, message):
            if let message, message.isEmpty == false {
                "OpenAI request failed (\(statusCode)): \(message)"
            } else {
                "OpenAI request failed (\(statusCode))."
            }
        }
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
