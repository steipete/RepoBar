import Foundation

public extension Error {
    var userFacingMessage: String {
        let localizer = RepoBarLocalization.localizer()
        if let decodingError = self as? DecodingError {
            return decodingError.userFacingMessage
        }
        if let ghError = self as? GitHubAPIError {
            return ghError.displayMessage
        }
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return localizer.string("error.noInternet")
            case .timedOut: return localizer.string("error.timeout")
            case .cannotLoadFromNetwork: return localizer.string("error.rateLimited")
            case .cannotParseResponse: return localizer.string("error.unexpectedResponse")
            case .userAuthenticationRequired: return localizer.string("error.authenticationRequired")
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid:
                return localizer.string("error.untrustedCertificate")
            default: break
            }
        }
        return localizedDescription
    }
}

private extension DecodingError {
    var userFacingMessage: String {
        switch self {
        case let .keyNotFound(key, _):
            return "Response missing expected field '\(key.stringValue)'. Try again or update RepoBar."
        case .valueNotFound:
            return "Response missing expected data. Try again or update RepoBar."
        case .typeMismatch:
            return "Response had unexpected data. Try again or update RepoBar."
        case .dataCorrupted:
            return "Response was malformed. Try again or update RepoBar."
        @unknown default:
            return "Response could not be decoded. Try again or update RepoBar."
        }
    }
}
