import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

@MainActor
struct LegacyRefreshRaceTests {
    @Test
    func `stored account refresh does not rotate the mirrored legacy token`() async throws {
        let fixture = try RefreshFixture()
        defer { fixture.cleanup() }

        let appState = fixture.makeAppState(includeAccount: true)
        await appState.bootstrapAccounts()
        await appState.refreshStoredTokensNow()

        let requestCount = await fixture.counter.value
        let accountRefresh = try fixture.store.loadTokens(accountID: fixture.account.id)?.refreshToken
        let legacyRefresh = try fixture.store.load()?.refreshToken
        #expect(requestCount == 1)
        #expect(accountRefresh == "r2")
        #expect(legacyRefresh == "r1")
    }

    @Test
    func `legacy refresh still runs when no account record exists`() async throws {
        let fixture = try RefreshFixture()
        defer { fixture.cleanup() }

        let appState = fixture.makeAppState(includeAccount: false)
        await appState.refreshStoredTokensNow()

        let requestCount = await fixture.counter.value
        let legacyRefresh = try fixture.store.load()?.refreshToken
        #expect(requestCount == 1)
        #expect(legacyRefresh == "r2")
    }
}

@MainActor
private struct RefreshFixture {
    let store: TokenStore
    let account: Account
    let counter = RequestCounter()
    let usedTokens = UsedRefreshTokens()
    let defaults: UserDefaults
    let suiteName: String

    init() throws {
        self.suiteName = "com.steipete.repobar.legacy-refresh-race.\(UUID().uuidString)"
        self.defaults = try #require(UserDefaults(suiteName: self.suiteName))
        let service = "com.steipete.repobar.legacy-refresh-race.\(UUID().uuidString)"
        self.store = TokenStore(service: service)
        let host = try #require(URL(string: "https://github.com"))
        self.account = Account(username: "octocat", host: host, authMethod: .oauth)
        let tokens = OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast)
        let credentials = OAuthClientCredentials(clientID: "cid", clientSecret: "csecret")
        try self.store.save(tokens: tokens)
        try self.store.save(clientCredentials: credentials)
        try self.store.save(tokens: tokens, accountID: self.account.id)
        try self.store.save(clientCredentials: credentials, accountID: self.account.id)
    }

    func cleanup() {
        self.store.clear(accountID: self.account.id)
        self.store.clear()
        self.defaults.removePersistentDomain(forName: self.suiteName)
    }

    func makeAppState(includeAccount: Bool) -> AppState {
        let refresher = OAuthTokenRefresher(tokenStore: self.store) { request in
            await self.counter.increment()
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let refreshToken = body
                .split(separator: "&")
                .first { $0.hasPrefix("refresh_token=") }
                .map { String($0.dropFirst("refresh_token=".count)) } ?? ""
            let accepted = await self.usedTokens.consume(refreshToken)
            let url = request.url ?? URL(string: "https://github.com/login/oauth/access_token")!
            if accepted == false {
                let response = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
                let data = Data(#"{"error":"invalid_grant","error_description":"token retired"}"#.utf8)
                return (data, response)
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(
                #"{"access_token":"new","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"r2"}"#
                    .utf8
            )
            return (data, response)
        }
        var settings = UserSettings()
        settings.authMethod = .oauth
        if includeAccount {
            settings.accounts = [self.account]
            settings.activeAccountID = self.account.id
        }
        let settingsStore = SettingsStore(defaults: self.defaults)
        settingsStore.save(settings)
        return AppState(
            settingsStore: settingsStore,
            accountManager: AccountManager(tokenStore: self.store, oauthRefresher: refresher),
            auth: OAuthCoordinator(tokenStore: self.store, tokenRefresher: refresher),
            patAuth: PATAuthenticator(tokenStore: self.store)
        )
    }
}

private actor RequestCounter {
    private(set) var value = 0

    func increment() {
        self.value += 1
    }
}

private actor UsedRefreshTokens {
    private var seen: Set<String> = []

    func consume(_ token: String) -> Bool {
        self.seen.insert(token).inserted
    }
}
