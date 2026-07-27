import Foundation

public struct GitHubReleaseNotificationEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let repositoryFullName: String
    public let tag: String
    public let name: String
    public let url: URL
    public let isPrerelease: Bool

    public init(
        id: String,
        repositoryFullName: String,
        tag: String,
        name: String,
        url: URL,
        isPrerelease: Bool
    ) {
        self.id = id
        self.repositoryFullName = repositoryFullName
        self.tag = tag
        self.name = name
        self.url = url
        self.isPrerelease = isPrerelease
    }
}

public struct GitHubReleaseNotificationSnapshotState: Equatable, Codable, Sendable {
    public var repositories: [String: [String: GitHubReleaseNotificationSnapshot]]
    public var repositoryBaselines: [String: Date]
    public var lastCheckedAt: Date?

    public init(
        repositories: [String: [String: GitHubReleaseNotificationSnapshot]] = [:],
        repositoryBaselines: [String: Date] = [:],
        lastCheckedAt: Date? = nil
    ) {
        self.repositories = repositories
        self.repositoryBaselines = repositoryBaselines
        self.lastCheckedAt = lastCheckedAt
    }

    private enum CodingKeys: String, CodingKey {
        case repositories
        case repositoryBaselines
        case lastCheckedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.repositories = try container.decodeIfPresent(
            [String: [String: GitHubReleaseNotificationSnapshot]].self,
            forKey: .repositories
        ) ?? [:]
        self.repositoryBaselines = try container.decodeIfPresent([String: Date].self, forKey: .repositoryBaselines) ?? [:]
        self.lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
    }
}

public struct GitHubReleaseNotificationSnapshot: Equatable, Codable, Sendable {
    public let publishedAt: Date
    public let isPrerelease: Bool

    public init(publishedAt: Date, isPrerelease: Bool) {
        self.publishedAt = publishedAt
        self.isPrerelease = isPrerelease
    }
}

public enum GitHubReleaseNotificationDetector {
    public static func shouldPoll(
        previousState: GitHubReleaseNotificationSnapshotState,
        now: Date = Date(),
        minimumInterval: TimeInterval
    ) -> Bool {
        guard minimumInterval > 0, let lastCheckedAt = previousState.lastCheckedAt else { return true }

        let elapsed = now.timeIntervalSince(lastCheckedAt)
        return elapsed < 0 || elapsed >= minimumInterval
    }

    public static func events(
        for currentReleases: [String: [RepoReleaseSummary]],
        previousState: GitHubReleaseNotificationSnapshotState,
        settings: GitHubReleaseNotificationSettings,
        trackedRepositoryFullNames: [String]? = nil,
        observedAt: Date = Date()
    ) -> (events: [GitHubReleaseNotificationEvent], state: GitHubReleaseNotificationSnapshotState) {
        guard settings.enabled else {
            return ([], previousState)
        }

        let trackedRepositoryKeys = Set((trackedRepositoryFullNames ?? Array(currentReleases.keys)).map(Self.repositoryKey))
        let previousRepositories = previousState.repositories.filter { trackedRepositoryKeys.contains($0.key) }
        let previousBaselines = previousState.repositoryBaselines.filter { trackedRepositoryKeys.contains($0.key) }
        var nextState = GitHubReleaseNotificationSnapshotState(
            repositories: previousRepositories,
            repositoryBaselines: previousBaselines,
            lastCheckedAt: previousState.lastCheckedAt
        )
        var events: [GitHubReleaseNotificationEvent] = []

        for (repositoryFullName, releases) in currentReleases {
            let repositoryKey = Self.repositoryKey(repositoryFullName)
            guard trackedRepositoryKeys.contains(repositoryKey) else { continue }

            let previousReleases = previousRepositories[repositoryKey]
            let previousBaseline = previousBaselines[repositoryKey]
                ?? previousReleases?.values.map(\.publishedAt).max()
            nextState.repositories[repositoryKey] = Dictionary(
                releases.map {
                    (
                        $0.tag,
                        GitHubReleaseNotificationSnapshot(
                            publishedAt: $0.publishedAt,
                            isPrerelease: $0.isPrerelease
                        )
                    )
                },
                uniquingKeysWith: { first, _ in first }
            )
            nextState.repositoryBaselines[repositoryKey] = max(previousBaseline ?? observedAt, observedAt)

            guard let previousReleases else {
                continue
            }

            for release in releases {
                let previousRelease = previousReleases[release.tag]
                let wasPromotedToStable = previousRelease?.isPrerelease == true && release.isPrerelease == false
                guard previousRelease == nil || wasPromotedToStable else { continue }

                if release.isPrerelease, settings.includePrereleases == false {
                    continue
                }

                let isNewAfterBaseline = previousBaseline.map { release.publishedAt > $0 } ?? false
                guard isNewAfterBaseline || wasPromotedToStable else { continue }

                events.append(Self.event(repositoryFullName: repositoryFullName, release: release))
            }
        }

        return (events, nextState)
    }

    private static func event(
        repositoryFullName: String,
        release: RepoReleaseSummary
    ) -> GitHubReleaseNotificationEvent {
        let id = [
            "github-release",
            Self.repositoryKey(repositoryFullName).replacingOccurrences(of: "/", with: "-"),
            Self.tagMarker(release.tag),
            release.isPrerelease ? "prerelease" : "release",
            Self.dateMarker(release.publishedAt)
        ].joined(separator: "-")

        return GitHubReleaseNotificationEvent(
            id: id,
            repositoryFullName: repositoryFullName,
            tag: release.tag,
            name: release.name,
            url: release.url,
            isPrerelease: release.isPrerelease
        )
    }

    private static func repositoryKey(_ repositoryFullName: String) -> String {
        repositoryFullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func tagMarker(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "untagged" : trimmed
    }

    private static func dateMarker(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }
}
