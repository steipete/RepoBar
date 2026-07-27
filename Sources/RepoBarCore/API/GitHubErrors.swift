import Foundation

public enum GitHubAPIError: Error {
    case rateLimited(until: Date?, message: String)
    case serviceUnavailable(retryAfter: Date?, message: String)
    case badStatus(code: Int, message: String?)
    case invalidHost
    case invalidPEM

    public var displayMessage: String {
        switch self {
        case let .rateLimited(_, message): message
        case let .serviceUnavailable(_, message): message
        case let .badStatus(code, message): message ?? "GitHub returned \(code)."
        case .invalidHost: "GitHub Enterprise host must use HTTPS and trusted certs."
        case .invalidPEM: "Private key file missing or unreadable."
        }
    }

    public var isAuthenticationFailure: Bool {
        switch self {
        case let .badStatus(code, message):
            if code == 401 {
                return true
            }
            if let message, message.localizedCaseInsensitiveContains("authentication refresh failed") {
                return true
            }
            return false
        default:
            return false
        }
    }

    public var rateLimitedUntil: Date? {
        if case let .rateLimited(until, _) = self {
            return until
        }
        return nil
    }

    public var retryAfter: Date? {
        if case let .serviceUnavailable(date, _) = self {
            return date
        }
        return nil
    }
}

extension GitHubAPIError: LocalizedError {
    public var errorDescription: String? {
        self.displayMessage
    }
}

struct RepoErrorAccumulator {
    private(set) var messages: [String] = []
    private(set) var rateLimit: Date?

    var message: String? {
        self.messages.first
    }

    mutating func absorb(_ error: Error) {
        if let gh = error as? GitHubAPIError {
            self.updateLimit(with: gh.rateLimitedUntil ?? gh.retryAfter)
            self.appendUnique(gh.displayMessage)
            return
        }
        self.appendUnique(error.userFacingMessage)
    }

    private mutating func appendUnique(_ message: String) {
        guard !self.messages.contains(message) else { return }

        self.messages.append(message)
    }

    private mutating func updateLimit(with candidate: Date?) {
        guard let candidate else { return }

        if let current = rateLimit {
            if candidate > current {
                self.rateLimit = candidate
            }
        } else {
            self.rateLimit = candidate
        }
    }
}
