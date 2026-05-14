import AppKit
import Foundation
import RepoBarCore
import UserNotifications

// swiftformat:disable:next redundantSendable
struct RepoBarNotification: Sendable {
    let identifier: String
    let title: String
    let body: String
    let url: URL?
    let clickAction: GitHubPullRequestNotificationClickAction
    let issueNavigatorMatch: GitHubReferenceMatch?

    init(
        identifier: String,
        title: String = "RepoBar",
        body: String,
        url: URL? = nil,
        clickAction: GitHubPullRequestNotificationClickAction = .openInBrowser,
        issueNavigatorMatch: GitHubReferenceMatch? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.url = url
        self.clickAction = clickAction
        self.issueNavigatorMatch = issueNavigatorMatch
    }
}

// swiftformat:disable:next redundantSendable
enum RepoBarNotificationClickTarget: Equatable, Sendable {
    case browser(URL)
    case issueNavigator([GitHubReferenceMatch])
    case none
}

actor RepoBarNotifier {
    static let shared = RepoBarNotifier()
    private let center: UNUserNotificationCenter?
    private let logger = RepoBarLogging.logger("Notifications")

    init() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            self.center = UNUserNotificationCenter.current()
        } else {
            self.center = nil
        }
    }

    func notify(_ notification: RepoBarNotification) async {
        guard let center = self.center else { return }

        let authorizationStatus = await self.authorizationStatus(using: center)
        let authorized: Bool = switch authorizationStatus {
        case .authorized, .provisional:
            true
        case .notDetermined:
            await self.requestAuthorization(for: notification.identifier, using: center)
        default:
            false
        }

        guard authorized else {
            self.logger.info("Notification skipped: \(notification.identifier), authorization: \(Self.authorizationLabel(authorizationStatus))")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.userInfo[Self.clickActionUserInfoKey] = notification.clickAction.rawValue
        if let url = notification.url {
            content.userInfo[Self.urlUserInfoKey] = url.absoluteString
        }
        if let match = notification.issueNavigatorMatch {
            content.userInfo[Self.repositoryFullNameUserInfoKey] = match.repositoryFullName
            if let number = match.query.issueNumber {
                content.userInfo[Self.pullRequestNumberUserInfoKey] = number
            }
            content.userInfo[Self.itemTitleUserInfoKey] = match.title
        }

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            let delivery = await self.deliveryStatus(identifier: notification.identifier, using: center)
            self.logger.info(
                "Notification scheduled: \(notification.identifier), delivered: \(delivery.delivered), urlAttached: \(delivery.urlAttached), clickAction: \(delivery.clickAction)"
            )
        } catch {
            self.logger.warning("Notification failed: \(notification.identifier), error: \(error.localizedDescription)")
        }
    }

    private func authorizationStatus(using center: UNUserNotificationCenter) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization(for identifier: String, using center: UNUserNotificationCenter) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    self.logger.warning(
                        "Notification authorization request failed: \(identifier), error: \(error.localizedDescription)"
                    )
                } else {
                    self.logger.info("Notification authorization request completed: \(identifier), granted: \(granted)")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    private func deliveryStatus(
        identifier: String,
        using center: UNUserNotificationCenter
    ) async -> RepoBarNotificationDeliveryStatus {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                guard let notification = notifications.first(where: { $0.request.identifier == identifier }) else {
                    continuation.resume(returning: RepoBarNotificationDeliveryStatus(
                        delivered: false,
                        urlAttached: false,
                        clickAction: "missing"
                    ))
                    return
                }

                let rawURL = notification.request.content.userInfo[Self.urlUserInfoKey] as? String
                let clickAction = notification.request.content.userInfo[Self.clickActionUserInfoKey] as? String ?? "missing"
                continuation.resume(returning: RepoBarNotificationDeliveryStatus(
                    delivered: true,
                    urlAttached: rawURL?.isEmpty == false,
                    clickAction: clickAction
                ))
            }
        }
    }

    private nonisolated static var urlUserInfoKey: String {
        "url"
    }

    private nonisolated static var clickActionUserInfoKey: String {
        "clickAction"
    }

    private nonisolated static var repositoryFullNameUserInfoKey: String {
        "repositoryFullName"
    }

    private nonisolated static var pullRequestNumberUserInfoKey: String {
        "pullRequestNumber"
    }

    private nonisolated static var itemTitleUserInfoKey: String {
        "itemTitle"
    }

    private nonisolated static func authorizationLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            "notDetermined"
        case .denied:
            "denied"
        case .authorized:
            "authorized"
        case .provisional:
            "provisional"
        case .ephemeral:
            "ephemeral"
        @unknown default:
            "unknown"
        }
    }
}

// swiftformat:disable:next redundantSendable
private struct RepoBarNotificationDeliveryStatus: Sendable {
    let delivered: Bool
    let urlAttached: Bool
    let clickAction: String
}

final class RepoBarNotificationResponseHandler: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    static let shared = RepoBarNotificationResponseHandler()
    private static let urlUserInfoKey = "url"
    private static let clickActionUserInfoKey = "clickAction"
    private static let repositoryFullNameUserInfoKey = "repositoryFullName"
    private static let pullRequestNumberUserInfoKey = "pullRequestNumber"
    private static let itemTitleUserInfoKey = "itemTitle"

    static func clickTarget(from userInfo: [AnyHashable: Any]) -> RepoBarNotificationClickTarget {
        let clickAction = (userInfo[Self.clickActionUserInfoKey] as? String)
            .flatMap(GitHubPullRequestNotificationClickAction.init(rawValue:)) ?? .openInBrowser

        switch clickAction {
        case .openInBrowser:
            guard let rawURL = userInfo[Self.urlUserInfoKey] as? String,
                  let url = URL(string: rawURL)
            else { return .none }

            return .browser(url)
        case .openIssueNavigator:
            return .issueNavigator(Self.issueNavigatorMatches(from: userInfo))
        }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let target = Self.clickTarget(from: response.notification.request.content.userInfo)

        await MainActor.run {
            switch target {
            case let .browser(url):
                NotificationCenter.default.post(name: .notificationBrowserOpenRequested, object: nil)
                _ = NSWorkspace.shared.open(url)
            case let .issueNavigator(matches):
                NotificationCenter.default.post(name: .issueNavigatorOpenRequested, object: matches)
            case .none:
                break
            }
        }
    }

    private static func issueNavigatorMatches(from userInfo: [AnyHashable: Any]) -> [GitHubReferenceMatch] {
        guard let rawURL = userInfo[urlUserInfoKey] as? String,
              let url = URL(string: rawURL),
              let repositoryFullName = userInfo[repositoryFullNameUserInfoKey] as? String,
              let number = userInfo[pullRequestNumberUserInfoKey] as? Int
        else { return [] }

        let title = (userInfo[Self.itemTitleUserInfoKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String = if let title, title.isEmpty == false {
            title
        } else {
            "#\(number)"
        }
        return [
            GitHubReferenceMatch(
                query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number),
                title: resolvedTitle,
                url: url,
                repositoryFullName: repositoryFullName,
                kind: .pullRequest,
                state: nil,
                createdAt: nil,
                updatedAt: Date()
            )
        ]
    }
}

private extension GitHubReferenceQuery {
    var issueNumber: Int? {
        switch self {
        case let .issueNumber(number),
             let .repositoryNameIssueNumber(_, number),
             let .repositoryIssueNumber(_, number):
            number
        case .commitHash, .repositoryCommitHash, .repositoryWorkflowRun:
            nil
        }
    }
}
