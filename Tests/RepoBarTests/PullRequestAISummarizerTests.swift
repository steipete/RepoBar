@testable import RepoBarCore
import Testing

struct PullRequestAISummarizerTests {
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
