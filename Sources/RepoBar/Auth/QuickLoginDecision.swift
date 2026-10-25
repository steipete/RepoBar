import Foundation
import RepoBarCore

enum QuickLoginDecision: Equatable {
    case openAccountSettings(Account)
    case startOAuth

    static func resolve(accounts: [Account], host: URL) -> Self {
        let hostName = host.host?.lowercased()
        if let account = accounts.first(where: { $0.authMethod == .pat && $0.host.host?.lowercased() == hostName }) {
            return .openAccountSettings(account)
        }
        return .startOAuth
    }
}
