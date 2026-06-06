using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsRepositoryDisplayTests
{
    [Fact]
    public void Apply_keeps_pinned_repositories_first_then_sorts_by_activity_and_limits()
    {
        var settings = new WindowsSettings
        {
            RepositoryDisplayLimit = 3,
            RepositorySortKey = RepositorySortKey.Activity,
            Repositories =
            [
                new RepositoryRef { Owner = "owner", Name = "pinned", Visibility = RepositoryVisibility.Pinned },
                new RepositoryRef { Owner = "owner", Name = "old", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "owner", Name = "new", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "owner", Name = "middle", Visibility = RepositoryVisibility.Visible },
            ],
        };
        var statuses = new[]
        {
            Status("owner/old", pushedAt: DateTimeOffset.Parse("2026-01-01T00:00:00Z")),
            Status("owner/new", pushedAt: DateTimeOffset.Parse("2026-03-01T00:00:00Z")),
            Status("owner/pinned", pushedAt: DateTimeOffset.Parse("2025-01-01T00:00:00Z")),
            Status("owner/middle", pushedAt: DateTimeOffset.Parse("2026-02-01T00:00:00Z")),
        };

        var displayed = WindowsRepositoryDisplay.Apply(statuses, settings);

        Assert.Equal(["owner/pinned", "owner/new", "owner/middle"], displayed.Select(status => status.Repository.FullName));
    }

    [Fact]
    public void Apply_sorts_normal_repositories_by_selected_metric()
    {
        var settings = new WindowsSettings
        {
            RepositoryDisplayLimit = 2,
            RepositorySortKey = RepositorySortKey.PullRequests,
            Repositories =
            [
                new RepositoryRef { Owner = "owner", Name = "one", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "owner", Name = "two", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "owner", Name = "three", Visibility = RepositoryVisibility.Visible },
            ],
        };
        var statuses = new[]
        {
            Status("owner/one", pulls: 1),
            Status("owner/two", pulls: 8),
            Status("owner/three", pulls: 3),
        };

        var displayed = WindowsRepositoryDisplay.Apply(statuses, settings);

        Assert.Equal(["owner/two", "owner/three"], displayed.Select(status => status.Repository.FullName));
    }

    [Fact]
    public void NormalizeSettings_clamps_repository_display_limit_and_preserves_sort_key()
    {
        var settings = new WindowsSettings
        {
            RepositoryDisplayLimit = 0,
            RepositorySortKey = RepositorySortKey.Stars,
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal(1, settings.RepositoryDisplayLimit);
        Assert.Equal(RepositorySortKey.Stars, settings.RepositorySortKey);
    }

    private static RepositoryStatus Status(
        string fullName,
        int issues = 0,
        int pulls = 0,
        int stars = 0,
        DateTimeOffset? pushedAt = null)
    {
        var parts = fullName.Split('/', 2);
        return new RepositoryStatus(
            new RepositoryRef { Owner = parts[0], Name = parts[1] },
            Stars: stars,
            Forks: 0,
            IssueCount: issues,
            PullRequestCount: pulls,
            DefaultBranch: "main",
            PushedAt: pushedAt,
            LatestRun: null,
            LatestRelease: null,
            RecentLists: RecentRepositoryLists.Empty,
            Traffic: null,
            Heatmap: null,
            Changelog: null,
            LocalStatus: null,
            ErrorMessage: null);
    }
}
