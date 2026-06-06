namespace RepoBar.Windows;

internal static class WindowsGlobalActivity
{
    public const int DefaultLimit = 10;

    public static IReadOnlyList<WindowsGlobalActivityItem> FromStatuses(
        IReadOnlyList<RepositoryStatus> statuses,
        int limit = DefaultLimit)
    {
        return statuses
            .SelectMany((status, statusIndex) => status.RecentLists.Activity.Select((activity, activityIndex) => new
            {
                status.Repository,
                Activity = activity,
                StatusIndex = statusIndex,
                ActivityIndex = activityIndex,
            }))
            .OrderByDescending(item => item.Activity.UpdatedAt ?? DateTimeOffset.MinValue)
            .ThenBy(item => item.StatusIndex)
            .ThenBy(item => item.ActivityIndex)
            .Take(Math.Clamp(limit, 1, 100))
            .Select(item => new WindowsGlobalActivityItem(item.Repository, item.Activity))
            .ToArray();
    }
}

internal sealed record WindowsGlobalActivityItem(RepositoryRef Repository, GitHubListItem Activity)
{
    public string Title => $"{Repository.FullName}: {Activity.Title}";
    public string? Url => Activity.Url;
    public string? Subtitle => Activity.Subtitle;
}

internal static class WindowsGlobalCommits
{
    public const int DefaultLimit = 10;

    public static IReadOnlyList<WindowsGlobalCommitItem> FromStatuses(
        IReadOnlyList<RepositoryStatus> statuses,
        int limit = DefaultLimit)
    {
        return statuses
            .SelectMany((status, statusIndex) => status.RecentLists.Commits.Select((commit, commitIndex) => new
            {
                status.Repository,
                Commit = commit,
                StatusIndex = statusIndex,
                CommitIndex = commitIndex,
            }))
            .OrderByDescending(item => item.Commit.UpdatedAt ?? DateTimeOffset.MinValue)
            .ThenBy(item => item.StatusIndex)
            .ThenBy(item => item.CommitIndex)
            .Take(Math.Clamp(limit, 1, 100))
            .Select(item => new WindowsGlobalCommitItem(item.Repository, item.Commit))
            .ToArray();
    }
}

internal sealed record WindowsGlobalCommitItem(RepositoryRef Repository, GitHubListItem Commit)
{
    public string Title => $"{Repository.FullName}: {Commit.Title}";
    public string? Url => Commit.Url;
    public string? Subtitle => Commit.Subtitle;
}
