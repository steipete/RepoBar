import Foundation

public struct LocalRepoStatus: Equatable, Sendable {
    public let path: URL
    public let name: String
    public let fullName: String?
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
        if let preferred = self.preferredPathsByFullName[repo.fullName], let status = self.byPath[preferred] {
            return status
        }
        if let exact = self.byFullName[repo.fullName] {
            return exact
        }
        if let match = self.preferredStatus(in: self.byFullNameLowercased, forKey: repo.fullName.lowercased()) {
            return match
        }
        return self.uniqueStatus(forName: repo.name)
    }

    public func status(forFullName fullName: String) -> LocalRepoStatus? {
        if let preferred = self.preferredPathsByFullName[fullName], let status = self.byPath[preferred] {
            return status
        }
        if let exact = self.byFullName[fullName] {
            return exact
        }
        if let match = self.preferredStatus(in: self.byFullNameLowercased, forKey: fullName.lowercased()) {
            return match
        }
        let name = fullName.split(separator: "/").last.map(String.init)
        if let name {
            return self.uniqueStatus(forName: name)
        }
        return nil
    }

    public func status(forRepositoryName name: String) -> LocalRepoStatus? {
        self.uniqueStatus(forName: name)
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

    private func uniqueStatus(forName name: String) -> LocalRepoStatus? {
        if let exact = self.uniqueStatus(in: self.byName, forKey: name) {
            return exact
        }
        return self.uniqueStatus(in: self.byNameLowercased, forKey: name.lowercased())
    }

    private func uniqueStatus(in index: [String: [LocalRepoStatus]], forKey key: String) -> LocalRepoStatus? {
        guard let matches = index[key], matches.count == 1 else { return nil }

        return matches.first
    }

    private func preferredStatus(in index: [String: [LocalRepoStatus]], forKey key: String) -> LocalRepoStatus? {
        guard let matches = index[key], matches.isEmpty == false else { return nil }

        return matches.reduce(matches[0]) { current, candidate in
            Self.preferredStatus(current, candidate)
        }
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
}
