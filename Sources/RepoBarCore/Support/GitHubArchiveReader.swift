import Foundation
@preconcurrency import GRDB

public enum GitHubArchiveReaderError: Error, LocalizedError {
    case unreadableDatabase(String)

    public var errorDescription: String? {
        switch self {
        case let .unreadableDatabase(path): "Unable to read GitHub archive database: \(path)"
        }
    }
}

public struct GitHubArchiveReader: Sendable {
    public let databasePath: String

    public init(databasePath: String) {
        self.databasePath = PathFormatter.expandTilde(databasePath)
    }

    public func recentIssues(owner: String, name: String, limit: Int) throws -> [RepoIssueSummary] {
        try self.readThreads(owner: owner, name: name, kinds: ["issue"], limit: limit).map { row in
            RepoIssueSummary(
                number: row.number,
                title: row.title,
                url: row.url ?? Self.defaultURL(owner: owner, name: name, number: row.number, kind: "issues"),
                updatedAt: row.updatedAt,
                authorLogin: row.authorLogin,
                authorAvatarURL: row.authorAvatarURL,
                assigneeLogins: row.assigneeLogins,
                commentCount: row.commentCount,
                labels: row.labels
            )
        }
    }

    public func recentPullRequests(owner: String, name: String, limit: Int) throws -> [RepoPullRequestSummary] {
        try self.readThreads(owner: owner, name: name, kinds: ["pull", "pr", "pull_request"], limit: limit).map { row in
            RepoPullRequestSummary(
                number: row.number,
                title: row.title,
                url: row.url ?? Self.defaultURL(owner: owner, name: name, number: row.number, kind: "pull"),
                updatedAt: row.updatedAt,
                authorLogin: row.authorLogin,
                authorAvatarURL: row.authorAvatarURL,
                isDraft: row.isDraft,
                commentCount: row.commentCount,
                reviewCommentCount: row.reviewCommentCount,
                labels: row.labels,
                headRefName: row.headRefName,
                baseRefName: row.baseRefName
            )
        }
    }

    public static func recentIssues(settings: GitHubArchiveSettings, owner: String, name: String, limit: Int) -> [RepoIssueSummary] {
        self.enabledReaders(settings: settings).lazy.compactMap { reader in
            try? reader.recentIssues(owner: owner, name: name, limit: limit)
        }.first { !$0.isEmpty } ?? []
    }

    public static func recentPullRequests(settings: GitHubArchiveSettings, owner: String, name: String, limit: Int) -> [RepoPullRequestSummary] {
        self.enabledReaders(settings: settings).lazy.compactMap { reader in
            try? reader.recentPullRequests(owner: owner, name: name, limit: limit)
        }.first { !$0.isEmpty } ?? []
    }

    private static func enabledReaders(settings: GitHubArchiveSettings) -> [GitHubArchiveReader] {
        settings.sources
            .filter(\.enabled)
            .map { GitHubArchiveReader(databasePath: $0.importedDatabasePath) }
    }

