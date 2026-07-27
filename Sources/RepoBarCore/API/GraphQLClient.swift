import Foundation

/// Minimal GraphQL helper (no codegen) to enrich repo data. Uses the same OAuth token as REST.
actor GraphQLClient {
    private var endpoint: URL = .init(string: "https://api.github.com/graphql")!
    private var tokenProvider: (@Sendable () async throws -> String)?
    private var rateLimit: RateLimitSnapshot?
    private let responseCache: GraphQLResponseDiskCache?
    private let dataLoader: HTTPDataLoader
    private let responseCacheTTL: TimeInterval = 15 * 60
    private let requestLimiter = AsyncPermitPool(limit: 4)
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let diag = DiagnosticsLogger.shared

    init(
        responseCache: GraphQLResponseDiskCache? = GraphQLResponseDiskCache.standard(),
        dataLoader: HTTPDataLoader = .live
    ) {
        self.responseCache = responseCache
        self.dataLoader = dataLoader
    }

    func setEndpoint(apiHost: URL) {
        // For GitHub.com apiHost is https://api.github.com
        // For GHE apiHost is https://host/api/v3 -> GraphQL lives at /api/graphql
        var components = URLComponents(url: apiHost, resolvingAgainstBaseURL: false)
        if apiHost.path.contains("/api/v3") {
            components?.path = "/api/graphql"
        } else {
            components?.path = "/graphql"
        }
        self.endpoint = components?.url ?? self.endpoint
    }

    func setTokenProvider(_ provider: @Sendable @escaping () async throws -> String) {
        self.tokenProvider = provider
    }

    func repoSummary(owner: String, name: String) async throws -> RepoSummary {
        let token = try await tokenProvider?() ?? { throw URLError(.userAuthenticationRequired) }()
        await diag.message("GraphQL RepoSummary \(owner)/\(name)")
        let startedAt = Date()

        let body = GraphQLRequest(
            query: """
            query RepoSummary($owner: String!, $name: String!) {
              repository(owner: $owner, name: $name) {
                name
                latestRelease { name tagName publishedAt createdAt url isDraft isPrerelease isLatest }
                issues(states: OPEN) { totalCount }
                pullRequests(states: OPEN) { totalCount }
              }
            }
            """,
            variables: ["owner": owner, "name": name]
        )

        let bodyData = try JSONEncoder().encode(body)
        let cacheKey = self.cacheKey(operation: "RepoSummary", bodyData: bodyData)
        if let cached = self.responseCache?.cached(key: cacheKey, maxAge: self.responseCacheTTL) {
            await self.diag.message("GraphQL RepoSummary \(owner)/\(name) cached")
            return try Self.decodeRepoSummary(from: cached.data, owner: owner, name: name)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch {
            if let stale = self.responseCache?.stale(key: cacheKey) {
                await self.diag.message("GraphQL RepoSummary \(owner)/\(name) using stale cache after \(error.userFacingMessage)")
                return try Self.decodeRepoSummary(from: stale.data, owner: owner, name: name)
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        await self.logGraphQLResponse(http, label: "RepoSummary", startedAt: startedAt)
        if let snapshot = RateLimitSnapshot.from(response: http) {
            self.rateLimit = snapshot
        }
        guard http.statusCode == 200 else {
            await self.diag.message("GraphQL status \(http.statusCode) for \(owner)/\(name)")
            if let stale = self.responseCache?.stale(key: cacheKey), Self.canUseStaleCache(for: http.statusCode) {
                await self.diag.message("GraphQL RepoSummary \(owner)/\(name) using stale cache for HTTP \(http.statusCode)")
                return try Self.decodeRepoSummary(from: stale.data, owner: owner, name: name)
            }
            if http.statusCode == 401 {
                throw URLError(.userAuthenticationRequired)
            }
            throw self.graphQLError(response: http)
        }

        self.responseCache?.save(key: cacheKey, endpoint: self.endpoint, operation: "RepoSummary", body: bodyData, responseBody: data)
        return try Self.decodeRepoSummary(from: data, owner: owner, name: name)
    }

    nonisolated static func decodeRepoSummary(from data: Data, owner _: String, name _: String) throws -> RepoSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GraphQLResponse<RepoSummaryData>.self, from: data)
        guard let repo = decoded.data.repository else {
            throw URLError(.cannotParseResponse)
        }

        let release = Self.latestRelease(from: repo.latestRelease)

        return RepoSummary(
            openIssues: repo.issues.totalCount,
            openPulls: repo.pullRequests.totalCount,
            release: release
        )
    }

    private nonisolated static func latestRelease(from release: ReleaseNode?) -> Release? {
        guard let release, release.isLatest, release.isDraft == false, release.isPrerelease == false else { return nil }

        let date = release.publishedAt ?? release.createdAt ?? Date.distantPast
        return Release(name: release.name ?? release.tagName, tag: release.tagName, publishedAt: date, url: release.url)
    }

    func userContributionHeatmap(login: String) async throws -> [HeatmapCell] {
        let token = try await tokenProvider?() ?? { throw URLError(.userAuthenticationRequired) }()
        await diag.message("GraphQL UserContributions \(login)")
        let startedAt = Date()

        let body = GraphQLRequest(
            query: """
            query UserContributions($login: String!) {
              user(login: $login) {
                contributionsCollection {
                  contributionCalendar {
                    weeks {
                      contributionDays {
                        date
                        contributionCount
                      }
                    }
                  }
                }
              }
            }
            """,
            variables: ["login": login]
        )

        let bodyData = try JSONEncoder().encode(body)
        let cacheKey = self.cacheKey(operation: "UserContributions", bodyData: bodyData)
        if let cached = self.responseCache?.cached(key: cacheKey, maxAge: self.responseCacheTTL) {
            await self.diag.message("GraphQL UserContributions \(login) cached")
            return try self.decodeContributionHeatmap(from: cached.data, login: login)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch {
            if let stale = self.responseCache?.stale(key: cacheKey) {
                await self.diag.message("GraphQL UserContributions \(login) using stale cache after \(error.userFacingMessage)")
                return try self.decodeContributionHeatmap(from: stale.data, login: login)
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        await self.logGraphQLResponse(http, label: "UserContributions", startedAt: startedAt)
        if let snapshot = RateLimitSnapshot.from(response: http) {
            self.rateLimit = snapshot
        }
        guard http.statusCode == 200 else {
            await self.diag.message("GraphQL status \(http.statusCode) for contributions \(login)")
            if let stale = self.responseCache?.stale(key: cacheKey), Self.canUseStaleCache(for: http.statusCode) {
                await self.diag.message("GraphQL UserContributions \(login) using stale cache for HTTP \(http.statusCode)")
                return try self.decodeContributionHeatmap(from: stale.data, login: login)
            }
            if http.statusCode == 401 {
                throw URLError(.userAuthenticationRequired)
            }
            throw self.graphQLError(response: http)
        }

        self.responseCache?.save(key: cacheKey, endpoint: self.endpoint, operation: "UserContributions", body: bodyData, responseBody: data)
        return try self.decodeContributionHeatmap(from: data, login: login)
    }

    private func decodeContributionHeatmap(from data: Data, login _: String) throws -> [HeatmapCell] {
        let decoded = try decoder.decode(GraphQLResponse<UserContributionData>.self, from: data)
        guard let weeks = decoded.data.user?.contributionsCollection.contributionCalendar.weeks else {
            return []
        }

        return weeks.flatMap { week in
            week.contributionDays.compactMap { day in
                HeatmapCell(date: day.date, count: day.contributionCount)
            }
        }
    }

    func rateLimitSnapshot() -> RateLimitSnapshot? {
        self.rateLimit
    }

    // MARK: - Logging

    private func logGraphQLResponse(_ response: HTTPURLResponse, label: String, startedAt: Date) async {
        let durationMs = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        let snapshot = RateLimitSnapshot.from(response: response)
        if let snapshot {
            self.rateLimit = snapshot
        }

        let remaining = snapshot?.remaining.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
        let limit = snapshot?.limit.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "?"
        let used = snapshot?.used.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Used") ?? "?"
        let resetDate = snapshot?.reset ?? {
            if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"), let epoch = TimeInterval(reset) {
                return Date(timeIntervalSince1970: epoch)
            }
            return nil
        }()
        let resetText = resetDate.map { RelativeFormatter.string(from: $0, relativeTo: Date()) } ?? "n/a"
        let resource = snapshot?.resource ?? response.value(forHTTPHeaderField: "X-RateLimit-Resource") ?? "graphql"

        await self.diag.message(
            "GraphQL \(label) status=\(response.statusCode) res=\(resource) lim=\(limit) rem=\(remaining) used=\(used) reset=\(resetText) dur=\(durationMs)ms"
        )
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        await self.requestLimiter.acquire()
        do {
            let result = try await self.dataLoader.data(for: request)
            await self.requestLimiter.release()
            return result
        } catch {
            await self.requestLimiter.release()
            throw error
        }
    }

    private func cacheKey(operation: String, bodyData: Data) -> String {
        let body = String(data: bodyData, encoding: .utf8) ?? bodyData.base64EncodedString()
        return "\(self.endpoint.absoluteString)\t\(operation)\t\(body)"
    }

    private func graphQLError(response: HTTPURLResponse) -> Error {
        if response.statusCode == 403 || response.statusCode == 429 {
            let reset = RateLimitSnapshot.from(response: response)?.reset
            return GitHubAPIError.rateLimited(
                until: reset,
                message: "GitHub GraphQL rate limit hit."
            )
        }
        if response.statusCode == 502 || response.statusCode == 503 || response.statusCode == 504 {
            return GitHubAPIError.serviceUnavailable(
                retryAfter: nil,
                message: "GitHub GraphQL is temporarily unavailable."
            )
        }
        return URLError(.badServerResponse)
    }

    private static func canUseStaleCache(for statusCode: Int) -> Bool {
        statusCode == 403 || statusCode == 429 || statusCode == 502 || statusCode == 503 || statusCode == 504
    }
}

struct RepoSummary {
    let openIssues: Int
    let openPulls: Int
    let release: Release?
}

// MARK: - Wire models

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: String]
}

private struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T
}

