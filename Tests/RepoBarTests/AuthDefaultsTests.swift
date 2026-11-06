import Testing
@testable import RepoBarCore

@Test func shippedClientSecretIsNotEmbedded() {
    #expect(RepoBarAuthDefaults.clientSecret.isEmpty)
}
