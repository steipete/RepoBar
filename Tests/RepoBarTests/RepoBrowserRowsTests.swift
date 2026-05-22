import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

struct RepoBrowserRowsTests {
    @Test
    func `make includes accessible repositories with visibility`() {
        let rows = RepoBrowserRows.make(
            repositories: [
                Self.makeRepo("steipete/RepoBar", issues: 2, pulls: 1, stars: 42),
                Self.makeRepo("amantus-ai/sweetistics", issues: 5, pulls: 3, stars: 9)
            ],
            pinnedRepositories: ["steipete/RepoBar"],
            hiddenRepositories: ["amantus-ai/sweetistics"],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )

        #expect(rows.map(\.fullName) == ["steipete/RepoBar", "amantus-ai/sweetistics"])
        #expect(rows[0].visibility == .pinned)
        #expect(rows[0].issueLabel == "2")
        #expect(rows[0].pullRequestLabel == "1")
        #expect(rows[0].starLabel == "42")
        #expect(rows[1].visibility == .hidden)
        #expect(rows[1].isManual == false)
    }

    @Test
    func `make keeps pinned and hidden manual rows missing from fetch`() {
        let rows = RepoBrowserRows.make(
            repositories: [Self.makeRepo("steipete/RepoBar")],
            pinnedRepositories: ["steipete/missing-pin"],
            hiddenRepositories: ["steipete/missing-hidden"],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )

        let manualRows = rows.filter(\.isManual)
        #expect(manualRows.map(\.fullName) == ["steipete/missing-pin", "steipete/missing-hidden"])
        #expect(manualRows.map(\.visibility) == [.pinned, .hidden])
        #expect(manualRows.allSatisfy { $0.issueLabel == "-" && $0.updatedLabel == "-" })
    }

    @Test
    func `sortable keys fold missing stats to a low sentinel`() throws {
        let loaded = try #require(RepoBrowserRows.make(
            repositories: [Self.makeRepo("a/loaded", issues: 3, pulls: 4, stars: 5)],
            pinnedRepositories: [],
            hiddenRepositories: [],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        ).first)
        let manual = try #require(RepoBrowserRows.make(
            repositories: [],
            pinnedRepositories: ["a/manual"],
            hiddenRepositories: [],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        ).first)

        #expect(loaded.sortableIssues == 3)
        #expect(loaded.sortablePulls == 4)
        #expect(loaded.sortableStars == 5)
        #expect(manual.sortableIssues == -1)
        #expect(manual.sortablePulls == -1)
        #expect(manual.sortableStars == -1)
        #expect(manual.sortablePushedAt == .distantPast)
    }

    @Test
    func `sorted by stars descending puts highest first and manual rows last`() {
        let rows = RepoBrowserRows.make(
            repositories: [
                Self.makeRepo("a/low", stars: 1),
                Self.makeRepo("a/high", stars: 100),
                Self.makeRepo("a/mid", stars: 50)
            ],
            pinnedRepositories: ["a/manual"],
            hiddenRepositories: [],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        )
        let comparator = KeyPathComparator(\RepoBrowserRow.sortableStars, order: .reverse)
        let sorted = rows.sorted(using: [comparator])
        #expect(sorted.map(\.fullName) == ["a/high", "a/mid", "a/low", "a/manual"])
    }

    @Test
    func `matches finds private org repository by owner or name`() {
        let row = RepoBrowserRows.make(
            repositories: [Self.makeRepo("amantus-ai/sweetistics")],
            pinnedRepositories: [],
            hiddenRepositories: [],
            now: Date(timeIntervalSinceReferenceDate: 1000)
        ).first

        #expect(row?.matches("amantus") == true)
        #expect(row?.matches("sweetis") == true)
        #expect(row?.matches("amantus sweetis") == true)
        #expect(row?.matches("steipete") == false)
    }
}

private extension RepoBrowserRowsTests {
    static func makeRepo(
        _ fullName: String,
        issues: Int = 0,
        pulls: Int = 0,
        stars: Int = 0
    ) -> Repository {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        return Repository(
            id: fullName,
            name: parts[1],
            owner: parts[0],
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: issues,
            openPulls: pulls,
            stars: stars,
            pushedAt: Date(timeIntervalSinceReferenceDate: 100),
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }
}
