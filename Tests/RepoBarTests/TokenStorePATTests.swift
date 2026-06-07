import Foundation
@testable import RepoBarCore
import Testing

struct TokenStorePATTests {
    @Test
    func `save PAT and load`() throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let pat = "ghp_test123456789"
        try store.savePAT(pat)

        let loaded = try store.loadPAT()
        #expect(loaded == pat)
    }

    @Test
    func `clear removes PAT`() throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let pat = "ghp_test123456789"
        try store.savePAT(pat)

        store.clearPAT()

        let loaded = try store.loadPAT()
        #expect(loaded == nil)
    }

    @Test
    func `load PAT when none stored`() throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let loaded = try store.loadPAT()
        #expect(loaded == nil)
    }

    @Test
    func `clear also clears PAT`() throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let pat = "ghp_test123456789"
        try store.savePAT(pat)

        // clear() should also clear PAT
        store.clear()

        let loaded = try store.loadPAT()
        #expect(loaded == nil)
    }

    @Test
    func `clear preserves OpenAI API key`() throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clearAllCredentials() }

        try store.saveOpenAIAPIKey("sk-test")

        store.clear()

        #expect(try store.loadOpenAIAPIKey() == "sk-test")
    }

    @Test
    func `clear all credentials clears OpenAI API key`() throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clearAllCredentials() }

        try store.saveOpenAIAPIKey("sk-test")

        store.clearAllCredentials()

        #expect(try store.loadOpenAIAPIKey() == nil)
    }

    @Test
    func `save PAT overwrites previous`() throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.savePAT("ghp_first")
        try store.savePAT("ghp_second")

        let loaded = try store.loadPAT()
        #expect(loaded == "ghp_second")
    }

    @Test
    func `save OpenAI API key and load`() throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clearOpenAIAPIKey() }

        try store.saveOpenAIAPIKey(" sk-test ")

        #expect(try store.loadOpenAIAPIKey() == "sk-test")
    }

    @Test
    func `OpenAI key store prefers stored key over environment`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repobar-openai-key-\(UUID().uuidString)", isDirectory: true)
        let store = TokenStore(service: "repobar-tests", storage: .file(directory))
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.saveOpenAIAPIKey("sk-stored")

        let keyStore = OpenAIAPIKeyStore(tokenStore: store) { name in
            name == "OPENAI_API_KEY" ? "sk-env" : nil
        }

        let resolved = keyStore.resolve()
        #expect(resolved.key == "sk-stored")
        #expect(resolved.source == .keychain)
    }

    @Test
    func `OpenAI key store reads exact environment names`() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repobar-openai-env-\(UUID().uuidString)", isDirectory: true)
        let store = TokenStore(service: "repobar-tests", storage: .file(directory))
        defer { try? FileManager.default.removeItem(at: directory) }

        let keyStore = OpenAIAPIKeyStore(tokenStore: store) { name in
            name == "REPOBAR_OPENAI_API_KEY" ? "sk-repobar" : nil
        }

        let resolved = keyStore.resolve()
        #expect(resolved.key == "sk-repobar")
        #expect(resolved.source == .environment("REPOBAR_OPENAI_API_KEY"))
    }
}
