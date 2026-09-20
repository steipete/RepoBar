import Foundation

public struct RateLimitSnapshot: Codable, Sendable {
    public let resource: String?
    public let limit: Int?
    public let remaining: Int?
    public let used: Int?
    public let reset: Date?
    public let fetchedAt: Date

    public static func from(response: HTTPURLResponse, now: Date = Date()) -> RateLimitSnapshot? {
        let limit = Int(response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "")
        let remaining = Int(response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "")
        let used = Int(response.value(forHTTPHeaderField: "X-RateLimit-Used") ?? "")
        let resource = response.value(forHTTPHeaderField: "X-RateLimit-Resource")

        let resetHeader = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
        let reset: Date? = if let resetHeader, let epoch = TimeInterval(resetHeader) {
            Date(timeIntervalSince1970: epoch)
        } else {
            nil
        }

        if limit == nil, remaining == nil, reset == nil, used == nil, resource == nil {
            return nil // No headers present; avoid producing empty snapshots.
        }

        return RateLimitSnapshot(
            resource: resource,
            limit: limit,
            remaining: remaining,
            used: used,
            reset: reset,
            fetchedAt: now
        )
    }

    static func newest(_ first: RateLimitSnapshot?, _ second: RateLimitSnapshot?) -> RateLimitSnapshot? {
        guard let first else { return second }
        guard let second, second.fetchedAt > first.fetchedAt else { return first }

        return second
    }

    /// GitHub's /rate_limit endpoint can report an unused, rolling window even
    /// while ordinary response headers show real usage. Keep that direct
    /// evidence until its window expires; a newer summary is not proof of a reset.
    static func preferred(reported: RateLimitSnapshot?, response: RateLimitSnapshot?) -> RateLimitSnapshot? {
        guard let response else { return reported }
        guard let reported else { return response }

        if response.fetchedAt >= reported.fetchedAt {
            return response
        }
        if let reset = response.reset, reset <= reported.fetchedAt {
            return reported
        }
        return response
    }

    public var remainingPercent: Double? {
        RateLimitJuice.percent(remaining: self.remaining, limit: self.limit)
    }
}

public struct RateLimitResourcesSnapshot: Sendable {
    public let fetchedAt: Date
    public let resources: [String: RateLimitSnapshot]

    public init(fetchedAt: Date, resources: [String: RateLimitSnapshot]) {
        self.fetchedAt = fetchedAt
        self.resources = resources
    }

    public subscript(resource: String) -> RateLimitSnapshot? {
        self.resources[resource]
    }
}
