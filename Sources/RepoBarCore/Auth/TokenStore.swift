import Foundation
import Logging
import Security

public struct OAuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date?

    public init(accessToken: String, refreshToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public struct OAuthClientCredentials: Codable, Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public enum TokenStoreError: Error {
    case saveFailed
    case loadFailed
}

public enum TokenStoreStorage: Sendable {
    case keychain
    case file(URL)
}

public struct TokenStore: Sendable {
    public static var shared: TokenStore {
        TokenStore()
    }

    private let service: String
    private let accessGroup: String?
    private let storage: TokenStoreStorage
    private let logger = RepoBarLogging.logger("token-store")

    public init(
        service: String = "com.steipete.repobar.auth",
        accessGroup: String? = nil,
        storage: TokenStoreStorage? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup ?? Self.defaultAccessGroup()
        self.storage = storage ?? Self.defaultStorage()
    }

    public func save(tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try self.save(data: data, account: "default")
    }

    public func load() throws -> OAuthTokens? {
        guard let data = try self.loadData(account: "default") else { return nil }

        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func save(clientCredentials: OAuthClientCredentials) throws {
        let data = try JSONEncoder().encode(clientCredentials)
        try self.save(data: data, account: "client")
    }

    public func loadClientCredentials() throws -> OAuthClientCredentials? {
        guard let data = try self.loadData(account: "client") else { return nil }

        return try JSONDecoder().decode(OAuthClientCredentials.self, from: data)
    }

    public func clear() {
        self.clear(account: "default")
        self.clear(account: "client")
        self.clearPAT()
    }

    public func clearAllCredentials() {
        self.clear()
        self.clearOpenAIAPIKey()
    }

    // MARK: - PAT Storage

    public func savePAT(_ token: String) throws {
        let data = Data(token.utf8)
        try self.save(data: data, account: "pat")
    }

    public func loadPAT() throws -> String? {
        guard let data = try self.loadData(account: "pat") else { return nil }

        return String(data: data, encoding: .utf8)
    }

    public func clearPAT() {
        self.clear(account: "pat")
    }

    // MARK: - OpenAI API Key Storage

    public func saveOpenAIAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            self.clearOpenAIAPIKey()
            return
        }

        try self.save(data: Data(trimmed.utf8), account: "openai-api-key")
    }

    public func loadOpenAIAPIKey() throws -> String? {
        guard let data = try self.loadData(account: "openai-api-key") else { return nil }

        let key = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    public func clearOpenAIAPIKey() {
        self.clear(account: "openai-api-key")
    }

    // MARK: - Account-Scoped Storage (Phase 1)

    public func save(tokens: OAuthTokens, accountID: String) throws {
        let data = try JSONEncoder().encode(tokens)
        try self.save(data: data, account: Self.accountKey(accountID, kind: .oauth))
        self.recordAccountInIndex(accountID)
    }

    public func loadTokens(accountID: String) throws -> OAuthTokens? {
        guard let data = try self.loadData(account: Self.accountKey(accountID, kind: .oauth)) else {
            return nil
        }

        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func save(clientCredentials: OAuthClientCredentials, accountID: String) throws {
        let data = try JSONEncoder().encode(clientCredentials)
        try self.save(data: data, account: Self.accountKey(accountID, kind: .client))
        self.recordAccountInIndex(accountID)
    }

    public func loadClientCredentials(accountID: String) throws -> OAuthClientCredentials? {
        guard let data = try self.loadData(account: Self.accountKey(accountID, kind: .client)) else {
            return nil
        }

        return try JSONDecoder().decode(OAuthClientCredentials.self, from: data)
    }

    public func savePAT(_ token: String, accountID: String) throws {
        let data = Data(token.utf8)
        try self.save(data: data, account: Self.accountKey(accountID, kind: .pat))
        self.recordAccountInIndex(accountID)
    }

    public func loadPAT(accountID: String) throws -> String? {
        guard let data = try self.loadData(account: Self.accountKey(accountID, kind: .pat)) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    public func clear(accountID: String) {
        for kind in AccountKeyKind.allCases {
            self.clear(account: Self.accountKey(accountID, kind: kind))
        }
        self.removeAccountFromIndex(accountID)
    }

    @discardableResult
    public func mirrorAccountCredentialsToLegacy(accountID: String, authMethod: AuthMethod) -> Bool {
        switch authMethod {
        case .oauth:
            guard let tokens = try? self.loadTokens(accountID: accountID) else {
                self.clear()
                return false
            }

            self.clear()
            try? self.save(tokens: tokens)
            if let credentials = try? self.loadClientCredentials(accountID: accountID) {
                try? self.save(clientCredentials: credentials)
            }
            return true
        case .pat:
            guard let pat = try? self.loadPAT(accountID: accountID) else {
                self.clear()
                return false
            }

            self.clear()
            try? self.savePAT(pat)
            return true
        }
    }

    public func allAccountIDs() throws -> [String] {
        var found = Set<String>()
        switch self.storage {
        case let .file(directory):
            let indexed = self.loadAccountIndex(directory: directory)
            for id in indexed {
                found.insert(id)
            }
            // Fallback: scan files for any account-scoped entries that aren't
            // represented in the index (e.g., pre-index entries on disk).
            // Skip scanned IDs whose sanitized form collides with an indexed ID
            // so that we never surface a mangled duplicate of an original ID.
            let sanitizedIndexed = Set(indexed.map { self.sanitizedFileComponent($0) })
            for id in self.scanFileAccountIDs(directory: directory) {
                if sanitizedIndexed.contains(self.sanitizedFileComponent(id)) { continue }
                found.insert(id)
            }
        case .keychain:
            for id in self.scanKeychainAccountIDs() {
                found.insert(id)
            }
        }
        return found.sorted()
    }
}

enum AccountKeyKind: String, CaseIterable {
    case oauth = "default"
    case client
    case pat
}

extension TokenStore {
    static let sharedAccessGroupSuffix = "com.steipete.repobar.shared"
    private static let storageModeInfoKey = "RepoBarTokenStore"
    private static let storageModeEnvKey = "REPOBAR_TOKEN_STORE"

    static func defaultAccessGroup() -> String? {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                  let entitlement = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil)
            else {
                return nil
            }

            if let groups = entitlement as? [String] {
                return groups.first(where: { $0.hasSuffix(Self.sharedAccessGroupSuffix) })
            }
            return nil
        #else
            if let group = Bundle.main.object(forInfoDictionaryKey: "RepoBarKeychainAccessGroup") as? String {
                if group.isEmpty == false {
                    return group
                }
            }
            return nil
        #endif
    }

    static func defaultStorage() -> TokenStoreStorage {
        let configured = ProcessInfo.processInfo.environment[Self.storageModeEnvKey]
            ?? Bundle.main.object(forInfoDictionaryKey: Self.storageModeInfoKey) as? String
        switch configured?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "file", "disk":
            return .file(Self.defaultFileDirectory())
        case "keychain":
            return .keychain
        default:
            #if DEBUG
                return .file(Self.defaultFileDirectory())
            #else
                return .keychain
            #endif
        }
    }

    static func defaultFileDirectory() -> URL {
        #if os(iOS)
            let fallback = FileManager.default.temporaryDirectory
        #else
            let fallback = FileManager.default.homeDirectoryForCurrentUser
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fallback
        return base
            .appendingPathComponent("RepoBar", isDirectory: true)
            .appendingPathComponent("DebugAuth", isDirectory: true)
    }
}

private extension TokenStore {
    func save(data: Data, account: String) throws {
        if case let .file(directory) = self.storage {
            try self.saveFile(data: data, account: account, directory: directory)
            return
        }

        let accessGroups = self.accessGroupsForOperation()
        var lastStatus: OSStatus = errSecSuccess
        for (index, group) in accessGroups.enumerated() {
            let query = self.baseQuery(account: account, accessGroup: group)
            let attributes: [CFString: Any] = [kSecValueData: data]
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            var status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            }
            if status == errSecSuccess { return }
            lastStatus = status
            let isFinalAttempt = index == accessGroups.count - 1
            if isFinalAttempt || self.shouldRetryWithoutAccessGroup(status: status, accessGroup: group) == false {
                break
            }
        }
        self.logFailure("save", status: lastStatus)
        throw TokenStoreError.saveFailed
    }

    func loadData(account: String) throws -> Data? {
        if case let .file(directory) = self.storage {
            return try self.loadFile(account: account, directory: directory)
        }

        let accessGroups = self.accessGroupsForOperation()
        var lastStatus: OSStatus = errSecSuccess
        for (index, group) in accessGroups.enumerated() {
            var query = self.baseQuery(account: account, accessGroup: group)
            query[kSecReturnData] = true
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound {
                if index == accessGroups.count - 1 { return nil }
                continue
            }
            if status == errSecSuccess, let data = item as? Data { return data }
            lastStatus = status
            let isFinalAttempt = index == accessGroups.count - 1
            if isFinalAttempt || self.shouldRetryWithoutAccessGroup(status: status, accessGroup: group) == false {
                break
            }
        }
        self.logFailure("load", status: lastStatus)
        throw TokenStoreError.loadFailed
    }

    func clear(account: String) {
        if case let .file(directory) = self.storage {
            try? FileManager.default.removeItem(at: self.fileURL(account: account, directory: directory))
            try? FileManager.default.removeItem(at: self.legacyFileURL(account: account, directory: directory))
            return
        }

        let accessGroups = self.accessGroupsForOperation()
        for group in accessGroups {
            let query = self.baseQuery(account: account, accessGroup: group)
            SecItemDelete(query as CFDictionary)
        }
    }

    func accessGroupsForOperation() -> [String?] {
        guard let accessGroup else { return [nil] }

        return [accessGroup, nil]
    }

    func baseQuery(account: String, accessGroup: String?) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        return query
    }

    func shouldRetryWithoutAccessGroup(status: OSStatus, accessGroup: String?) -> Bool {
        guard accessGroup != nil else { return false }

        switch status {
        case errSecMissingEntitlement, errSecInteractionNotAllowed:
            return true
        default:
            return false
        }
    }

    func logFailure(_ action: String, status: OSStatus) {
        guard status != errSecSuccess else { return }

        let statusMessage = SecCopyErrorMessageString(status, nil) as String?
        if let statusMessage {
            self.logger.error("Keychain \(action) failed: \(statusMessage)")
        } else {
            self.logger.error("Keychain \(action) failed: OSStatus \(status)")
        }
    }

    func saveFile(data: Data, account: String, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = self.fileURL(account: account, directory: directory)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func loadFile(account: String, directory: URL) throws -> Data? {
        let url = self.fileURL(account: account, directory: directory)
        if FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }

        let legacyURL = self.legacyFileURL(account: account, directory: directory)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }

        return try Data(contentsOf: legacyURL)
    }

    func fileURL(account: String, directory: URL) -> URL {
        let serviceName = self.encodedFileComponent(self.service)
        let accountName = self.encodedFileComponent(account)
        return directory.appendingPathComponent("\(serviceName)-\(accountName).json", isDirectory: false)
    }

    func legacyFileURL(account: String, directory: URL) -> URL {
        let serviceName = self.sanitizedFileComponent(self.service)
        let accountName = self.sanitizedFileComponent(account)
        return directory.appendingPathComponent("\(serviceName)-\(accountName).json", isDirectory: false)
    }

    func encodedFileComponent(_ value: String) -> String {
        let hex = value.utf8.map { String(format: "%02x", $0) }.joined()
        return "v2-\(hex)"
    }

    func decodedFileComponent(_ value: String) -> String? {
        guard value.hasPrefix("v2-") else { return nil }

        let hex = String(value.dropFirst(3))
        guard hex.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }

            bytes.append(byte)
            index = next
        }
        return String(data: Data(bytes), encoding: .utf8)
    }

    func sanitizedFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(scalars)
        return result.isEmpty ? "value" : result
    }

    static func accountKey(_ accountID: String, kind: AccountKeyKind) -> String {
        "\(accountID):\(kind.rawValue)"
    }

    func accountIndexURL(directory: URL) -> URL {
        let serviceName = self.encodedFileComponent(self.service)
        return directory.appendingPathComponent("\(serviceName)-accounts-index.json", isDirectory: false)
    }

    func legacyAccountIndexURL(directory: URL) -> URL {
        let serviceName = self.sanitizedFileComponent(self.service)
        return directory.appendingPathComponent("\(serviceName)-accounts-index.json", isDirectory: false)
    }

    func loadAccountIndex(directory: URL) -> Set<String> {
        for url in [self.accountIndexURL(directory: directory), self.legacyAccountIndexURL(directory: directory)] {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let ids = try? JSONDecoder().decode([String].self, from: data)
            else {
                continue
            }

            return Set(ids)
        }

        return []
    }

    func writeAccountIndex(_ ids: Set<String>, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = self.accountIndexURL(directory: directory)
        let data = try JSONEncoder().encode(ids.sorted())
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func recordAccountInIndex(_ accountID: String) {
        guard case let .file(directory) = self.storage else { return }

        var ids = self.loadAccountIndex(directory: directory)
        guard ids.insert(accountID).inserted else { return }

        do {
            try self.writeAccountIndex(ids, directory: directory)
        } catch {
            self.logger.error("Failed to update account index: \(error.localizedDescription)")
        }
    }

    func removeAccountFromIndex(_ accountID: String) {
        guard case let .file(directory) = self.storage else { return }

        var ids = self.loadAccountIndex(directory: directory)
        guard ids.remove(accountID) != nil else { return }

        do {
            try self.writeAccountIndex(ids, directory: directory)
        } catch {
            self.logger.error("Failed to update account index: \(error.localizedDescription)")
        }
    }

    func scanFileAccountIDs(directory: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }

        let servicePrefixes = [
            "\(self.encodedFileComponent(self.service))-",
            "\(self.sanitizedFileComponent(self.service))-"
        ]
        let suffix = ".json"
        var result: [String] = []
        for name in entries {
            guard name.hasSuffix(suffix),
                  let servicePrefix = servicePrefixes.first(where: { name.hasPrefix($0) })
            else {
                continue
            }

            let middle = String(name.dropFirst(servicePrefix.count).dropLast(suffix.count))
            if let decoded = self.decodedFileComponent(middle) {
                if decoded == "default" || decoded == "client" || decoded == "pat" { continue }
                for kind in AccountKeyKind.allCases {
                    let trailing = ":\(kind.rawValue)"
                    if decoded.hasSuffix(trailing), decoded.count > trailing.count {
                        result.append(String(decoded.dropLast(trailing.count)))
                        break
                    }
                }
                continue
            }

            // Skip legacy fixed-key entries.
            if middle == "default" || middle == "client" || middle == "pat" { continue }
            for kind in AccountKeyKind.allCases {
                // The colon separator becomes `-` after sanitization.
                let trailing = "-\(kind.rawValue)"
                if middle.hasSuffix(trailing), middle.count > trailing.count {
                    let id = String(middle.dropLast(trailing.count))
                    result.append(id)
                    break
                }
            }
        }
        return result
    }

    func scanKeychainAccountIDs() -> [String] {
        let accessGroups = self.accessGroupsForOperation()
        let accountKey = kSecAttrAccount as String
        var result: [String] = []
        for group in accessGroups {
            var query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: self.service,
                kSecReturnAttributes: true,
                kSecMatchLimit: kSecMatchLimitAll
            ]
            if let group {
                query[kSecAttrAccessGroup] = group
            }
            var items: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &items)
            guard status == errSecSuccess else { continue }

            let entries: [[String: Any]] = if let many = items as? [[String: Any]] {
                many
            } else if let one = items as? [String: Any] {
                [one]
            } else {
                []
            }
            for entry in entries {
                guard let account = entry[accountKey] as? String else { continue }

                if account == "default" || account == "client" || account == "pat" { continue }
                for kind in AccountKeyKind.allCases {
                    let trailing = ":\(kind.rawValue)"
                    if account.hasSuffix(trailing), account.count > trailing.count {
                        result.append(String(account.dropLast(trailing.count)))
                        break
                    }
                }
            }
        }
        return result
    }
}
