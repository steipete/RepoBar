import Foundation

public struct AISummaryEndpoint: Equatable, Sendable {
    public static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    public let provider: AISummaryProvider
    public let baseURL: URL
    public let model: String

    public var responsesURL: URL {
        self.baseURL.appendingPathComponent("responses")
    }

    public var sendsReasoningEffort: Bool {
        self.provider == .openAI
    }

    public static func resolve(_ settings: AISummarySettings) throws -> AISummaryEndpoint {
        switch settings.provider {
        case .openAI:
            return AISummaryEndpoint(
                provider: .openAI,
                baseURL: self.openAIBaseURL,
                model: AISummarySettings.normalizedModel(settings.model)
            )
        case .openAICompatible:
            let model = settings.compatibleModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard model.isEmpty == false else { throw AISummaryEndpointError.missingModel }

            return try AISummaryEndpoint(
                provider: .openAICompatible,
                baseURL: Self.validatedBaseURL(settings.compatibleBaseURL),
                model: model
            )
        }
    }

    public static func validatedBaseURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AISummaryEndpointError.missingBaseURL }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              host.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { throw AISummaryEndpointError.invalidBaseURL }

        switch scheme {
        case "https":
            break
        case "http" where Self.loopbackHosts.contains(host):
            break
        case "http":
            throw AISummaryEndpointError.insecureBaseURL
        default:
            throw AISummaryEndpointError.invalidBaseURL
        }

        components.scheme = scheme
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else { throw AISummaryEndpointError.invalidBaseURL }

        return url
    }
}

public enum AISummaryEndpointError: LocalizedError, Equatable {
    case missingBaseURL
    case invalidBaseURL
    case insecureBaseURL
    case missingModel

    public var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            "Enter a base URL for the OpenAI-compatible endpoint."
        case .invalidBaseURL:
            "Base URL must be an http(s) URL without credentials, query, or fragment."
        case .insecureBaseURL:
            "Base URL must use HTTPS unless it points to localhost."
        case .missingModel:
            "Enter a model for the OpenAI-compatible endpoint."
        }
    }
}
