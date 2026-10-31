import Foundation

public enum OpenAIAPIKeySource: Equatable, Sendable {
    case keychain
    case environment(String)
    case missing

    public var label: String {
        switch self {
        case .keychain:
            "Stored in Keychain"
        case let .environment(name):
            "Using \(name)"
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

    public func save(_ key: String, for provider: AISummaryProvider = .openAI) throws {
        switch provider {
        case .openAI:
            try self.tokenStore.saveOpenAIAPIKey(key)
        case .openAICompatible:
            try self.tokenStore.saveOpenAICompatibleAPIKey(key)
        }
    }

    public func clearStoredKey(for provider: AISummaryProvider = .openAI) {
        switch provider {
        case .openAI:
            self.tokenStore.clearOpenAIAPIKey()
        case .openAICompatible:
            self.tokenStore.clearOpenAICompatibleAPIKey()
        }
    }

    public func resolve(for provider: AISummaryProvider = .openAI) -> OpenAIAPIKeyResolution {
        switch provider {
        case .openAI:
            self.resolveOpenAIKey()
        case .openAICompatible:
            self.resolveCompatibleKey()
        }
    }

    private func resolveOpenAIKey() -> OpenAIAPIKeyResolution {
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

    private func resolveCompatibleKey() -> OpenAIAPIKeyResolution {
        if let stored = try? self.tokenStore.loadOpenAICompatibleAPIKey(), stored.isEmpty == false {
            return OpenAIAPIKeyResolution(key: stored, source: .keychain)
        }

        return OpenAIAPIKeyResolution(key: nil, source: .missing)
    }
}
