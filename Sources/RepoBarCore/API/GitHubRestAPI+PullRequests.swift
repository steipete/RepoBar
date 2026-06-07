import Foundation

extension GitHubRestAPI {
    func recentPullRequests(
        owner: String,
        name: String,
        limit: Int = 20,
        state: GitHubPullRequestListState = .open,
        includeCommentCounts: Bool = false
    ) async throws -> [RepoPullRequestSummary] {
        let pullRequests = try await self.recentList(
            owner: owner,
            name: name,
            path: "pulls",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "state", value: state.rawValue),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ],
            decode: GitHubRecentDecoders.decodeRecentPullRequests(from:)
        )
        guard includeCommentCounts else { return pullRequests }

        let targetNumbers = Set(pullRequests.map(\.number))
        let issueCommentCounts = await (try? self.recentPullRequestIssueCommentCounts(
            owner: owner,
            name: name,
            state: state,
            targetNumbers: targetNumbers
        )) ?? [:]
        let reviewCommentCounts = await self.recentPullRequestReviewCommentCounts(
            owner: owner,
            name: name,
            targetNumbers: targetNumbers
        )

        guard issueCommentCounts.isEmpty == false || reviewCommentCounts.isEmpty == false else { return pullRequests }

        return pullRequests.map { pullRequest in
            self.pullRequest(
                pullRequest,
                issueCommentCounts: issueCommentCounts,
                reviewCommentCounts: reviewCommentCounts
            )
        }
    }

    private func pullRequest(
        _ pullRequest: RepoPullRequestSummary,
        issueCommentCounts: [Int: Int],
        reviewCommentCounts: [Int: Int]
    ) -> RepoPullRequestSummary {
        let commentCount = issueCommentCounts[pullRequest.number] ?? pullRequest.commentCount
        let reviewCommentCount = reviewCommentCounts[pullRequest.number] ?? pullRequest.reviewCommentCount
        guard commentCount != pullRequest.commentCount || reviewCommentCount != pullRequest.reviewCommentCount else {
            return pullRequest
        }

        return RepoPullRequestSummary(
            number: pullRequest.number,
            title: pullRequest.title,
            url: pullRequest.url,
            updatedAt: pullRequest.updatedAt,
            createdAt: pullRequest.createdAt,
            state: pullRequest.state,
            mergedAt: pullRequest.mergedAt,
            authorLogin: pullRequest.authorLogin,
            authorAvatarURL: pullRequest.authorAvatarURL,
            isDraft: pullRequest.isDraft,
            commentCount: commentCount,
            reviewCommentCount: reviewCommentCount,
            labels: pullRequest.labels,
            headRefName: pullRequest.headRefName,
            baseRefName: pullRequest.baseRefName,
            bodyPreview: pullRequest.bodyPreview,
            requestedReviewerLogins: pullRequest.requestedReviewerLogins,
            requestedTeamNames: pullRequest.requestedTeamNames
        )
    }

    private func recentPullRequestIssueCommentCounts(
        owner: String,
        name: String,
        state: GitHubPullRequestListState,
        targetNumbers: Set<Int>
    ) async throws -> [Int: Int] {
        guard targetNumbers.isEmpty == false else { return [:] }

        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        let pageSize = 100
        let maxPages = 3
        var collected: [Int: Int] = [:]
        var page = 1

        while page <= maxPages, targetNumbers.isSubset(of: Set(collected.keys)) == false {
            var components = URLComponents(
                url: baseURL.appending(path: "/repos/\(owner)/\(name)/issues"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "state", value: state.rawValue),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc"),
                URLQueryItem(name: "per_page", value: "\(pageSize)"),
                URLQueryItem(name: "page", value: "\(page)")
            ]
            let (data, _) = try await self.authorizedGet(url: components.url!, token: token)
            let counts = try GitHubRecentDecoders.decodePullRequestIssueCommentCounts(from: data)
            collected.merge(counts.filter { targetNumbers.contains($0.key) }) { _, new in new }
            page += 1
        }

        return collected
    }

    private func recentPullRequestReviewCommentCounts(
        owner: String,
        name: String,
        targetNumbers: Set<Int>
    ) async -> [Int: Int] {
        guard targetNumbers.isEmpty == false else { return [:] }

        var counts: [Int: Int] = [:]
        for batch in Array(targetNumbers).repoBarBatches(of: 8) {
            let batchCounts = await withTaskGroup(of: PullRequestReviewCommentCount?.self) { group in
                for number in batch {
                    group.addTask {
                        do {
                            let count = try await self.pullRequestReviewCommentCount(owner: owner, name: name, number: number)
                            return PullRequestReviewCommentCount(number: number, count: count)
                        } catch {
                            return nil
                        }
                    }
                }

                var batchOut: [Int: Int] = [:]
                for await result in group {
                    guard let result else { continue }

                    batchOut[result.number] = result.count
                }
                return batchOut
            }
            counts.merge(batchCounts) { _, new in new }
        }
        return counts
    }

    private func pullRequestReviewCommentCount(owner: String, name: String, number: Int) async throws -> Int {
        let token = try await self.tokenProvider()
        let baseURL = await self.apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/pulls/\(number)/comments"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "1")]
        let (data, response) = try await self.authorizedGet(url: components.url!, token: token)
        if let link = response.value(forHTTPHeaderField: "Link"), let last = GitHubPagination.lastPage(from: link) {
            return last
        }

        return try GitHubDecoding.decode([PullRequestReviewCommentCountResponse].self, from: data).count
    }
}

private struct PullRequestReviewCommentCount {
    let number: Int
    let count: Int
}

private struct PullRequestReviewCommentCountResponse: Decodable {}
