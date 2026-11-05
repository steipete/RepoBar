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
        settings.enterpriseHost = try #require(URL(string: enterpriseHost))
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
