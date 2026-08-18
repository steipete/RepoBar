import Foundation
@testable import RepoBarCore
import Testing

struct UserSettingsMultiAccountTests {
    @Test
    func `defaults have empty accounts and default selection`() {
        let settings = UserSettings()
        #expect(settings.accounts.isEmpty)
        #expect(settings.activeAccountID == nil)
        #expect(settings.accountSelection == .all)
        #expect(settings.accountRepoLists.isEmpty)
        #expect(settings.resolvedActiveAccount() == nil)
        #expect(settings.visibleAccountIDs.isEmpty)
    }

    @Test
    func `resolves single configured account when active id missing`() throws {
        var settings = UserSettings()
        let account = try Account(
            username: "alice",
            host: #require(URL(string: "https://github.com")),
            authMethod: .oauth
        )
        settings.accounts = [account]
        // No explicit activeAccountID: convenience fallback returns the only one.
        #expect(settings.resolvedActiveAccount()?.id == account.id)
    }

    @Test
    func `respects active account id when multiple`() throws {
        var settings = UserSettings()
        let alice = try Account(username: "alice", host: #require(URL(string: "https://github.com")), authMethod: .oauth)
        let bob = try Account(username: "bob", host: #require(URL(string: "https://github.com")), authMethod: .oauth)
        settings.accounts = [alice, bob]
        settings.activeAccountID = bob.id
        #expect(settings.resolvedActiveAccount()?.id == bob.id)
    }

    @Test
    func `visible accounts respects only selection`() throws {
        var settings = UserSettings()
        let alice = try Account(username: "alice", host: #require(URL(string: "https://github.com")), authMethod: .oauth)
        let bob = try Account(username: "bob", host: #require(URL(string: "https://github.com")), authMethod: .oauth)
        settings.accounts = [alice, bob]
        settings.accountSelection = .only([alice.id])
        #expect(settings.visibleAccountIDs == [alice.id])
    }

    @Test
    func `codable round trip preserves multi-account fields`() throws {
        var settings = UserSettings()
        let alice = try Account(username: "alice", host: #require(URL(string: "https://github.com")), authMethod: .oauth)
        let bob = try Account(
            username: "bob",
            host: #require(URL(string: "https://ghe.example.com")),
            authMethod: .pat
        )
        settings.accounts = [alice, bob]
        settings.activeAccountID = bob.id
        settings.accountSelection = .only([alice.id])
        settings.accountRepoLists.setPinned(["acme/widget"], for: alice.id)
        settings.accountRepoLists.setHidden(["acme/legacy"], for: bob.id)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)

        #expect(decoded.accounts == settings.accounts)
        #expect(decoded.activeAccountID == bob.id)
        #expect(decoded.accountSelection == .only([alice.id]))
        #expect(decoded.accountRepoLists.pinned(for: alice.id) == ["acme/widget"])
        #expect(decoded.accountRepoLists.hidden(for: bob.id) == ["acme/legacy"])
    }

    @Test
    func `decoding legacy json without account fields preserves defaults`() throws {
        // Simulate a legacy persisted blob that predates the multi-account work.
        let legacyJSON = """
        {
            "githubHost": "https://github.com",
            "loopbackPort": 53682,
            "authMethod": "oauth"
        }
        """
        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        #expect(decoded.accounts.isEmpty)
        #expect(decoded.activeAccountID == nil)
        #expect(decoded.accountSelection == .all)
        #expect(decoded.accountRepoLists.isEmpty)
        // Legacy single-account fields still load.
        #expect(decoded.githubHost.absoluteString == "https://github.com")
        #expect(decoded.loopbackPort == 53682)
    }

    @Test
    func `encoded output omits default account fields`() throws {
        let settings = UserSettings()
        let data = try JSONEncoder().encode(settings)
        let json = String(data: data, encoding: .utf8) ?? ""
        // accounts array is empty: should be omitted to keep legacy reads clean.
        #expect(json.contains("\"accounts\"") == false)
        #expect(json.contains("\"accountSelection\"") == false)
        #expect(json.contains("\"accountRepoLists\"") == false)
    }

    @Test
    func `legacy repository lists belong only to active account`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice, bob]
        settings.activeAccountID = alice.id
        settings.repoList.pinnedRepositories = ["owner/shared"]
        settings.repoList.hiddenRepositories = ["owner/hidden"]

        #expect(settings.pinnedRepositories(for: alice.id) == ["owner/shared"])
        #expect(settings.hiddenRepositories(for: alice.id) == ["owner/hidden"])
        #expect(settings.pinnedRepositories(for: bob.id).isEmpty)
        #expect(settings.hiddenRepositories(for: bob.id).isEmpty)
    }

    @Test
    func `deliberate empty account lists suppress legacy fallback`() throws {
        let alice = try Self.account("alice")
        var settings = UserSettings()
        settings.accounts = [alice]
        settings.activeAccountID = alice.id
        settings.repoList.pinnedRepositories = ["owner/legacy"]
        settings.repoList.hiddenRepositories = ["owner/legacy-hidden"]
        settings.accountRepoLists.setPinned([], for: alice.id)
        settings.accountRepoLists.setHidden([], for: alice.id)

        #expect(settings.pinnedRepositories(for: alice.id).isEmpty)
        #expect(settings.hiddenRepositories(for: alice.id).isEmpty)
    }

    @Test
    func `active mutations mirror legacy lists while nonactive mutations do not`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice, bob]
        settings.activeAccountID = alice.id
        settings.setPinnedRepositories(["owner/alice"], for: alice.id)
        settings.setHiddenRepositories(["owner/alice-hidden"], for: alice.id)

        #expect(settings.repoList.pinnedRepositories == ["owner/alice"])
        #expect(settings.repoList.hiddenRepositories == ["owner/alice-hidden"])

        settings.setPinnedRepositories(["owner/bob"], for: bob.id)
        settings.setHiddenRepositories(["owner/bob-hidden"], for: bob.id)

        #expect(settings.pinnedRepositories(for: bob.id) == ["owner/bob"])
        #expect(settings.hiddenRepositories(for: bob.id) == ["owner/bob-hidden"])
        #expect(settings.repoList.pinnedRepositories == ["owner/alice"])
        #expect(settings.repoList.hiddenRepositories == ["owner/alice-hidden"])
    }

