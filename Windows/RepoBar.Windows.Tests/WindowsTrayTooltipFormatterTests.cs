using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsTrayTooltipFormatterTests
{
    [Fact]
    public void Build_includes_compact_rate_limits_when_enabled()
    {
        var text = WindowsTrayTooltipFormatter.Build(
            visibleRepositoryCount: 6,
            localRepositoryCount: 2,
            TrayHealth.Healthy,
            [
                new GitHubRateLimitSnapshot(5000, 4999, null, "core"),
                new GitHubRateLimitSnapshot(5000, 2500, null, "graphql"),
            ],
            showRateLimits: true);

        Assert.Contains("healthy", text);
        Assert.Contains("core 100%", text);
        Assert.Contains("graphql 50%", text);
        Assert.True(text.Length <= 63);
    }

    [Fact]
    public void Build_omits_rate_limits_when_disabled()
    {
        var text = WindowsTrayTooltipFormatter.Build(
            visibleRepositoryCount: 3,
            localRepositoryCount: 1,
            TrayHealth.Busy,
            [new GitHubRateLimitSnapshot(5000, 0, null, "core")],
            showRateLimits: false);

        Assert.Equal("RepoBar - 3 repos / 1 local - running", text);
    }

    [Fact]
    public void Build_truncates_long_tooltips_for_notify_icon()
    {
        var text = WindowsTrayTooltipFormatter.Build(
            visibleRepositoryCount: 10_000,
            localRepositoryCount: 10_000,
            TrayHealth.Failing,
            [
                new GitHubRateLimitSnapshot(5_000, 4_999, null, "graphql"),
                new GitHubRateLimitSnapshot(5_000, 4_999, null, "integration-manifest"),
            ],
            showRateLimits: true);

        Assert.True(text.Length <= 63);
        Assert.EndsWith("...", text);
    }
}
