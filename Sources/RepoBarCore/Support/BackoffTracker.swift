import Foundation

/// Tracks per-URL backoff windows to avoid hammering rate-limited endpoints.
actor BackoffTracker {
    private var cooldowns: [String: Date] = [:]

    func cooldown(for url: URL, now: Date = Date()) -> Date? {
        if let until = cooldowns[url.absoluteString], until > now {
            return until
        }
        return nil
    }

    func activeCooldowns(now: Date = Date()) -> [String: Date] {
        self.cooldowns = self.cooldowns.filter { $0.value > now }
        return self.cooldowns
    }

    func setCooldown(url: URL, until: Date) {
        self.cooldowns[url.absoluteString] = until
    }

    func clear() {
        self.cooldowns.removeAll()
    }
}
