import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

@MainActor
struct AccountManagerTests {
    @Test
    func `oauth refresh uses shared account scoped refresher`() async throws {
        let (store, account) = try Self.makeStoreAndAccount(authMethod: .oauth)
        defer { store.clear(accountID: account.id) }

        try store.save(
            tokens: OAuthTokens(accessToken: "expired", refreshToken: "refresh", expiresAt: .distantPast),
            accountID: account.id
        )
        try store.save(
            clientCredentials: OAuthClientCredentials(clientID: "account-client", clientSecret: "account-secret"),
            accountID: account.id
        )
        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let body = try String(data: #require(request.httpBody), encoding: .utf8)
            #expect(body?.contains("client_id=account-client") == true)
            #expect(body?.contains("refresh_token=refresh") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"fresh","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"next"}
            """.utf8)
            return (data, response)
        }
        let manager = AccountManager(tokenStore: store, oauthRefresher: refresher)
        await manager.bootstrap(from: Self.settings(account: account))

        let accessToken = try await manager.currentAccessToken(accountID: account.id)

        #expect(accessToken == "fresh")
        #expect(try store.loadTokens(accountID: account.id)?.refreshToken == "next")
        #expect(try store.load() == nil)
    }

    @Test
    func `oauth refresh failure does not return expired token`() async throws {
        let (store, account) = try Self.makeStoreAndAccount(authMethod: .oauth)
        defer { store.clear(accountID: account.id) }

        try store.save(
            tokens: OAuthTokens(accessToken: "expired", refreshToken: "revoked", expiresAt: .distantPast),
            accountID: account.id
        )
        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"error":"invalid_grant","error_description":"token revoked"}"#.utf8), response)
        }
        let manager = AccountManager(tokenStore: store, oauthRefresher: refresher)
        await manager.bootstrap(from: Self.settings(account: account))

        do {
            _ = try await manager.currentAccessToken(accountID: account.id)
            Issue.record("Expected refresh failure")
        } catch let GitHubAPIError.badStatus(code, message) {
            #expect(code == 400)
            #expect(message?.contains("token revoked") == true)
        }
    }

    @Test
    func `pat account never invokes oauth refresher`() async throws {
        let (store, account) = try Self.makeStoreAndAccount(authMethod: .pat)
        defer { store.clear(accountID: account.id) }

        try store.savePAT("pat-token", accountID: account.id)
        let refresher = OAuthTokenRefresher(tokenStore: store) { _ in
            Issue.record("PAT account attempted OAuth refresh")
            throw URLError(.userAuthenticationRequired)
        }
        let manager = AccountManager(tokenStore: store, oauthRefresher: refresher)
        await manager.bootstrap(from: Self.settings(account: account))

        #expect(try await manager.currentAccessToken(accountID: account.id) == "pat-token")
    }

    @Test
    func `explicit client resolver returns scoped client and throws for unknown account`() async throws {
        let (store, account) = try Self.makeStoreAndAccount(authMethod: .pat)
        defer { store.clear(accountID: account.id) }
        try store.savePAT("pat-token", accountID: account.id)
        let manager = AccountManager(tokenStore: store)
        await manager.bootstrap(from: Self.settings(account: account))

        let resolved = try manager.resolveClient(for: account.id)
        let expected = try #require(manager.client(for: account.id))
        #expect(resolved === expected)

        do {
            _ = try manager.resolveClient(for: "github.com#missing")
            Issue.record("Expected unknown account error")
        } catch let AccountManagerError.unknownAccount(accountID) {
            #expect(accountID == "github.com#missing")
        }
    }

    private static func makeStoreAndAccount(authMethod: AuthMethod) throws -> (TokenStore, Account) {
        let service = "com.steipete.repobar.account-manager-tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        let host = try #require(URL(string: "https://github.com"))
        return (store, Account(username: "alice", host: host, authMethod: authMethod))
    }

    private static func settings(account: Account) -> UserSettings {
        var settings = UserSettings()
        settings.accounts = [account]
        settings.activeAccountID = account.id
        return settings
    }
}