    @Test
    func `switching active account does not copy previous legacy lists`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice, bob]
        settings.activeAccountID = alice.id
        settings.repoList.pinnedRepositories = ["owner/alice"]
        settings.repoList.hiddenRepositories = ["owner/alice-hidden"]

        settings.prepareRepositoryListsForActiveAccountChange(to: bob.id)

        #expect(settings.pinnedRepositories(for: alice.id) == ["owner/alice"])
        #expect(settings.hiddenRepositories(for: alice.id) == ["owner/alice-hidden"])
        #expect(settings.pinnedRepositories(for: bob.id).isEmpty)
        #expect(settings.hiddenRepositories(for: bob.id).isEmpty)
        #expect(settings.repoList.pinnedRepositories.isEmpty)
        #expect(settings.repoList.hiddenRepositories.isEmpty)
    }

    @Test
    func `removing one account leaves another repository preferences intact`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice, bob]
        settings.activeAccountID = bob.id
        settings.setPinnedRepositories(["owner/alice"], for: alice.id)
        settings.setPinnedRepositories(["owner/bob"], for: bob.id)
        settings.setHiddenRepositories(["owner/bob-hidden"], for: bob.id)

        settings.removeRepositoryLists(for: alice.id)

        #expect(settings.accountRepoLists.hasPinnedEntry(for: alice.id) == false)
        #expect(settings.pinnedRepositories(for: bob.id) == ["owner/bob"])
        #expect(settings.hiddenRepositories(for: bob.id) == ["owner/bob-hidden"])
        #expect(settings.repoList.pinnedRepositories == ["owner/bob"])
        #expect(settings.repoList.hiddenRepositories == ["owner/bob-hidden"])
    }

    private static func account(_ username: String) throws -> Account {
        try Account(
            username: username,
            host: #require(URL(string: "https://github.com")),
            authMethod: .oauth
        )
    }
}
