import AppKit
import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

@MainActor
struct QuickLoginDecisionTests {
    @Test
    func `quick login redirects matching PAT accounts only`() throws {
        let host = RepoBarAuthDefaults.githubHost
        let pat = try Account(username: "alice", host: #require(URL(string: "https://GITHUB.COM/path")), authMethod: .pat)
        #expect(QuickLoginDecision.resolve(accounts: [pat], host: host) == .openAccountSettings(pat))
        let oauth = Account(username: "bob", host: host, authMethod: .oauth)
        #expect(QuickLoginDecision.resolve(accounts: [oauth], host: host) == .startOAuth)
        let enterprise = try Account(username: "alice", host: #require(URL(string: "https://github.example.com")), authMethod: .pat)
        #expect(QuickLoginDecision.resolve(accounts: [enterprise], host: host) == .startOAuth)
        #expect(QuickLoginDecision.resolve(accounts: [], host: host) == .startOAuth)
        #expect(QuickLoginDecision.resolve(accounts: [oauth, pat], host: host) == .openAccountSettings(pat))
    }

    @Test
    func `PAT quick login opens settings without mutating credentials or settings`() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.cleanUp() }
        try fixture.tokens.savePAT("unchanged", accountID: fixture.account.id)
        var saved = fixture.settings.load()
        saved.githubHost = try #require(URL(string: "https://custom.example.com"))
        saved.enterpriseHost = saved.githubHost
        saved.loopbackPort = 54321
        fixture.settings.save(saved)
        let app = fixture.makeApp()
        _ = NSApplication.shared
        var opened = false
        SettingsOpener.shared.configure { opened = true }
        defer { SettingsOpener.shared.configure(open: nil) }
        await app.quickLogin()
        #expect(opened)
        #expect(app.session.settingsSelectedTab == .accounts)
        #expect(app.session.settings == saved)
        #expect(fixture.settings.load() == saved)
        #expect(app.session.account == .loggedOut)
        #expect(app.session.lastError == String(format: AppLocalizer().string(
            "%@ @ %@ uses a personal access token. Update it in Accounts settings."
        ), "alice", "github.com"))
        #expect(try fixture.tokens.loadPAT(accountID: fixture.account.id) == "unchanged")
        #expect(try fixture.tokens.loadTokens(accountID: fixture.account.id) == nil)
    }
}
