import Foundation

public enum GlobalActivityMerger {
    public static func repositoryEvents(from repositories: [Repository]) -> [ActivityEvent] {
        repositories.flatMap { repository in
            if repository.activityEvents.isEmpty == false {
                return repository.activityEvents
            }
            if let latestActivity = repository.latestActivity {
                return [latestActivity]
            }
            return []
        }
    }

    public static func merge(
        userEvents: [ActivityEvent],
        repoEvents: [ActivityEvent],
        scope: GlobalActivityScope,
        username: String,
        limit: Int
    ) -> [ActivityEvent] {
        let combined = userEvents + repoEvents
        let filtered = scope == .myActivity
            ? combined.filter { $0.actor.caseInsensitiveCompare(username) == .orderedSame }
            : combined
        let sorted = filtered.sorted { $0.date > $1.date }
        var seen: Set<String> = []
        var results: [ActivityEvent] = []
        results.reserveCapacity(max(limit, 0))
        for event in sorted {
            let key = "\(event.url.absoluteString)|\(event.date.timeIntervalSinceReferenceDate)|\(event.actor)"
            guard seen.insert(key).inserted else { continue }

            results.append(event)
            if results.count >= limit {
                break
            }
        }
        return results
    }
}
