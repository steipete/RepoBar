import Foundation
@testable import RepoBarCore
import Testing

struct RecentRepoItemsDecodingTests {
    @Test
    func `issues endpoint filters out pull requests`() throws {
        let json = """
        [
          {
            "number": 1,
            "title": "Issue one",
            "html_url": "https://github.com/acme/widget/issues/1",
            "updated_at": "2025-12-28T10:00:00Z",
            "comments": 3,
            "labels": [
              { "name": "bug", "color": "d73a4a" },
              { "name": "good first issue", "color": "7057ff" }
            ],
            "assignees": [
              { "login": "steipete", "avatar_url": "https://avatars.githubusercontent.com/u/583?v=4" }
            ],
            "user": { "login": "alice", "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4" }
          },
          {
            "number": 2,
            "title": "PR (should not appear as issue)",
            "html_url": "https://github.com/acme/widget/pull/2",
            "updated_at": "2025-12-28T12:00:00Z",
            "comments": 0,
            "labels": [],
            "user": { "login": "bob", "avatar_url": "https://avatars.githubusercontent.com/u/2?v=4" },
            "pull_request": {}
          }
        ]
        """

        let items = try GitHubClient.decodeRecentIssues(from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items.first?.number == 1)
        #expect(items.first?.authorLogin == "alice")
        #expect(items.first?.authorAvatarURL != nil)
        #expect(items.first?.commentCount == 3)
        #expect(items.first?.labels.count == 2)
        #expect(items.first?.assigneeLogins == ["steipete"])
    }

    @Test
    func `issues endpoint extracts pull request comment counts`() throws {
        let json = """
        [
          {
            "number": 1,
            "title": "Issue one",
            "html_url": "https://github.com/acme/widget/issues/1",
            "updated_at": "2025-12-28T10:00:00Z",
            "comments": 3,
            "labels": []
          },
          {
            "number": 2,
            "title": "PR with conversation comments",
            "html_url": "https://github.com/acme/widget/pull/2",
            "updated_at": "2025-12-28T12:00:00Z",
            "comments": 4,
            "labels": [],
            "pull_request": {}
          }
        ]
        """

        let counts = try GitHubClient.decodePullRequestIssueCommentCounts(from: Data(json.utf8))
        #expect(counts == [2: 4])
    }

    @Test
    func `pulls endpoint maps draft and author`() throws {
        let json = """
        [
          {
            "number": 42,
            "title": "Add repo submenu items",
            "html_url": "https://github.com/acme/widget/pull/42",
            "updated_at": "2025-12-27T09:30:00Z",
            "state": "closed",
            "merged_at": "2025-12-27T10:00:00Z",
            "draft": true,
            "comments": 2,
            "review_comments": 5,
            "requested_reviewers": [
              { "login": "alice", "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4" }
            ],
            "requested_teams": [
              { "name": "ios" }
            ],
            "labels": [
              { "name": "bug", "color": "d73a4a" }
            ],
            "head": { "ref": "feature/menu-rows" },
            "base": { "ref": "main" },
            "body": "Adds sidebar rows.\\n\\nKeeps summaries compact.",
            "user": { "login": "steipete", "avatar_url": "https://avatars.githubusercontent.com/u/583?v=4" }
          }
        ]
        """

        let items = try GitHubClient.decodeRecentPullRequests(from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items.first?.number == 42)
        #expect(items.first?.state == .closed)
        #expect(items.first?.mergedAt == Date(timeIntervalSince1970: 1_766_829_600))
        #expect(items.first?.isDraft == true)
        #expect(items.first?.authorLogin == "steipete")
        #expect(items.first?.authorAvatarURL != nil)
        #expect(items.first?.commentCount == 2)
        #expect(items.first?.reviewCommentCount == 5)
        #expect(items.first?.requestedReviewerLogins == ["alice"])
        #expect(items.first?.requestedTeamNames == ["ios"])
        #expect(items.first?.labels.first?.name == "bug")
        #expect(items.first?.headRefName == "feature/menu-rows")
        #expect(items.first?.baseRefName == "main")
        #expect(items.first?.bodyPreview == "Adds sidebar rows. Keeps summaries compact.")
    }

    @Test
    func `releases endpoint skips draft and aggregates assets`() throws {
        let json = """
        [
          {
            "name": "v1.2.3",
            "tag_name": "v1.2.3",
            "html_url": "https://github.com/acme/widget/releases/tag/v1.2.3",
            "published_at": "2025-12-28T10:00:00Z",
            "created_at": "2025-12-28T09:50:00Z",
            "draft": false,
            "prerelease": true,
            "author": { "login": "alice", "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4" },
            "assets": [
              { "download_count": 10 },
              { "download_count": 5 }
            ]
          },
          {
            "name": "Draft release",
            "tag_name": "v1.2.4",
            "html_url": "https://github.com/acme/widget/releases/tag/v1.2.4",
            "draft": true
          }
        ]
        """

        let items = try GitHubClient.decodeRecentReleases(from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items.first?.tag == "v1.2.3")
        #expect(items.first?.name == "v1.2.3")
        #expect(items.first?.isPrerelease == true)
        #expect(items.first?.authorLogin == "alice")
        #expect(items.first?.authorAvatarURL != nil)
        #expect(items.first?.assetCount == 2)
        #expect(items.first?.downloadCount == 15)
    }
}
