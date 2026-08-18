import Foundation
@preconcurrency import GRDB

public struct PersistentHTTPResponse: Equatable, Sendable {
    public let etag: String
    public let data: Data
    public let fetchedAt: Date

    public init(etag: String, data: Data, fetchedAt: Date) {
        self.etag = etag
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

public struct RepoBarCacheSummary: Codable, Equatable, Sendable {
    public let databasePath: String
    public let exists: Bool
    public let apiResponseCount: Int
    public let graphQLResponseCount: Int
    public let rateLimitCount: Int
    public let latestResponses: [RepoBarCachedResponseSummary]
    public let rateLimits: [RepoBarRateLimitSummary]
}

public struct RepoBarCachedResponseSummary: Codable, Equatable, Sendable {
    public let method: String
    public let url: String
    public let hasETag: Bool
    public let statusCode: Int?
    public let fetchedAt: Date
    public let rateLimitResource: String?
    public let rateLimitLimit: Int?
    public let rateLimitRemaining: Int?
    public let rateLimitReset: Date?

    public init(
        method: String,
        url: String,
        hasETag: Bool,
        statusCode: Int?,
        fetchedAt: Date,
        rateLimitResource: String?,
        rateLimitLimit: Int? = nil,
        rateLimitRemaining: Int?,
        rateLimitReset: Date?
    ) {
        self.method = method
        self.url = url
        self.hasETag = hasETag
        self.statusCode = statusCode
        self.fetchedAt = fetchedAt
        self.rateLimitResource = rateLimitResource
        self.rateLimitLimit = rateLimitLimit
        self.rateLimitRemaining = rateLimitRemaining
        self.rateLimitReset = rateLimitReset
    }
}

public struct RepoBarRateLimitSummary: Codable, Equatable, Sendable {
    public let resource: String
    public let remaining: Int?
    public let resetAt: Date
    public let lastError: String?
}

public enum RepoBarPersistentCache {
    public static func standardDatabaseURL(fileManager: FileManager = .default) -> URL? {
        HTTPResponseDiskCache.standardDatabaseURL(fileManager: fileManager)
    }

    /// Account-scoped persistent cache path:
    /// `~/Library/Application Support/RepoBar/Cache/<safe-accountID>.sqlite`.
    ///
    /// Falls back to `standardDatabaseURL` when `accountID` is nil so legacy
    /// single-account callers keep their existing on-disk file. The account ID
    /// is sanitized for use as a filename: any character outside
    /// `[A-Za-z0-9._-]` is replaced with `_`.
    public static func databaseURL(
        accountID: String?,
        fileManager: FileManager = .default
    ) -> URL? {
        HTTPResponseDiskCache.databaseURL(accountID: accountID, fileManager: fileManager)
    }

    public static func summary(limit: Int = 10, fileManager: FileManager = .default) throws -> RepoBarCacheSummary {
        try self.summary(accountID: nil, limit: limit, fileManager: fileManager)
    }

    public static func summary(
        accountID: String?,
        limit: Int = 10,
        fileManager: FileManager = .default
    ) throws -> RepoBarCacheSummary {
        guard let url = self.databaseURL(accountID: accountID, fileManager: fileManager) else {
            throw RepoBarCacheError.missingApplicationSupportDirectory
        }

        let exists = fileManager.fileExists(atPath: url.path)
        guard exists else {
            return RepoBarCacheSummary(
                databasePath: url.path,
                exists: false,
                apiResponseCount: 0,
                graphQLResponseCount: 0,
                rateLimitCount: 0,
                latestResponses: [],
                rateLimits: []
            )
        }

        return try HTTPResponseDiskCache(path: url.path).summary(limit: limit)
    }

    public static func clear(fileManager: FileManager = .default) throws -> RepoBarCacheSummary {
        guard let url = self.standardDatabaseURL(fileManager: fileManager) else {
            throw RepoBarCacheError.missingApplicationSupportDirectory
        }

        let cache = try HTTPResponseDiskCache(path: url.path)
        cache.clear()
        return try cache.summary(limit: 0)
    }
}

public enum RepoBarCacheError: Error, LocalizedError {
    case missingApplicationSupportDirectory

    public var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory: "Unable to resolve Application Support directory."
        }
    }
}

