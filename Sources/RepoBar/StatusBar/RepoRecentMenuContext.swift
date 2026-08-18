import Foundation

enum RepoRecentMenuKind: Hashable {
    case commits
    case issues
    case pullRequests
    case releases
    case ciRuns
    case discussions
    case tags
    case branches
    case contributors
}

struct RepoRecentMenuContext: Hashable {
    let accountID: String
    let fullName: String
    let kind: RepoRecentMenuKind
}
