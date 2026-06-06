using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class GitHubReferenceClipboardMonitorTests
{
    [Fact]
    public void Observe_ignores_clipboard_when_disabled()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings(enableMonitor: false);

        Assert.Null(monitor.Observe("see #12", settings));
    }

    [Fact]
    public void Observe_baselines_initial_clipboard_without_notifying()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();

        Assert.Null(monitor.Observe("see #12", settings));

        var notification = monitor.Observe("see #13", settings);

        Assert.NotNull(notification);
        Assert.Equal("see #13", notification.IssueNavigatorText);
        Assert.Equal("steipete/RepoBar #13", notification.DisplayText);
        Assert.Single(notification.References);
    }

    [Fact]
    public void Observe_uses_pinned_repository_for_bare_references()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();
        settings.Repositories =
        [
            new RepositoryRef { Owner = "openclaw", Name = "openclaw", Visibility = RepositoryVisibility.Visible },
            new RepositoryRef { Owner = "steipete", Name = "RepoBar", Visibility = RepositoryVisibility.Pinned },
        ];

        Assert.Null(monitor.Observe("baseline", settings));

        var notification = monitor.Observe("see #42", settings);

        Assert.NotNull(notification);
        Assert.Contains(notification.References, reference =>
            reference.RepositoryFullName == "steipete/RepoBar" && reference.Number == 42);
    }

    [Fact]
    public void Observe_suppresses_duplicate_reference_sets_until_non_reference_text()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();

        Assert.Null(monitor.Observe("baseline", settings));
        Assert.NotNull(monitor.Observe("see #9", settings));
        Assert.Null(monitor.Observe("same reference #9 again", settings));
        Assert.Null(monitor.Observe("plain text", settings));

        Assert.NotNull(monitor.Observe("see #9", settings));
    }

    [Fact]
    public void Observe_reports_multiple_references()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();

        Assert.Null(monitor.Observe("baseline", settings));

        var notification = monitor.Observe("steipete/RepoBar#10 and openclaw/openclaw PR #11", settings);

        Assert.NotNull(notification);
        Assert.Equal("2 GitHub references copied", notification.DisplayText);
        Assert.Equal(2, notification.References.Count);
    }

    private static WindowsSettings Settings(bool enableMonitor = true)
    {
        return new WindowsSettings
        {
            EnableGitHubReferenceMonitor = enableMonitor,
            Repositories =
            [
                new RepositoryRef { Owner = "steipete", Name = "RepoBar", Visibility = RepositoryVisibility.Pinned },
            ],
        };
    }
}
