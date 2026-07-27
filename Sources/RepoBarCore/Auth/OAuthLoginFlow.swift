import Foundation

@MainActor
protocol LoopbackServing: AnyObject {
    func start() throws -> URL
    func waitForCallback(timeout: TimeInterval) async throws -> (code: String, state: String)
    func stop()
}

extension LoopbackServer: LoopbackServing {}

@MainActor
public struct OAuthLoginFlow {
    private let tokenStore: TokenStore
    private let openURL: @Sendable (URL) throws -> Void
    private let dataProvider: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let makeLoopbackServer: (Int) -> LoopbackServing
    private let stateProvider: @Sendable () -> String

    public init(
        tokenStore: TokenStore = .shared,
        openURL: @escaping @Sendable (URL) throws -> Void,
        dataProvider: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.init(
            tokenStore: tokenStore,
            openURL: openURL,
            dataProvider: dataProvider,
            makeLoopbackServer: { port in LoopbackServer(port: port) },
            stateProvider: { UUID().uuidString }
        )
    }

    init(
        tokenStore: TokenStore,
        openURL: @escaping @Sendable (URL) throws -> Void,
        dataProvider: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
        makeLoopbackServer: @escaping (Int) -> LoopbackServing,
        stateProvider: @escaping @Sendable () -> String
    ) {
        self.tokenStore = tokenStore
        self.openURL = openURL
        self.dataProvider = dataProvider
        self.makeLoopbackServer = makeLoopbackServer
        self.stateProvider = stateProvider
    }

    public func login(
        clientID: String,
        clientSecret: String,
        host: URL,
        loopbackPort: Int,
        scope: String? = nil,
        timeout: TimeInterval = 180
    ) async throws -> OAuthTokens {
        let normalizedHost = try Self.normalizeHost(host)
        let authBase = normalizedHost.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authEndpoint = URL(string: "\(authBase)/login/oauth/authorize")!
        let tokenEndpoint = URL(string: "\(authBase)/login/oauth/access_token")!

        let pkce = PKCE.generate()
        let state = self.stateProvider()

        let server = self.makeLoopbackServer(loopbackPort)
        let redirectURL = try server.start()
        defer { server.stop() }

        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if let scope, scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            queryItems.append(URLQueryItem(name: "scope", value: scope))
        }
        components.queryItems = queryItems
        guard let authorizeURL = components.url else { throw URLError(.badURL) }

        try self.openURL(authorizeURL)

        let result = try await server.waitForCallback(timeout: timeout)
        guard result.state == state else { throw URLError(.badServerResponse) }

        var tokenRequest = URLRequest(url: tokenEndpoint)
        tokenRequest.httpMethod = "POST"
        tokenRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        tokenRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = OAuthFormEncoder.encode([
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": result.code,
            "redirect_uri": redirectURL.absoluteString,
            "grant_type": "authorization_code",
            "code_verifier": pkce.verifier
        ])

        let (data, response) = try await self.dataProvider(tokenRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let tokens = OAuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
        )
        try self.tokenStore.save(tokens: tokens)
        try self.tokenStore.save(clientCredentials: OAuthClientCredentials(clientID: clientID, clientSecret: clientSecret))
        return tokens
    }

    public static func normalizeHost(_ host: URL) throws -> URL {
        guard var components = URLComponents(url: host, resolvingAgainstBaseURL: false) else {
            throw GitHubAPIError.invalidHost
        }

        if components.scheme == nil {
            components.scheme = "https"
        }
        guard components.scheme?.lowercased() == "https", components.host != nil else {
            throw GitHubAPIError.invalidHost
        }

        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let cleaned = components.url else { throw GitHubAPIError.invalidHost }

        return cleaned
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
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
