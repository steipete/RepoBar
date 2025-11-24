import Foundation
import OSLog

/// Lightweight GitHub client using REST plus a minimal GraphQL enrichment step.
actor GitHubClient {
    var apiHost: URL = .init(string: "https://api.github.com")!
    private let tokenStore = TokenStore()
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let etagCache = ETagCache()
    private let backoff = BackoffTracker()
    private var lastRateLimitReset: Date?
    private var lastRateLimitError: String?
    private var tokenProvider: (@Sendable () async throws -> OAuthTokens?)?
    private let graphQL = GraphQLClient()
    private let diag = DiagnosticsLogger.shared
    private var installationTokenProvider: (@Sendable () async throws -> String)?

    // MARK: - Config

    func setAPIHost(_ host: URL) {
        do {
            let trusted = try self.trusted(host)
            self.apiHost = trusted
            Task { await self.graphQL.setEndpoint(apiHost: trusted) }
            Task { await self.diag.message("API host set to \(trusted.absoluteString)") }
        } catch {
            Task { await self.diag.message("Rejected API host \(host) (must be https with hostname)") }
        }
    }

    private func trusted(_ host: URL) throws -> URL {
        guard host.scheme?.lowercased() == "https" else { throw GitHubAPIError.invalidHost }
        guard host.host != nil else { throw GitHubAPIError.invalidHost }
        return host
    }

    func setTokenProvider(_ provider: @Sendable @escaping () async throws -> OAuthTokens?) {
        self.tokenProvider = provider
        Task {
            await self.graphQL.setTokenProvider {
                guard let tokens = try await provider() else { throw URLError(.userAuthenticationRequired) }
                return tokens.accessToken
            }
        }
    }

    func setInstallationTokenProvider(_ provider: @Sendable @escaping () async throws -> String) {
        self.installationTokenProvider = provider
    }

    func rateLimitReset() -> Date? { self.lastRateLimitReset }
    func rateLimitMessage() -> String? { self.lastRateLimitError }

    // MARK: - High level fetchers

    func defaultRepositories(limit: Int, for username: String) async throws -> [Repository] {
        let repos = try await userReposSorted(limit: max(limit, 10))
        return try await withThrowingTaskGroup(of: Repository.self) { group in
            for repo in repos.prefix(limit) {
                group.addTask { try await self.fullRepository(owner: repo.owner.login, name: repo.name) }
            }
            var items: [Repository] = []
            for try await repo in group {
                items.append(repo)
            }
            return items
        }
    }

    func fullRepository(owner: String, name: String) async throws -> Repository {
        var accumulator = RepoErrorAccumulator()

        let details: RepoItem
        do {
            details = try await self.repoDetails(owner: owner, name: name)
        } catch {
            accumulator.absorb(error)
            return Repository(
                id: "\(owner)/\(name)",
                name: name,
                owner: owner,
                sortOrder: nil,
                error: accumulator.message,
                rateLimitedUntil: accumulator.rateLimit,
                ciStatus: .unknown,
                openIssues: 0,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: [])
        }

        async let issuesResult: Result<Int, Error> = self.capture { try await self.openCount(
            owner: owner,
            name: name,
            type: .issue) }
        async let prsResult: Result<Int, Error> = self.capture { try await self.openCount(
            owner: owner,
            name: name,
            type: .pullRequest) }
        async let releaseResult: Result<Release, Error> = self.capture { try await self.latestRelease(
            owner: owner,
            name: name) }
        async let ciResult: Result<CIStatus, Error> = self.capture { try await self.ciStatus(owner: owner, name: name) }
        async let activityResult: Result<ActivityEvent, Error> = self.capture { try await self.latestActivity(
            owner: owner,
            name: name) }
        async let trafficResult: Result<TrafficStats, Error> = self.capture { try await self.trafficStats(
            owner: owner,
            name: name) }
        async let heatmapResult: Result<[HeatmapCell], Error> = self.capture { try await self.commitHeatmap(
            owner: owner,
            name: name) }
        async let graphResult: Result<GraphRepoSnapshot, Error> = self
            .capture { try await self.graphQL.fetchRepoSnapshot(
                owner: owner,
                name: name) }

        let issues = await self.value(from: issuesResult, into: &accumulator) ?? details.openIssuesCount
        let pulls = await self.value(from: prsResult, into: &accumulator) ?? 0
        let releaseREST = await self.value(from: releaseResult, into: &accumulator)
        let ci = await self.value(from: ciResult, into: &accumulator) ?? .unknown
        let activity = await self.value(from: activityResult, into: &accumulator)
        let traffic = await self.value(from: trafficResult, into: &accumulator)
        let heatmap = await self.value(from: heatmapResult, into: &accumulator) ?? []

        if case let .failure(err) = await graphResult { accumulator.absorb(err) }
        let graph = try? await graphResult.get()

        let finalIssues = graph?.openIssues ?? issues
        let finalPulls = graph?.openPulls ?? pulls
        let finalRelease = graph?.release ?? releaseREST
        let finalActivity = graph?.activity ?? activity

        return Repository(
            id: "\(details.id)",
            name: details.name,
            owner: details.owner.login,
            sortOrder: nil,
            error: accumulator.message,
            rateLimitedUntil: accumulator.rateLimit,
            ciStatus: ci,
            openIssues: finalIssues,
            openPulls: finalPulls,
            latestRelease: finalRelease,
            latestActivity: finalActivity,
            traffic: traffic,
            heatmap: heatmap)
    }

    func currentUser() async throws -> UserIdentity {
        let token = try await validAccessToken()
        let url = self.apiHost.appending(path: "/user")
        let (data, _) = try await authorizedGet(url: url, token: token)
        let user = try jsonDecoder.decode(CurrentUser.self, from: data)
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        let rawHost = url.host ?? "github.com"
        components.host = rawHost == "api.github.com" ? "github.com" : rawHost
        let hostURL = components.url ?? URL(string: "https://github.com")!
        return UserIdentity(username: user.login, host: hostURL)
    }

    func searchRepositories(matching query: String) async throws -> [Repository] {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: apiHost.appending(path: "/search/repositories"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "per_page", value: "5")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let decoded = try jsonDecoder.decode(SearchResponse.self, from: data)
        return decoded.items.map { item in
            Repository(
                id: item.id.description,
                name: item.name,
                owner: item.owner.login,
                sortOrder: nil,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .unknown,
                openIssues: item.openIssuesCount,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: [])
        }
    }

    func clearCache() async {
        await self.etagCache.clear()
        await self.backoff.clear()
        self.lastRateLimitReset = nil
        self.lastRateLimitError = nil
    }

    func diagnostics() async -> DiagnosticsSummary {
        let etagCount = await self.etagCache.count()
        let backoffCount = await self.backoff.count()
        return DiagnosticsSummary(
            apiHost: self.apiHost,
            rateLimitReset: self.lastRateLimitReset,
            lastRateLimitError: self.lastRateLimitError,
            etagEntries: etagCount,
            backoffEntries: backoffCount)
    }

    /// Recent repositories for the authenticated user, sorted by activity.
    func recentRepositories(limit: Int = 8) async throws -> [Repository] {
        let items = try await self.userReposSorted(limit: limit)
        return items.map { item in
            Repository(
                id: item.id.description,
                name: item.name,
                owner: item.owner.login,
                sortOrder: nil,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .unknown,
                openIssues: item.openIssuesCount,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: [])
        }
    }

    // MARK: - Internal REST helpers

    private enum CountType { case issue, pullRequest }

    private func userReposSorted(limit: Int) async throws -> [RepoItem] {
        let token = try await validAccessToken()
        var components = URLComponents(url: apiHost.appending(path: "/user/repos"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "\(limit)"),
            URLQueryItem(name: "sort", value: "pushed"),
            URLQueryItem(name: "direction", value: "desc"),
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try self.jsonDecoder.decode([RepoItem].self, from: data)
    }

    private func repoDetails(owner: String, name: String) async throws -> RepoItem {
        let token = try await validAccessToken()
        let url = self.apiHost.appending(path: "/repos/\(owner)/\(name)")
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try self.jsonDecoder.decode(RepoItem.self, from: data)
    }

    private func openCount(owner: String, name: String, type: CountType) async throws -> Int {
        let token = try await validAccessToken()
        let typeQuery = (type == .issue) ? "type:issue" : "type:pr"
        var components = URLComponents(url: apiHost.appending(path: "/search/issues"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "repo:\(owner)/\(name)+state:open+\(typeQuery)"),
            URLQueryItem(name: "per_page", value: "1"),
        ]
        let (data, response) = try await authorizedGet(url: components.url!, token: token)
        self.detectRateLimit(from: response)
        let decoded = try jsonDecoder.decode(SearchIssuesResponse.self, from: data)
        return decoded.totalCount
    }

    private func latestRelease(owner: String, name: String) async throws -> Release {
        let token = try await validAccessToken()
        let url = self.apiHost.appending(path: "/repos/\(owner)/\(name)/releases/latest")
        let (data, response) = try await authorizedGet(url: url, token: token, allowedStatuses: [200, 304, 404])
        guard response.statusCode != 404 else { throw URLError(.fileDoesNotExist) }
        let rel = try jsonDecoder.decode(ReleaseResponse.self, from: data)
        return Release(name: rel.name ?? rel.tagName, tag: rel.tagName, publishedAt: rel.publishedAt, url: rel.htmlUrl)
    }

    private func ciStatus(owner: String, name: String) async throws -> CIStatus {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: apiHost.appending(path: "/repos/\(owner)/\(name)/actions/runs"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "1")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let runs = try jsonDecoder.decode(ActionsRunsResponse.self, from: data)
        guard let run = runs.workflowRuns.first else { return .unknown }
        switch run.conclusion ?? run.status {
        case "success": return .passing
        case "failure", "cancelled", "timed_out": return .failing
        case "in_progress", "queued", "waiting": return .pending
        default: return .unknown
        }
    }

    private func latestActivity(owner: String, name: String) async throws -> ActivityEvent {
        let token = try await validAccessToken()
        async let issueComment = self.latestComment(
            from: self.apiHost.appending(path: "/repos/\(owner)/\(name)/issues/comments"),
            token: token)
        async let reviewComment = self.latestComment(
            from: self.apiHost.appending(path: "/repos/\(owner)/\(name)/pulls/comments"),
            token: token)
        let candidates = await [try? issueComment, try? reviewComment]
            .compactMap(\.self)
            .sorted(by: { $0.date > $1.date })
        guard let newest = candidates.first
        else { throw URLError(.cannotParseResponse) }
        return newest
    }

    private func latestComment(from url: URL, token: String) async throws -> ActivityEvent {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "sort", value: "created"),
            URLQueryItem(name: "direction", value: "desc"),
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let decoded = try jsonDecoder.decode([CommentResponse].self, from: data)
        guard let comment = decoded.first else { throw URLError(.cannotParseResponse) }
        return ActivityEvent(
            title: comment.bodyPreview,
            actor: comment.user.login,
            date: comment.createdAt,
            url: comment.htmlUrl)
    }

    private func trafficStats(owner: String, name: String) async throws -> TrafficStats {
        let token = try await validAccessToken()
        let viewsURL = self.apiHost.appending(path: "/repos/\(owner)/\(name)/traffic/views")
        let clonesURL = self.apiHost.appending(path: "/repos/\(owner)/\(name)/traffic/clones")
        async let viewsPair = self.authorizedGet(url: viewsURL, token: token)
        async let clonesPair = self.authorizedGet(url: clonesURL, token: token)
        let views = try await jsonDecoder.decode(TrafficResponse.self, from: viewsPair.0)
        let clones = try await jsonDecoder.decode(TrafficResponse.self, from: clonesPair.0)
        return TrafficStats(uniqueVisitors: views.uniques, uniqueCloners: clones.uniques)
    }

    private func commitHeatmap(owner: String, name: String) async throws -> [HeatmapCell] {
        let token = try await validAccessToken()
        let (data, _) = try await authorizedGet(
            url: apiHost.appending(path: "/repos/\(owner)/\(name)/stats/commit_activity"),
            token: token)
        let weeks = try jsonDecoder.decode([CommitActivityWeek].self, from: data)
        return weeks.flatMap { week in
            zip(0..<7, week.days).map { offset, count in
                let date = Date(timeIntervalSince1970: TimeInterval(week.weekStart + offset * 86400))
                return HeatmapCell(date: date, count: count)
            }
        }
    }

    private func authorizedGet(
        url: URL,
        token: String,
        allowedStatuses: Set<Int> = [200, 304]) async throws -> (Data, HTTPURLResponse)
    {
        await self.diag.message("GET \(url.absoluteString)")
        if await self.etagCache.isRateLimited(), let until = await etagCache.rateLimitUntil() {
            await self.diag.message("Blocked by local rateLimit until \(until)")
            throw GitHubAPIError.rateLimited(
                until: until,
                message: "GitHub rate limit hit; resets \(RelativeFormatter.string(from: until, relativeTo: Date())).")
        }
        if let cooldown = await backoff.cooldown(for: url) {
            await self.diag.message("Cooldown active for \(url.absoluteString) until \(cooldown)")
            throw GitHubAPIError.serviceUnavailable(
                retryAfter: cooldown,
                message: "Cooling down until \(RelativeFormatter.string(from: cooldown, relativeTo: Date())).")
        }

        var request = URLRequest(url: url)
        // GitHub requires "Bearer" here for OAuth access tokens; "token" is for classic tokens.
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let cached = await etagCache.cached(for: url) {
            request.addValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, responseAny) = try await URLSession.shared.data(for: request)
        guard let response = responseAny as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        let status = response.statusCode
        if status == 304, let cached = await etagCache.cached(for: url) {
            await self.diag.message("304 Not Modified for \(url.lastPathComponent); using cached")
            return (cached.data, response)
        }

        if status == 202 {
            let retryAfter = self.retryAfterDate(from: response) ?? Date().addingTimeInterval(90)
            await self.backoff.setCooldown(url: response.url ?? url, until: retryAfter)
            let retryText = RelativeFormatter.string(from: retryAfter, relativeTo: Date())
            let message = "GitHub is preparing stats; retry \(retryText)."
            await self.diag.message("202 for \(url.lastPathComponent); cooldown until \(retryAfter)")
            throw GitHubAPIError.serviceUnavailable(
                retryAfter: retryAfter,
                message: message)
        }

        if status == 403 || status == 429 {
            let resetDate = self.rateLimitDate(from: response) ?? Date().addingTimeInterval(60)
            self.lastRateLimitReset = resetDate
            await self.etagCache.setRateLimitReset(date: resetDate)
            await self.backoff.setCooldown(url: response.url ?? url, until: resetDate)
            self.lastRateLimitError = "GitHub rate limit hit; resets " +
                "\(RelativeFormatter.string(from: resetDate, relativeTo: Date()))."
            await self.diag.message("Rate limited on \(url.lastPathComponent); resets \(resetDate)")
            throw GitHubAPIError.rateLimited(until: resetDate, message: self.lastRateLimitError ?? "Rate limited.")
        }

        guard allowedStatuses.contains(status) else {
            await self.diag.message("Unexpected status \(status) for \(url.lastPathComponent)")
            throw GitHubAPIError.badStatus(
                code: status,
                message: HTTPURLResponse.localizedString(forStatusCode: status))
        }

        if let etag = response.value(forHTTPHeaderField: "ETag") {
            await self.etagCache.save(url: url, etag: etag, data: data)
            await self.diag.message("Cached ETag for \(url.lastPathComponent)")
        }
        self.detectRateLimit(from: response)
        return (data, response)
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
        if let resetDate = rateLimitDate(from: response) {
            self.lastRateLimitReset = resetDate
        }
    }

    private func validAccessToken() async throws -> String {
        // Prefer installation token when available.
        if let installProvider = installationTokenProvider {
            if let cached = try tokenStore.load()?.accessToken { return cached }
            let installToken = try await installProvider()
            return installToken
        }
        if let token = try tokenStore.load()?.accessToken { return token }
        if let provider = tokenProvider, let tokens = try await provider() { return tokens.accessToken }
        throw URLError(.userAuthenticationRequired)
    }

    // MARK: - Small helpers

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }

    private func value<T>(from result: Result<T, Error>, into accumulator: inout RepoErrorAccumulator) -> T? {
        switch result {
        case let .success(value): return value
        case let .failure(error):
            accumulator.absorb(error)
            return nil
        }
    }
}

struct DiagnosticsSummary {
    let apiHost: URL
    let rateLimitReset: Date?
    let lastRateLimitError: String?
    let etagEntries: Int
    let backoffEntries: Int

    static let empty = DiagnosticsSummary(
        apiHost: URL(string: "https://api.github.com")!,
        rateLimitReset: nil,
        lastRateLimitError: nil,
        etagEntries: 0,
        backoffEntries: 0)
}
