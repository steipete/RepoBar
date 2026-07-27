import AppKit
import Foundation
import OSLog
import RepoBarCore

/// Handles GitHub App OAuth using browser + loopback, PKCE, and refresh tokens.
@MainActor
final class OAuthCoordinator {
    private let tokenStore = TokenStore.shared
    private let tokenRefresher = OAuthTokenRefresher()
    private let signposter = OSSignposter(subsystem: "com.steipete.repobar", category: "oauth")
    private var lastHost: URL = .init(string: "https://github.com")!
    private var cachedTokens: OAuthTokens?
    private var hasLoadedTokens = false

    func login(clientID: String, clientSecret: String, host: URL, loopbackPort: Int, scope: String? = nil) async throws {
        let normalizedHost = try OAuthLoginFlow.normalizeHost(host)
        self.lastHost = normalizedHost
        let flow = OAuthLoginFlow(tokenStore: self.tokenStore) { url in
            NSWorkspace.shared.open(url)
        }
        let tokens = try await flow.login(
            clientID: clientID,
            clientSecret: clientSecret,
            host: normalizedHost,
            loopbackPort: loopbackPort,
            scope: scope
        )
        self.cachedTokens = tokens
        self.hasLoadedTokens = true
        await DiagnosticsLogger.shared.message("Login succeeded; tokens stored.")
    }

    func logout() async {
        self.tokenStore.clear()
        self.cachedTokens = nil
        self.hasLoadedTokens = false
    }

    func loadTokens() -> OAuthTokens? {
        if self.hasLoadedTokens {
            return self.cachedTokens
        }
        self.hasLoadedTokens = true
        let tokens = try? self.tokenStore.load()
        self.cachedTokens = tokens
        return tokens
    }

    func refreshIfNeeded(force: Bool = false) async throws -> OAuthTokens? {
        let signpost = self.signposter.beginInterval("refreshIfNeeded")
        defer { self.signposter.endInterval("refreshIfNeeded", signpost) }

        let cachedTokens = self.cachedTokens
        let shouldReuseCachedTokens = force == false
            && cachedTokens?.expiresAt.map { $0 > Date().addingTimeInterval(60) } != false
        if shouldReuseCachedTokens, let cachedTokens {
            return cachedTokens
        }

        let refreshed = try await self.tokenRefresher.refreshIfNeeded(host: self.lastHost, force: force)
        if refreshed != nil {
            self.cachedTokens = refreshed
            self.hasLoadedTokens = true
        }
        return refreshed
    }

    // MARK: - Installation token

    // Installation flow removed: this app now uses user OAuth only.

    // PEM resolution removed; GitHub App installation tokens are not used.
}
