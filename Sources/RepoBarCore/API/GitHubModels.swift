import Foundation

struct CurrentUser: Decodable {
    let login: String
    let htmlUrl: String
    let plan: Plan?

    struct Plan: Decodable {
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case login
        case htmlUrl = "html_url"
        case plan
    }
}

struct UserOrganization: Decodable {
    let login: String

    enum CodingKeys: String, CodingKey {
        case login
    }
}

struct OrganizationDetail: Decodable {
    let login: String
    let plan: Plan?

    struct Plan: Decodable {
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case login
        case plan
    }
}

struct ReleaseResponse: Decodable {
    let name: String?
    let tagName: String
    let publishedAt: Date?
    let createdAt: Date?
    let draft: Bool?
    let prerelease: Bool?
    let htmlUrl: URL

    enum CodingKeys: String, CodingKey {
        case name
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case draft
        case prerelease
        case htmlUrl = "html_url"
    }
}

struct ActionsRunsResponse: Decodable {
    let totalCount: Int?
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case workflowRuns = "workflow_runs"
    }

    struct WorkflowRun: Decodable {
        let id: Int?
        let name: String?
        let displayTitle: String?
        let runNumber: Int?
        let event: String?
        let headBranch: String?
        let status: String?
        let conclusion: String?
        let htmlUrl: URL?
        let createdAt: Date?
        let updatedAt: Date?
        let actor: Actor?
        let repository: Repository?

        struct Actor: Decodable {
            let login: String
            let avatarUrl: URL?

            enum CodingKeys: String, CodingKey {
                case login
                case avatarUrl = "avatar_url"
            }
        }

        struct Repository: Decodable {
            let fullName: String

            enum CodingKeys: String, CodingKey {
                case fullName = "full_name"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case displayTitle = "display_title"
            case runNumber = "run_number"
            case event
            case headBranch = "head_branch"
            case status
            case conclusion
            case htmlUrl = "html_url"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case actor
            case repository
        }
    }
}

struct CommentResponse: Decodable {
    let body: String
    let user: CommentUser
    let htmlUrl: URL
    let createdAt: Date

    var bodyPreview: String {
        let trimmed = self.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(trimmed.prefix(80))
        return prefix + (trimmed.count > 80 ? "…" : "")
    }

    enum CodingKeys: String, CodingKey {
        case body
        case user
        case htmlUrl = "html_url"
        case createdAt = "created_at"
    }

    struct CommentUser: Decodable {
        let login: String
    }
}

struct TrafficResponse: Decodable {
    let uniques: Int
}

struct CommitActivityWeek: Decodable {
    let total: Int
    let weekStart: Int
    let days: [Int]

    enum CodingKeys: String, CodingKey {
        case total
        case weekStart = "week"
        case days
    }
}

struct RepoEvent: Decodable {
    let type: String
    let actor: EventActor
    let repo: EventRepo?
    let payload: EventPayload
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case type, actor, repo, payload
        case createdAt = "created_at"
    }
}

struct EventRepo: Decodable {
    let name: String?
    let url: URL?

    enum CodingKeys: String, CodingKey {
        case name
        case url
    }

    var fullName: String? {
        if let name, name.contains("/") {
            return name
        }
        guard let url else { return nil }

        let parts = url.path.split(separator: "/")
        guard let reposIndex = parts.firstIndex(where: { $0 == "repos" }),
              parts.count > reposIndex + 2 else { return nil }

        return "\(parts[reposIndex + 1])/\(parts[reposIndex + 2])"
    }
}

struct EventActor: Decodable {
    let login: String
    let avatarUrl: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

struct EventPayload: Decodable {
    let action: String?
    let comment: EventComment?
    let issue: EventIssue?
    let pullRequest: EventPullRequest?
    let release: EventRelease?
    let forkee: EventForkee?
    let ref: String?
    let refType: String?
    let head: String?
    let commits: [EventCommit]?

    enum CodingKeys: String, CodingKey {
        case action, comment, issue, release, forkee, ref, head, commits
        case refType = "ref_type"
        case pullRequest = "pull_request"
    }

    init(
        action: String?,
        comment: EventComment?,
        issue: EventIssue?,
        pullRequest: EventPullRequest?,
        release: EventRelease? = nil,
        forkee: EventForkee? = nil,
        ref: String? = nil,
        refType: String? = nil,
        head: String? = nil,
        commits: [EventCommit]? = nil
    ) {
        self.action = action
        self.comment = comment
        self.issue = issue
        self.pullRequest = pullRequest
        self.release = release
        self.forkee = forkee
        self.ref = ref
        self.refType = refType
        self.head = head
        self.commits = commits
    }
}

struct EventComment: Decodable {
    let body: String?
    let htmlUrl: URL?

