using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsGlobalActivityTests
{
    [Fact]
    public void FromStatuses_sorts_commits_across_repositories_and_prefixes_titles()
    {
        var older = DateTimeOffset.Parse("2026-06-01T10:00:00Z");
        var newer = DateTimeOffset.Parse("2026-06-01T12:00:00Z");
        var statuses = new[]
        {
            Status("owner/one", commits:
            [
                new GitHubListItem("aaaa111 Fix Windows tray", "https://example.com/one/commit", "alice", UpdatedAt: older),
            ]),
            Status("owner/two", commits:
            [
                new GitHubListItem("bbbb222 Add menu", "https://example.com/two/commit", "bob", UpdatedAt: newer),
                new GitHubListItem("cccc333 No date", "https://example.com/two/old", "carol"),
            ]),
        };

        var commits = WindowsGlobalCommits.FromStatuses(statuses, limit: 2);

        Assert.Equal(["owner/two: bbbb222 Add menu", "owner/one: aaaa111 Fix Windows tray"], commits.Select(item => item.Title));
        Assert.Equal("https://example.com/two/commit", commits[0].Url);
        Assert.Equal("bob", commits[0].Subtitle);
    }

    [Fact]
    public void FromStatuses_filters_commits_to_viewer_when_scope_is_my_activity()
    {
        var timestamp = DateTimeOffset.Parse("2026-06-01T12:00:00Z");
        var statuses = new[]
        {
            Status("owner/one", commits:
            [
                new GitHubListItem("aaaa111 Mine", "https://example.com/mine", "me", AuthorLogin: "octocat", UpdatedAt: timestamp),
                new GitHubListItem("bbbb222 Other", "https://example.com/other", "bot", AuthorLogin: "hubot", UpdatedAt: timestamp.AddMinutes(-1)),
            ]),
        };

        var commits = WindowsGlobalCommits.FromStatuses(
            statuses,
            scope: WindowsActivityScope.MyActivity,
            viewerLogin: "octocat");

        var commit = Assert.Single(commits);
        Assert.Equal("owner/one: aaaa111 Mine", commit.Title);
    }

    [Fact]
    public void FromStatuses_sorts_activity_across_repositories_and_prefixes_titles()
    {
        var older = DateTimeOffset.Parse("2026-06-01T10:00:00Z");
        var newer = DateTimeOffset.Parse("2026-06-01T12:00:00Z");
        var statuses = new[]
        {
            Status(
                "owner/one",
                activity:
                [
                    new GitHubListItem("Pushed 1 commit", "https://example.com/one", "alice", UpdatedAt: older),
                ]),
            Status(
                "owner/two",
                activity:
                [
                    new GitHubListItem("opened Issue #2", "https://example.com/two", "bob", UpdatedAt: newer),
                    new GitHubListItem("Created branch main", "https://example.com/two/branch", "carol"),
                ]),
        };

        var activity = WindowsGlobalActivity.FromStatuses(statuses, limit: 2);

        Assert.Equal(["owner/two: opened Issue #2", "owner/one: Pushed 1 commit"], activity.Select(item => item.Title));
        Assert.Equal("https://example.com/two", activity[0].Url);
        Assert.Equal("bob", activity[0].Subtitle);
    }

    [Fact]
    public void FromStatuses_filters_activity_to_viewer_when_scope_is_my_activity()
    {
        var timestamp = DateTimeOffset.Parse("2026-06-01T12:00:00Z");
        var statuses = new[]
        {
            Status("owner/one", activity:
            [
                new GitHubListItem("opened Issue #1", "https://example.com/mine", "me", AuthorLogin: "octocat", UpdatedAt: timestamp),
                new GitHubListItem("opened Issue #2", "https://example.com/other", "bot", AuthorLogin: "hubot", UpdatedAt: timestamp.AddMinutes(-1)),
            ]),
        };

        var activity = WindowsGlobalActivity.FromStatuses(
            statuses,
            scope: WindowsActivityScope.MyActivity,
            viewerLogin: "octocat");

        var item = Assert.Single(activity);
        Assert.Equal("owner/one: opened Issue #1", item.Title);
    }

    [Fact]
    public void FromStatuses_keeps_items_when_my_activity_scope_has_no_viewer_login()
    {
        var statuses = new[]
        {
            Status("owner/one", activity:
            [
                new GitHubListItem("opened Issue #1", "https://example.com/one", "me", AuthorLogin: "octocat"),
            ]),
        };

        var activity = WindowsGlobalActivity.FromStatuses(
            statuses,
            scope: WindowsActivityScope.MyActivity,
            viewerLogin: null);

        Assert.Single(activity);
    }

    private static RepositoryStatus Status(
        string fullName,
        GitHubListItem[]? activity = null,
        GitHubListItem[]? commits = null)
    {
        var parts = fullName.Split('/', 2);
        return new RepositoryStatus(
            new RepositoryRef { Owner = parts[0], Name = parts[1] },
            Stars: 0,
            Forks: 0,
            IssueCount: 0,
            PullRequestCount: 0,
            DefaultBranch: "main",
            PushedAt: null,
            LatestRun: null,
            LatestRelease: null,
            RecentLists: RecentRepositoryLists.Empty with { Activity = activity ?? [], Commits = commits ?? [] },
            Traffic: null,
            Heatmap: null,
            Changelog: null,
            LocalStatus: null,
            ErrorMessage: null);
    }
}
