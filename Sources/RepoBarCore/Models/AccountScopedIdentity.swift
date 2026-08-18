import Foundation

/// Identifies the account that supplied a GitHub-backed value.
public struct AccountSource: Codable, Equatable, Hashable, Sendable {
    public let accountID: String

    public init(accountID: String) {
        self.accountID = accountID
    }

    public init(account: Account) {
        self.init(accountID: account.id)
    }
}

/// Collision-safe identity for a repository returned through a specific account.
public struct AccountScopedRepositoryIdentity: Codable, Equatable, Hashable, Sendable {
    public let source: AccountSource
    public let repositoryID: String

    public init(source: AccountSource, repositoryID: String) {
        self.source = source
        self.repositoryID = repositoryID
    }

    public init(accountID: String, repositoryID: String) {
        self.init(source: AccountSource(accountID: accountID), repositoryID: repositoryID)
    }
}

/// Collision-safe identity for account-scoped references that have a canonical URL.
public struct AccountScopedURLIdentity: Codable, Equatable, Hashable, Sendable {
    public let source: AccountSource
    public let url: URL

    public init(source: AccountSource, url: URL) {
        self.source = source
        self.url = url
    }

    public init(accountID: String, url: URL) {
        self.init(source: AccountSource(accountID: accountID), url: url)
    }
}

/// Collision-safe identity for notification and attention events.
public struct AccountScopedEventIdentity: Codable, Equatable, Hashable, Sendable {
    public let source: AccountSource
    public let namespace: String
    public let eventID: String

    public init(source: AccountSource, namespace: String, eventID: String) {
        self.source = source
        self.namespace = namespace
        self.eventID = eventID
    }

    public init(accountID: String, namespace: String, eventID: String) {
        self.init(
            source: AccountSource(accountID: accountID),
            namespace: namespace,
            eventID: eventID
        )
    }
}

/// Cache key that cannot collide across account-specific stores or request routes.
public struct AccountScopedCacheKey: Codable, Equatable, Hashable, Sendable {
    public let source: AccountSource
    public let key: String

    public init(source: AccountSource, key: String) {
        self.source = source
        self.key = key
    }

    public init(accountID: String, key: String) {
        self.init(source: AccountSource(accountID: accountID), key: key)
    }

    public var accountID: String {
        self.source.accountID
    }
}