    enum CodingKeys: String, CodingKey {
        case body
        case htmlUrl = "html_url"
    }

    var bodyPreview: String {
        let trimmed = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(trimmed.prefix(80))
        return prefix + (trimmed.count > 80 ? "…" : "")
    }
}

struct EventIssue: Decodable {
    let title: String?
    let number: Int?
    let htmlUrl: URL?

    enum CodingKeys: String, CodingKey {
        case title, number
        case htmlUrl = "html_url"
    }
}

struct EventPullRequest: Decodable {
    let title: String?
    let number: Int?
    let merged: Bool?
    let htmlUrl: URL?

    enum CodingKeys: String, CodingKey {
        case title, number, merged
        case htmlUrl = "html_url"
    }
}

struct EventRelease: Decodable {
    let htmlUrl: URL?
    let tagName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case htmlUrl = "html_url"
        case tagName = "tag_name"
        case name
    }
}

struct EventForkee: Decodable {
    let htmlUrl: URL?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case htmlUrl = "html_url"
        case fullName = "full_name"
    }
}

struct EventCommit: Decodable {
    let sha: String
    let message: String?
    let author: EventCommitAuthor?
    let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case sha, message, author, timestamp
    }
}

struct EventCommitAuthor: Decodable {
    let name: String?
}

extension RepoEvent {
    var eventType: ActivityEventType? {
        ActivityEventType.parse(self.type)
    }

    var displayTitle: String {
        let base = Self.displayName(for: self.eventType, raw: self.type)
        guard let action = self.payload.action, action.isEmpty == false else { return base }

        let actionLabel = action.replacingOccurrences(of: "_", with: " ")
        return "\(base) \(actionLabel)"
    }

    var hasRichPayload: Bool {
        self.payload.comment != nil
            || self.payload.issue != nil
            || self.payload.pullRequest != nil
            || self.payload.release != nil
            || self.payload.forkee != nil
            || self.payload.head != nil
            || (self.payload.commits?.isEmpty == false)
    }

    func commitSummaries(webHost: URL) -> [RepoCommitSummary] {
        guard let repo, let repoName = repo.fullName else { return [] }

        let parts = repoName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }

