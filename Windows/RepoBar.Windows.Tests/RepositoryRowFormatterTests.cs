using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class RepositoryRowFormatterTests
{
    [Fact]
    public void BuildLabel_includes_repository_status_signals()
    {
        var local = new LocalGitRepositoryStatus(
            Path: @"C:\Projects\name",
            Name: "name",
            FullName: "owner/name",
            Branch: "main",
            IsClean: true,
            AheadCount: 0,
            BehindCount: 2,
            SyncState: LocalSyncState.Behind,
            DirtyCounts: LocalDirtyCounts.Empty,
            DirtyFiles: [],
            WorktreeName: null,
            UpstreamBranch: "origin/main");
        var status = new RepositoryStatus(
            new RepositoryRef { Owner = "owner", Name = "name" },
            Stars: 1234,
            Forks: 56,
            IssueCount: 7,
            PullRequestCount: 8,
            DefaultBranch: "main",
            PushedAt: new DateTimeOffset(2026, 6, 1, 12, 30, 0, TimeSpan.Zero),
            LatestRun: new WorkflowRunStatus("completed", "success", "https://github.example/actions/1", DateTimeOffset.UtcNow),
            LatestRelease: new ReleaseStatus("v1.2.3", "https://github.example/releases/v1.2.3", DateTimeOffset.UtcNow),
            RecentLists: RecentRepositoryLists.Empty,
            Traffic: new TrafficStatus(42, 12, 8, 3),
            Heatmap: new HeatmapStatus(99, 4, null, DateTimeOffset.UtcNow, WindowsHeatmapSpan.TwelveMonths),
            Changelog: null,
            LocalStatus: local,
            ErrorMessage: null);

        var label = RepositoryRowFormatter.BuildLabel(status);

        Assert.Contains("[ok] owner/name", label);
        Assert.Contains("7 issues", label);
        Assert.Contains("8 PRs", label);
        Assert.Contains("CI success", label);
        Assert.Contains("release v1.2.3", label);
        Assert.Contains("1,234 stars", label);
        Assert.Contains("56 forks", label);
        Assert.Contains("local Behind 2", label);
        Assert.Contains("traffic 42 views, 12 unique", label);
        Assert.Contains("8 clones, 3 unique", label);
        Assert.Contains("heatmap 99 commits", label);
        Assert.Contains("pushed", label);
    }

    [Fact]
    public void BuildLabel_marks_failing_repository_rows()
    {
        var label = RepositoryRowFormatter.BuildLabel(RepositoryStatus.Failed(
            new RepositoryRef { Owner = "owner", Name = "broken" },
            localStatus: null,
            errorMessage: "boom"));

        Assert.StartsWith("[!] owner/broken", label);
    }

    [Fact]
    public void BuildLabel_hides_heatmap_when_row_display_is_disabled()
    {
        var status = new RepositoryStatus(
            new RepositoryRef { Owner = "owner", Name = "name" },
            Stars: 0,
            Forks: 0,
            IssueCount: 1,
            PullRequestCount: 2,
            DefaultBranch: "main",
            PushedAt: null,
            LatestRun: null,
            LatestRelease: null,
            RecentLists: RecentRepositoryLists.Empty,
            Traffic: null,
            Heatmap: new HeatmapStatus(99, 4, null, DateTimeOffset.UtcNow, WindowsHeatmapSpan.ThreeMonths),
            Changelog: null,
            LocalStatus: null,
            ErrorMessage: null);

        var label = RepositoryRowFormatter.BuildLabel(
            status,
            new WindowsSettings { HeatmapDisplay = WindowsHeatmapDisplay.Submenu });

        Assert.DoesNotContain("heatmap", label);
    }
}
