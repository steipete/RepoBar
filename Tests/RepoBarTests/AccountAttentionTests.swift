import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

struct AccountAttentionTests {
    @Test
    func `attention precedence covers every account state`() throws {
        let identity = try UserIdentity(username: "test", host: #require(URL(string: "https://github.com")))
        let cases: [(AccountState, AccountAttention)] = [
            (.loggedOut, .signIn), (.loggingIn, .signingIn), (.loggedIn(identity), .none),
            (.credentialsUnavailable(identity), .credentialsUnavailable),
            (.credentialsUnavailable(nil), .credentialsUnavailable)
        ]
        for (account, expected) in cases {
            #expect(AccountAttention.resolve(account: account, bundleReplacement: nil) == expected)
            for version: String? in [nil, "1.2.3"] {
                #expect(AccountAttention.resolve(account: account, bundleReplacement: AppBundleReplacement(version: version))
                    == .relaunchAfterUpdate(version: version))
            }
        }
        #expect(AccountState.credentialsUnavailable(identity).isLoggedIn == false)
    }
}
