import Foundation
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case display
    case repositories
    case accounts
    case notifications
    case advanced
    case about
    #if DEBUG
        case debug
    #endif

    static let defaultWidth: CGFloat = 540
    static let repositoriesWidth: CGFloat = 980
    static let windowHeight: CGFloat = 770

    var title: String {
        switch self {
        case .general: "General"
        case .display: "Display"
        case .repositories: "Repositories"
        case .accounts: "Accounts"
        case .notifications: "Notifications"
        case .advanced: "Advanced"
        case .about: "About"
        #if DEBUG
            case .debug: "Debug"
        #endif
        }
    }

    var preferredWidth: CGFloat {
        self == .repositories ? Self.repositoriesWidth : Self.defaultWidth
    }

    var preferredHeight: CGFloat {
        Self.windowHeight
    }
}
