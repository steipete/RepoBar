import Foundation
import OSLog
import RepoBarCore

public enum PATAuthError: Error, LocalizedError {
    case invalidToken
    case forbidden(String)
    case networkError(Error)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            "Invalid token"
        case let .forbidden(message):
            message
        case let .networkError(error):
            error.localizedDescription
        case .invalidResponse:
            "Invalid response from server"
        }
    }
}

/// Handles Personal Access Token authentication as an alternative to OAuth.
/// PATs can be authorized for SAML SSO organizations in GitHub settings.
@MainActor
public final class PATAuthenticator {
    private let tokenStore: TokenStore
    private let signposter = OSSignposter(subsystem: "com.steipete.repobar", category: "pat-auth")
    private var cachedPAT: String?
    private var hasLoadedPAT = false
    private let session: URLSession

    public init(
        tokenStore: TokenStore = .shared,
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.session = session
    }

    /// Validates PAT via GET /user, stores on success, returns UserIdentity.
    public func authenticate(pat: String, host: URL) async throws -> UserIdentity {
        let signpost = self.signposter.beginInterval("authenticate")
        defer { self.signposter.endInterval("authenticate", signpost) }

        let apiHost = Self.apiHost(for: host)
        let userURL = apiHost.appendingPathComponent("user")

        var request = URLRequest(url: userURL)
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw PATAuthError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PATAuthError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw PATAuthError.invalidToken
        case 403:
            throw PATAuthError.forbidden("Access forbidden. Token may lack required scopes (repo, read:org)")
        default:
            throw PATAuthError.invalidResponse
        }

        struct UserResponse: Decodable {
            let login: String
        }

        let user: UserResponse
        do {
            user = try JSONDecoder().decode(UserResponse.self, from: data)
        } catch {
            throw PATAuthError.invalidResponse
        }

        try self.tokenStore.savePAT(pat)
        self.cachedPAT = pat
        self.hasLoadedPAT = true
        await DiagnosticsLogger.shared.message("PAT login succeeded; token stored.")

        return UserIdentity(username: user.login, host: host)
    }

    /// Loads the stored PAT from Keychain.
    public func loadPAT() -> String? {
        if self.hasLoadedPAT {
            return self.cachedPAT
        }
        self.hasLoadedPAT = true
        let pat = try? self.tokenStore.loadPAT()
        self.cachedPAT = pat
        return pat
    }

    /// Clears the stored PAT.
    public func logout() async {
        self.tokenStore.clearPAT()
        self.cachedPAT = nil
        self.hasLoadedPAT = false
        await DiagnosticsLogger.shared.message("PAT cleared.")
    }

    /// Converts a GitHub host URL to its API endpoint.
    private static func apiHost(for host: URL) -> URL {
        let hostString = host.host ?? "github.com"
        if hostString == "github.com" {
            return URL(string: "https://api.github.com")!
        }
        // Enterprise: use /api/v3 path
        return host.appendingPathComponent("api/v3")
    }
}
