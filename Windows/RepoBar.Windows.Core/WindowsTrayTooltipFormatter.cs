namespace RepoBar.Windows;

internal static class WindowsTrayTooltipFormatter
{
    private const int MaxTooltipLength = 63;

    public static string Build(
        int visibleRepositoryCount,
        int localRepositoryCount,
        TrayHealth health,
        IReadOnlyList<GitHubRateLimitSnapshot> rateLimits,
        bool showRateLimits)
    {
        var summary = health switch
        {
            TrayHealth.Healthy => "healthy",
            TrayHealth.Busy => "running",
            TrayHealth.Failing => "needs attention",
            _ => "ready",
        };
        var text = $"RepoBar - {visibleRepositoryCount} repos / {localRepositoryCount} local - {summary}";
        if (showRateLimits && rateLimits.Count > 0)
        {
            text = $"{text} - {RateLimitText(rateLimits)}";
        }

        return Truncate(text);
    }

    private static string RateLimitText(IReadOnlyList<GitHubRateLimitSnapshot> rateLimits)
    {
        var parts = rateLimits
            .Take(2)
            .Select(snapshot =>
            {
                var resource = string.IsNullOrWhiteSpace(snapshot.Resource) ? "core" : snapshot.Resource;
                return snapshot.PercentRemaining is { } percent
                    ? $"{resource} {percent}%"
                    : $"{resource} {snapshot.Remaining?.ToString() ?? "?"}/{snapshot.Limit?.ToString() ?? "?"}";
            });
        return string.Join(", ", parts);
    }

    private static string Truncate(string value)
    {
        return value.Length <= MaxTooltipLength
            ? value
            : value[..(MaxTooltipLength - 3)] + "...";
    }
}
