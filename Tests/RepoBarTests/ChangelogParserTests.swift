@testable import RepoBarCore
import Testing

struct ChangelogParserTests {
    @Test
    func `Unreleased entries produce badge count`() {
        let markdown = """
        # Changelog

        ## Unreleased
        - Added first
        - Fixed second

        ## 1.0.0
        - Old
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        let presentation = ChangelogParser.presentation(parsed: parsed, releaseTag: "v1.0.0")
        #expect(presentation?.title == "Changelog • Unreleased")
        #expect(presentation?.badgeText == "2")
        #expect(presentation?.detailText == nil)
    }

    @Test
    func `Empty unreleased maps to up-to-date`() {
        let markdown = """
        # Changelog

        ## Unreleased

        ## 1.0.0
        - Old
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        let presentation = ChangelogParser.presentation(parsed: parsed, releaseTag: "1.0.0")
        #expect(presentation?.badgeText == nil)
        #expect(presentation?.detailText == "Up to date")
    }

    @Test
    func `empty unreleased still counts entries in newer dated sections`() {
        let markdown = """
        # Changelog

        ## 0.8.9 - Unreleased

        ## 0.8.8 - 2026-08-20
        - Rewrite README
        - Update Sparkle

        ## 0.8.7 - 2026-08-02
        - Update Commander
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        let presentation = ChangelogParser.presentation(parsed: parsed, releaseTag: "0.8.7")
        #expect(presentation?.title == "Changelog • Since 0.8.7")
        #expect(presentation?.badgeText == "2")
        #expect(presentation?.detailText == nil)
    }

    @Test
    func `empty unreleased maps to up to date without release tag`() {
        let markdown = """
        # Changelog

        ## Unreleased

        ## 1.0.0
        - Old
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        let presentation = ChangelogParser.presentation(parsed: parsed, releaseTag: nil)
        #expect(presentation?.badgeText == nil)
        #expect(presentation?.detailText == "Up to date")
    }

    @Test
    func `Fuzzy version matching counts entries since release`() {
        let markdown = """
        # Changelog

        ## 1.1.0 - 2025-01-02
        - Added feature
        - Fixed bug

        ## v1.0.0 - 2024-12-01
        - Initial release
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        let presentation = ChangelogParser.presentation(parsed: parsed, releaseTag: "v1.0.0")
        #expect(presentation?.title == "Changelog • Since v1.0.0")
        #expect(presentation?.badgeText == "2")
    }

    @Test
    func `Missing release match returns no metadata`() {
        let markdown = """
        # Changelog

        ## 1.0.0
        - Old
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        let presentation = ChangelogParser.presentation(parsed: parsed, releaseTag: "2.0.0")
        #expect(presentation == nil)
    }

    @Test
    func `Subheadings do not split sections`() {
        let markdown = """
        # Changelog

        ## 1.2.0
        ### Added
        - A
        - B
        ### Fixed
        - C

        ## 1.1.0
        - Older
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        #expect(parsed.sections.count == 2)
        #expect(parsed.sections.first?.entryCount == 3)
    }

    @Test
    func `Numbered list items are counted`() {
        let markdown = """
        # Changelog

        ## Unreleased
        1. First
        2. Second
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        let presentation = ChangelogParser.presentation(parsed: parsed, releaseTag: nil)
        #expect(presentation?.badgeText == "2")
    }

    @Test
    func `Headline prefers first release section over Unreleased`() {
        let markdown = """
        # Changelog

        ## Unreleased
        - Work in progress

        ## 1.2.0 - 2025-12-31
        - Shipped
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        #expect(ChangelogParser.headline(parsed: parsed) == "1.2.0 - 2025-12-31")
    }

    @Test
    func `Headline falls back to first section when no version exists`() {
        let markdown = """
        # Changelog

        ## Highlights
        - Big change
        """
        let parsed = ChangelogParser.parse(markdown: markdown)
        #expect(ChangelogParser.headline(parsed: parsed) == "Highlights")
    }
}
