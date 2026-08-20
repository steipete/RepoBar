import Foundation
@testable import repobarcli
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

    @Test
    func `CLI repository mutation preserves scoped empty across account switches`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice, bob]
        settings.activeAccountID = alice.id
        settings.accountRepoLists.setPinned(["owner/repo"], for: alice.id)
        settings.accountRepoLists.setHidden(["owner/bob-hidden"], for: bob.id)
        settings.mirrorRepositoryListsToLegacy(for: alice.id)

        applyRepoListMutation(.unpin, repository: "owner/repo", settings: &settings)
        settings.prepareRepositoryListsForActiveAccountChange(to: bob.id)
        settings.prepareRepositoryListsForActiveAccountChange(to: alice.id)

        #expect(settings.pinnedRepositories(for: alice.id).isEmpty)
        #expect(settings.repoList.pinnedRepositories.isEmpty)
        #expect(settings.hiddenRepositories(for: bob.id) == ["owner/bob-hidden"])
    }

    @Test
    func `CLI repository mutations isolate active account lists`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob")
        var settings = UserSettings()
        settings.accounts = [alice, bob]
        settings.activeAccountID = alice.id
        settings.accountRepoLists.setPinned(["owner/bob"], for: bob.id)
        settings.accountRepoLists.setHidden(["owner/bob-hidden"], for: bob.id)
        settings.mirrorRepositoryListsToLegacy(for: alice.id)

        applyRepoListMutation(.pin, repository: "owner/alice", settings: &settings)
        applyRepoListMutation(.hide, repository: "owner/alice-hidden", settings: &settings)
        applyRepoListMutation(.show, repository: "owner/alice-hidden", settings: &settings)

        #expect(settings.pinnedRepositories(for: alice.id) == ["owner/alice"])
        #expect(settings.hiddenRepositories(for: alice.id).isEmpty)
        #expect(settings.pinnedRepositories(for: bob.id) == ["owner/bob"])
        #expect(settings.hiddenRepositories(for: bob.id) == ["owner/bob-hidden"])
    }

    @Test
    func `OAuth activation migrates sole implicit account before append`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob", authMethod: .oauth)
        var settings = UserSettings()
        settings.accounts = [alice]
        settings.activeAccountID = nil
        settings.repoList.pinnedRepositories = ["owner/alice"]
        settings.repoList.hiddenRepositories = ["owner/alice-hidden"]

        activateCLIAccount(bob, settings: &settings)

        #expect(settings.pinnedRepositories(for: alice.id) == ["owner/alice"])
        #expect(settings.hiddenRepositories(for: alice.id) == ["owner/alice-hidden"])
        #expect(settings.pinnedRepositories(for: bob.id).isEmpty)
        #expect(settings.hiddenRepositories(for: bob.id).isEmpty)
        #expect(settings.repoList.pinnedRepositories.isEmpty)
        #expect(settings.repoList.hiddenRepositories.isEmpty)
    }

    @Test
    func `PAT import activation migrates sole implicit account before append`() throws {
        let alice = try Self.account("alice")
        let bob = try Self.account("bob", authMethod: .pat)
        var settings = UserSettings()
        settings.accounts = [alice]
        settings.activeAccountID = nil
        settings.repoList.pinnedRepositories = ["owner/alice"]

        activateCLIAccount(bob, settings: &settings)

        #expect(settings.pinnedRepositories(for: alice.id) == ["owner/alice"])
        #expect(settings.pinnedRepositories(for: bob.id).isEmpty)
        #expect(settings.repoList.pinnedRepositories.isEmpty)
    }

    private static func account(_ username: String, authMethod: AuthMethod = .oauth) throws -> Account {
        try Account(
            username: username,
            host: #require(URL(string: "https://github.com")),
            authMethod: authMethod
        )
    }
}
