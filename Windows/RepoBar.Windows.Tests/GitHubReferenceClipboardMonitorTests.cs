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
            reference.RepositoryFullName == "steipete/RepoBar" && reference.Number == 42L);
    }

    [Fact]
    public void Observe_prefers_local_repository_context_from_copied_path()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();
        var localGitIndex = LocalIndex(LocalRepository(@"C:\Projects\clawhub", "openclaw/clawhub"));

        Assert.Null(monitor.Observe("baseline", settings, localGitIndex));

        var notification = monitor.Observe(@"PS C:\Projects\clawhub> #908", settings, localGitIndex);

        Assert.NotNull(notification);
        Assert.Equal("openclaw/clawhub #908", notification.DisplayText);
        Assert.Contains(notification.References, reference =>
            reference.RepositoryFullName == "openclaw/clawhub" && reference.Number == 908L);
    }

    [Fact]
    public void Observe_resolves_local_repository_name_shorthand()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();
        var localGitIndex = LocalIndex(LocalRepository(@"C:\Projects\clawhub", "openclaw/clawhub"));

        Assert.Null(monitor.Observe("baseline", settings, localGitIndex));

        var notification = monitor.Observe("clawhub#908", settings, localGitIndex);

        Assert.NotNull(notification);
        Assert.Equal("openclaw/clawhub #908", notification.DisplayText);
    }

    [Fact]
    public void Observe_ignores_local_repository_context_from_other_host()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();
        var localGitIndex = LocalIndex(LocalRepository(@"C:\Projects\clawhub", "openclaw/clawhub", "github.enterprise.test"));

        Assert.Null(monitor.Observe("baseline", settings, localGitIndex));

        var notification = monitor.Observe(@"PS C:\Projects\clawhub> #908", settings, localGitIndex);

        Assert.NotNull(notification);
        Assert.Equal("steipete/RepoBar #908", notification.DisplayText);
    }

    [Fact]
    public void Observe_ignores_local_repository_name_shorthand_from_other_host()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();
        var localGitIndex = LocalIndex(LocalRepository(@"C:\Projects\clawhub", "openclaw/clawhub", "github.enterprise.test"));

        Assert.Null(monitor.Observe("baseline", settings, localGitIndex));

        Assert.Null(monitor.Observe("clawhub#908", settings, localGitIndex));
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

    [Fact]
    public void Observe_resolves_unique_repository_name_shorthand()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();
        settings.Repositories =
        [
            new RepositoryRef { Owner = "openclaw", Name = "discrawl", Visibility = RepositoryVisibility.Visible },
            new RepositoryRef { Owner = "steipete", Name = "RepoBar", Visibility = RepositoryVisibility.Pinned },
        ];

        Assert.Null(monitor.Observe("baseline", settings));

        var notification = monitor.Observe("discrawl#64", settings);

        Assert.NotNull(notification);
        Assert.Equal("openclaw/discrawl #64", notification.DisplayText);
        Assert.Contains(notification.References, reference =>
            reference.RepositoryFullName == "openclaw/discrawl" && reference.Number == 64L);
    }

    [Fact]
    public void Observe_displays_commit_hash_references()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();

        Assert.Null(monitor.Observe("baseline", settings));

        var notification = monitor.Observe("commit ffd212ca43abcdef", settings);

        Assert.NotNull(notification);
        Assert.Equal("steipete/RepoBar @ffd212ca43", notification.DisplayText);
        Assert.Contains(notification.References, reference =>
            reference.RepositoryFullName == "steipete/RepoBar" &&
            reference.Kind == "commit" &&
            reference.ReferenceValue == "ffd212ca43abcdef");
    }

    [Fact]
    public void Observe_treats_same_reference_on_different_hosts_as_distinct()
    {
        var monitor = new GitHubReferenceClipboardMonitor();
        var settings = Settings();

        Assert.Null(monitor.Observe("baseline", settings));
        Assert.NotNull(monitor.Observe("https://github.com/owner/repo/issues/9", settings));

        var notification = monitor.Observe("https://github.enterprise.test/owner/repo/issues/9", settings);

        Assert.NotNull(notification);
        Assert.Contains(notification.References, reference => reference.Host == "github.enterprise.test");
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

    private static LocalGitIndex LocalIndex(params LocalGitRepositoryStatus[] repositories)
    {
        return new LocalGitIndex(repositories, [], "github.com");
    }

    private static LocalGitRepositoryStatus LocalRepository(
        string path,
        string fullName,
        string host = "github.com")
    {
        return new LocalGitRepositoryStatus(
            path,
            fullName.Split('/').Last(),
            fullName,
            "main",
            true,
            null,
            null,
            LocalSyncState.Synced,
            LocalDirtyCounts.Empty,
            [],
            null,
            "origin/main",
            host);
    }
}
