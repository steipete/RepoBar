import Foundation

@MainActor
public enum OAuthRefreshHost {
    /// Chooses the OAuth host for a stored refresh token.
    /// Enterprise settings win, then the signed-in account, then the configured host.
    public static func resolved(
        enterpriseHost: URL?,
        accountHost: URL?,
        configuredHost: URL = RepoBarAuthDefaults.githubHost
    ) -> URL {
        let candidates = [enterpriseHost, accountHost, configuredHost].compactMap(\.self)
        for candidate in candidates {
            if let normalized = try? OAuthLoginFlow.normalizeHost(candidate) {
                return normalized
            }
        }
        return RepoBarAuthDefaults.githubHost
    }
}
