import AppKit
import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

@MainActor
struct EnterpriseRefreshHostTests {
    @Test
    func `relaunch keeps the legacy refresh host on the saved enterprise server`() throws {
        let appState = try makeAppState(enterpriseHost: "https://ghe.example.com", accountHost: nil)
        let refreshHost = Self.storedRefreshHost(of: appState.auth)

        #expect(refreshHost?.host == "ghe.example.com")
    }

    @Test
    func `relaunch keeps the legacy refresh host on the saved account server`() throws {
        let appState = try makeAppState(enterpriseHost: nil, accountHost: "https://ghe.example.com")
        let refreshHost = Self.storedRefreshHost(of: appState.auth)

        #expect(refreshHost?.host == "ghe.example.com")
    }

    @Test
    func `saved enterprise server wins over a github.com account host`() throws {
        let appState = try makeAppState(
            enterpriseHost: "https://ghe.example.com",
            accountHost: "https://github.com"
        )
        let refreshHost = Self.storedRefreshHost(of: appState.auth)

        #expect(refreshHost?.host == "ghe.example.com")
    }

    @Test
    func `refresh request follows the saved enterprise host after settings change`() async throws {
        let suiteName = "com.steipete.repobar.enterprise-request.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let tokenStore = TokenStore(service: suiteName)
        defer {
            tokenStore.clear()
            defaults.removePersistentDomain(forName: suiteName)
        }
        try tokenStore.save(tokens: OAuthTokens(accessToken: "old", refreshToken: "refresh", expiresAt: .distantPast))
        try tokenStore.save(clientCredentials: OAuthClientCredentials(clientID: "fixture", clientSecret: "fixture"))
        let refresher = OAuthTokenRefresher(tokenStore: tokenStore) { request in
            #expect(request.url?.absoluteString == "https://ghe-after.example.com/login/oauth/access_token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"access_token":"new","token_type":"bearer","scope":"repo","refresh_token":"next","expires_in":3600}"#.utf8), response)
        }
        let settingsStore = SettingsStore(defaults: defaults)
        var settings = UserSettings()
        settings.enterpriseHost = URL(string: "https://ghe-before.example.com")
        settingsStore.save(settings)
        let appState = AppState(
            settingsStore: settingsStore,
            accountManager: AccountManager(tokenStore: tokenStore),
            auth: OAuthCoordinator(tokenStore: tokenStore, tokenRefresher: refresher)
        )
        appState.session.settings.enterpriseHost = URL(string: "https://ghe-after.example.com")

        let tokens = try await appState.auth.refreshIfNeeded(force: true)

        #expect(tokens?.accessToken == "new")
    }

    private static func storedRefreshHost(of auth: OAuthCoordinator) -> URL? {
        Mirror(reflecting: auth).children.first { $0.label == "lastHost" }?.value as? URL
    }
}

@MainActor
private func makeAppState(enterpriseHost: String?, accountHost: String?) throws -> AppState {
    let suiteName = "com.steipete.repobar.enterprise-refresh-host.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let store = SettingsStore(defaults: defaults)
    var settings = UserSettings()
    settings.authMethod = .oauth
    if let enterpriseHost {
        settings.enterpriseHost = URL(string: enterpriseHost)
    }
    if let accountHost {
        let host = try #require(URL(string: accountHost))
        let account = Account(username: "octocat", host: host, authMethod: .oauth)
        settings.accounts = [account]
        settings.activeAccountID = account.id
    }
    store.save(settings)
    let appState = AppState(settingsStore: store)
    defaults.removePersistentDomain(forName: suiteName)
    return appState
}
