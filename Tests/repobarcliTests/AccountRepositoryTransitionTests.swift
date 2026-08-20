import Foundation
import RepoBarCore
import Testing

struct AccountRepositoryTransitionTests {
    @Test
    func `account use preserves old lists and restores selected lists`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice, bob]
        settings.activeAccountID = alice.id
        settings.repoList.pinnedRepositories = ["owner/alice"]
        settings.repoList.hiddenRepositories = ["owner/alice-hidden"]
        settings.accountRepoLists.setPinned(["owner/bob"], for: bob.id)
        settings.accountRepoLists.setHidden(["owner/bob-hidden"], for: bob.id)

        settings.prepareRepositoryListsForActiveAccountChange(to: bob.id)

        #expect(settings.pinnedRepositories(for: alice.id) == ["owner/alice"])
        #expect(settings.hiddenRepositories(for: alice.id) == ["owner/alice-hidden"])
        #expect(settings.repoList.pinnedRepositories == ["owner/bob"])
        #expect(settings.repoList.hiddenRepositories == ["owner/bob-hidden"])
    }

    @Test
    func `login activation initializes new account without inheriting active lists`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice]
        settings.activeAccountID = alice.id
        settings.repoList.pinnedRepositories = ["owner/alice"]
        settings.accounts.append(bob)

        settings.prepareRepositoryListsForActiveAccountChange(to: bob.id)

        #expect(settings.pinnedRepositories(for: alice.id) == ["owner/alice"])
        #expect(settings.pinnedRepositories(for: bob.id).isEmpty)
        #expect(settings.repoList.pinnedRepositories.isEmpty)
    }

    @Test
    func `active removal restores fallback account lists`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice, bob]
        settings.activeAccountID = alice.id
        settings.repoList.pinnedRepositories = ["owner/alice"]
        settings.accountRepoLists.setPinned(["owner/bob"], for: bob.id)

        settings.prepareRepositoryListsForActiveAccountChange(to: bob.id)
        settings.accounts.removeAll { $0.id == alice.id }
        settings.removeRepositoryLists(for: alice.id)

        #expect(settings.activeAccountID == bob.id)
        #expect(settings.repoList.pinnedRepositories == ["owner/bob"])
        #expect(settings.pinnedRepositories(for: bob.id) == ["owner/bob"])
    }

    @Test
    func `deliberate empty selected account clears stale legacy lists`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice, bob]
        settings.activeAccountID = alice.id
        settings.repoList.pinnedRepositories = ["owner/alice"]
        settings.repoList.hiddenRepositories = ["owner/alice-hidden"]
        settings.accountRepoLists.setPinned([], for: bob.id)
        settings.accountRepoLists.setHidden([], for: bob.id)

        settings.prepareRepositoryListsForActiveAccountChange(to: bob.id)

        #expect(settings.repoList.pinnedRepositories.isEmpty)
        #expect(settings.repoList.hiddenRepositories.isEmpty)
    }

    private static func account(_ username: String) throws -> Account {
        try Account(
            username: username,
            host: #require(URL(string: "https://github.com")),
            authMethod: .oauth
        )
    }
}
