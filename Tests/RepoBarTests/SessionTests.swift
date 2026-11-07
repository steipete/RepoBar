import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

struct SessionTests {
    @Test(arguments: [MenuRepoSelection.all, .pinned, .work])
    func `unavailable credentials use local scope without changing the saved selection`(selection: MenuRepoSelection) {
        let session = Session()
        session.account = .credentialsUnavailable(nil)
        session.menuRepoSelection = selection

        #expect(session.effectiveMenuRepoSelection == .local)
        #expect(session.menuRepoSelection == selection)
    }

    @Test(arguments: MenuRepoSelection.allCases)
    func `other account states use the saved menu selection`(selection: MenuRepoSelection) throws {
        let session = Session()
        let identity = try UserIdentity(username: "alice", host: #require(URL(string: "https://github.com")))
        session.menuRepoSelection = selection

        for account in [AccountState.loggedIn(identity), .loggedOut, .loggingIn] {
            session.account = account
            #expect(session.effectiveMenuRepoSelection == selection)
            #expect(session.menuRepoSelection == selection)
        }
    }
}
