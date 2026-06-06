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

    [Fact]
    public void NormalizeSettings_migrates_legacy_repositories_to_active_account()
    {
        var settings = new WindowsSettings
        {
            ActiveAccountId = "work",
            Accounts =
            [
                Account("default", "Default"),
                Account("work", "Work"),
            ],
            Repositories =
            [
                Repo("owner/legacy", RepositoryVisibility.Pinned),
            ],
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal(["owner/legacy"], settings.RepositoriesByAccount["work"].Select(repository => repository.FullName));
        Assert.Empty(settings.RepositoriesByAccount["default"]);
        Assert.Equal(["owner/legacy"], settings.Repositories.Select(repository => repository.FullName));
    }

    [Fact]
    public void SetActiveAccount_switches_visible_repository_list()
    {
        var store = CreateStore(new WindowsSettings
        {
            ActiveAccountId = "default",
            Accounts =
            [
                Account("default", "Default"),
                Account("work", "Work"),
            ],
            RepositoriesByAccount = new Dictionary<string, List<RepositoryRef>>(StringComparer.OrdinalIgnoreCase)
            {
                ["default"] = [Repo("personal/project", RepositoryVisibility.Pinned)],
                ["work"] = [Repo("work/project", RepositoryVisibility.Pinned)],
            },
        });

        Assert.Equal(["personal/project"], store.VisibleRepositories.Select(repository => repository.FullName));

        Assert.True(store.SetActiveAccount("work"));

        Assert.Equal(["work/project"], store.VisibleRepositories.Select(repository => repository.FullName));
        Assert.Equal(["work/project"], store.Settings.Repositories.Select(repository => repository.FullName));
    }

    [Fact]
    public void NormalizeSettings_sanitizes_active_account_id_before_matching_profiles()
    {
        var settings = new WindowsSettings
        {
            ActiveAccountId = "Work Account",
            Accounts =
            [
                Account("default", "Default"),
                Account("Work Account", "Work"),
            ],
            RepositoriesByAccount = new Dictionary<string, List<RepositoryRef>>(StringComparer.OrdinalIgnoreCase)
            {
                ["default"] = [Repo("personal/project", RepositoryVisibility.Pinned)],
                ["Work Account"] = [Repo("work/project", RepositoryVisibility.Pinned)],
            },
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal("work-account", settings.ActiveAccountId);
        Assert.Equal("Work", settings.GetActiveAccount().Label);
        Assert.Equal(["work/project"], settings.Repositories.Select(repository => repository.FullName));
        Assert.Equal(["work/project"], settings.RepositoriesByAccount["work-account"].Select(repository => repository.FullName));
    }

    [Fact]
    public void NormalizeSettings_ignores_null_accounts_and_repositories_from_scriptable_json()
    {
        var settings = new WindowsSettings
        {
            ActiveAccountId = "work",
            Accounts =
            [
                null!,
                Account("work", "Work"),
            ],
            Repositories =
            [
                null!,
                Repo("owner/legacy", RepositoryVisibility.Pinned),
            ],
            RepositoriesByAccount = new Dictionary<string, List<RepositoryRef>>(StringComparer.OrdinalIgnoreCase)
            {
                ["work"] = [null!, Repo("work/project", RepositoryVisibility.Pinned)],
            },
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal(["work"], settings.Accounts.Select(account => account.Id));
        Assert.Equal(["work/project"], settings.Repositories.Select(repository => repository.FullName));
        Assert.Equal(["work/project"], settings.RepositoriesByAccount["work"].Select(repository => repository.FullName));
    }

    [Fact]
    public void NormalizeSettings_defaults_null_active_account_id_without_crashing()
    {
        var settings = new WindowsSettings
        {
            ActiveAccountId = null!,
            Accounts =
            [
                Account("default", "Default"),
                Account("work", "Work"),
            ],
            RepositoriesByAccount = new Dictionary<string, List<RepositoryRef>>(StringComparer.OrdinalIgnoreCase)
            {
                ["default"] = [Repo("personal/project", RepositoryVisibility.Pinned)],
                ["work"] = [Repo("work/project", RepositoryVisibility.Pinned)],
            },
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal("default", settings.ActiveAccountId);
        Assert.Equal(["personal/project"], settings.Repositories.Select(repository => repository.FullName));
    }

    [Fact]
    public void ReplaceRepositories_updates_active_account_only()
    {
        var store = CreateStore(new WindowsSettings
        {
            ActiveAccountId = "default",
            Accounts =
            [
                Account("default", "Default"),
                Account("work", "Work"),
            ],
            RepositoriesByAccount = new Dictionary<string, List<RepositoryRef>>(StringComparer.OrdinalIgnoreCase)
            {
                ["default"] = [Repo("personal/old", RepositoryVisibility.Pinned)],
                ["work"] = [Repo("work/project", RepositoryVisibility.Pinned)],
            },
        });

        store.ReplaceRepositories([Repo("personal/new", RepositoryVisibility.Visible)]);

        Assert.Equal(["personal/new"], store.Settings.RepositoriesByAccount["default"].Select(repository => repository.FullName));
        Assert.Equal(["work/project"], store.Settings.RepositoriesByAccount["work"].Select(repository => repository.FullName));
    }

    [Fact]
    public void SetVisibility_applies_to_active_account_repository_list()
    {
        var store = CreateStore(new WindowsSettings
        {
            ActiveAccountId = "work",
            Accounts =
            [
                Account("default", "Default"),
                Account("work", "Work"),
            ],
            RepositoriesByAccount = new Dictionary<string, List<RepositoryRef>>(StringComparer.OrdinalIgnoreCase)
            {
                ["default"] = [Repo("personal/project", RepositoryVisibility.Pinned)],
                ["work"] = [],
            },
        });

        store.SetVisibility("work/project", RepositoryVisibility.Pinned);

        Assert.Equal(["work/project"], store.Settings.RepositoriesByAccount["work"].Select(repository => repository.FullName));
        Assert.Equal(["personal/project"], store.Settings.RepositoriesByAccount["default"].Select(repository => repository.FullName));
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
    public void NormalizeSettings_resets_unknown_actions_plan_tier()
    {
        var settings = new WindowsSettings
        {
            ActionsPlanTier = (WindowsActionsPlanTier)999,
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal(WindowsActionsPlanTier.Free, settings.ActionsPlanTier);
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

    [Fact]
    public void SetRepositoryOwnerFilter_normalizes_and_persists_owner_changes()
    {
        var store = CreateStore(new WindowsSettings
        {
            RepositoryOwnerFilter = ["other"],
        });

        Assert.True(store.SetRepositoryOwnerFilter([" OctoCat ", "octocat", "RepoBar"]));
        Assert.Equal(["octocat", "repobar"], store.Settings.RepositoryOwnerFilter);
        Assert.False(store.SetRepositoryOwnerFilter(["repobar", "octocat"]));
        Assert.True(store.SetRepositoryOwnerFilter([]));
        Assert.Empty(store.Settings.RepositoryOwnerFilter);
    }

    [Fact]
    public void NormalizeSettings_normalizes_actions_monitored_owners()
    {
        var settings = new WindowsSettings
        {
            ActionsMonitoredOwners = [" RepoBar ", "octocat", "repobar"],
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal(["octocat", "repobar"], settings.ActionsMonitoredOwners);
    }

    [Fact]
    public void NormalizeSettings_ignores_null_owner_filter_entries_from_scriptable_json()
    {
        var settings = new WindowsSettings
        {
            RepositoryOwnerFilter = [null!, " OctoCat ", ""],
            ActionsMonitoredOwners = [null!, " RepoBar ", "repobar"],
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal(["octocat"], settings.RepositoryOwnerFilter);
        Assert.Equal(["repobar"], settings.ActionsMonitoredOwners);
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

    private static WindowsAccountProfile Account(string id, string label)
    {
        return new WindowsAccountProfile
        {
            Id = id,
            Label = label,
            GitHubHost = "github.com",
            TokenEnvironmentVariable = $"REPOBAR_{id.ToUpperInvariant()}_TOKEN",
        };
    }
}
