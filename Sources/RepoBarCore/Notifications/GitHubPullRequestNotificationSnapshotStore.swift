import Foundation

public struct GitHubPullRequestNotificationSnapshotStore {
    public static let storageKey = "com.steipete.repobar.github-pr-notification-snapshots"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = Self.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> GitHubPullRequestNotificationSnapshotState {
        guard let data = self.defaults.data(forKey: self.key) else {
            return GitHubPullRequestNotificationSnapshotState()
        }

        return (try? JSONDecoder().decode(GitHubPullRequestNotificationSnapshotState.self, from: data))
            ?? GitHubPullRequestNotificationSnapshotState()
    }

    public func save(_ state: GitHubPullRequestNotificationSnapshotState) {
        guard let data = try? JSONEncoder().encode(state) else { return }

        self.defaults.set(data, forKey: self.key)
    }

    public func clear() {
        self.defaults.removeObject(forKey: self.key)
    }
}
