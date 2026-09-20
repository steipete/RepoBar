import Foundation
@testable import RepoBarCore
import Testing

struct RateLimitWindowSamplesTests {
    @Test
    func `overlapping windows keep most constrained budget until expiry`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let coreReset = now.addingTimeInterval(600)
        let eventsReset = now.addingTimeInterval(3600)
        var samples = RateLimitWindowSamples()
        samples.record(Self.sample(remaining: 599, reset: coreReset, at: now))
        samples.record(Self.sample(remaining: 4959, reset: eventsReset, at: now.addingTimeInterval(1)))
        #expect(samples.snapshot(now: now.addingTimeInterval(2))?.remaining == 599)
        #expect(samples.snapshot(now: now.addingTimeInterval(2))?.reset == coreReset)

        // A late response from the same window cannot refill the counter.
        samples.record(Self.sample(remaining: 610, reset: coreReset, at: now.addingTimeInterval(3)))
        #expect(samples.snapshot(now: now.addingTimeInterval(4))?.remaining == 599)
        #expect(samples.snapshot(now: coreReset)?.remaining == 4959)

        // Preserve the still-active events window when the repository window rolls over.
        samples.record(Self.sample(remaining: 4999, reset: now.addingTimeInterval(4200), at: coreReset))
        #expect(samples.snapshot(now: coreReset)?.remaining == 4959)
        #expect(samples.snapshot(now: eventsReset)?.remaining == 4999)
    }

    @Test
    func `samples without reset use latest observation`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var samples = RateLimitWindowSamples()
        samples.record(Self.sample(remaining: 10, reset: nil, at: now))
        samples.record(Self.sample(remaining: 9, reset: nil, at: now.addingTimeInterval(1)))
        #expect(samples.snapshot(now: now.addingTimeInterval(2))?.remaining == 9)
    }

    private static func sample(remaining: Int, reset: Date?, at date: Date) -> RateLimitSnapshot {
        RateLimitSnapshot(resource: "core", limit: 5000, remaining: remaining, used: 5000 - remaining, reset: reset, fetchedAt: date)
    }
}
