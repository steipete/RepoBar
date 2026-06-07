import Foundation
@testable import RepoBarCore
import Testing

struct PullRequestAISummarizerTests {
    @Test
    func `AI summary model options include supported OpenAI ids`() {
        #expect(AISummarySettings.modelOptions.map(\.id) == ["chat-latest", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini"])
    }

    @Test
    func `AI summary model normalization keeps selector values`() {
        #expect(AISummarySettings.normalizedModel("gpt-5.4-mini") == "gpt-5.4-mini")
        #expect(AISummarySettings.normalizedModel("gpd-5.5") == AISummarySettings.defaultModel)
        #expect(AISummarySettings.normalizedModel("") == AISummarySettings.defaultModel)
    }

    @Test
    func `legacy enabled AI summary settings stay pull request scoped`() throws {
        let data = try JSONEncoder().encode(LegacyAISummarySettings(enabled: true, model: "chat-latest"))

        let settings = try JSONDecoder().decode(AISummarySettings.self, from: data)

        #expect(settings.scope == .pullRequests)
        #expect(settings.includes(kind: .pullRequest))
        #expect(settings.includes(kind: .issue) == false)
    }

    @Test
    func `legacy disabled AI summary settings default to all items for later opt in`() throws {
        let data = try JSONEncoder().encode(LegacyAISummarySettings(enabled: false, model: "chat-latest"))

        let settings = try JSONDecoder().decode(AISummarySettings.self, from: data)

        #expect(settings.scope == .allItems)
        #expect(settings.includes(kind: .issue))
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
}

private struct LegacyAISummarySettings: Encodable {
    let enabled: Bool
    let model: String
}
