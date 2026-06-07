import Commander
import Foundation
import RepoBarCore

struct AuthContext {
    let client: GitHubClient
    let settings: UserSettings
    let host: URL
}

struct RepoIdentifier: Equatable {
    let owner: String
    let name: String

    var fullName: String {
        "\(self.owner)/\(self.name)"
    }

    func webURL(baseHost: URL) -> URL {
        baseHost.appending(path: "/\(self.owner)/\(self.name)")
    }
}

func makeAuthenticatedClient() async throws -> AuthContext {
    let settings = cliSettingsStore().load()
    if let account = settings.resolvedActiveAccount() {
        guard (try? TokenStore.shared.loadTokens(accountID: account.id)) != nil
            || (try? TokenStore.shared.loadPAT(accountID: account.id)) != nil
        else {
            throw CLIError.notAuthenticated
        }

        let archiveSettings = settings.githubArchives
        let client = GitHubClient(
            accountID: account.id,
            archiveSettingsProvider: { archiveSettings }
        )
        await client.setAPIHost(account.apiHost)
        await client.setTokenProvider { @Sendable () async throws -> OAuthTokens? in
            if account.authMethod == .pat, let pat = try? TokenStore.shared.loadPAT(accountID: account.id) {
                return OAuthTokens(accessToken: pat, refreshToken: "", expiresAt: nil)
            }
            return try await OAuthTokenRefresher().refreshIfNeeded(
                host: account.host,
                accountID: account.id
            )
        }
        return AuthContext(client: client, settings: settings, host: account.host)
    }

    guard (try? TokenStore.shared.load()) != nil else {
        throw CLIError.notAuthenticated
    }

    let host = settings.enterpriseHost ?? settings.githubHost
    let apiHost: URL = if let enterprise = settings.enterpriseHost {
        enterprise.appending(path: "/api/v3")
    } else {
        RepoBarAuthDefaults.apiHost
    }

    let archiveSettings = settings.githubArchives
    let client = GitHubClient(archiveSettingsProvider: { archiveSettings })
    await client.setAPIHost(apiHost)
    await client.setTokenProvider { @Sendable () async throws -> OAuthTokens? in
        try await OAuthTokenRefresher().refreshIfNeeded(host: host)
    }
    return AuthContext(client: client, settings: settings, host: host)
}

func mirrorAccountCredentialsToLegacy(_ account: Account) throws {
    if TokenStore.shared.mirrorAccountCredentialsToLegacy(accountID: account.id, authMethod: account.authMethod) == false {
        throw CLIError.notAuthenticated
    }
}

func mirrorActiveAccountIntoSettings(_ account: Account, settings: inout UserSettings) {
    settings.githubHost = account.host
    settings.enterpriseHost = account.host.host?.lowercased() == "github.com" ? nil : account.host
    settings.authMethod = account.authMethod
    settings.loopbackPort = account.loopbackPort
}

func mirrorResolvedActiveAccount(settings: inout UserSettings) {
    guard let active = settings.resolvedActiveAccount() else {
        TokenStore.shared.clear()
        return
    }

    mirrorActiveAccountIntoSettings(active, settings: &settings)
    _ = TokenStore.shared.mirrorAccountCredentialsToLegacy(
        accountID: active.id,
        authMethod: active.authMethod
    )
}

func makeRepoURL(baseHost: URL, owner: String, name: String) -> URL {
    RepoIdentifier(owner: owner, name: name).webURL(baseHost: baseHost)
}

func requireRepoName(_ name: String?) throws -> String {
    guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), name.isEmpty == false else {
        throw ValidationError("Missing repository name (owner/name)")
    }

    return name
}

func requireRepoIdentifier(_ name: String?) throws -> RepoIdentifier {
    try parseRepoName(requireRepoName(name))
}

func parseRepoName(_ value: String) throws -> RepoIdentifier {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
        throw ValidationError("Repository must be in owner/name format")
    }

    if let remoteParts = repoPartsFromRemote(trimmed) {
        return try RepoIdentifier(validatingOwner: remoteParts.owner, name: remoteParts.name)
    }

    let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2 else {
        throw ValidationError("Repository must be in owner/name format")
    }

    return try RepoIdentifier(validatingOwner: parts[0], name: parts[1])
}

private func repoPartsFromRemote(_ value: String) -> (owner: String, name: String)? {
    if let url = URL(string: value), let host = url.host, host.isEmpty == false {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }

        return (parts[0], parts[1])
    }

    guard let separator = value.firstIndex(of: ":") else { return nil }

    let prefix = value[..<separator]
    guard prefix.contains("@") else { return nil }

    let path = String(value[value.index(after: separator)...])
    let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard parts.count >= 2 else { return nil }

    return (parts[parts.count - 2], parts[parts.count - 1])
}

private extension RepoIdentifier {
    init(validatingOwner rawOwner: String, name rawName: String) throws {
        let owner = rawOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }

        guard owner.isEmpty == false, name.isEmpty == false else {
            throw ValidationError("Repository must be in owner/name format")
        }
        guard owner.contains("/") == false, name.contains("/") == false else {
            throw ValidationError("Repository must be in owner/name format")
        }

        self.init(owner: owner, name: name)
    }
}
