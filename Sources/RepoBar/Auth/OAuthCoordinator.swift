import AppKit
import Foundation
import OSLog

/// Handles GitHub App OAuth using browser + loopback, PKCE, and refresh tokens.
@MainActor
final class OAuthCoordinator {
    private let tokenStore = TokenStore()
    private let logger = Logger(subsystem: "com.steipete.repobar", category: "oauth")
    private var lastHost: URL = .init(string: "https://github.com")!

    func login(clientID: String, clientSecret: String, pemPath: String, host: URL, loopbackPort: Int) async throws {
        let normalizedHost = try normalize(host: host)
        if !pemPath.isEmpty {
            let exists = FileManager.default.fileExists(atPath: pemPath)
            guard exists else { throw GitHubAPIError.invalidPEM }
            let pem = try String(contentsOfFile: pemPath, encoding: .utf8)
            let appJWT = try? JWTSigner.sign(appID: "2344358", pemString: pem)
            await DiagnosticsLogger.shared.message("Using PEM at \(pemPath); JWT generated: \(appJWT != nil)")
        } else {
            await DiagnosticsLogger.shared.message("No PEM provided; continuing with client secret only.")
        }
        self.lastHost = normalizedHost
        let authBase = normalizedHost.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authEndpoint = URL(string: "\(authBase)/login/oauth/authorize")!
        let tokenEndpoint = URL(string: "\(authBase)/login/oauth/access_token")!

        let pkce = PKCE.generate()
        let state = UUID().uuidString

        let server = LoopbackServer(port: loopbackPort)
        let redirectURL = try server.start()

        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "repo read:org"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authorizeURL = components.url else { throw URLError(.badURL) }
        NSWorkspace.shared.open(authorizeURL)

        let result = try await server.waitForCallback(timeout: 180)

        guard result.state == state else { throw URLError(.badServerResponse) }

        var tokenRequest = URLRequest(url: tokenEndpoint)
        tokenRequest.httpMethod = "POST"
        tokenRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        tokenRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = Self.formUrlEncoded([
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": result.code,
            "redirect_uri": redirectURL.absoluteString,
            "grant_type": "authorization_code",
            "code_verifier": pkce.verifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: tokenRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            self.logger.error("Token exchange failed")
            await DiagnosticsLogger.shared
                .message("Token exchange failed status=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let tokens = OAuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600)))
        try self.tokenStore.save(tokens: tokens)
        await DiagnosticsLogger.shared.message("Login succeeded; tokens stored.")
        server.stop()
    }

    func logout() async {
        self.tokenStore.clear()
    }

    func loadTokens() -> OAuthTokens? {
        try? self.tokenStore.load()
    }

    func refreshIfNeeded() async throws -> OAuthTokens? {
        guard var tokens = try tokenStore.load() else { return nil }
        if let expiry = tokens.expiresAt, expiry > Date().addingTimeInterval(60) {
            return tokens
        }
        // refresh
        let base = self.lastHost.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let refreshURL = URL(string: "\(base)/login/oauth/access_token")!
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formUrlEncoded([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expires = Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
        tokens = OAuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? tokens.refreshToken,
            expiresAt: expires)
        try self.tokenStore.save(tokens: tokens)
        return tokens
    }

    private func normalize(host: URL) throws -> URL {
        guard var components = URLComponents(url: host, resolvingAgainstBaseURL: false) else {
            throw GitHubAPIError.invalidHost
        }
        if components.scheme == nil { components.scheme = "https" }
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

// MARK: - Helpers

extension OAuthCoordinator {
    fileprivate static func formUrlEncoded(_ params: [String: String]) -> Data? {
        let encoded = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return encoded.data(using: .utf8)
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