    private func readThreads(owner: String, name: String, kinds: [String], limit: Int) throws -> [ArchiveThreadRow] {
        guard FileManager.default.fileExists(atPath: self.databasePath) else { return [] }

        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: self.databasePath)
        } catch {
            throw GitHubArchiveReaderError.unreadableDatabase(self.databasePath)
        }

        return try queue.read { db in
            guard try Self.tableExists("threads", db: db) else { return [] }

            let columns = try Self.columnSet(table: "threads", db: db)
            guard columns.contains("repository"), columns.contains("kind"), columns.contains("number") else {
                return []
            }

            let select = ThreadColumnSelection(columns: columns)
            let statePredicate = columns.contains("state") ? "and lower(coalesce(\"state\", 'open')) = 'open'" : ""
            let kindPlaceholders = Array(repeating: "?", count: kinds.count).joined(separator: ", ")
            var arguments: StatementArguments = [
                "\(owner.lowercased())/\(name.lowercased())"
            ]
            for kind in kinds {
                _ = arguments.append(contentsOf: [kind])
            }
            _ = arguments.append(contentsOf: [max(0, limit)])

            let rows = try Row.fetchAll(
                db,
                sql: """
                select \(select.sql)
                from "threads"
                where lower("repository") = ?
                  and lower("kind") in (\(kindPlaceholders))
                  \(statePredicate)
                order by \(select.updatedAtOrderSQL) desc, cast("number" as integer) desc
                limit ?
                """,
                arguments: arguments
            )
            return rows.compactMap { row in
                Self.threadRow(row: row, owner: owner, name: name)
            }
        }
    }

    private static func threadRow(row: Row, owner _: String, name _: String) -> ArchiveThreadRow? {
        let raw = Self.jsonObject(row["raw_json"] as String?)
        let number = Self.int(row["number"] as String?) ?? Self.int(raw, keys: ["number"])
        guard let number else { return nil }

        let title = Self.string(row["title"] as String?) ?? Self.string(raw, keys: ["title"]) ?? "#\(number)"
        let updatedAt = Self.date(row["updated_at"] as String?)
            ?? Self.date(Self.string(raw, keys: ["updated_at", "updatedAt"]))
            ?? .distantPast
        let url = Self.url(row["url"] as String?)
            ?? Self.url(row["html_url"] as String?)
            ?? Self.url(Self.string(raw, keys: ["html_url", "url"]))
        let authorLogin = Self.string(row["author_login"] as String?)
            ?? Self.string(raw, keys: ["author_login"])
            ?? Self.string(Self.dictionary(raw, keys: ["user", "author"]), keys: ["login"])
        let authorAvatarURL = Self.url(row["author_avatar_url"] as String?)
            ?? Self.url(Self.string(raw, keys: ["author_avatar_url"]))
            ?? Self.url(Self.string(Self.dictionary(raw, keys: ["user", "author"]), keys: ["avatar_url", "avatarUrl"]))
        let labels = Self.labels(
            row["labels_json"] as String?,
            row["labels"] as String?,
            raw
        )

        return ArchiveThreadRow(
            number: number,
            title: title,
            url: url,
            updatedAt: updatedAt,
            authorLogin: authorLogin,
            authorAvatarURL: authorAvatarURL,
            assigneeLogins: Self.assigneeLogins(row["assignees_json"] as String?, raw),
            commentCount: Self.int(row["comment_count"] as String?)
                ?? Self.int(row["comments"] as String?)
                ?? Self.int(raw, keys: ["comment_count", "comments"])
                ?? 0,
            reviewCommentCount: Self.int(row["review_comment_count"] as String?)
                ?? Self.int(row["review_comments"] as String?)
                ?? Self.int(raw, keys: ["review_comment_count", "review_comments"])
                ?? 0,
            isDraft: Self.bool(row["is_draft"] as String?)
                ?? Self.bool(row["draft"] as String?)
                ?? Self.bool(raw, keys: ["is_draft", "draft"])
                ?? false,
            labels: labels,
            headRefName: Self.string(row["head_ref_name"] as String?)
                ?? Self.string(row["head_ref"] as String?)
                ?? Self.string(Self.dictionary(raw, keys: ["head"]), keys: ["ref"]),
            baseRefName: Self.string(row["base_ref_name"] as String?)
                ?? Self.string(row["base_ref"] as String?)
                ?? Self.string(Self.dictionary(raw, keys: ["base"]), keys: ["ref"])
        )
    }

    private static func tableExists(_ table: String, db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "select exists(select 1 from sqlite_master where type = 'table' and name = ?)",
            arguments: [table]
        ) ?? false
    }

    private static func columnSet(table: String, db: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(Self.quoted(table)))")
        return Set(rows.compactMap { $0["name"] as String? })
    }

    private static func defaultURL(owner: String, name: String, number: Int, kind: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(name)/\(kind)/\(number)")!
    }

    fileprivate static func quoted(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func string(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }

        return value
    }

    private static func string(_ object: [String: Any]?, keys: [String]) -> String? {
        guard let object else { return nil }

        for key in keys {
            if let value = object[key] as? String, let string = self.string(value) {
                return string
            }
            if let number = object[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func int(_ value: String?) -> Int? {
        guard let string = self.string(value) else { return nil }

        return Int(string)
    }

    private static func int(_ object: [String: Any]?, keys: [String]) -> Int? {
        guard let object else { return nil }

        for key in keys {
            if let value = object[key] as? Int {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.intValue
            }
            if let value = object[key] as? String, let int = Int(value) {
                return int
            }
        }
        return nil
    }

    private static func bool(_ value: String?) -> Bool? {
        guard let string = self.string(value)?.lowercased() else { return nil }

        if ["1", "true", "yes"].contains(string) {
            return true
        }
        if ["0", "false", "no"].contains(string) {
            return false
        }
        return nil
    }

    private static func bool(_ object: [String: Any]?, keys: [String]) -> Bool? {
        guard let object else { return nil }

        for key in keys {
            if let value = object[key] as? Bool {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.boolValue
            }
            if let value = object[key] as? String, let bool = self.bool(value) {
                return bool
            }
        }
        return nil
    }

    private static func date(_ value: String?) -> Date? {
        ArchiveDateParser.date(from: value)
    }

    private static func url(_ value: String?) -> URL? {
        guard let value = self.string(value) else { return nil }

        return URL(string: value)
    }

    private static func jsonObject(_ value: String?) -> [String: Any]? {
        guard let value, let data = value.data(using: .utf8) else { return nil }

        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func jsonArray(_ value: String?) -> [[String: Any]]? {
        guard let value, let data = value.data(using: .utf8) else { return nil }

        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private static func dictionary(_ object: [String: Any]?, keys: [String]) -> [String: Any]? {
        guard let object else { return nil }

        for key in keys {
            if let dictionary = object[key] as? [String: Any] {
                return dictionary
            }
        }
        return nil
    }

    private static func labels(_ primary: String?, _ secondary: String?, _ raw: [String: Any]?) -> [RepoIssueLabel] {
        let arrays = [
            self.jsonArray(primary),
            self.jsonArray(secondary),
            raw?["labels"] as? [[String: Any]]
        ]

        for array in arrays.compactMap(\.self) where array.isEmpty == false {
            return array.compactMap { label in
                guard let name = self.string(label, keys: ["name"]) else { return nil }

                return RepoIssueLabel(name: name, colorHex: self.string(label, keys: ["color", "colorHex"]) ?? "")
            }
        }
        return []
    }

    private static func assigneeLogins(_ value: String?, _ raw: [String: Any]?) -> [String] {
        let arrays = [
            self.jsonArray(value),
            raw?["assignees"] as? [[String: Any]]
        ]

        for array in arrays.compactMap(\.self) where array.isEmpty == false {
            return array.compactMap { self.string($0, keys: ["login"]) }
        }
        return []
    }
}

private struct ThreadColumnSelection {
    let sql: String
    let updatedAtOrderSQL: String

    init(columns: Set<String>) {
        func expression(_ candidates: [String], alias: String) -> String {
            if let column = candidates.first(where: { columns.contains($0) }) {
                return "\(GitHubArchiveReader.quoted(column)) as \(GitHubArchiveReader.quoted(alias))"
            }
            return "null as \(GitHubArchiveReader.quoted(alias))"
        }

        let aliases: [(String, [String])] = [
            ("number", ["number"]),
            ("title", ["title"]),
            ("updated_at", ["updated_at", "updatedAt"]),
            ("url", ["url"]),
            ("html_url", ["html_url", "htmlUrl"]),
            ("author_login", ["author_login", "author"]),
            ("author_avatar_url", ["author_avatar_url"]),
            ("assignees_json", ["assignees_json", "assignees"]),
            ("comment_count", ["comment_count"]),
            ("comments", ["comments"]),
            ("review_comment_count", ["review_comment_count"]),
            ("review_comments", ["review_comments"]),
            ("labels_json", ["labels_json"]),
            ("labels", ["labels"]),
            ("is_draft", ["is_draft"]),
            ("draft", ["draft"]),
            ("head_ref_name", ["head_ref_name"]),
            ("head_ref", ["head_ref"]),
            ("base_ref_name", ["base_ref_name"]),
            ("base_ref", ["base_ref"]),
            ("raw_json", ["_repobar_raw_json", "raw_json"])
        ]
        self.sql = aliases.map { expression($0.1, alias: $0.0) }.joined(separator: ", ")
        if columns.contains("updated_at") {
            self.updatedAtOrderSQL = "\"updated_at\""
        } else if columns.contains("updatedAt") {
            self.updatedAtOrderSQL = "\"updatedAt\""
        } else {
            self.updatedAtOrderSQL = "\"number\""
        }
    }
}

private struct ArchiveThreadRow {
    let number: Int
    let title: String
    let url: URL?
    let updatedAt: Date
    let authorLogin: String?
    let authorAvatarURL: URL?
    let assigneeLogins: [String]
    let commentCount: Int
    let reviewCommentCount: Int
    let isDraft: Bool
    let labels: [RepoIssueLabel]
    let headRefName: String?
    let baseRefName: String?
}
