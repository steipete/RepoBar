import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

struct RepoBarNotificationResponseHandlerTests {
    @Test
    func `click target defaults older notifications to browser URLs`() throws {
        let url = try #require(URL(string: "https://github.com/steipete/RepoBar/pull/57"))

        let target = RepoBarNotificationResponseHandler.clickTarget(from: ["url": url.absoluteString])

        #expect(target == .browser(url))
    }

    @Test
    func `click target opens issue navigator when configured`() {
        let target = RepoBarNotificationResponseHandler.clickTarget(from: [
            "clickAction": GitHubPullRequestNotificationClickAction.openIssueNavigator.rawValue,
            "url": "https://github.com/steipete/RepoBar/pull/57",
            "repositoryFullName": "steipete/RepoBar",
            "pullRequestNumber": 57,
            "itemTitle": "Add notifications"
        ])

        guard case let .issueNavigator(matches) = target else {
            Issue.record("Expected issue navigator target")
            return
        }

        #expect(matches.count == 1)
        #expect(matches.first?.repositoryFullName == "steipete/RepoBar")
        #expect(matches.first?.title == "Add notifications")
        #expect(matches.first?.url.absoluteString == "https://github.com/steipete/RepoBar/pull/57")
    }

    @Test
    func `click target opens empty issue navigator for old issue navigator notifications`() {
        let target = RepoBarNotificationResponseHandler.clickTarget(from: [
            "clickAction": GitHubPullRequestNotificationClickAction.openIssueNavigator.rawValue
        ])

        #expect(target == .issueNavigator([]))
    }

    @Test
    func `click target ignores browser action without a valid URL`() {
        let target = RepoBarNotificationResponseHandler.clickTarget(from: [
            "clickAction": GitHubPullRequestNotificationClickAction.openInBrowser.rawValue
        ])

        #expect(target == .none)
    }
}
