import Foundation

enum AccountAttention: Equatable, Hashable {
    case relaunchAfterUpdate(version: String?)
    case credentialsUnavailable
    case signIn
    case signingIn
    case none

    static func resolve(account: AccountState, bundleReplacement: AppBundleReplacement?) -> Self {
        if let bundleReplacement {
            return .relaunchAfterUpdate(version: bundleReplacement.version)
        }

        switch account {
        case .credentialsUnavailable: return .credentialsUnavailable
        case .loggedOut: return .signIn
        case .loggingIn: return .signingIn
        case .loggedIn: return .none
        }
    }

    var title: String? {
        switch self {
        case .relaunchAfterUpdate: AppLocalizer().string("RepoBar was updated while running")
        case .credentialsUnavailable: AppLocalizer().string("Can’t read your saved GitHub credentials")
        default: nil
        }
    }

    var subtitle: String? {
        let localizer = AppLocalizer()
        switch self {
        case let .relaunchAfterUpdate(version):
            if let version {
                return String(format: localizer.string("Relaunch to finish updating to %@."), version)
            }
            return localizer.string("Relaunch to finish updating.")
        case .credentialsUnavailable:
            return localizer.string("macOS denied Keychain access. Relaunch RepoBar to restore it.")
        default: return nil
        }
    }
}
