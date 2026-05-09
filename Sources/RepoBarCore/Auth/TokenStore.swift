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
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        return try Data(contentsOf: url)
    }

    func fileURL(account: String, directory: URL) -> URL {
        let serviceName = self.sanitizedFileComponent(self.service)
        let accountName = self.sanitizedFileComponent(account)
        return directory.appendingPathComponent("\(serviceName)-\(accountName).json", isDirectory: false)
    }

    func sanitizedFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(scalars)
        return result.isEmpty ? "value" : result
    }
}
