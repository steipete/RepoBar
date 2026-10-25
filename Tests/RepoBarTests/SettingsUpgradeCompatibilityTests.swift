import Foundation
@testable import RepoBar
@testable import RepoBarCore
import Testing

@MainActor
struct SettingsUpgradeCompatibilityTests {
    @Test(arguments: [AuthMethod.pat, .oauth])
    func `bootstrap preserves 0_10_3 settings bytes and credentials`(method: AuthMethod) async throws {
        let fixture = try CredentialFixture(method: method)
        defer { fixture.cleanUp() }
        var saved = fixture.settings.load()
        saved.repoList.pinnedRepositories = ["alice/first", "alice/second"]
        saved.repoList.displayLimit = 12
        saved.repoList.hiddenRepositories = ["alice/hidden"]
        saved.heatmap.span = .threeMonths
        fixture.settings.save(saved)
        let pat = "test-upgrade-pat"
        let oauth = OAuthTokens(
            accessToken: "test-upgrade-access",
            refreshToken: "test-upgrade-refresh",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        switch method {
        case .pat:
            try fixture.tokens.savePAT(pat, accountID: fixture.account.id)
        case .oauth:
            try fixture.tokens.save(tokens: oauth, accountID: fixture.account.id)
        }
        let storedBytes = try #require(fixture.defaults.data(forKey: SettingsStore.storageKey))

        let app = fixture.makeApp()
        await app.bootstrapAccounts()

        #expect(app.session.account == .loggedIn(fixture.identity))
        #expect(app.session.settings == saved)
        #expect(app.accountManager.accounts == saved.accounts)
        #expect(app.accountManager.activeAccountID == saved.activeAccountID)
        #expect(fixture.settings.load() == saved)
        #expect(fixture.defaults.data(forKey: SettingsStore.storageKey) == storedBytes)
        switch method {
        case .pat:
            #expect(try fixture.tokens.loadPAT(accountID: fixture.account.id) == pat)
        case .oauth:
            #expect(try fixture.tokens.loadTokens(accountID: fixture.account.id) == oauth)
        }
    }
}