private struct RepoSummaryData: Decodable {
    let repository: RepoSummaryNode?
}

private struct RepoSummaryNode: Decodable {
    let latestRelease: ReleaseNode?
    let issues: CountContainer
    let pullRequests: CountContainer
}

private struct ReleaseNode: Decodable {
    let name: String?
    let tagName: String
    let publishedAt: Date?
    let createdAt: Date?
    let url: URL
    let isDraft: Bool
    let isPrerelease: Bool
    let isLatest: Bool
}

private struct CountContainer: Decodable {
    let totalCount: Int
}

private struct UserContributionData: Decodable {
    let user: ContributionUser?
}

private struct ContributionUser: Decodable {
    let contributionsCollection: ContributionsCollection
}

private struct ContributionsCollection: Decodable {
    let contributionCalendar: ContributionCalendar
}

private struct ContributionCalendar: Decodable {
    let weeks: [ContributionWeek]
}

private struct ContributionWeek: Decodable {
    let contributionDays: [ContributionDay]
}

struct ContributionDay: Decodable {
    let date: Date
    let contributionCount: Int

    private enum CodingKeys: String, CodingKey {
        case date
        case contributionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawDate = try container.decode(String.self, forKey: .date)
        guard let parsedDate = Self.parseDate(rawDate) else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: container,
                debugDescription: "Unsupported date format: \(rawDate)"
            )
        }

        self.date = parsedDate
        self.contributionCount = try container.decode(Int.self, forKey: .contributionCount)
    }

    private static func parseDate(_ raw: String) -> Date? {
        if raw.contains("T") {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}
