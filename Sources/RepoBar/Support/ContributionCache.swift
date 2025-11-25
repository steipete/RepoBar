import Foundation

struct ContributionCache: Codable {
    let username: String
    let expires: Date
    let cells: [HeatmapCell]

    var isValid: Bool {
        Date() < self.expires
    }
}

enum ContributionCacheStore {
    private static let key = "ContributionHeatmapCache"

    static func load() -> ContributionCache? {
        guard let data = UserDefaults.standard.data(forKey: self.key) else { return nil }
        return try? JSONDecoder().decode(ContributionCache.self, from: data)
    }

    static func save(_ cache: ContributionCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: self.key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: self.key)
    }
}
