import Foundation

public enum OpenAIAPIKeySource: Equatable, Sendable {
    case keychain
    case environment(String)
    case keychainForOtherEndpoint
    case missing

    public var label: String {
        switch self {
        case .keychain:
            "Stored in Keychain"
        case let .environment(name):
            "Using \(name)"
        case .keychainForOtherEndpoint:
            "Stored key belongs to a different base URL"
        case .missing:
            "No key configured"
        }
    }
}

public struct OpenAIAPIKeyResolution: Equatable, Sendable {
    public let key: String?
    public let source: OpenAIAPIKeySource
}

public struct OpenAIAPIKeyStore: Sendable {
    private let tokenStore: TokenStore
    private let environmentValue: @Sendable (String) -> String?

    public init(
        tokenStore: TokenStore = .shared,
        environmentValue: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) {
        self.tokenStore = tokenStore
        self.environmentValue = environmentValue
    }

    public func save(_ key: String) throws {
        try self.tokenStore.saveOpenAIAPIKey(key)
    }

    public func clearStoredKey() {
        self.tokenStore.clearOpenAIAPIKey()
    }

    public func saveCompatibleKey(_ key: String, for baseURL: URL) throws {
        try self.tokenStore.saveOpenAICompatibleAPIKey(key, baseURL: baseURL)
    }

    public func clearCompatibleKey() {
        self.tokenStore.clearOpenAICompatibleAPIKey()
    }

    public func resolve() -> OpenAIAPIKeyResolution {
        if let stored = try? self.tokenStore.loadOpenAIAPIKey(), stored.isEmpty == false {
            return OpenAIAPIKeyResolution(key: stored, source: .keychain)
        }

        for name in ["OPENAI_API_KEY", "REPOBAR_OPENAI_API_KEY"] {
            guard let value = self.environmentValue(name)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                continue
            }

            if value.isEmpty == false {
                return OpenAIAPIKeyResolution(key: value, source: .environment(name))
            }
        }

        return OpenAIAPIKeyResolution(key: nil, source: .missing)
    }

    public func resolve(for endpoint: AISummaryEndpoint) -> OpenAIAPIKeyResolution {
        switch endpoint.provider {
        case .openAI:
            return self.resolve()
        case .openAICompatible:
            guard let stored = try? self.tokenStore.loadOpenAICompatibleAPIKey() else {
                return OpenAIAPIKeyResolution(key: nil, source: .missing)
            }
            guard stored.baseURL == endpoint.baseURL else {
                return OpenAIAPIKeyResolution(key: nil, source: .keychainForOtherEndpoint)
            }

            return OpenAIAPIKeyResolution(key: stored.key, source: .keychain)
        }
    }
}
