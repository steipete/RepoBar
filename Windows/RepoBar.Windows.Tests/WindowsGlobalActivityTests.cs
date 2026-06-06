using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsGlobalActivityTests
{
    [Fact]
    public void FromStatuses_sorts_activity_across_repositories_and_prefixes_titles()
    {
        var older = DateTimeOffset.Parse("2026-06-01T10:00:00Z");
        var newer = DateTimeOffset.Parse("2026-06-01T12:00:00Z");
        var statuses = new[]
        {
            Status(
                "owner/one",
                new GitHubListItem("Pushed 1 commit", "https://example.com/one", "alice", UpdatedAt: older)),
            Status(
                "owner/two",
                new GitHubListItem("opened Issue #2", "https://example.com/two", "bob", UpdatedAt: newer),
                new GitHubListItem("Created branch main", "https://example.com/two/branch", "carol")),
        };

        var activity = WindowsGlobalActivity.FromStatuses(statuses, limit: 2);

        Assert.Equal(["owner/two: opened Issue #2", "owner/one: Pushed 1 commit"], activity.Select(item => item.Title));
        Assert.Equal("https://example.com/two", activity[0].Url);
        Assert.Equal("bob", activity[0].Subtitle);
    }

    private static RepositoryStatus Status(string fullName, params GitHubListItem[] activity)
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
            RecentLists: RecentRepositoryLists.Empty with { Activity = activity },
            Traffic: null,
            Heatmap: null,
            Changelog: null,
            LocalStatus: null,
            ErrorMessage: null);
    }
}
