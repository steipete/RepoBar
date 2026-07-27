import Foundation
@preconcurrency import GRDB
import zlib

public struct GitHubArchiveImportResult: Codable, Equatable, Sendable {
    public let sourceName: String
    public let snapshotPath: String
    public let databasePath: String
    public let manifestVersion: Int
    public let generatedAt: Date?
    public let importedAt: Date
    public let tables: [GitHubArchiveImportedTable]
    public let totalRows: Int
}

public struct GitHubArchiveImportedTable: Codable, Equatable, Sendable {
    public let name: String
    public let files: [String]
    public let columns: [String]
    public let declaredRows: Int
    public let importedRows: Int
}

public enum GitHubArchiveImportError: Error, LocalizedError {
    case missingManifest(String)
    case invalidRelativePath(String)
    case invalidIdentifier(String)
    case missingFile(String)
    case gzipFailed(String)
    case rowIsNotObject(String)
    case invalidUTF8(String)

    public var errorDescription: String? {
        switch self {
        case let .missingManifest(path): "Archive manifest not found: \(path)"
        case let .invalidRelativePath(path): "Archive manifest contains invalid relative path: \(path)"
        case let .invalidIdentifier(name): "Archive manifest contains invalid table or column name: \(name)"
        case let .missingFile(path): "Archive manifest references missing file: \(path)"
        case let .gzipFailed(path): "Unable to decompress snapshot file: \(path)"
        case let .rowIsNotObject(path): "Snapshot file contains a JSON row that is not an object: \(path)"
        case let .invalidUTF8(path): "Snapshot file is not valid UTF-8: \(path)"
        }
    }
}

