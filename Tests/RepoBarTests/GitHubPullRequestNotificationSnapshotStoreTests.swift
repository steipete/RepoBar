import Foundation
@testable import RepoBarCore
import Testing

struct GitHubPullRequestNotificationSnapshotStoreTests {
    @Test
    func `snapshot store round trips and clears state`() throws {
        let suiteName = "GitHubPullRequestNotificationSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = GitHubPullRequestNotificationSnapshotStore(defaults: defaults)
        let snapshot = GitHubPullRequestNotificationSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            commentCount: 2,
            reviewCommentCount: 1,
            requestedReviewerLogins: ["alice"],
            requestedTeamNames: ["ios"]
        )
        let state = GitHubPullRequestNotificationSnapshotState(
            repositories: ["steipete/repobar": [57: snapshot]]
        )

        store.save(state)

        let loaded = store.load()
        #expect(loaded == state)

        store.clear()

        #expect(store.load() == GitHubPullRequestNotificationSnapshotState())
    }

    @Test
    func `snapshot store falls back to empty state for invalid data`() throws {
        let suiteName = "GitHubPullRequestNotificationSnapshotStoreTests.invalid.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data([0x00, 0x01]), forKey: GitHubPullRequestNotificationSnapshotStore.storageKey)
        let store = GitHubPullRequestNotificationSnapshotStore(defaults: defaults)

        #expect(store.load() == GitHubPullRequestNotificationSnapshotState())
    }
}
