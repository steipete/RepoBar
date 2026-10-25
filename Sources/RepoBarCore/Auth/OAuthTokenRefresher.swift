import Foundation

public struct OAuthTokenRefresher: Sendable {
    private static let refreshGate = OAuthRefreshGate()

    private let tokenStore: TokenStore
    private let load: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        tokenStore: TokenStore = .shared,
        load: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.tokenStore = tokenStore
        self.load = load
    }

    public func refreshIfNeeded(host: URL, force: Bool = false) async throws -> OAuthTokens? {
        try await self.refreshIfNeeded(host: host, force: force, accountID: nil)
    }

    public func refreshIfNeeded(host: URL, force: Bool = false, accountID: String?) async throws -> OAuthTokens? {
        guard let tokens = try self.loadTokens(accountID: accountID) else { return nil }

        if tokens.refreshToken.isEmpty {
            return tokens
        }
        if force == false, let expiry = tokens.expiresAt, expiry > Date().addingTimeInterval(60) {
            return tokens
        }

        let key = OAuthRefreshKey(
            tokenStore: self.tokenStore.oauthRefreshCoordinationID,
            host: host.absoluteString,
            accountID: accountID
        )
        return try await Self.refreshGate.run(key: key) {
            try await self.performRefreshIfNeeded(host: host, force: force, accountID: accountID)
        }
    }

    private func performRefreshIfNeeded(host: URL, force: Bool, accountID: String?) async throws -> OAuthTokens? {
        guard var tokens = try self.loadTokens(accountID: accountID) else { return nil }

        if tokens.refreshToken.isEmpty {
            return tokens
        }
        if force == false, let expiry = tokens.expiresAt, expiry > Date().addingTimeInterval(60) {
            return tokens
        }

        let storedCredentials = if let accountID {
            try self.tokenStore.loadClientCredentials(accountID: accountID)
        } else {
            try self.tokenStore.loadClientCredentials()
        }
        let credentials = storedCredentials
            ?? OAuthClientCredentials(clientID: RepoBarAuthDefaults.clientID, clientSecret: RepoBarAuthDefaults.clientSecret)

        let base = host.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let refreshURL = URL(string: "\(base)/login/oauth/access_token")!
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthFormEncoder.encode([
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken
        ])

        let (data, responseAny) = try await self.load(request)
        guard let response = responseAny as? HTTPURLResponse else {
            throw GitHubAPIError.badStatus(code: -1, message: "GitHub returned an unexpected response.")
        }
        guard response.statusCode == 200 else {
            let detail = Self.refreshErrorDetail(from: data)
            let message = Self.refreshErrorMessage(status: response.statusCode, detail: detail)
            throw GitHubAPIError.badStatus(code: response.statusCode, message: message)
        }

        do {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            let expires = Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
            tokens = OAuthTokens(
                accessToken: decoded.accessToken,
                refreshToken: decoded.refreshToken ?? tokens.refreshToken,
                expiresAt: expires
            )
            if let accountID {
                try self.tokenStore.save(tokens: tokens, accountID: accountID)
            } else {
                try self.tokenStore.save(tokens: tokens)
            }
            return tokens
        } catch {
            let detail = Self.refreshErrorDetail(from: data)
            let message = Self.refreshDecodeFailureMessage(detail: detail)
            throw GitHubAPIError.badStatus(code: response.statusCode, message: message)
        }
    }

    private func loadTokens(accountID: String?) throws -> OAuthTokens? {
        if let accountID {
            return try self.tokenStore.loadTokens(accountID: accountID)
        }
        return try? self.tokenStore.load()
    }
}

private struct OAuthRefreshKey: Hashable {
    let tokenStore: String
    let host: String
    let accountID: String?
}

private actor OAuthRefreshGate {
    private struct Entry {
        let id: UUID
        let task: Task<OAuthTokens?, Error>
    }

    private var entries: [OAuthRefreshKey: Entry] = [:]

    func run(
        key: OAuthRefreshKey,
        operation: @escaping @Sendable () async throws -> OAuthTokens?
    ) async throws -> OAuthTokens? {
        if let entry = self.entries[key] {
            return try await entry.task.value
        }

        let id = UUID()
        let task = Task { try await operation() }
        self.entries[key] = Entry(id: id, task: task)
        do {
            let tokens = try await task.value
            self.removeEntry(key: key, id: id)
            return tokens
        } catch {
            self.removeEntry(key: key, id: id)
            throw error
        }
    }

    private func removeEntry(key: OAuthRefreshKey, id: UUID) {
        guard self.entries[key]?.id == id else { return }

        self.entries[key] = nil
    }
}

private extension OAuthTokenRefresher {
    static func refreshErrorDetail(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            let error = decoded.errorDescription ?? decoded.message ?? decoded.error
            return error.flatMap(Self.cleaned)
        }
        if let text = String(data: data, encoding: .utf8) {
            return self.cleaned(text)
        }
        return nil
    }

    static func refreshErrorMessage(status: Int, detail: String?) -> String {
        if let detail, detail.isEmpty == false {
            return "Authentication refresh failed (HTTP \(status)). \(detail) Please sign in again."
        }
        return "Authentication refresh failed (HTTP \(status)). Please sign in again."
    }

    static func refreshDecodeFailureMessage(detail: String?) -> String {
        if let detail, detail.isEmpty == false {
            return "Authentication refresh failed. \(detail) Please sign in again."
        }
        return "Authentication refresh failed. Please sign in again."
    }

    static func cleaned(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let expiresIn: Int?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case message
    }
}
