import Foundation

actor GitHubRequestRunner {
    private let etagCache: ETagCache
    private let backoff: BackoffTracker
    private let diag: DiagnosticsLogger
    private let dataLoader: HTTPDataLoader
    private let logger = RepoBarLogging.logger("github-rest")
    private var lastRateLimitReset: Date?
    private var lastRateLimitError: String?
    private var latestRestRateLimit: RateLimitSnapshot?
    private var latestRateLimitResources: RateLimitResourcesSnapshot?
    private let coreLimiter = AsyncPermitPool(limit: 6)
    private let searchLimiter = AsyncPermitPool(limit: 1)
    private let statsLimiter = AsyncPermitPool(limit: 2)

    init(
        etagCache: ETagCache = ETagCache.persistent(),
        backoff: BackoffTracker = BackoffTracker(),
        diag: DiagnosticsLogger = .shared,
        dataLoader: HTTPDataLoader = .live
    ) {
        self.etagCache = etagCache
        self.backoff = backoff
        self.diag = diag
        self.dataLoader = dataLoader
    }

    func rateLimitReset(now: Date = Date()) -> Date? {
        guard let reset = self.lastRateLimitReset, reset > now else {
            self.lastRateLimitReset = nil
            self.lastRateLimitError = nil
            return nil
        }

        return reset
    }

    func rateLimitMessage(now: Date = Date()) -> String? {
        guard self.rateLimitReset(now: now) != nil else { return nil }

        return self.lastRateLimitError
    }

    func get(
        url: URL,
        token: String,
        allowedStatuses: Set<Int> = [200, 304],
        headers: [String: String] = [:],
        useETag: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let startedAt = Date()
        self.logger.debug("GET \(Self.logPath(for: url))")
        await self.diag.message("GET \(Self.logPath(for: url))")
        if await self.etagCache.isRateLimited(), let until = await etagCache.rateLimitUntil() {
            self.logger.warning("Blocked by local rate limit until \(until)")
            await self.diag.message("Blocked by local rateLimit until \(until)")
            throw GitHubAPIError.rateLimited(
                until: until,
                message: "GitHub rate limit hit; resets \(RelativeFormatter.string(from: until, relativeTo: Date()))."
            )
        }
        if let cooldown = await backoff.cooldown(for: url) {
            self.logger.warning("Cooldown active for \(Self.logPath(for: url)) until \(cooldown)")
            await self.diag.message("Cooldown active for \(Self.logPath(for: url)) until \(cooldown)")
            throw GitHubAPIError.serviceUnavailable(
                retryAfter: cooldown,
                message: Self.cooldownMessage(for: url, until: cooldown)
            )
        }

        var request = Self.makeRequest(url: url, token: token, headers: headers, useETag: useETag)
        if useETag, let cached = await etagCache.cached(for: url) {
            request.addValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, responseAny) = try await self.data(for: request, url: url)
        guard let response = responseAny as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        await self.logResponse("GET", url: url, response: response, startedAt: startedAt)

        let status = response.statusCode
        if status == 304, useETag, let cached = await etagCache.cached(for: url) {
            self.logger.debug("HTTP GET \(Self.logPath(for: url)) status=304 cached=true")
            await self.diag.message("304 Not Modified for \(url.lastPathComponent); using cached")
            return (cached.data, response)
        }

        if status == 202 {
            let retryAfter = self.retryAfterDate(from: response) ?? Date().addingTimeInterval(90)
            await self.backoff.setCooldown(url: response.url ?? url, until: retryAfter)
            let retryText = RelativeFormatter.string(from: retryAfter, relativeTo: Date())
            let message = "GitHub is generating repository stats; some numbers may be stale. RepoBar will retry \(retryText)."
            self.logger.warning("HTTP GET \(Self.logPath(for: url)) status=202 retryAfter=\(retryAfter)")
            await self.diag.message("202 for \(url.lastPathComponent); cooldown until \(retryAfter)")
            throw GitHubAPIError.serviceUnavailable(
                retryAfter: retryAfter,
                message: message
            )
        }

        if status == 403 || status == 429 {
            let remainingHeader = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            let remaining = Int(remainingHeader ?? "")

            // If we still have quota, this 403 is likely permissions/abuse detection; surface it as a normal error.
            if let remaining, remaining > 0 {
                self.logger.warning("HTTP GET \(Self.logPath(for: url)) status=\(status) remaining=\(remaining)")
                await self.diag.message("403 with remaining=\(remaining) on \(url.lastPathComponent); treating as bad status")
                throw GitHubAPIError.badStatus(code: status, message: Self.statusMessage(for: status, data: data))
            }

            let resetDate = self.rateLimitDate(from: response) ?? Date().addingTimeInterval(60)
            self.lastRateLimitReset = resetDate
            await self.etagCache.setRateLimitReset(date: resetDate)
            self.lastRateLimitError = "GitHub rate limit hit; resets " +
                "\(RelativeFormatter.string(from: resetDate, relativeTo: Date()))."
            self.logger.warning("HTTP GET \(Self.logPath(for: url)) rateLimited status=\(status) reset=\(resetDate)")
            await self.diag.message("Rate limited on \(url.lastPathComponent); resets \(resetDate)")
            throw GitHubAPIError.rateLimited(until: resetDate, message: self.lastRateLimitError ?? "Rate limited.")
        }

        guard allowedStatuses.contains(status) else {
            self.logger.warning("HTTP GET \(Self.logPath(for: url)) unexpectedStatus=\(status)")
            await self.diag.message("Unexpected status \(status) for \(url.lastPathComponent)")
            throw GitHubAPIError.badStatus(
                code: status,
                message: Self.statusMessage(for: status, data: data)
            )
        }

        if useETag, Self.shouldCacheETagResponse(statusCode: status), let etag = response.value(forHTTPHeaderField: "ETag") {
            await self.etagCache.save(url: url, etag: etag, data: data, response: response)
            await self.diag.message("Cached ETag for \(url.lastPathComponent)")
        }
        if let snapshot = RateLimitSnapshot.from(response: response) {
            self.latestRestRateLimit = snapshot
        }
        self.detectRateLimit(from: response)
        return (data, response)
    }

    static func makeRequest(
        url: URL,
        token: String,
        headers: [String: String] = [:],
        useETag: Bool = true
    ) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: useETag ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        )
        // GitHub requires "Bearer" for OAuth access tokens; "token" is for classic tokens.
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (header, value) in headers {
            request.addValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    static func shouldCacheETagResponse(statusCode: Int) -> Bool {
        statusCode == 200
    }

    private func data(for request: URLRequest, url: URL) async throws -> (Data, URLResponse) {
        let limiter = self.limiter(for: url)
        await limiter.acquire()
        do {
            let result = try await self.dataLoader.data(for: request)
            await limiter.release()
            return result
        } catch {
            await limiter.release()
            throw error
        }
    }

    private func limiter(for url: URL) -> AsyncPermitPool {
        let path = url.path
        if path.hasPrefix("/search/") {
            return self.searchLimiter
        }
        if path.contains("/stats/") {
            return self.statsLimiter
        }
        return self.coreLimiter
    }

    static func cooldownMessage(for url: URL, until: Date, now: Date = Date()) -> String {
        "GitHub endpoint cooldown (\(self.endpointDescription(for: url))); retry \(RelativeFormatter.string(from: until, relativeTo: now))"
    }

    static func statusMessage(for status: Int, data: Data) -> String {
        let fallback = HTTPURLResponse.localizedString(forStatusCode: status)
        guard let error = try? GitHubDecoding.decode(GitHubErrorResponse.self, from: data) else {
            return "GitHub returned \(status): \(fallback)."
        }

        var parts = [error.message]
        for detail in error.errors ?? [] {
            guard let message = detail.message?.trimmingCharacters(in: .whitespacesAndNewlines), message.isEmpty == false else {
                continue
            }

            if parts.contains(where: { $0.caseInsensitiveCompare(message) == .orderedSame }) == false {
                parts.append(message)
            }
        }

        let detail = parts.joined(separator: ": ")
        let suffix = detail.hasSuffix(".") || detail.hasSuffix("!") || detail.hasSuffix("?") ? "" : "."
        return "GitHub returned \(status): \(detail)\(suffix)"
    }

    func clear() async {
        await self.etagCache.clear()
        await self.backoff.clear()
        self.lastRateLimitReset = nil
        self.lastRateLimitError = nil
        self.latestRestRateLimit = nil
        self.latestRateLimitResources = nil
    }

    func recordRateLimitResources(_ snapshot: RateLimitResourcesSnapshot) {
        self.latestRateLimitResources = snapshot
        if let core = snapshot.resources["core"] ?? snapshot.resources["rate"] {
            self.latestRestRateLimit = core
            self.detectRateLimit(from: core)
        }
    }

    func diagnosticsSnapshot() async -> RequestRunnerDiagnostics {
        let etagCount = await self.etagCache.count()
        let activeCooldowns = await self.backoff.activeCooldowns()
        let endpointCooldowns = activeCooldowns
            .compactMap { urlString, retryAfter -> EndpointCooldownSummary? in
                guard let url = URL(string: urlString) else { return nil }

                return EndpointCooldownSummary(
                    endpoint: Self.endpointDescription(for: url),
                    repository: Self.repositoryName(for: url),
                    url: urlString,
                    retryAfter: retryAfter
                )
            }
            .sorted { lhs, rhs in
                if lhs.retryAfter != rhs.retryAfter {
                    return lhs.retryAfter < rhs.retryAfter
                }
                return lhs.url < rhs.url
            }
        return RequestRunnerDiagnostics(
            rateLimitReset: self.lastRateLimitReset,
            lastRateLimitError: self.lastRateLimitError,
            etagEntries: etagCount,
            backoffEntries: activeCooldowns.count,
            endpointCooldowns: endpointCooldowns,
            restRateLimit: self.latestRestRateLimit,
            rateLimitResources: self.latestRateLimitResources
        )
    }

    private func logResponse(
        _ method: String,
        url: URL,
        response: HTTPURLResponse,
        startedAt: Date
    ) async {
        let durationMs = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        let snapshot = RateLimitSnapshot.from(response: response)
        if let snapshot {
            self.latestRestRateLimit = snapshot
        }

        let remaining = snapshot?.remaining.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
        let limit = snapshot?.limit.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "?"
        let used = snapshot?.used.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Used") ?? "?"
        let resetDate = snapshot?.reset ?? self.rateLimitDate(from: response)
        let resetText = resetDate.map { RelativeFormatter.string(from: $0, relativeTo: Date()) } ?? "n/a"
        let resource = snapshot?.resource ?? response.value(forHTTPHeaderField: "X-RateLimit-Resource") ?? "rest"

        await self.diag.message(
            "HTTP \(method) \(url.path) status=\(response.statusCode) res=\(resource) lim=\(limit) rem=\(remaining) used=\(used) reset=\(resetText) dur=\(durationMs)ms"
        )
        let path = Self.logPath(for: url)
        self.logger.debug(
            "HTTP \(method) \(path) status=\(response.statusCode) res=\(resource) rem=\(remaining)/\(limit) used=\(used) reset=\(resetText) dur=\(durationMs)ms"
        )
    }

    private func rateLimitDate(from response: HTTPURLResponse) -> Date? {
        guard let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let epoch = TimeInterval(reset) else { return nil }

        return Date(timeIntervalSince1970: epoch)
    }

    private func retryAfterDate(from response: HTTPURLResponse) -> Date? {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(retryAfter) {
            return Date().addingTimeInterval(seconds)
        }
        return nil
    }

    private func detectRateLimit(from response: HTTPURLResponse) {
        guard
            let remainingText = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
            let remaining = Int(remainingText)
        else { return }

        if remaining <= 0 {
            self.lastRateLimitReset = self.rateLimitDate(from: response)
        } else if let reset = self.lastRateLimitReset, reset <= Date() {
            self.lastRateLimitReset = nil
            self.lastRateLimitError = nil
        }
    }

    private func detectRateLimit(from snapshot: RateLimitSnapshot) {
        guard let remaining = snapshot.remaining else { return }

        if remaining <= 0 {
            self.lastRateLimitReset = snapshot.reset
        } else if let reset = self.lastRateLimitReset, reset <= Date() {
            self.lastRateLimitReset = nil
            self.lastRateLimitError = nil
        }
    }

    private static func endpointDescription(for url: URL) -> String {
        let components = url.path.split(separator: "/").map(String.init)
        let suffix: String = if let repoIndex = components.firstIndex(of: "repos"), components.count > repoIndex + 3 {
            components[(repoIndex + 3)...].joined(separator: "/")
        } else {
            components.joined(separator: "/")
        }

        switch suffix {
        case "":
            return "repository details"
        case "actions/runs":
            return "Actions runs"
        case "pulls":
            return "pull requests"
        case "issues":
            return "issues"
        case "releases":
            return "releases"
        case "stats/commit_activity":
            return "commit activity"
        case "traffic/clones":
            return "traffic clones"
        case "traffic/views":
            return "traffic views"
        default:
            return suffix
        }
    }

    private static func repositoryName(for url: URL) -> String? {
        let components = url.path.split(separator: "/").map(String.init)
        guard let repoIndex = components.firstIndex(of: "repos"), components.count > repoIndex + 2 else {
            return nil
        }

        return "\(components[repoIndex + 1])/\(components[repoIndex + 2])"
    }

    static func logPath(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.isEmpty == false
        else {
            guard let query = url.query, query.isEmpty == false else { return url.path }

            return "\(url.path)?<redacted>"
        }

        let query = queryItems
            .map { "\($0.name)=<redacted>" }
            .joined(separator: "&")
        return "\(url.path)?\(query)"
    }
}

private struct GitHubErrorResponse: Decodable {
    let message: String
    let errors: [GitHubErrorDetail]?
}

private struct GitHubErrorDetail: Decodable {
    let message: String?
}

struct RequestRunnerDiagnostics {
    let rateLimitReset: Date?
    let lastRateLimitError: String?
    let etagEntries: Int
    let backoffEntries: Int
    let endpointCooldowns: [EndpointCooldownSummary]
    let restRateLimit: RateLimitSnapshot?
    let rateLimitResources: RateLimitResourcesSnapshot?
}
