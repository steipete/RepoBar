import Foundation
@preconcurrency import GRDB

public struct GitHubArchiveStatusOutput: Codable, Equatable, Sendable {
    public let sources: [GitHubArchiveSourceStatus]

    public init(sources: [GitHubArchiveSourceStatus]) {
        self.sources = sources
    }
}

public struct GitHubArchiveSourceStatus: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let enabled: Bool
    public let format: GitHubArchiveFormat
    public let localRepositoryPath: String?
    public let localRepositoryExists: Bool
    public let remoteURL: String?
    public let branch: String
    public let manifestPath: String?
    public let manifestExists: Bool
    public let importedDatabasePath: String
    public let databaseExists: Bool
    public let configValid: Bool
    public let readyForRead: Bool
    public let issues: [String]
    public let lastImportAt: Date?
    public let manifestGeneratedAt: Date?
    public let importedTableCount: Int?
    public let importedRowCount: Int?
    public let databaseUserVersion: Int?

    public init(
        id: String,
        name: String,
        enabled: Bool,
        format: GitHubArchiveFormat,
        localRepositoryPath: String?,
        localRepositoryExists: Bool,
        remoteURL: String?,
        branch: String,
        manifestPath: String?,
        manifestExists: Bool,
        importedDatabasePath: String,
        databaseExists: Bool,
        configValid: Bool,
        readyForRead: Bool,
        issues: [String],
        lastImportAt: Date?,
        manifestGeneratedAt: Date?,
        importedTableCount: Int?,
        importedRowCount: Int?,
        databaseUserVersion: Int?
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.format = format
        self.localRepositoryPath = localRepositoryPath
        self.localRepositoryExists = localRepositoryExists
        self.remoteURL = remoteURL
        self.branch = branch
        self.manifestPath = manifestPath
        self.manifestExists = manifestExists
        self.importedDatabasePath = importedDatabasePath
        self.databaseExists = databaseExists
        self.configValid = configValid
        self.readyForRead = readyForRead
        self.issues = issues
        self.lastImportAt = lastImportAt
        self.manifestGeneratedAt = manifestGeneratedAt
        self.importedTableCount = importedTableCount
        self.importedRowCount = importedRowCount
        self.databaseUserVersion = databaseUserVersion
    }
}

public struct GitHubArchiveUpdateResult: Codable, Equatable, Sendable {
    public let source: GitHubArchiveSource
    public let importResult: GitHubArchiveImportResult

    public init(source: GitHubArchiveSource, importResult: GitHubArchiveImportResult) {
        self.source = source
        self.importResult = importResult
    }
}

public enum GitHubArchiveStoreError: Error, LocalizedError {
    case missingArchiveName
    case archiveNotFound(String)
    case archiveDisabled(String)
    case missingSnapshotSource(String)
    case missingRepositoryPath(String)
    case gitFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingArchiveName:
            "Missing archive name"
        case let .archiveNotFound(name):
            "Archive not found: \(name)"
        case let .archiveDisabled(name):
            "Archive is disabled: \(name)"
        case let .missingSnapshotSource(name):
            "Archive update needs --repo or --remote: \(name)"
        case let .missingRepositoryPath(name):
            "Archive update needs a local repository path: \(name)"
        case let .gitFailed(message):
            message
        }
    }
}

public enum GitHubArchiveStore {
    public static func requireName(_ raw: String?) throws -> String {
        guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), name.isEmpty == false else {
            throw GitHubArchiveStoreError.missingArchiveName
        }

