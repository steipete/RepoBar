namespace RepoBar.Windows;

internal static class RepositoryRowFormatter
{
    public static string BuildLabel(RepositoryStatus status, WindowsSettings? settings = null)
    {
        var parts = new List<string>
        {
            $"{HealthPrefix(status.Health)} {status.Repository.FullName}",
            $"{status.IssueCount:n0} issues",
            $"{status.PullRequestCount:n0} PRs",
        };

        if (status.LatestRun != null)
        {
            parts.Add($"CI {status.LatestRun.DisplayText}");
        }
        if (status.LatestRelease is { TagName.Length: > 0 })
        {
            parts.Add($"release {status.LatestRelease.TagName}");
        }
        if (status.Stars > 0 || status.Forks > 0)
        {
            parts.Add($"{status.Stars:n0} stars");
            parts.Add($"{status.Forks:n0} forks");
        }
        if (status.LocalStatus != null)
        {
            parts.Add($"local {status.LocalStatus.SyncDetail}");
        }
        if (status.Traffic is { DisplayText.Length: > 0 })
        {
            parts.Add($"traffic {status.Traffic.DisplayText}");
        }
        if (status.Heatmap != null && (settings?.HeatmapDisplay ?? WindowsHeatmapDisplay.RowAndSubmenu).ShowsRow())
        {
            parts.Add($"heatmap {status.Heatmap.TotalCommits:n0} commits");
        }
        if (status.PushedAt != null)
        {
            parts.Add($"pushed {status.PushedAt.Value.LocalDateTime:g}");
        }

        return string.Join(" | ", parts);
    }

    private static string HealthPrefix(TrayHealth health)
    {
        return health switch
        {
            TrayHealth.Healthy => "[ok]",
            TrayHealth.Busy => "[..]",
            TrayHealth.Failing => "[!]",
            _ => "[ ]",
        };
    }
}
