import Foundation

struct ActivitySnapshot {
    let events: [ActivityEvent]
    let latest: ActivityEvent?
}

struct GitHubRestAPI {
    let apiHost: @Sendable () async -> URL
    let tokenProvider: @Sendable () async throws -> String
    let requestRunner: GitHubRequestRunner
    let diag: DiagnosticsLogger

    static func userReposQueryItems() -> [URLQueryItem] {
        [
            URLQueryItem(name: "sort", value: "pushed"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
            URLQueryItem(name: "visibility", value: "all")
        ]
    }

    func userReposSorted(limit: Int) async throws -> [RepoItem] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(url: baseURL.appending(path: "/user/repos"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "\(limit)")] + Self.userReposQueryItems()
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try GitHubDecoding.decode([RepoItem].self, from: data)
    }

    /// Pulls paginated `/user/repos` in 100-item pages until the limit is reached or GitHub runs out.
    func userReposPaginated(limit: Int?) async throws -> [RepoItem] {
        try await self.fetchAllPages(
            path: "/user/repos",
            queryItems: Self.userReposQueryItems(),
            limit: limit,
            decode: { try GitHubDecoding.decode([RepoItem].self, from: $0) }
        )
    }

    func cachedUserReposPaginated(limit: Int?) async throws -> [RepoItem] {
        guard let cache = HTTPResponseDiskCache.standard() else { return [] }

        let pageSize = 100
        let baseURL = await apiHost()
        var collected: [RepoItem] = []
        var page = 1

        while true {
            var components = URLComponents(url: baseURL.appending(path: "/user/repos"), resolvingAgainstBaseURL: false)!
            var items = Self.userReposQueryItems()
            items.append(URLQueryItem(name: "per_page", value: "\(pageSize)"))
            items.append(URLQueryItem(name: "page", value: "\(page)"))
            components.queryItems = items

            guard let cached = cache.cached(url: components.url!) else { break }

            let pageItems = try GitHubDecoding.decode([RepoItem].self, from: cached.data)
            collected.append(contentsOf: pageItems)

            if let limit, collected.count >= limit {
                break
            }
            if pageItems.count < pageSize {
                break
            }
            page += 1
        }

        if let limit {
            return Array(collected.prefix(limit))
        }
        return collected
    }

    func fetchCurrentUser() async throws -> CurrentUser {
        let token = try await tokenProvider()
        let baseURL = await self.apiHost()
        let url = baseURL.appending(path: "/user")
        let (data, _) = try await authorizedGet(url: url, token: token, useETag: false)
        return try GitHubDecoding.decode(CurrentUser.self, from: data)
    }

    func fetchUserOrganizations() async throws -> [String] {
        let token = try await tokenProvider()
        let baseURL = await self.apiHost()
        let (data, _) = try await authorizedGet(
            url: baseURL.appending(path: "/user/orgs"),
            token: token,
            allowedStatuses: [200, 304],
            useETag: false
        )
        let orgs = try GitHubDecoding.decode([UserOrganization].self, from: data)
        return orgs.map(\.login)
    }

    func fetchOrganizationPlan(org: String) async throws -> String? {
        let token = try await tokenProvider()
        let baseURL = await self.apiHost()
        let (data, _) = try await authorizedGet(
            url: baseURL.appending(path: "/orgs/\(org)"),
            token: token,
            allowedStatuses: [200, 304, 403, 404],
            useETag: false
        )
        let detail = try? GitHubDecoding.decode(OrganizationDetail.self, from: data)
        return detail?.plan?.name
    }

    func rateLimitResources() async throws -> RateLimitResourcesSnapshot {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let now = Date()
        let (data, _) = try await authorizedGet(
            url: baseURL.appending(path: "/rate_limit"),
            token: token,
            useETag: false
        )
        let decoded = try GitHubDecoding.decode(RateLimitResponse.self, from: data)
        let resources = decoded.resources.mapValues { resource in
            RateLimitSnapshot(
                resource: resource.resource,
                limit: resource.limit,
                remaining: resource.remaining,
                used: resource.used,
                reset: Date(timeIntervalSince1970: TimeInterval(resource.reset)),
                fetchedAt: now
            )
        }
        let snapshot = RateLimitResourcesSnapshot(fetchedAt: now, resources: resources)
        await self.requestRunner.recordRateLimitResources(snapshot)
        return snapshot
    }