        return name
    }

    public static func statuses(settings: GitHubArchiveSettings, name rawName: String? = nil) throws -> [GitHubArchiveSourceStatus] {
        let sources: [GitHubArchiveSource]
        if let rawName {
            let name = try self.requireName(rawName)
            sources = settings.githubArchivesSources(matching: name)
            if sources.isEmpty {
                throw GitHubArchiveStoreError.archiveNotFound(name)
            }
        } else {
            sources = settings.sources
        }

        return sources.map { self.status(for: $0) }
    }

    public static func status(for source: GitHubArchiveSource, fileManager: FileManager = .default) -> GitHubArchiveSourceStatus {
        let repoPath = source.localRepositoryPath.map(PathFormatter.expandTilde)
        let repoExists = repoPath.map { fileManager.fileExists(atPath: $0) } ?? false
        let manifestPath = repoPath.map { URL(fileURLWithPath: $0).appending(path: "manifest.json").path }
        let manifestExists = manifestPath.map { fileManager.fileExists(atPath: $0) } ?? false
        let databasePath = PathFormatter.expandTilde(source.importedDatabasePath)
        let databaseExists = fileManager.fileExists(atPath: databasePath)
        let metadata = databaseExists ? self.importMetadata(databasePath: databasePath) : nil
        var issues: [String] = []

        if repoPath == nil, source.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append("missing local repository path or remote URL")
        }
        if let repoPath, repoExists == false {
            issues.append("local repository path does not exist: \(PathFormatter.displayString(repoPath))")
        }
        if source.importedDatabasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("missing imported database path")
        }
        if databaseExists, metadata == nil {
            issues.append("import metadata missing or unreadable")
        }

        return GitHubArchiveSourceStatus(
            id: source.id,
            name: source.name,
            enabled: source.enabled,
            format: source.format,
            localRepositoryPath: repoPath.map(PathFormatter.displayString),
            localRepositoryExists: repoExists,
            remoteURL: source.remoteURL,
            branch: source.branch,
            manifestPath: manifestPath.map(PathFormatter.displayString),
            manifestExists: manifestExists,
            importedDatabasePath: PathFormatter.displayString(databasePath),
            databaseExists: databaseExists,
            configValid: issues.isEmpty || (databaseExists && issues == ["import metadata missing or unreadable"]),
            readyForRead: databaseExists,
            issues: issues,
            lastImportAt: metadata?.lastImportAt,
            manifestGeneratedAt: metadata?.manifestGeneratedAt,
            importedTableCount: metadata?.tableCount,
            importedRowCount: metadata?.rowCount,
            databaseUserVersion: metadata?.userVersion
        )
    }

    public static func update(source: GitHubArchiveSource) throws -> GitHubArchiveUpdateResult {
        guard source.enabled else {
            throw GitHubArchiveStoreError.archiveDisabled(source.name)
        }

        var resolvedSource = source
        if resolvedSource.localRepositoryPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            guard resolvedSource.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw GitHubArchiveStoreError.missingSnapshotSource(resolvedSource.name)
            }

            resolvedSource.localRepositoryPath = self.defaultSnapshotRepositoryPath(name: resolvedSource.name)
        }

        guard let rawRepoPath = resolvedSource.localRepositoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawRepoPath.isEmpty == false
        else {
            throw GitHubArchiveStoreError.missingRepositoryPath(resolvedSource.name)
        }

        let repoPath = PathFormatter.expandTilde(rawRepoPath)
        try self.updateSnapshotRepository(source: resolvedSource, repoPath: repoPath)
        let databasePath = PathFormatter.expandTilde(resolvedSource.importedDatabasePath)
        let result = try GitHubArchiveImporter.importSnapshot(
            sourceName: resolvedSource.name,
            snapshotPath: repoPath,
            databasePath: databasePath
        )
        return GitHubArchiveUpdateResult(source: resolvedSource, importResult: result)
    }

    public static func defaultSnapshotRepositoryPath(name: String) -> String {
        let fileName = self.sanitizedArchiveName(name)
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "RepoBar", directoryHint: .isDirectory)
            .appending(path: "Archives", directoryHint: .isDirectory)
            .appending(path: "\(fileName)-snapshot", directoryHint: .isDirectory)
            .path

        return base ?? "~/Library/Application Support/RepoBar/Archives/\(fileName)-snapshot"
    }

    public static func sanitizedArchiveName(_ name: String) -> String {
        let safeName = name.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == Unicode.Scalar("-")
                || scalar == Unicode.Scalar("_")
                ? Character(scalar)
                : "-"
        }
        let fileName = String(safeName).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return fileName.isEmpty ? "archive" : fileName
    }

    public static func archiveDateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func importMetadata(databasePath: String) -> ImportMetadata? {
        do {
            let queue = try DatabaseQueue(path: databasePath)
            return try queue.read { db in
                let userVersion = try Int.fetchOne(db, sql: "PRAGMA user_version")
                guard try self.tableExists("repo_bar_archive_imports", db: db) else {
                    return ImportMetadata(userVersion: userVersion, lastImportAt: nil, manifestGeneratedAt: nil, tableCount: nil, rowCount: nil)
                }

                let row = try Row.fetchOne(
                    db,
                    sql: """
                    select imported_at, manifest_generated_at, table_count, row_count
                    from repo_bar_archive_imports
                    order by imported_at desc
                    limit 1
                    """
                )
                return ImportMetadata(
                    userVersion: userVersion,
                    lastImportAt: row.flatMap { ArchiveDateParser.date(from: $0["imported_at"] as String?) },
                    manifestGeneratedAt: row.flatMap { ArchiveDateParser.date(from: $0["manifest_generated_at"] as String?) },
                    tableCount: row?["table_count"],
                    rowCount: row?["row_count"]
                )
            }
        } catch {
            return nil
        }
    }

    private static func tableExists(_ table: String, db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "select exists(select 1 from sqlite_master where type = 'table' and name = ?)",
            arguments: [table]
        ) ?? false
    }

    private static func updateSnapshotRepository(source: GitHubArchiveSource, repoPath: String) throws {
        let remote = source.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard remote?.isEmpty == false else {
            return
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: URL(fileURLWithPath: repoPath).appending(path: ".git").path) == false {
            try fileManager.createDirectory(
                at: URL(fileURLWithPath: repoPath).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try self.runGit(arguments: ["clone", remote!, repoPath], workingDirectory: nil)
        }

        let branch = source.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : source.branch
        try self.runGit(arguments: ["fetch", "--prune", "origin"], workingDirectory: repoPath)
        try self.runGit(arguments: ["checkout", "-B", branch, "origin/\(branch)"], workingDirectory: repoPath)
        try self.runGit(arguments: ["pull", "--ff-only", "origin", branch], workingDirectory: repoPath)
    }

    private static func runGit(arguments: [String], workingDirectory: String?) throws {
        #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }
            process.standardOutput = Pipe()
            let error = Pipe()
            process.standardError = error
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let errorData = try error.fileHandleForReading.readToEnd() ?? Data()
                let message = (String(bytes: errorData, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw GitHubArchiveStoreError.gitFailed(message.isEmpty ? "git failed: \(arguments.joined(separator: " "))" : message)
            }

        #else
            throw GitHubArchiveStoreError.gitFailed("git is unavailable on this platform")
        #endif
    }
}

private struct ImportMetadata {
    let userVersion: Int?
    let lastImportAt: Date?
    let manifestGeneratedAt: Date?
    let tableCount: Int?
    let rowCount: Int?
}

private extension GitHubArchiveSettings {
    func githubArchivesSources(matching name: String) -> [GitHubArchiveSource] {
        self.sources.filter { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame || $0.id == name }
    }
}

enum ArchiveDateParser {
    static func date(from text: String?) -> Date? {
        guard let text else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return fractional.date(from: text) ?? plain.date(from: text)
    }
}