public enum GitHubArchiveImporter {
    public static func importSnapshot(
        sourceName: String,
        snapshotPath: String,
        databasePath: String,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> GitHubArchiveImportResult {
        let rootURL = URL(fileURLWithPath: snapshotPath)
        let manifestURL = rootURL.appending(path: "manifest.json", directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw GitHubArchiveImportError.missingManifest(manifestURL.path)
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder.archiveManifest.decode(ArchiveManifest.self, from: manifestData)
        try self.validate(manifest: manifest)

        let databaseURL = URL(fileURLWithPath: databasePath)
        let parent = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let tempURL = parent.appending(path: "\(databaseURL.lastPathComponent).importing-\(UUID().uuidString)", directoryHint: .notDirectory)
        try? fileManager.removeItem(at: tempURL)
        defer {
            try? fileManager.removeItem(at: tempURL)
            try? fileManager.removeItem(atPath: tempURL.path + "-wal")
            try? fileManager.removeItem(atPath: tempURL.path + "-shm")
        }

        let importedTables = try self.writeDatabase(
            tempURL: tempURL,
            manifest: manifest,
            metadata: ImportMetadata(sourceName: sourceName, manifestData: manifestData, importedAt: now),
            context: ImportContext(rootURL: rootURL, fileManager: fileManager)
        )

        try self.replaceDatabase(at: databaseURL, with: tempURL, fileManager: fileManager)
        return GitHubArchiveImportResult(
            sourceName: sourceName,
            snapshotPath: snapshotPath,
            databasePath: databasePath,
            manifestVersion: manifest.version,
            generatedAt: manifest.generatedAt,
            importedAt: now,
            tables: importedTables,
            totalRows: importedTables.reduce(0) { $0 + $1.importedRows }
        )
    }

    private static func writeDatabase(
        tempURL: URL,
        manifest: ArchiveManifest,
        metadata: ImportMetadata,
        context: ImportContext
    ) throws -> [GitHubArchiveImportedTable] {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
        }
        let queue = try DatabaseQueue(path: tempURL.path, configuration: configuration)
        var importedTables: [GitHubArchiveImportedTable] = []

        try queue.write { db in
            try db.execute(sql: "PRAGMA user_version = \(max(1, manifest.version))")
            try self.createMetadataTables(db)
            for table in manifest.tables {
                let tableResult = try self.importTable(
                    table,
                    db: db,
                    context: context
                )
                importedTables.append(tableResult)
            }
            try self.ensureSyncState(db: db)
            try self.writeImportMetadata(
                db: db,
                metadata: metadata,
                manifest: manifest,
                tables: importedTables
            )
        }

        return importedTables
    }

    private static func createMetadataTables(_ db: Database) throws {
        try db.execute(sql: """
        create table if not exists repo_bar_archive_imports(
            source_name text not null,
            manifest_version integer not null,
            manifest_generated_at text,
            imported_at text not null,
            table_count integer not null,
            row_count integer not null,
            manifest_json text not null
        )
        """)
    }

    private static func importTable(
        _ table: ArchiveTableManifest,
        db: Database,
        context: ImportContext
    ) throws -> GitHubArchiveImportedTable {
        try self.dropAndCreate(table: table, db: db)
        var importedRows = 0

        for relativePath in table.allFiles {
            let fileURL = try self.fileURL(
                relativePath: relativePath,
                rootURL: context.rootURL,
                fileManager: context.fileManager
            )
            let data = try self.readSnapshotFile(fileURL)
            guard let text = String(bytes: data, encoding: .utf8) else {
                throw GitHubArchiveImportError.invalidUTF8(relativePath)
            }

            for line in text.split(whereSeparator: \.isNewline) {
                let rowData = Data(line.utf8)
                let object = try self.decodeRow(rowData, filePath: relativePath)
                try self.insert(object: object, into: table, db: db)
                importedRows += 1
            }
        }

        return GitHubArchiveImportedTable(
            name: table.name,
            files: table.allFiles,
            columns: table.columns,
            declaredRows: table.rows,
            importedRows: importedRows
        )
    }

    private static func dropAndCreate(table: ArchiveTableManifest, db: Database) throws {
        let tableName = self.quoted(table.name)
        try db.execute(sql: "drop table if exists \(tableName)")
        let columnSQL = table.columns
            .map { "\(self.quoted($0)) text" }
            .joined(separator: ", ")
        try db.execute(sql: "create table \(tableName)(\(columnSQL), \(self.quoted("_repobar_raw_json")) text not null)")
    }

    private static func insert(object: [String: Any], into table: ArchiveTableManifest, db: Database) throws {
        var values = StatementArguments()
        for column in table.columns {
            _ = values.append(contentsOf: [self.sqliteValue(object[column])])
        }
        let rawData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        _ = values.append(contentsOf: [self.utf8String(from: rawData)])

        let names = (table.columns + ["_repobar_raw_json"]).map(self.quoted).joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: table.columns.count + 1).joined(separator: ", ")
        try db.execute(
            sql: "insert into \(self.quoted(table.name))(\(names)) values(\(placeholders))",
            arguments: values
        )
    }

    private static func ensureSyncState(db: Database) throws {
        try db.execute(sql: """
        create table if not exists sync_state(
            scope text primary key,
            cursor text,
            updated_at text not null
        )
        """)
    }

