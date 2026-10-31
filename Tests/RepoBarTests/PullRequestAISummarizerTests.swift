import Foundation
@testable import RepoBarCore
import Testing

struct PullRequestAISummarizerTests {
    @Test
    func `AI summary model options include supported OpenAI ids`() {
        #expect(AISummarySettings.modelOptions.map(\.id) == ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini"])
    }

    @Test
    func `AI summary model normalization keeps selector values`() {
        #expect(AISummarySettings.normalizedModel("gpt-5.4-mini") == "gpt-5.4-mini")
        #expect(AISummarySettings.normalizedModel("gpd-5.5") == AISummarySettings.defaultModel)
        #expect(AISummarySettings.normalizedModel("") == AISummarySettings.defaultModel)
    }

    @Test
    func `AI summary request uses the selected OpenAI model`() async throws {
        let summarizer = PullRequestAISummarizer { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == "gpt-5.4-mini")
            #expect(json["max_output_tokens"] as? Int == 1024)
            #expect((json["reasoning"] as? [String: Any])?["effort"] as? String == "low")

            let data = Data(#"{"output":[{"content":[{"type":"output_text","text":"RepoBar AI summaries are ready."}]}]}"#.utf8)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (data, response)
        }
        var settings = AISummarySettings()
        settings.model = "gpt-5.4-mini"

        let summary = try await summarizer.test(settings: settings, apiKeyOverride: "test-key")

        #expect(summary == "RepoBar AI summaries are ready.")
    }

