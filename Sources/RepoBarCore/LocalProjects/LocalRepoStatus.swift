import Foundation

public struct LocalRepoStatus: Equatable, Sendable {
    public let path: URL
    public let name: String
    public let fullName: String?
    public let remoteHost: String?
    public let branch: String
    public let isClean: Bool
    public let aheadCount: Int?
    public let behindCount: Int?
    public let syncState: LocalSyncState
    public let dirtyCounts: LocalDirtyCounts?
    public let dirtyFiles: [String]
    public let worktreeName: String?
    public let upstreamBranch: String?
    public let lastFetchAt: Date?

    public init(
        path: URL,
        name: String,
        fullName: String?,
        remoteHost: String? = nil,
        branch: String,
        isClean: Bool,
        aheadCount: Int?,
        behindCount: Int?,
        syncState: LocalSyncState,
        dirtyCounts: LocalDirtyCounts? = nil,
        dirtyFiles: [String] = [],
        worktreeName: String? = nil,
        upstreamBranch: String? = nil,
        lastFetchAt: Date? = nil
    ) {
        self.path = path
        self.name = name
        self.fullName = fullName
        self.remoteHost = remoteHost.map(Self.normalizedHost)
        self.branch = branch
        self.isClean = isClean
        self.aheadCount = aheadCount
        self.behindCount = behindCount
        self.syncState = syncState
        self.dirtyCounts = dirtyCounts
        self.dirtyFiles = dirtyFiles
        self.worktreeName = worktreeName
        self.upstreamBranch = upstreamBranch
        self.lastFetchAt = lastFetchAt
    }

    public var displayName: String {
        self.fullName ?? self.name
    }

    public var syncDetail: String {
        switch self.syncState {
        case .synced:
            "Up to date"
        case .behind:
            self.behindCount.map { "Behind \($0)" } ?? "Behind"
        case .ahead:
            self.aheadCount.map { "Ahead \($0)" } ?? "Ahead"
        case .diverged:
            "Diverged"
        case .dirty:
            if let dirtyCounts, dirtyCounts.isEmpty == false {
                "Dirty (\(dirtyCounts.summary))"
            } else {
                "Dirty"
            }
        case .unknown:
            "No upstream"
        }
    }

    public var canAutoSync: Bool {
        self.isClean
            && self.syncState == .behind
            && (self.aheadCount ?? 0) == 0
            && self.branch != "detached"
    }

    public func withLastFetch(_ date: Date?) -> LocalRepoStatus {
        LocalRepoStatus(
            path: self.path,
            name: self.name,
            fullName: self.fullName,
            remoteHost: self.remoteHost,
            branch: self.branch,
            isClean: self.isClean,
            aheadCount: self.aheadCount,
            behindCount: self.behindCount,
            syncState: self.syncState,
            dirtyCounts: self.dirtyCounts,
            dirtyFiles: self.dirtyFiles,
            worktreeName: self.worktreeName,
            upstreamBranch: self.upstreamBranch,
            lastFetchAt: date
        )
    }

    public func matches(host: URL) -> Bool {
        guard let remoteHost else { return true }

        return remoteHost == Account.hostAuthority(for: host)
    }

    private static func normalizedHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)") else {
            return trimmed
        }

        return Account.hostAuthority(for: url)
    }
}

public struct LocalDirtyCounts: Equatable, Sendable {
    public let added: Int
    public let modified: Int
    public let deleted: Int

    public init(added: Int, modified: Int, deleted: Int) {
        self.added = added
        self.modified = modified
        self.deleted = deleted
    }

    public var isEmpty: Bool {
        self.added == 0 && self.modified == 0 && self.deleted == 0
    }

    public var summary: String {
        var parts: [String] = []
        if self.added > 0 {
            parts.append("+\(self.added)")
        }
        if self.deleted > 0 {
            parts.append("-\(self.deleted)")
        }
        if self.modified > 0 {
            parts.append("~\(self.modified)")
        }
        return parts.joined(separator: " ")
    }
}

public enum LocalSyncState: String, Equatable, Sendable {
    case synced
    case behind
    case ahead
    case diverged
    case dirty
    case unknown

    public static func resolve(isClean: Bool, ahead: Int?, behind: Int?) -> LocalSyncState {
        if !isClean {
            return .dirty
        }
        guard let ahead, let behind else { return .unknown }

        if ahead == 0, behind == 0 {
            return .synced
        }
        if behind > 0, ahead == 0 {
            return .behind
        }
        if ahead > 0, behind == 0 {
            return .ahead
        }
        if ahead > 0, behind > 0 {
            return .diverged
        }
        return .unknown
    }

    public var symbolName: String {
        switch self {
        case .synced: "checkmark.square"
        case .behind: "arrow.down.square"
        case .ahead: "arrow.up.square"
        case .diverged: "arrow.triangle.branch"
        case .dirty: "exclamationmark.square"
        case .unknown: "questionmark.square"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .synced: "Up to date"
        case .behind: "Behind"
        case .ahead: "Ahead"
        case .diverged: "Diverged"
        case .dirty: "Dirty"
        case .unknown: "No upstream"
        }
    }
}

public struct LocalRepoIndex: Equatable, Sendable {
    public var all: [LocalRepoStatus] = []
    public var byFullName: [String: LocalRepoStatus] = [:]
    public var byName: [String: [LocalRepoStatus]] = [:]
    public var byFullNameLowercased: [String: [LocalRepoStatus]] = [:]
    public var byNameLowercased: [String: [LocalRepoStatus]] = [:]
    public var byPath: [String: LocalRepoStatus] = [:]
    public var preferredPathsByFullName: [String: String] = [:]

    public static let empty = LocalRepoIndex()

