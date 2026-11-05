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
    private let sleep: @Sendable (Duration) async throws -> Void

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
        stateProvider: @escaping @Sendable () -> String,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.tokenStore = tokenStore
        self.openURL = openURL
        self.dataProvider = dataProvider
        self.makeLoopbackServer = makeLoopbackServer
        self.stateProvider = stateProvider
        self.sleep = sleep
    }

    public func login(
        clientID: String,
        clientSecret: String,
        host: URL,
        loopbackPort: Int,
        scope: String? = nil,
        timeout: TimeInterval = 180,
        devicePrompt: ((String, URL) -> Void)? = nil
    ) async throws -> OAuthTokens {
        let normalizedHost = try Self.normalizeHost(host)
        if clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try await self.loginWithDeviceCode(
                clientID: clientID,
                host: normalizedHost,
                timeout: timeout,
                devicePrompt: devicePrompt
            )
        }
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

    private func loginWithDeviceCode(
        clientID: String,
        host: URL,
        timeout: TimeInterval,
        devicePrompt: ((String, URL) -> Void)?
    ) async throws -> OAuthTokens {
        let authBase = host.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard
            let deviceEndpoint = URL(string: "\(authBase)/login/device/code"),
            let tokenEndpoint = URL(string: "\(authBase)/login/oauth/access_token")
        else {
            throw URLError(.badURL)
        }

        let (deviceData, deviceStatus) = try await self.oauthPost(
            url: deviceEndpoint,
            fields: ["client_id": clientID]
        )
        if let failure = Self.oauthError(in: deviceData) {
            throw GitHubAPIError.badStatus(code: deviceStatus, message: failure.description)
        }
        guard deviceStatus == 200 else {
            throw GitHubAPIError.badStatus(code: deviceStatus, message: "GitHub refused device sign-in.")
        }

        let device = try JSONDecoder().decode(DeviceCodeBody.self, from: deviceData)
        guard let verificationURL = URL(string: device.verificationURI) else {
            throw URLError(.badURL)
        }

        devicePrompt?(device.userCode, verificationURL)
        try self.openURL(verificationURL)

        let deadline = Date().addingTimeInterval(timeout)
        var interval = max(device.interval, 0)
        while Date() < deadline {
            if interval > 0 {
                try await self.sleep(.seconds(interval))
            }
            let (tokenData, tokenStatus) = try await self.oauthPost(
                url: tokenEndpoint,
                fields: [
                    "client_id": clientID,
                    "device_code": device.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ]
            )
            if let failure = Self.oauthError(in: tokenData) {
                if failure.name == "authorization_pending" {
                    if interval == 0 {
                        interval = 1
                    }
                    continue
                }
                if failure.name == "slow_down" {
                    interval += 5
                    continue
                }
                throw GitHubAPIError.badStatus(code: tokenStatus, message: failure.description)
            }
            guard tokenStatus == 200 else {
                throw GitHubAPIError.badStatus(
                    code: tokenStatus,
                    message: "GitHub refused the device sign-in."
                )
            }

            let decoded = try JSONDecoder().decode(TokenResponse.self, from: tokenData)
            let expiresAt = decoded.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            let tokens = OAuthTokens(
                accessToken: decoded.accessToken,
                refreshToken: decoded.refreshToken ?? "",
                expiresAt: expiresAt
            )
            try self.tokenStore.save(tokens: tokens)
            return tokens
        }
        throw GitHubAPIError.badStatus(code: 0, message: "GitHub device sign-in timed out.")
    }

    private func oauthPost(url: URL, fields: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthFormEncoder.encode(fields)
        let (data, response) = try await self.dataProvider(request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError.badStatus(code: -1, message: "GitHub returned an unexpected response.")
        }

        return (data, http.statusCode)
    }

    private static func oauthError(in data: Data) -> (name: String, description: String)? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = object["error"] as? String
        else {
            return nil
        }

        let description = object["error_description"] as? String ?? name
        return (name, description)
    }
}

private struct DeviceCodeBody: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
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
