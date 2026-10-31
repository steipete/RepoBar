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
            try await URLSession.shared.data(for: request, delegate: RedirectRejectingTaskDelegate())
        }
    }

    init(keyStore: OpenAIAPIKeyStore = OpenAIAPIKeyStore(), dataLoader: @escaping DataLoader) {
        self.keyStore = keyStore
        self.dataLoader = dataLoader
    }

    public func summarize(_ match: GitHubReferenceMatch, settings: AISummarySettings, apiKeyOverride: String? = nil) async throws -> String? {
        guard settings.enabled, match.isResolved else { return nil }

        let endpoint = try AISummaryEndpoint.resolve(settings)
        guard let key = self.resolvedAPIKey(apiKeyOverride: apiKeyOverride, provider: endpoint.provider) else { return nil }

        let summary = try await self.generate(
            input: Self.prompt(for: match),
            endpoint: endpoint,
            system: Self.systemPrompt,
            maxTokens: 1024,
            apiKey: key
        )

        return Self.clean(summary)
    }

    public func test(settings: AISummarySettings, apiKeyOverride: String? = nil) async throws -> String {
        let endpoint = try AISummaryEndpoint.resolve(settings)
        guard let key = self.resolvedAPIKey(apiKeyOverride: apiKeyOverride, provider: endpoint.provider) else {
            throw AISummaryTestError.missingAPIKey(endpoint.provider)
        }

        let rawSummary = try await self.generate(
            input: "Return one short sentence confirming RepoBar AI summaries are ready.",
            endpoint: endpoint,
            system: "You test a macOS app AI summary connection. Return one plain sentence, no markdown.",
            maxTokens: 1024,
            apiKey: key
        )

        guard let summary = Self.clean(rawSummary) else {
            throw AISummaryTestError.missingSummary
        }

        return summary
    }

    private func generate(
        input: String,
        endpoint: AISummaryEndpoint,
        system: String,
        maxTokens: Int,
        apiKey: String
    ) async throws -> String {
        var request = URLRequest(url: endpoint.responsesURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIResponseRequest(
            model: endpoint.model,
            instructions: system,
            input: input,
            maxOutputTokens: maxTokens,
            reasoning: endpoint.sendsReasoningEffort ? OpenAIResponseRequest.Reasoning(effort: "low") : nil
        ))

        let (data, response) = try await self.dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AISummaryServiceError.invalidResponse(endpoint.provider)
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data).error.message
            throw AISummaryServiceError.requestFailed(
                provider: endpoint.provider,
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        let decoded = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        guard let text = decoded.text else {
            throw AISummaryTestError.missingSummary
        }

        return text
    }

    private func resolvedAPIKey(apiKeyOverride: String?, provider: AISummaryProvider) -> String? {
        let override = apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, override.isEmpty == false {
            return override
        }

        return self.keyStore.resolve(for: provider).key
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
    let reasoning: Reasoning?

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
        if let outputText, outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return outputText
        }
        let messageText = (self.output ?? [])
            .filter(\.isAssistantMessage)
            .flatMap(\.content)
            .filter(\.isOutputText)
            .compactMap(\.text)
            .joined(separator: "\n")
        return messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : messageText
    }

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    struct OutputItem: Decodable {
        let type: String?
        let content: [ContentItem]

        var isAssistantMessage: Bool {
            self.type == nil || self.type == "message"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try container.decodeIfPresent(String.self, forKey: .type)
            self.content = try container.decodeIfPresent([ContentItem].self, forKey: .content) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case type
            case content
        }
    }

    struct ContentItem: Decodable {
        let type: String?
        let text: String?

        var isOutputText: Bool {
            self.type == nil || self.type == "output_text"
        }
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

private final class RedirectRejectingTaskDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

private enum AISummaryServiceError: LocalizedError {
    case invalidResponse(AISummaryProvider)
    case requestFailed(provider: AISummaryProvider, statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(provider):
            "\(provider.serviceName) returned an invalid response."
        case let .requestFailed(provider, statusCode, message):
            if let message, message.isEmpty == false {
                "\(provider.serviceName) request failed (\(statusCode)): \(message)"
            } else {
                "\(provider.serviceName) request failed (\(statusCode))."
            }
        }
    }
}

enum AISummaryTestError: LocalizedError {
    case missingAPIKey(AISummaryProvider)
    case missingSummary

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(.openAI):
            "No OpenAI API key configured."
        case .missingAPIKey(.openAICompatible):
            "No API key configured for the OpenAI-compatible endpoint."
        case .missingSummary:
            "The model did not return a summary."
        }
    }
}

private extension AISummaryProvider {
    var serviceName: String {
        switch self {
        case .openAI: "OpenAI"
        case .openAICompatible: "OpenAI-compatible endpoint"
        }
    }
}
