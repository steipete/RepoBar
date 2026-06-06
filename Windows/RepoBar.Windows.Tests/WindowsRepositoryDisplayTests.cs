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
    public void Apply_filters_normal_repositories_by_owner_and_issue_or_pull_state()
    {
        var settings = new WindowsSettings
        {
            RepositoryDisplayLimit = 10,
            RepositoryOwnerFilter = ["target"],
            ShowOnlyRepositoriesWithIssues = true,
            ShowOnlyRepositoriesWithPullRequests = true,
            Repositories =
            [
                new RepositoryRef { Owner = "other", Name = "pinned", Visibility = RepositoryVisibility.Pinned },
                new RepositoryRef { Owner = "target", Name = "issues", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "target", Name = "pulls", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "target", Name = "quiet", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "other", Name = "issues", Visibility = RepositoryVisibility.Visible },
            ],
        };
        var statuses = new[]
        {
            Status("target/quiet"),
            Status("other/issues", issues: 4),
            Status("target/pulls", pulls: 2),
            Status("target/issues", issues: 3),
            Status("other/pinned"),
        };

        var displayed = WindowsRepositoryDisplay.Apply(statuses, settings);

        Assert.Equal(["other/pinned", "target/issues", "target/pulls"], displayed.Select(status => status.Repository.FullName));
    }

    [Fact]
    public void Apply_pinned_scope_returns_only_pinned_repositories_in_configured_order()
    {
        var settings = new WindowsSettings
        {
            RepositoryDisplayLimit = 10,
            RepositoryMenuScope = RepositoryMenuScope.Pinned,
            Repositories =
            [
                new RepositoryRef { Owner = "owner", Name = "second", Visibility = RepositoryVisibility.Pinned },
                new RepositoryRef { Owner = "owner", Name = "visible", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "owner", Name = "first", Visibility = RepositoryVisibility.Pinned },
            ],
        };
        var statuses = new[]
        {
            Status("owner/first"),
            Status("owner/visible", issues: 4),
            Status("owner/second"),
        };

        var displayed = WindowsRepositoryDisplay.Apply(statuses, settings);

        Assert.Equal(["owner/second", "owner/first"], displayed.Select(status => status.Repository.FullName));
    }

    [Fact]
    public void Apply_local_scope_returns_only_repositories_with_local_status()
    {
        var settings = new WindowsSettings
        {
            RepositoryDisplayLimit = 10,
            RepositoryMenuScope = RepositoryMenuScope.Local,
            Repositories =
            [
                new RepositoryRef { Owner = "owner", Name = "remote", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "owner", Name = "local-b", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "owner", Name = "local-a", Visibility = RepositoryVisibility.Pinned },
            ],
        };
        var statuses = new[]
        {
            Status("owner/remote"),
            Status("owner/local-b", local: true),
            Status("owner/local-a", local: true),
        };

        var displayed = WindowsRepositoryDisplay.Apply(statuses, settings);

        Assert.Equal(["owner/local-a", "owner/local-b"], displayed.Select(status => status.Repository.FullName));
    }

    [Fact]
    public void Apply_work_scope_filters_normal_repositories_with_issues_or_pull_requests_and_keeps_pinned()
    {
        var settings = new WindowsSettings
        {
            RepositoryDisplayLimit = 10,
            RepositoryMenuScope = RepositoryMenuScope.Work,
            Repositories =
            [
                new RepositoryRef { Owner = "owner", Name = "quiet-pinned", Visibility = RepositoryVisibility.Pinned },
                new RepositoryRef { Owner = "owner", Name = "issues", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "owner", Name = "pulls", Visibility = RepositoryVisibility.Visible },
                new RepositoryRef { Owner = "owner", Name = "quiet", Visibility = RepositoryVisibility.Visible },
            ],
        };
        var statuses = new[]
        {
            Status("owner/quiet"),
            Status("owner/pulls", pulls: 1),
            Status("owner/issues", issues: 2),
            Status("owner/quiet-pinned"),
        };

        var displayed = WindowsRepositoryDisplay.Apply(statuses, settings);

        Assert.Equal(["owner/quiet-pinned", "owner/issues", "owner/pulls"], displayed.Select(status => status.Repository.FullName));
    }

    [Fact]
    public void NormalizeSettings_clamps_repository_display_limit_normalizes_owner_filter_and_preserves_sort_key()
    {
        var settings = new WindowsSettings
        {
            RepositoryDisplayLimit = 0,
            RepositorySortKey = RepositorySortKey.Stars,
            RepositoryOwnerFilter = [" Beta ", "alpha", "", "ALPHA"],
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal(1, settings.RepositoryDisplayLimit);
        Assert.Equal(RepositorySortKey.Stars, settings.RepositorySortKey);
        Assert.Equal(["alpha", "beta"], settings.RepositoryOwnerFilter);
    }

    private static RepositoryStatus Status(
        string fullName,
        int issues = 0,
        int pulls = 0,
        int stars = 0,
        DateTimeOffset? pushedAt = null,
        bool local = false)
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
            LocalStatus: local ? LocalStatus(fullName) : null,
            ErrorMessage: null);
    }

    private static LocalGitRepositoryStatus LocalStatus(string fullName)
    {
        var parts = fullName.Split('/', 2);
        return new LocalGitRepositoryStatus(
            Path: Path.Combine("C:\\Projects", parts[1]),
            Name: parts[1],
            FullName: fullName,
            Branch: "main",
            IsClean: true,
            AheadCount: 0,
            BehindCount: 0,
            SyncState: LocalSyncState.Synced,
            DirtyCounts: LocalDirtyCounts.Empty,
            DirtyFiles: [],
            WorktreeName: null,
            UpstreamBranch: "origin/main");
    }
}