    @Test
    func `AI summary request surfaces OpenAI errors`() async throws {
        let summarizer = PullRequestAISummarizer { request in
            let data = Data(#"{"error":{"message":"Invalid API key."}}"#.utf8)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            ))
            return (data, response)
        }

        do {
            _ = try await summarizer.test(settings: AISummarySettings(), apiKeyOverride: "test-key")
            Issue.record("Expected the OpenAI request to fail")
        } catch {
            #expect(error.localizedDescription == "OpenAI request failed (401): Invalid API key.")
        }
    }

    @Test
    func `compatible provider request omits reasoning and uses the configured endpoint`() async throws {
        let summarizer = PullRequestAISummarizer { request in
            #expect(request.url?.absoluteString == "https://gateway.example/v1/responses")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gateway-key")

            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == "deepseek-flash")
            #expect(json["reasoning"] == nil)

            let data = Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"Gateway ready."}]}]}"#.utf8)
            let response = try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (data, response)
        }
        let settings = AISummaryEndpointTests.compatibleSettings(baseURL: "https://gateway.example/v1", model: "deepseek-flash")

        let summary = try await summarizer.test(settings: settings, apiKeyOverride: "gateway-key")

        #expect(summary == "Gateway ready.")
    }

    @Test
    func `compatible provider with an invalid base URL makes no request`() async {
        let requests = RequestCounter()
        let summarizer = PullRequestAISummarizer { request in
            requests.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        var settings = AISummaryEndpointTests.compatibleSettings(baseURL: "http://gateway.example/v1", model: "deepseek-flash")
        settings.enabled = true

        await #expect(throws: AISummaryEndpointError.insecureBaseURL) {
            try await summarizer.test(settings: settings, apiKeyOverride: "gateway-key")
        }
        #expect(requests.total == 0)
    }

    @Test
    func `compatible provider never falls back to the stored OpenAI key`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repobar-ai-key-\(UUID().uuidString)", isDirectory: true)
        let store = TokenStore(service: "repobar-tests", storage: .file(directory))
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.saveOpenAIAPIKey("sk-openai")
        let keyStore = OpenAIAPIKeyStore(tokenStore: store) { name in
            name == "OPENAI_API_KEY" ? "sk-env" : nil
        }
        let requests = RequestCounter()
        let summarizer = PullRequestAISummarizer(keyStore: keyStore) { request in
            requests.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let settings = AISummaryEndpointTests.compatibleSettings(baseURL: "https://gateway.example/v1", model: "deepseek-flash")

        do {
            _ = try await summarizer.test(settings: settings)
            Issue.record("Expected a missing API key error")
        } catch {
            #expect(error.localizedDescription == "No API key configured for the OpenAI-compatible endpoint.")
        }
        #expect(requests.total == 0)
    }

    @Test
    func `compatible provider errors name the endpoint instead of OpenAI`() async throws {
        let summarizer = PullRequestAISummarizer { request in
            let data = Data(#"{"error":{"message":"Invalid model."}}"#.utf8)
            let response = try #require(HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil))
            return (data, response)
        }
        let settings = AISummaryEndpointTests.compatibleSettings(baseURL: "https://gateway.example/v1", model: "nope")

        do {
            _ = try await summarizer.test(settings: settings, apiKeyOverride: "gateway-key")
            Issue.record("Expected the request to fail")
        } catch {
            #expect(error.localizedDescription == "OpenAI-compatible endpoint request failed (400): Invalid model.")
        }
    }

    @Test
    func `AI summary skips reasoning items before the message`() async throws {
        let summary = try await Self.testSummary(responseBody: #"""
        {"output":[
          {"type":"reasoning","content":[{"type":"output_text","text":"Thinking about the request."}]},
          {"type":"message","content":[{"type":"output_text","text":"RepoBar AI summaries are ready."}]}
        ]}
        """#)

        #expect(summary == "RepoBar AI summaries are ready.")
    }

    @Test
    func `AI summary joins message text blocks in order`() async throws {
        let summary = try await Self.testSummary(responseBody: #"""
        {"output":[{"type":"message","content":[
          {"type":"output_text","text":"First part."},
          {"type":"refusal","refusal":"Ignored."},
          {"type":"output_text","text":"Second part."}
        ]}]}
        """#)

        #expect(summary == "First part. Second part.")
    }

    @Test
    func `AI summary ignores whitespace output text convenience field`() async throws {
        let summary = try await Self.testSummary(responseBody: #"""
        {"output_text":"  ","output":[{"type":"message","content":[{"type":"output_text","text":"Message text."}]}]}
        """#)

        #expect(summary == "Message text.")
    }

    @Test
    func `AI summary fails when only reasoning is returned`() async throws {
        do {
            _ = try await Self.testSummary(responseBody: #"""
            {"output":[{"type":"reasoning","content":[{"type":"output_text","text":"Only thinking."}]},{"type":"message"}]}
            """#)
            Issue.record("Expected a missing summary error")
        } catch {
            #expect(error.localizedDescription == "The model did not return a summary.")
        }
    }

    @Test
    func `legacy enabled AI summary settings decode without scope`() throws {
        let data = try JSONEncoder().encode(LegacyAISummarySettings(enabled: true, model: "chat-latest"))

        let settings = try JSONDecoder().decode(AISummarySettings.self, from: data)

        #expect(settings.enabled)
        #expect(settings.model == AISummarySettings.defaultModel)
    }

    @Test
    func `legacy disabled AI summary settings decode without scope`() throws {
        let data = try JSONEncoder().encode(LegacyAISummarySettings(enabled: false, model: "chat-latest"))

        let settings = try JSONDecoder().decode(AISummarySettings.self, from: data)

        #expect(settings.enabled == false)
        #expect(settings.model == AISummarySettings.defaultModel)
    }

    @Test
    func `cleaned summary fits sidebar character budget`() throws {
        let raw = String(repeating: "This summary explains a concrete pull request change with enough detail to overflow the sidebar. ", count: 8)

        let summary = try #require(PullRequestAISummarizer.clean(raw))

        #expect(summary.count <= PullRequestAISummarizer.maximumSummaryCharacters)
        #expect(summary.hasSuffix("..."))
    }

    @Test
    func `cleaned summary collapses multiline output`() throws {
        let summary = try #require(PullRequestAISummarizer.clean(" First line.\n\n Second line. "))

        #expect(summary == "First line. Second line.")
    }

    private static func testSummary(responseBody: String) async throws -> String {
        let summarizer = PullRequestAISummarizer { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (Data(responseBody.utf8), response)
        }
        return try await summarizer.test(settings: AISummarySettings(), apiKeyOverride: "test-key")
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var total: Int {
        self.lock.withLock { self.value }
    }

    func increment() {
        self.lock.withLock { self.value += 1 }
    }
}

private struct LegacyAISummarySettings: Encodable {
    let enabled: Bool
    let model: String
}
