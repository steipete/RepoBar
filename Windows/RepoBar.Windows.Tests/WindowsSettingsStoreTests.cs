using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsSettingsStoreTests
{
    [Fact]
    public void VisibleRepositories_keeps_configured_order_with_pinned_first()
    {
        var store = CreateStore(new WindowsSettings
        {
            Repositories =
            [
                Repo("owner/visible-b", RepositoryVisibility.Visible),
                Repo("owner/pinned-b", RepositoryVisibility.Pinned),
                Repo("owner/hidden", RepositoryVisibility.Hidden),
                Repo("owner/visible-a", RepositoryVisibility.Visible),
                Repo("owner/pinned-a", RepositoryVisibility.Pinned),
            ],
        });

        Assert.Equal(
            ["owner/pinned-b", "owner/pinned-a", "owner/visible-b", "owner/visible-a"],
            store.VisibleRepositories.Select(repository => repository.FullName));
    }

    [Fact]
    public void ReplaceRepositories_preserves_user_order_and_deduplicates_first_entry()
    {
        var store = CreateStore(new WindowsSettings());

        store.ReplaceRepositories(
        [
            Repo("owner/second", RepositoryVisibility.Visible),
            Repo("owner/first", RepositoryVisibility.Pinned),
            Repo("owner/second", RepositoryVisibility.Pinned),
        ]);

        Assert.Equal(
            ["owner/second", "owner/first"],
            store.Settings.Repositories.Select(repository => repository.FullName));
        Assert.Equal(RepositoryVisibility.Visible, store.Settings.Repositories[0].Visibility);
    }

    [Fact]
    public void MoveRepository_reorders_within_visible_bucket_and_persists()
    {
        var store = CreateStore(new WindowsSettings
        {
            Repositories =
            [
                Repo("owner/pinned-a", RepositoryVisibility.Pinned),
                Repo("owner/visible-a", RepositoryVisibility.Visible),
                Repo("owner/pinned-b", RepositoryVisibility.Pinned),
                Repo("owner/visible-b", RepositoryVisibility.Visible),
            ],
        });

        Assert.True(store.CanMoveRepository("owner/pinned-b", -1));
        Assert.True(store.MoveRepository("owner/pinned-b", -1));
        Assert.False(store.CanMoveRepository("owner/pinned-b", -1));
        Assert.False(store.MoveRepository("owner/pinned-b", -1));
        Assert.True(store.MoveRepository("owner/visible-a", 1));

        Assert.Equal(
            ["owner/pinned-b", "owner/pinned-a", "owner/visible-b", "owner/visible-a"],
            store.VisibleRepositories.Select(repository => repository.FullName));
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(2, 2)]
    [InlineData(120, 60)]
    public void NormalizeSettings_clamps_local_fetch_interval(int configured, int expected)
    {
        var settings = new WindowsSettings
        {
            LocalProjectsFetchIntervalMinutes = configured,
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal(expected, settings.LocalProjectsFetchIntervalMinutes);
    }

    [Fact]
    public void NormalizeSettings_resets_unknown_log_verbosity()
    {
        var settings = new WindowsSettings
        {
            LoggingVerbosity = (WindowsLogVerbosity)999,
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal(WindowsLogVerbosity.Info, settings.LoggingVerbosity);
    }

    [Fact]
    public void SetRepositoryMenuScope_persists_scope_changes()
    {
        var store = CreateStore(new WindowsSettings());

        Assert.True(store.SetRepositoryMenuScope(RepositoryMenuScope.Local));
        Assert.Equal(RepositoryMenuScope.Local, store.Settings.RepositoryMenuScope);
        Assert.False(store.SetRepositoryMenuScope(RepositoryMenuScope.Local));
        Assert.False(store.SetRepositoryMenuScope((RepositoryMenuScope)999));
    }

    [Fact]
    public void SetRepositorySortKey_persists_sort_changes()
    {
        var store = CreateStore(new WindowsSettings());

        Assert.True(store.SetRepositorySortKey(RepositorySortKey.Name));
        Assert.Equal(RepositorySortKey.Name, store.Settings.RepositorySortKey);
        Assert.False(store.SetRepositorySortKey(RepositorySortKey.Name));
        Assert.False(store.SetRepositorySortKey((RepositorySortKey)999));
    }

    private static WindowsSettingsStore CreateStore(WindowsSettings settings)
    {
        var settingsPath = Path.Combine(Path.GetTempPath(), $"repobar-settings-{Guid.NewGuid():N}.json");
        WindowsSettingsStore.NormalizeSettings(settings);
        return new WindowsSettingsStore(settingsPath, settings);
    }

    private static RepositoryRef Repo(string fullName, RepositoryVisibility visibility)
    {
        var parts = fullName.Split('/', 2);
        return new RepositoryRef
        {
            Owner = parts[0],
            Name = parts[1],
            Visibility = visibility,
        };
    }
}
