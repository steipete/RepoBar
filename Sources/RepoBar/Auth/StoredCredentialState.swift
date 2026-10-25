import Foundation
import RepoBarCore

enum StoredCredentialState: Equatable, Sendable {
    case present
    case missing
    case unavailable
}
