import Foundation
@testable import RepoBarCore
import Testing

struct AISummaryEndpointTests {
    @Test
    func `OpenAI provider keeps the public endpoint and model list`() throws {
        var settings = AISummarySettings()
        settings.model = "deepseek-flash"
        settings.compatibleBaseURL = "https://gateway.example/v1"

        let endpoint = try AISummaryEndpoint.resolve(settings)

        #expect(endpoint.provider == .openAI)
        #expect(endpoint.responsesURL.absoluteString == "https://api.openai.com/v1/responses")
        #expect(endpoint.model == AISummarySettings.defaultModel)
        #expect(endpoint.sendsReasoningEffort)
    }

    @Test
    func `compatible provider uses its base URL and free-form model`() throws {
        let endpoint = try AISummaryEndpoint.resolve(Self.compatibleSettings(baseURL: "https://gateway.example/v1/", model: " deepseek-flash "))

        #expect(endpoint.provider == .openAICompatible)
        #expect(endpoint.responsesURL.absoluteString == "https://gateway.example/v1/responses")
        #expect(endpoint.model == "deepseek-flash")
        #expect(endpoint.sendsReasoningEffort == false)
    }

    @Test
    func `compatible provider rejects missing or unsafe base URLs`() {
        let cases: [(String, AISummaryEndpointError)] = [
            ("", .missingBaseURL),
            ("   ", .missingBaseURL),
            ("gateway.example/v1", .invalidBaseURL),
            ("ftp://gateway.example/v1", .invalidBaseURL),
            ("https://user:secret@gateway.example/v1", .invalidBaseURL),
            ("https://gateway.example/v1?key=1", .invalidBaseURL),
            ("https://gateway.example/v1#frag", .invalidBaseURL),
            ("http://gateway.example/v1", .insecureBaseURL),
            ("http://localhost.evil.example/v1", .insecureBaseURL),
            ("http://127.0.0.2/v1", .insecureBaseURL)
        ]

        for (rawValue, expected) in cases {
            #expect(throws: expected) {
                try AISummaryEndpoint.resolve(Self.compatibleSettings(baseURL: rawValue, model: "m"))
            }
        }
    }

    @Test
    func `compatible provider allows plain HTTP on loopback hosts`() throws {
        for rawValue in ["http://localhost:4000/v1", "http://127.0.0.1:4000/v1", "http://[::1]:4000/v1", "HTTP://LOCALHOST:4000/v1"] {
            let url = try AISummaryEndpoint.validatedBaseURL(rawValue)
            #expect(url.scheme == "http")
        }
    }

    @Test
    func `compatible provider requires a model`() {
        #expect(throws: AISummaryEndpointError.missingModel) {
            try AISummaryEndpoint.resolve(Self.compatibleSettings(baseURL: "https://gateway.example/v1", model: " "))
        }
    }

    @Test
    func `compatible settings survive an encode and decode round trip`() throws {
        var settings = Self.compatibleSettings(baseURL: "https://gateway.example/v1", model: "deepseek-flash")
        settings.enabled = true

        let decoded = try JSONDecoder().decode(AISummarySettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded == settings)
    }

    @Test
    func `unknown provider decodes as OpenAI`() throws {
        let data = Data(#"{"enabled":true,"model":"gpt-5.4","provider":"other"}"#.utf8)

        let settings = try JSONDecoder().decode(AISummarySettings.self, from: data)

        #expect(settings.provider == .openAI)
        #expect(settings.model == "gpt-5.4")
        #expect(settings.compatibleBaseURL.isEmpty)
        #expect(settings.compatibleModel.isEmpty)
    }

    @Test
    func `compatible key is stored separately from the OpenAI key`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repobar-compatible-key-\(UUID().uuidString)", isDirectory: true)
        let store = TokenStore(service: "repobar-tests", storage: .file(directory))
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyStore = OpenAIAPIKeyStore(tokenStore: store) { name in
            name == "OPENAI_API_KEY" ? "sk-env" : nil
        }

        try keyStore.save("sk-openai", for: .openAI)
        #expect(keyStore.resolve(for: .openAICompatible) == OpenAIAPIKeyResolution(key: nil, source: .missing))

        try keyStore.save("sk-gateway", for: .openAICompatible)
        #expect(keyStore.resolve(for: .openAICompatible).key == "sk-gateway")
        #expect(keyStore.resolve(for: .openAI).key == "sk-openai")

        keyStore.clearStoredKey(for: .openAICompatible)
        #expect(keyStore.resolve(for: .openAICompatible).key == nil)
        #expect(keyStore.resolve(for: .openAI).key == "sk-openai")
    }

    static func compatibleSettings(baseURL: String, model: String) -> AISummarySettings {
        var settings = AISummarySettings()
        settings.provider = .openAICompatible
        settings.compatibleBaseURL = baseURL
        settings.compatibleModel = model
        return settings
    }
}