        let owner = parts[0]
        let name = parts[1]
        let repoURL = webHost.appending(path: owner).appending(path: name)
        let commits = self.payload.commits ?? []
        return commits.compactMap { commit in
            let message = commit.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
            let date = commit.timestamp ?? self.createdAt
            let url = repoURL.appending(path: "commit").appending(path: commit.sha)
            return RepoCommitSummary(
                sha: commit.sha,
                message: title.isEmpty ? "Commit" : title,
                url: url,
                authoredAt: date,
                authorName: commit.author?.name,
                authorLogin: self.actor.login,
                authorAvatarURL: self.actor.avatarUrl,
                repoFullName: repoName
            )
        }
    }

    func activityEvent(owner: String, name: String, webHost: URL) -> ActivityEvent {
        let url = self.activityURL(owner: owner, name: name, webHost: webHost)
        let metadata = self.activityMetadata(owner: owner, name: name, url: url)
        let baseTitle = metadata.label.isEmpty ? self.displayTitle : metadata.label
        let preview = self.payload.comment?.bodyPreview ?? baseTitle
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return ActivityEvent(
            title: trimmed.isEmpty ? baseTitle : trimmed,
            actor: self.actor.login,
            actorAvatarURL: self.actor.avatarUrl,
            date: self.createdAt,
            url: url,
            eventType: self.type,
            metadata: metadata
        )
    }

    func activityEventFromRepo(webHost: URL) -> ActivityEvent? {
        guard let repo, let repoName = repo.fullName else { return nil }

        let parts = repoName.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        return self.activityEvent(owner: String(parts[0]), name: String(parts[1]), webHost: webHost)
    }

    private func activityURL(owner: String, name: String, webHost: URL) -> URL {
        let repoURL = webHost.appending(path: owner).appending(path: name)
        let starURL = repoURL.appending(path: "stargazers")
        let fallbackURL = (self.eventType == .watch) ? starURL : repoURL
        let commitSHA = self.payload.head ?? self.payload.commits?.first?.sha
        let commitURL = commitSHA.map { repoURL.appending(path: "commit").appending(path: $0) }
        return self.payload.comment?.htmlUrl
            ?? self.payload.issue?.htmlUrl
            ?? self.payload.pullRequest?.htmlUrl
            ?? self.payload.release?.htmlUrl
            ?? self.payload.forkee?.htmlUrl
            ?? commitURL
            ?? fallbackURL
    }

    private func activityMetadata(owner: String, name: String, url: URL) -> ActivityMetadata {
        let action = self.activityActionLabel()
        let target = self.activityTargetLabel(owner: owner, name: name)
        return ActivityMetadata(actor: self.actor.login, action: action, target: target, url: url)
    }

    private func activityActionLabel() -> String? {
        let action = self.actionSuffix()
        switch self.eventType {
        case .pullRequest:
            return self.issueAction(prefix: "PR", action: action)
        case .issues:
            return self.issueAction(prefix: "Issue", action: action)
        case .release:
            let base = "Release"
            return action.map { "\(base) \($0)" } ?? base
        case .watch:
            return "Starred"
        case .fork:
            return "Forked"
        case .create:
            return self.refTitle(prefix: "Created")
        case .delete:
            return self.refTitle(prefix: "Deleted")
        default:
            return self.displayTitle
        }
    }

    private func activityTargetLabel(owner: String, name: String) -> String? {
        switch self.eventType {
        case .pullRequest:
            self.issueTarget(number: self.payload.pullRequest?.number, title: self.payload.pullRequest?.title)
        case .issues:
            self.issueTarget(number: self.payload.issue?.number, title: self.payload.issue?.title)
        case .release:
            self.payload.release?.tagName ?? self.payload.release?.name
        case .fork, .create, .delete:
            self.repoTarget(owner: owner, name: name).map { "→ \($0)" }
        default:
            nil
        }
    }

    private func issueAction(prefix: String, action: String?) -> String {
        guard let action else { return prefix }

        return "\(prefix) \(action)"
    }

    private func issueTarget(number: Int?, title: String?) -> String? {
        var parts: [String] = []
        if let number {
            parts.append("#\(number)")
        }
        if let title, !title.isEmpty {
            parts.append(title)
        }
        guard parts.isEmpty == false else { return nil }

        return parts.joined(separator: ": ")
    }

    private func actionSuffix() -> String? {
        guard let action = self.payload.action, action.isEmpty == false else { return nil }

        if self.eventType == .watch, action == "started" {
            return "starred"
        }
        if self.eventType == .pullRequest, action == "closed", self.payload.pullRequest?.merged == true {
            return "merged"
        }
        return action.replacingOccurrences(of: "_", with: " ")
    }

    private func repoTarget(owner: String, name: String) -> String? {
        switch self.eventType {
        case .fork:
            self.payload.forkee?.fullName ?? "\(owner)/\(name)"
        case .create, .delete:
            "\(owner)/\(name)"
        default:
            nil
        }
    }

    private func refTitle(prefix: String) -> String {
        let refType = self.payload.refType?.replacingOccurrences(of: "_", with: " ")
        let ref = self.payload.ref
        switch (refType, ref) {
        case let (type?, ref?): return "\(prefix) \(type) \(ref)"
        case let (type?, nil): return "\(prefix) \(type)"
        case let (nil, ref?): return "\(prefix) \(ref)"
        default: return prefix
        }
    }

    static func displayName(for type: ActivityEventType?, raw: String) -> String {
        guard let type else { return self.prettyName(for: raw) }

        return switch type {
        case .pullRequest: "Pull Request"
        case .pullRequestReview: "Pull Request Review"
        case .pullRequestReviewComment: "Pull Request Review Comment"
        case .pullRequestReviewThread: "Pull Request Review Thread"
        case .issueComment: "Issue Comment"
        case .issues: "Issue"
        case .push: "Push"
        case .release: "Release"
        case .watch: "Star"
        case .fork: "Fork"
        case .create: "Create"
        case .delete: "Delete"
        case .member: "Member"
        case .public: "Public"
        case .gollum: "Wiki"
        case .commitComment: "Commit Comment"
        case .discussion: "Discussion"
        case .sponsorship: "Sponsorship"
        }
    }

    private static func prettyName(for raw: String) -> String {
        let trimmed = raw.hasSuffix("Event") ? String(raw.dropLast(5)) : raw
        var result = ""
        for scalar in trimmed.unicodeScalars {
            let char = Character(scalar)
            if char.isUppercase, result.isEmpty == false, result.last != " " {
                result.append(" ")
            }
            result.append(char)
        }
        return result
    }
}
