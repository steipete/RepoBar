import Foundation

/// Some REST endpoints report independent windows under the same `core`
/// resource. Surface the most constrained active observation, not whichever
/// endpoint happened to finish last.
struct RateLimitWindowSamples {
    private var windows: [Date: RateLimitSnapshot] = [:]
    private var latest: RateLimitSnapshot?

    mutating func record(_ sample: RateLimitSnapshot) {
        self.latest = RateLimitSnapshot.newest(self.latest, sample)
        self.windows = self.windows.filter { $0.key > sample.fetchedAt }
        guard let reset = sample.reset, reset > sample.fetchedAt else { return }

        self.windows[reset] = Self.mostConstrained([self.windows[reset], sample].compactMap(\.self))
    }

    func snapshot(now: Date = Date()) -> RateLimitSnapshot? {
        Self.mostConstrained(self.windows.filter { $0.key > now }.map(\.value)) ?? self.latest
    }

    private static func mostConstrained(_ samples: [RateLimitSnapshot]) -> RateLimitSnapshot? {
        samples.min {
            let first = $0.remaining ?? Int.max
            let second = $1.remaining ?? Int.max
            return first == second ? $0.fetchedAt > $1.fetchedAt : first < second
        }
    }
}
