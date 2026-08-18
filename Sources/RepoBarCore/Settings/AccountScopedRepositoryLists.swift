import Foundation

/// Pinned and hidden repository lists, partitioned by account ID.
///
/// Entries are stored as `owner/name` to mirror the legacy single-account
/// `RepoListSettings.pinnedRepositories` / `hiddenRepositories` format.
public struct AccountScopedRepositoryLists: Equatable, Codable, Sendable {
    public var pinnedByAccount: [String: [String]]
    public var hiddenByAccount: [String: [String]]

    public init(
        pinnedByAccount: [String: [String]] = [:],
        hiddenByAccount: [String: [String]] = [:]
    ) {
        self.pinnedByAccount = pinnedByAccount
        self.hiddenByAccount = hiddenByAccount
    }

    public var isEmpty: Bool {
        self.pinnedByAccount.isEmpty && self.hiddenByAccount.isEmpty
    }

    public func pinned(for accountID: String) -> [String] {
        self.pinnedByAccount[accountID] ?? []
    }

    public func hidden(for accountID: String) -> [String] {
        self.hiddenByAccount[accountID] ?? []
    }

    public func hasPinnedEntry(for accountID: String) -> Bool {
        self.pinnedByAccount[accountID] != nil
    }

    public func hasHiddenEntry(for accountID: String) -> Bool {
        self.hiddenByAccount[accountID] != nil
    }

    public mutating func setPinned(_ items: [String], for accountID: String) {
        self.pinnedByAccount[accountID] = Self.normalize(items)
    }

    public mutating func setHidden(_ items: [String], for accountID: String) {
        self.hiddenByAccount[accountID] = Self.normalize(items)
    }

    public func pinned(for accountID: String, legacy: [String]) -> [String] {
        if let perAccount = self.pinnedByAccount[accountID] {
            return perAccount
        }
        return legacy
    }

    public func hidden(for accountID: String, legacy: [String]) -> [String] {
        if let perAccount = self.hiddenByAccount[accountID] {
            return perAccount
        }
        return legacy
    }

    public mutating func remove(accountID: String) {
        self.pinnedByAccount.removeValue(forKey: accountID)
        self.hiddenByAccount.removeValue(forKey: accountID)
    }

    private static func normalize(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        return items.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }

            let lower = trimmed.lowercased()
            guard seen.insert(lower).inserted else { return nil }

            return trimmed
        }
    }
}
