import Foundation
import RepoBarCore

struct LocalRefMenuRowViewModel {
    enum Kind {
        case branch
        case worktree
    }

    let kind: Kind
    let title: String
    let detail: String?
    let isCurrent: Bool
    let isDetached: Bool
    let upstream: String?
    let aheadCount: Int?
    let behindCount: Int?
    let lastCommitDate: Date?
    let lastCommitAuthor: String?
    let dirtySummary: String?

    var usesMiddleTruncation: Bool {
        self.kind == .worktree
    }

    var syncLabel: String {
        let ahead = self.aheadCount ?? 0
        let behind = self.behindCount ?? 0
        guard ahead > 0 || behind > 0 else { return "" }

        var parts: [String] = []
        if ahead > 0 {
            parts.append("↑\(ahead)")
        }
        if behind > 0 {
            parts.append("↓\(behind)")
        }
        return parts.joined(separator: " ")
    }

    var commitLine: String? {
        guard let lastCommitDate, let lastCommitAuthor else { return nil }

        let when = RelativeFormatter.string(from: lastCommitDate, relativeTo: Date())
        return "\(lastCommitAuthor) · \(when)"
    }
}