    func searchRepositories(matching query: String) async throws -> [RepoItem] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(
            url: baseURL.appending(path: "/search/repositories"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: Self.repoSearchQuery(from: trimmed)),
            URLQueryItem(name: "per_page", value: "8")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let decoded = try GitHubDecoding.decode(SearchResponse.self, from: data)
        return decoded.items
    }

    func searchIssueReferences(
        matching query: String,
        repositoryFullName: String?,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int
    ) async throws -> [GitHubReferenceMatch] {
        guard includeIssues || includePullRequests else { return [] }

        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/search/issues"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(
                name: "q",
                value: Self.issueReferenceSearchQuery(
                    from: query,
                    repositoryFullName: repositoryFullName,
                    includeIssues: includeIssues,
                    includePullRequests: includePullRequests
                )
            ),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(max(1, min(limit, 100)))")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let decoded = try GitHubDecoding.decode(IssueReferenceSearchResponse.self, from: data)
        return decoded.items.compactMap { $0.match() }
    }

    func recentIssueReferences(
        filter: String,
        includeIssues: Bool,
        includePullRequests: Bool,
        limit: Int
    ) async throws -> [GitHubReferenceMatch] {
        guard includeIssues || includePullRequests else { return [] }

        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/issues"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(max(1, min(limit, 100)))")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let decoded = try GitHubDecoding.decode([IssueReferenceSearchItem].self, from: data)
        return decoded.compactMap { item in
            guard let match = item.match() else { return nil }

            switch match.kind {
            case .issue:
                return includeIssues ? match : nil
            case .pullRequest:
                return includePullRequests ? match : nil
            case .commit, .workflowRun:
                return nil
            }
        }
    }

    private static func issueReferenceSearchQuery(
        from query: String,
        repositoryFullName: String?,
        includeIssues: Bool,
        includePullRequests: Bool
    ) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if trimmed.isEmpty == false {
            parts.append(trimmed)
        }
        if let repositoryFullName, repositoryFullName.isEmpty == false {
            parts.append("repo:\(repositoryFullName)")
        }
        switch (includeIssues, includePullRequests) {
        case (true, false):
            parts.append("is:issue")
        case (false, true):
            parts.append("is:pr")
        default:
            break
        }
        if parts.isEmpty {
            parts.append("is:open")
        }
        return parts.joined(separator: " ")
    }

    private static func repoSearchQuery(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "stars:>0" }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            let owner = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = (parts.count > 1 ? String(parts[1]) : "").trimmingCharacters(in: .whitespacesAndNewlines)

            if !owner.isEmpty, !name.isEmpty {
                return "\(name) in:name user:\(owner)"
            }
            if !owner.isEmpty {
                return "user:\(owner)"
            }
        }

        return "\(trimmed) in:name"
    }

    func userEvents(username: String, scope: GlobalActivityScope) async throws -> [RepoEvent] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let path = scope == .allActivity
            ? "/users/\(username)/received_events"
            : "/users/\(username)/events"
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "30")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try GitHubDecoding.decode([RepoEvent].self, from: data)
    }

    func repoDetails(owner: String, name: String) async throws -> RepoItem {
        let token = try await tokenProvider()
        let baseURL = await self.apiHost()
        let url = baseURL.appending(path: "/repos/\(owner)/\(name)")
        let data: Data
        do {
            (data, _) = try await self.authorizedGet(url: url, token: token)
        } catch let error as GitHubAPIError {
            if case .badStatus(404, _) = error {
                throw GitHubAPIError.badStatus(code: 404, message: Self.repoNotVisibleMessage(owner: owner, name: name))
            }
            throw error
        }
        return try GitHubDecoding.decode(RepoItem.self, from: data)
    }

    static func repoNotVisibleMessage(owner: String, name: String) -> String {
        "\(owner)/\(name) was not found or is not visible to RepoBar's token. " +
            "For private organization repositories, install the RepoBar GitHub App on that organization/repository or sign in with a PAT that has repo access."
    }

    func ciStatus(owner: String, name: String) async throws -> CIStatusDetails {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/actions/runs"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "branch", value: "main")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let runs = try GitHubDecoding.decode(ActionsRunsResponse.self, from: data)
        guard let run = runs.workflowRuns.first else { return CIStatusDetails(status: .unknown, runCount: runs.totalCount) }

        let status = GitHubStatusMapper.ciStatus(fromStatus: run.status, conclusion: run.conclusion)
        return CIStatusDetails(status: status, runCount: runs.totalCount)
    }

    func recentActivity(owner: String, name: String, limit: Int) async throws -> ActivitySnapshot {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let webHost = self.webHostURL(from: baseURL)
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "30")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let events = try GitHubDecoding.decode([RepoEvent].self, from: data)
        return Self.activitySnapshot(from: events, owner: owner, name: name, webHost: webHost, limit: limit)
    }

    static func activitySnapshot(
        from events: [RepoEvent],
        owner: String,
        name: String,
        webHost: URL,
        limit: Int
    ) -> ActivitySnapshot {
        let sorted = events.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt > rhs.element.createdAt
            }
            .map(\.element)
        let mapped = sorted.map { event in
            (event: event, activity: event.activityEvent(owner: owner, name: name, webHost: webHost))
        }
        let limited = Array(mapped.prefix(max(limit, 0)))
        let preferred = limited.first(where: \.event.hasRichPayload)?.activity
        return ActivitySnapshot(
            events: limited.map(\.activity),
            latest: preferred ?? limited.first?.activity
        )
    }

    private func webHostURL(from apiHost: URL) -> URL {
        var components = URLComponents()
        components.scheme = apiHost.scheme ?? "https"
        let rawHost = apiHost.host ?? "github.com"
        components.host = rawHost == "api.github.com" ? "github.com" : rawHost
        return components.url ?? URL(string: "https://github.com")!
    }

    func trafficStats(owner: String, name: String) async throws -> TrafficStats? {
        do {
            let token = try await tokenProvider()
            let baseURL = await apiHost()
            let viewsURL = baseURL.appending(path: "/repos/\(owner)/\(name)/traffic/views")
            let clonesURL = baseURL.appending(path: "/repos/\(owner)/\(name)/traffic/clones")
            async let viewsPair = self.authorizedGet(url: viewsURL, token: token)
            async let clonesPair = self.authorizedGet(url: clonesURL, token: token)
            let views = try await GitHubDecoding.decode(TrafficResponse.self, from: viewsPair.0)
            let clones = try await GitHubDecoding.decode(TrafficResponse.self, from: clonesPair.0)
            return TrafficStats(uniqueVisitors: views.uniques, uniqueCloners: clones.uniques)
        } catch let error as GitHubAPIError {
            if case let .badStatus(code, _) = error, code == 403 {
                await self.diag.message("Traffic endpoints forbidden for \(owner)/\(name); skipping")
                return nil
            }
            throw error
        }
    }

    func commitHeatmap(owner: String, name: String) async throws -> [HeatmapCell] {
        do {
            let token = try await tokenProvider()
            let baseURL = await apiHost()
            let (data, _) = try await authorizedGet(
                url: baseURL.appending(path: "/repos/\(owner)/\(name)/stats/commit_activity"),
                token: token
            )
            let weeks = try GitHubDecoding.decode([CommitActivityWeek].self, from: data)
            return weeks.flatMap { week in
                zip(0 ..< 7, week.days).map { offset, count in
                    let date = Date(timeIntervalSince1970: TimeInterval(week.weekStart + offset * 86400))
                    return HeatmapCell(date: date, count: count)
                }
            }
        } catch let error as GitHubAPIError {
            if case let .badStatus(code, _) = error, code == 403 {
                await self.diag.message("Commit activity forbidden for \(owner)/\(name); skipping heatmap")
                return []
            }
            throw error
        }
    }

    func repoContents(owner: String, name: String, path: String? = nil) async throws -> [RepoContentItem] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = trimmed.isEmpty ? "" : "/\(trimmed)"
        let url = baseURL.appending(path: "/repos/\(owner)/\(name)/contents\(suffix)")
        let (data, response) = try await authorizedGet(
            url: url,
            token: token,
            allowedStatuses: [200, 304, 404]
        )
        if response.statusCode == 404 {
            return []
        }
        if let list = try? GitHubDecoding.decode([RepoContentItem].self, from: data) {
            return list
        }
        let item = try GitHubDecoding.decode(RepoContentItem.self, from: data)
        return [item]
    }

    func repoFileContents(owner: String, name: String, path: String) async throws -> Data {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = baseURL.appending(path: "/repos/\(owner)/\(name)/contents/\(trimmed)")
        let (data, _) = try await authorizedGet(
            url: url,
            token: token,
            headers: ["Accept": "application/vnd.github.raw"],
            useETag: false
        )
        return data
    }

    func openPullRequestCount(owner: String, name: String) async throws -> Int {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/pulls"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "page", value: "1")
        ]
        let (data, response) = try await authorizedGet(url: components.url!, token: token, useETag: false)
        let pulls = try GitHubDecoding.decode([PullRequestListItem].self, from: data)

        if let link = response.value(forHTTPHeaderField: "Link"), let last = GitHubPagination.lastPage(from: link) {
            return last
        }

        return pulls.count
    }

    func commitTotalCount(owner: String, name: String) async throws -> Int? {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/commits"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "1")]
        let (data, response) = try await authorizedGet(url: components.url!, token: token, useETag: false)
        if let link = response.value(forHTTPHeaderField: "Link"), let last = GitHubPagination.lastPage(from: link) {
            return last
        }
        let items = try GitHubDecoding.decode([CommitRecentResponse].self, from: data)
        return items.count
    }

    func recentIssues(owner: String, name: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        let token = try await tokenProvider()
        let target = max(1, min(limit, 100))
        let pageSize = 100
        let maxPages = 10
        let baseURL = await apiHost()
        var collected: [RepoIssueSummary] = []
        var page = 1

        while collected.count < target, page <= maxPages {
            var components = URLComponents(
                url: baseURL.appending(path: "/repos/\(owner)/\(name)/issues"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "state", value: "open"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc"),
                URLQueryItem(name: "per_page", value: "\(pageSize)"),
                URLQueryItem(name: "page", value: "\(page)")
            ]
            let (data, _) = try await authorizedGet(url: components.url!, token: token)
            let decoded = try GitHubRecentDecoders.decodeRecentIssuePage(from: data)
            collected.append(contentsOf: decoded.issues)

            if decoded.rawCount < pageSize {
                break
            }
            page += 1
        }

        return Array(collected.prefix(target))
    }

    func recentReleases(owner: String, name: String, limit: Int = 20) async throws -> [RepoReleaseSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "releases",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentReleases(from:)
        )
    }

    func recentWorkflowRuns(owner: String, name: String, limit: Int = 20) async throws -> [RepoWorkflowRunSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "actions/runs",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentWorkflowRuns(from:)
        )
    }

    func recentCommits(owner: String, name: String, limit: Int = 20) async throws -> RepoCommitList {
        let token = try await tokenProvider()
        let limit = max(1, min(limit, 100))
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/commits"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "\(limit)")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let items = try GitHubRecentDecoders.decodeRecentCommits(from: data)
        let totalCount = try await self.commitTotalCount(owner: owner, name: name)
        return RepoCommitList(items: items, totalCount: totalCount)
    }

    func recentDiscussions(owner: String, name: String, limit: Int = 20) async throws -> [RepoDiscussionSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "discussions",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ],
            decode: GitHubRecentDecoders.decodeRecentDiscussions(from:)
        )
    }

    func recentTags(owner: String, name: String, limit: Int = 20) async throws -> [RepoTagSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "tags",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentTags(from:)
        )
    }

    func recentBranches(owner: String, name: String, limit: Int = 20) async throws -> [RepoBranchSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "branches",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentBranches(from:)
        )
    }

    func topContributors(owner: String, name: String, limit: Int = 20) async throws -> [RepoContributorSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "contributors",
            limit: limit,
            decode: GitHubRecentDecoders.decodeContributors(from:)
        )
    }

    /// Most recent release (including prereleases) ordered by creation date; skips drafts.
    /// Returns `nil` if the repository has no releases.
    func latestReleaseAny(owner: String, name: String) async throws -> Release? {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/releases"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "20")]
        let (data, response) = try await authorizedGet(url: components.url!, token: token, allowedStatuses: [200, 304, 404])
        guard response.statusCode != 404 else { return nil }

        let releases = try GitHubDecoding.decode([ReleaseResponse].self, from: data)
        return GitHubReleasePicker.latestRelease(from: releases)
    }

    func recentList<T>(
        owner: String,
        name: String,
        path: String,
        limit: Int,
        queryItems: [URLQueryItem] = [],
        decode: (Data) throws -> [T]
    ) async throws -> [T] {
        let token = try await tokenProvider()
        let limit = max(1, min(limit, 100))
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/\(path)"),
            resolvingAgainstBaseURL: false
        )!
        var items = queryItems.filter { $0.name != "per_page" }
        items.append(URLQueryItem(name: "per_page", value: "\(limit)"))
        components.queryItems = items
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try decode(data)
    }

    private func fetchAllPages<T>(
        path: String,
        queryItems: [URLQueryItem],
        limit: Int?,
        decode: @escaping (Data) throws -> [T]
    ) async throws -> [T] {
        let pageSize = 100 // GitHub maximum.
        var collected: [T] = []
        var page = 1

        while true {
            // Each page is a separate request; stop early if GitHub returns a short page.
            let token = try await tokenProvider()
            let baseURL = await apiHost()
            var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
            var items = queryItems.filter { $0.name != "per_page" && $0.name != "page" }
            items.append(URLQueryItem(name: "per_page", value: "\(pageSize)"))
            items.append(URLQueryItem(name: "page", value: "\(page)"))
            components.queryItems = items
            let (data, _) = try await authorizedGet(url: components.url!, token: token)
            let itemsPage = try decode(data)
            collected.append(contentsOf: itemsPage)

            if let limit, collected.count >= limit {
                break
            }
            if itemsPage.count < pageSize {
                break // GitHub returned a short page.
            }
            page += 1
        }

        if let limit {
            return Array(collected.prefix(limit))
        }
        return collected
    }

    func authorizedGet(
        url: URL,
        token: String,
        allowedStatuses: Set<Int> = [200, 304],
        headers: [String: String] = [:],
        useETag: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        try await self.requestRunner.get(
            url: url,
            token: token,
            allowedStatuses: allowedStatuses,
            headers: headers,
            useETag: useETag
        )
    }
}

private struct CommitRecentResponse: Decodable {
    let sha: String
}

private struct InstallationReposResponse: Decodable {
    let totalCount: Int
    let repositories: [RepoItem]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case repositories
    }
}

private struct RateLimitResponse: Decodable {
    let resources: [String: RateLimitResourceResponse]
}

private struct RateLimitResourceResponse: Decodable {
    let limit: Int?
    let used: Int?
    let remaining: Int?
    let reset: Int
    let resource: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        self.used = try container.decodeIfPresent(Int.self, forKey: .used)
        self.remaining = try container.decodeIfPresent(Int.self, forKey: .remaining)
        self.reset = try container.decode(Int.self, forKey: .reset)
        self.resource = container.codingPath.last?.stringValue ?? "unknown"
    }

    private enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remaining
        case reset
    }
}