    public init() {}

    public init(statuses: [LocalRepoStatus], preferredPathsByFullName: [String: String] = [:]) {
        self.all = statuses
        self.preferredPathsByFullName = preferredPathsByFullName
        // Use uniquingKeysWith to handle duplicate fullNames (e.g., worktrees sharing same remote)
        self.byFullName = Dictionary(
            statuses.compactMap { status in status.fullName.map { ($0, status) } },
            uniquingKeysWith: { first, second in Self.preferredStatus(first, second) }
        )
        // Use uniquingKeysWith to handle any duplicate paths
        self.byPath = Dictionary(
            statuses.map { ($0.path.path, $0) },
            uniquingKeysWith: { first, second in Self.preferredStatus(first, second) }
        )
        var nameIndex: [String: [LocalRepoStatus]] = [:]
        var nameIndexLowercased: [String: [LocalRepoStatus]] = [:]
        var fullNameIndexLowercased: [String: [LocalRepoStatus]] = [:]
        for status in statuses {
            nameIndex[status.name, default: []].append(status)
            nameIndexLowercased[status.name.lowercased(), default: []].append(status)
            if let fullName = status.fullName?.lowercased() {
                fullNameIndexLowercased[fullName, default: []].append(status)
            }
        }
        self.byName = nameIndex
        self.byNameLowercased = nameIndexLowercased
        self.byFullNameLowercased = fullNameIndexLowercased
    }

    public func status(for repo: Repository) -> LocalRepoStatus? {
        self.status(for: repo, host: nil)
    }

    public func status(for repo: Repository, host: URL?) -> LocalRepoStatus? {
        self.status(forFullName: repo.fullName, repositoryName: repo.name, host: host)
    }

    public func status(forFullName fullName: String) -> LocalRepoStatus? {
        self.status(forFullName: fullName, repositoryName: fullName.split(separator: "/").last.map(String.init), host: nil)
    }

    public func status(forFullName fullName: String, host: URL) -> LocalRepoStatus? {
        self.status(forFullName: fullName, repositoryName: fullName.split(separator: "/").last.map(String.init), host: host)
    }

    private func status(forFullName fullName: String, repositoryName: String?, host: URL?) -> LocalRepoStatus? {
        if let preferred = self.preferredPathsByFullName[fullName], let status = self.byPath[preferred] {
            if Self.matchesHost(status, host: host) {
                return status
            }
        }
        if let exact = self.byFullName[fullName], Self.matchesHost(exact, host: host) {
            return exact
        }
        if let match = self.preferredStatus(
            in: self.byFullNameLowercased,
            forKey: fullName.lowercased(),
            host: host
        ) {
            return match
        }
        if let repositoryName {
            return self.uniqueStatus(forName: repositoryName, host: host)
        }
        return nil
    }

    public func status(forRepositoryName name: String) -> LocalRepoStatus? {
        self.uniqueStatus(forName: name, host: nil)
    }

    public func status(containingPath path: String) -> LocalRepoStatus? {
        let normalizedPath = URL(fileURLWithPath: PathFormatter.expandTilde(path)).standardizedFileURL.path
        if let exact = self.byPath[normalizedPath] {
            return exact
        }

        let matches = self.all.filter { status in
            let repoPath = status.path.standardizedFileURL.path
            return normalizedPath == repoPath || normalizedPath.hasPrefix(repoPath + "/")
        }
        guard matches.isEmpty == false else { return nil }

        return matches.reduce(matches[0]) { current, candidate in
            current.path.path.count >= candidate.path.path.count ? current : candidate
        }
    }

    private func uniqueStatus(forName name: String, host: URL?) -> LocalRepoStatus? {
        if let exact = self.uniqueStatus(in: self.byName, forKey: name, host: host) {
            return exact
        }
        return self.uniqueStatus(in: self.byNameLowercased, forKey: name.lowercased(), host: host)
    }

    private func uniqueStatus(
        in index: [String: [LocalRepoStatus]],
        forKey key: String,
        host: URL?
    ) -> LocalRepoStatus? {
        guard let indexed = index[key] else { return nil }

        let matches = indexed.filter { Self.matchesHost($0, host: host) }
        guard matches.count == 1 else { return nil }

        return matches.first
    }

    private func preferredStatus(
        in index: [String: [LocalRepoStatus]],
        forKey key: String,
        host: URL?
    ) -> LocalRepoStatus? {
        guard let indexed = index[key] else { return nil }

        let matches = indexed.filter { Self.matchesHost($0, host: host) }
        guard matches.isEmpty == false else { return nil }

        return matches.reduce(matches[0]) { current, candidate in
            Self.preferredStatus(current, candidate)
        }
    }

    private static func matchesHost(_ status: LocalRepoStatus, host: URL?) -> Bool {
        guard let host else { return true }

        return status.matches(host: host)
    }

    private static func preferredStatus(_ lhs: LocalRepoStatus, _ rhs: LocalRepoStatus) -> LocalRepoStatus {
        let lhsDepth = lhs.path.pathComponents.count
        let rhsDepth = rhs.path.pathComponents.count
        if lhsDepth != rhsDepth {
            return lhsDepth < rhsDepth ? lhs : rhs
        }
        if lhs.worktreeName == nil, rhs.worktreeName != nil {
            return lhs
        }
        if rhs.worktreeName == nil, lhs.worktreeName != nil {
            return rhs
        }
        return lhs.path.path <= rhs.path.path ? lhs : rhs
    }

    private static func normalizedHost(_ host: URL) -> String {
        Account.hostAuthority(for: host)
    }

    private static func normalizedHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)") else {
            return trimmed
        }

        return Account.hostAuthority(for: url)
    }
}
