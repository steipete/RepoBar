import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

struct RepositoryHydrationTests {
    @Test
    func `merge keeps accessible repos and overlays hydrated stats`() {
        let raw = [
            Self.makeRepo("stablyai/orca", issues: 249, pulls: 0),
            Self.makeRepo("steipete/RepoBar", issues: 1, pulls: 0)
        ]
        let hydrated = [
            Self.makeRepo("stablyai/orca", issues: 0, pulls: 249)
        ]

        let merged = RepositoryHydration.merge(hydrated, into: raw)

        #expect(merged.map(\.fullName) == ["stablyai/orca", "steipete/RepoBar"])
        #expect(merged[0].openIssues == 0)
        #expect(merged[0].openPulls == 249)
        #expect(merged[1].openIssues == 1)
        #expect(merged[1].openPulls == 0)
    }
}

private extension RepositoryHydrationTests {
    static func makeRepo(_ fullName: String, issues: Int, pulls: Int) -> Repository {
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
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }
}