/// DatabaseQueue serializes access; GitHub lookup task groups share this cache.
final class HTTPResponseDiskCache: @unchecked Sendable {
    private let queue: DatabaseQueue
    private let path: String
    private let clock: @Sendable () -> Date
    private let logger = RepoBarLogging.logger("cache-db")

    init(path: String, clock: @escaping @Sendable () -> Date = Date.init) throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        self.queue = try DatabaseQueue(path: path, configuration: configuration)
        self.path = path
        self.clock = clock
        try Self.migrate(self.queue)
    }

    static func standard() -> HTTPResponseDiskCache? {
        self.scoped(accountID: nil)
    }

    static func scoped(accountID: String?) -> HTTPResponseDiskCache? {
        let url = self.databaseURL(accountID: accountID)
            ?? self.standardDatabaseURL()
        guard let path = url?.path else { return nil }

        do {
            return try HTTPResponseDiskCache(path: path)
        } catch {
            RepoBarLogging.logger("cache-db").error("Unable to open persistent cache: \(error.localizedDescription)")
            return nil
        }
    }

    static func standardDatabaseURL(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return base
            .appending(path: "RepoBar", directoryHint: .isDirectory)
            .appending(path: "Cache.sqlite", directoryHint: .notDirectory)
    }

    /// Account-scoped variant of `standardDatabaseURL`. See
    /// `RepoBarPersistentCache.databaseURL(accountID:fileManager:)`.
    static func databaseURL(
        accountID: String?,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let accountID, accountID.isEmpty == false else {
            return self.standardDatabaseURL(fileManager: fileManager)
        }
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return base
            .appending(path: "RepoBar", directoryHint: .isDirectory)
            .appending(path: "Cache", directoryHint: .isDirectory)
            .appending(path: "\(Self.safeAccountFilename(accountID)).sqlite", directoryHint: .notDirectory)
    }

    static func safeAccountFilename(_ accountID: String) -> String {
        let hex = accountID.utf8.map { String(format: "%02x", $0) }.joined()
        return "v2-\(hex)"
    }

    func cached(url: URL) -> PersistentHTTPResponse? {
        let key = Self.key(url: url)
        do {
            return try self.queue.read { db in
                guard let row = try Row.fetchOne(
                    db,
                    sql: "select etag, body, fetched_at from api_responses where key = ? and etag is not null",
                    arguments: [key]
                ) else { return nil }

                let etag: String = row["etag"]
                let body: Data = row["body"]
                let fetchedAt: Double = row["fetched_at"]
                return PersistentHTTPResponse(
                    etag: etag,
                    data: body,
                    fetchedAt: Date(timeIntervalSinceReferenceDate: fetchedAt)
                )
            }
        } catch {
            self.logger.error("Unable to read cached response: \(error.localizedDescription)")
            return nil
        }
    }

    func save(url: URL, etag: String, data: Data, response: HTTPURLResponse? = nil) {
        let now = self.clock()
        let reset = response.flatMap(Self.rateLimitReset)
        let limit = response.flatMap(Self.rateLimitLimit)
        let remaining = response.flatMap(Self.rateLimitRemaining)
        let resource = response?.value(forHTTPHeaderField: "X-RateLimit-Resource")
        let statusCode = response?.statusCode
        let headersJSON = response.flatMap(Self.headersJSON)
        let key = Self.key(url: url)

        do {
            try self.queue.write { db in
                try db.execute(
                    sql: """
                    insert into api_responses(
                        key, method, url, etag, status_code, headers_json, body, fetched_at,
                        rate_limit_resource, rate_limit_limit, rate_limit_remaining, rate_limit_reset, updated_at
                    )
                    values (?, 'GET', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    on conflict(key) do update set
                        etag = excluded.etag,
                        status_code = excluded.status_code,
                        headers_json = excluded.headers_json,
                        body = excluded.body,
                        fetched_at = excluded.fetched_at,
                        rate_limit_resource = excluded.rate_limit_resource,
                        rate_limit_limit = excluded.rate_limit_limit,
                        rate_limit_remaining = excluded.rate_limit_remaining,
                        rate_limit_reset = excluded.rate_limit_reset,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [
                        key,
                        url.absoluteString,
                        etag,
                        statusCode,
                        headersJSON,
                        data,
                        now.timeIntervalSinceReferenceDate,
                        resource,
                        limit,
                        remaining,
                        reset?.timeIntervalSinceReferenceDate,
                        now.timeIntervalSinceReferenceDate
                    ]
                )
            }
        } catch {
            self.logger.error("Unable to save cached response: \(error.localizedDescription)")
        }
    }

    func setRateLimitReset(resource: String = "core", date: Date, message: String? = nil) {
        let now = self.clock()
        do {
            try self.queue.write { db in
                try db.execute(
                    sql: """
                    insert into rate_limits(resource, remaining, reset_at, last_error, updated_at)
                    values (?, 0, ?, ?, ?)
                    on conflict(resource) do update set
                        remaining = excluded.remaining,
                        reset_at = excluded.reset_at,
                        last_error = excluded.last_error,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [
                        resource,
                        date.timeIntervalSinceReferenceDate,
                        message,
                        now.timeIntervalSinceReferenceDate
                    ]
                )
            }
        } catch {
            self.logger.error("Unable to save rate-limit state: \(error.localizedDescription)")
        }
    }

    func rateLimitUntil(resource: String = "core", now: Date = Date()) -> Date? {
        let reset: Double?
        do {
            reset = try self.queue.read { db -> Double? in
                try Double.fetchOne(
                    db,
                    sql: "select reset_at from rate_limits where resource = ?",
                    arguments: [resource]
                )
            }
        } catch {
            self.logger.error("Unable to read rate-limit state: \(error.localizedDescription)")
            return nil
        }
        guard let reset else { return nil }

        let date = Date(timeIntervalSinceReferenceDate: reset)
        if date <= now {
            self.clearExpiredRateLimit(resource: resource, reset: reset)
            return nil
        }
        return date
    }

    func count() -> Int {
        do {
            return try self.queue.read { db in
                try Int.fetchOne(db, sql: "select count(*) from api_responses") ?? 0
            }
        } catch {
            self.logger.error("Unable to count cached responses: \(error.localizedDescription)")
            return 0
        }
    }

    func summary(limit: Int = 10) throws -> RepoBarCacheSummary {
        try self.queue.read { db in
            let apiResponseCount = try Int.fetchOne(db, sql: "select count(*) from api_responses") ?? 0
            let graphQLResponseCount = try Int.fetchOne(db, sql: "select count(*) from graphql_responses") ?? 0
            let rateLimitCount = try Int.fetchOne(db, sql: "select count(*) from rate_limits") ?? 0
            let responses = try Row.fetchAll(
                db,
                sql: """
                select method, url, etag, status_code, fetched_at, rate_limit_resource,
                    rate_limit_limit, rate_limit_remaining, rate_limit_reset
                from api_responses
                order by fetched_at desc
                limit ?
                """,
                arguments: [max(0, limit)]
            ).map { row in
                let fetchedAt: Double = row["fetched_at"]
                let rateLimitReset: Double? = row["rate_limit_reset"]
                let etag: String? = row["etag"]
                return RepoBarCachedResponseSummary(
                    method: row["method"],
                    url: row["url"],
                    hasETag: etag?.isEmpty == false,
                    statusCode: row["status_code"],
                    fetchedAt: Date(timeIntervalSinceReferenceDate: fetchedAt),
                    rateLimitResource: row["rate_limit_resource"],
                    rateLimitLimit: row["rate_limit_limit"],
                    rateLimitRemaining: row["rate_limit_remaining"],
                    rateLimitReset: rateLimitReset.map { Date(timeIntervalSinceReferenceDate: $0) }
                )
            }
            let rateLimits = try Row.fetchAll(
                db,
                sql: "select resource, remaining, reset_at, last_error from rate_limits order by resource"
            ).map { row in
                let resetAt: Double = row["reset_at"]
                return RepoBarRateLimitSummary(
                    resource: row["resource"],
                    remaining: row["remaining"],
                    resetAt: Date(timeIntervalSinceReferenceDate: resetAt),
                    lastError: row["last_error"]
                )
            }
            return RepoBarCacheSummary(
                databasePath: self.path,
                exists: true,
                apiResponseCount: apiResponseCount,
                graphQLResponseCount: graphQLResponseCount,
                rateLimitCount: rateLimitCount,
                latestResponses: responses,
                rateLimits: rateLimits
            )
        }
    }

    func clear() {
        do {
            try self.queue.write { db in
                try db.execute(sql: "delete from api_responses")
                try db.execute(sql: "delete from graphql_responses")
                try db.execute(sql: "delete from rate_limits")
            }
        } catch {
            self.logger.error("Unable to clear persistent cache: \(error.localizedDescription)")
        }
    }

    private func clearExpiredRateLimit(resource: String, reset: Double) {
        do {
            try self.queue.write { db in
                try db.execute(
                    sql: "delete from rate_limits where resource = ? and reset_at = ?",
                    arguments: [resource, reset]
                )
            }
        } catch {
            self.logger.error("Unable to clear expired rate-limit state: \(error.localizedDescription)")
        }
    }

    static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "api_responses", ifNotExists: true) { table in
                table.column("key", .text).primaryKey()
                table.column("method", .text).notNull()
                table.column("url", .text).notNull()
                table.column("etag", .text)
                table.column("status_code", .integer)
                table.column("headers_json", .text)
                table.column("body", .blob).notNull()
                table.column("fetched_at", .double).notNull()
                table.column("expires_at", .double)
                table.column("rate_limit_resource", .text)
                table.column("rate_limit_remaining", .integer)
                table.column("rate_limit_reset", .double)
                table.column("updated_at", .double).notNull()
            }
            try db.create(index: "idx_api_responses_url", on: "api_responses", columns: ["url"], ifNotExists: true)
            try db.create(table: "rate_limits", ifNotExists: true) { table in
                table.column("resource", .text).primaryKey()
                table.column("remaining", .integer)
                table.column("reset_at", .double).notNull()
                table.column("last_error", .text)
                table.column("updated_at", .double).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.create(table: "graphql_responses", ifNotExists: true) { table in
                table.column("key", .text).primaryKey()
                table.column("endpoint", .text).notNull()
                table.column("operation", .text).notNull()
                table.column("body_hash", .text).notNull()
                table.column("response_body", .blob).notNull()
                table.column("fetched_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }
            try db.create(index: "idx_graphql_responses_fetched_at", on: "graphql_responses", columns: ["fetched_at"], ifNotExists: true)
        }
        migrator.registerMigration("v3") { db in
            try db.alter(table: "api_responses") { table in
                table.add(column: "rate_limit_limit", .integer)
            }
        }
        try migrator.migrate(queue)
    }

    private static func key(url: URL) -> String {
        "GET\t\(url.absoluteString)"
    }

    private static func rateLimitReset(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let epoch = TimeInterval(value) else { return nil }

        return Date(timeIntervalSince1970: epoch)
    }

    private static func rateLimitRemaining(from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") else { return nil }

        return Int(value)
    }

    private static func rateLimitLimit(from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "X-RateLimit-Limit") else { return nil }

        return Int(value)
    }

    private static func headersJSON(from response: HTTPURLResponse) -> String? {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String else { return }

            result[key] = "\(pair.value)"
        }
        guard let data = try? JSONEncoder().encode(headers) else { return nil }

        return String(data: data, encoding: .utf8)
    }
}