    private static func writeImportMetadata(
        db: Database,
        metadata: ImportMetadata,
        manifest: ArchiveManifest,
        tables: [GitHubArchiveImportedTable]
    ) throws {
        let importedAtText = ArchiveDateCoding.string(from: metadata.importedAt)
        let generatedAtText = manifest.generatedAt.map { ArchiveDateCoding.string(from: $0) }
        let rowCount = tables.reduce(0) { $0 + $1.importedRows }
        try db.execute(
            sql: """
            insert into repo_bar_archive_imports(
                source_name, manifest_version, manifest_generated_at, imported_at,
                table_count, row_count, manifest_json
            ) values (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                metadata.sourceName,
                manifest.version,
                generatedAtText,
                importedAtText,
                tables.count,
                rowCount,
                self.utf8String(from: metadata.manifestData)
            ]
        )
        try db.execute(
            sql: """
            insert into sync_state(scope, cursor, updated_at)
            values ('repobar:last_import', ?, ?)
            on conflict(scope) do update set
                cursor = excluded.cursor,
                updated_at = excluded.updated_at
            """,
            arguments: [generatedAtText ?? importedAtText, importedAtText]
        )
    }

    private static func replaceDatabase(at databaseURL: URL, with tempURL: URL, fileManager: FileManager) throws {
        try? fileManager.removeItem(at: databaseURL)
        try? fileManager.removeItem(atPath: databaseURL.path + "-wal")
        try? fileManager.removeItem(atPath: databaseURL.path + "-shm")
        try fileManager.moveItem(at: tempURL, to: databaseURL)
    }

    private static func validate(manifest: ArchiveManifest) throws {
        for table in manifest.tables {
            try self.validateIdentifier(table.name)
            for column in table.columns {
                try self.validateIdentifier(column)
            }
            if table.columns.contains("_repobar_raw_json") {
                throw GitHubArchiveImportError.invalidIdentifier("_repobar_raw_json")
            }
            for file in table.allFiles {
                try self.validateRelativePath(file)
            }
        }
    }

    private static func validateIdentifier(_ name: String) throws {
        guard let first = name.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first)
        else {
            throw GitHubArchiveImportError.invalidIdentifier(name)
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw GitHubArchiveImportError.invalidIdentifier(name)
        }
    }

    private static func validateRelativePath(_ path: String) throws {
        if path.hasPrefix("/") || path.split(separator: "/").contains("..") {
            throw GitHubArchiveImportError.invalidRelativePath(path)
        }
    }

    private static func fileURL(relativePath: String, rootURL: URL, fileManager: FileManager) throws -> URL {
        let url = rootURL.appending(path: relativePath, directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: url.path) else {
            throw GitHubArchiveImportError.missingFile(relativePath)
        }

        return url
    }

    private static func readSnapshotFile(_ url: URL) throws -> Data {
        if url.pathExtension == "gz" {
            return try self.gunzippedData(from: url)
        }
        return try Data(contentsOf: url)
    }

    private static func gunzippedData(from url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            16 + MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw GitHubArchiveImportError.gzipFailed(url.path)
        }

        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 64 * 1024
        let result = data.withUnsafeBytes { inputBuffer in
            guard let inputBase = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBase)
            stream.avail_in = uInt(data.count)

            while true {
                var chunk = Data(count: chunkSize)
                let status = chunk.withUnsafeMutableBytes { outputBuffer in
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                let written = chunkSize - Int(stream.avail_out)
                output.append(chunk.prefix(written))

                if status == Z_STREAM_END {
                    return status
                }
                guard status == Z_OK else {
                    return status
                }
            }
        }

        guard result == Z_STREAM_END else {
            throw GitHubArchiveImportError.gzipFailed(url.path)
        }

        return output
    }

    private static func decodeRow(_ data: Data, filePath: String) throws -> [String: Any] {
        let row = try JSONSerialization.jsonObject(with: data)
        guard let object = row as? [String: Any] else {
            throw GitHubArchiveImportError.rowIsNotObject(filePath)
        }

        return object
    }

    private static func sqliteValue(_ value: Any?) -> DatabaseValueConvertible? {
        switch value {
        case nil, is NSNull:
            return nil
        case let bool as Bool:
            return bool ? "1" : "0"
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let value?:
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            else { return String(describing: value) }

            return self.utf8String(from: data)
        }
    }

    private static func utf8String(from data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }

    private static func quoted(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct ImportContext {
    let rootURL: URL
    let fileManager: FileManager
}

private struct ImportMetadata {
    let sourceName: String
    let manifestData: Data
    let importedAt: Date
}

private struct ArchiveManifest: Decodable {
    let version: Int
    let generatedAt: Date?
    let tables: [ArchiveTableManifest]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case tables
    }
}

private struct ArchiveTableManifest: Decodable {
    let name: String
    let file: String?
    let files: [String]?
    let columns: [String]
    let rows: Int

    var allFiles: [String] {
        if let files, files.isEmpty == false {
            return files
        }
        return self.file.map { [$0] } ?? []
    }
}

private extension JSONDecoder {
    static var archiveManifest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ArchiveDateCoding.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }

            return date
        }
        return decoder
    }
}

private enum ArchiveDateCoding {
    static func string(from date: Date) -> String {
        self.fractionalFormatter().string(from: date)
    }

    static func date(from text: String) -> Date? {
        self.fractionalFormatter().date(from: text) ?? self.plainFormatter().date(from: text)
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func plainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
