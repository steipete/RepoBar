using System.Text.Json;
using System.Text.Json.Serialization;

namespace RepoBar.Windows;

internal sealed class WindowsSettings
{
    public string GitHubHost { get; set; } = "github.com";
    public string TokenEnvironmentVariable { get; set; } = "REPOBAR_GITHUB_TOKEN";
    public string GitHubOAuthClientId { get; set; } = WindowsOAuthClient.DefaultClientId;
    public string GitHubOAuthClientSecretEnvironmentVariable { get; set; } = WindowsOAuthClient.DefaultClientSecretEnvironmentVariable;
    public string ActiveAccountId { get; set; } = WindowsAccountProfile.DefaultId;
    public List<WindowsAccountProfile> Accounts { get; set; } = [];
    public int RefreshIntervalMinutes { get; set; } = 5;
    public bool OpenMenuOnLeftClick { get; set; } = true;
    public bool LaunchAtLogin { get; set; }
    public bool CheckForUpdatesAutomatically { get; set; } = true;
    public bool DiscoverLocalProjects { get; set; } = true;
    public string? LocalProjectsRoot { get; set; }
    public int LocalProjectsMaxDepth { get; set; } = 3;
    public string LocalWorktreeFolderName { get; set; } = ".work";
    public WindowsTerminalPreference TerminalPreference { get; set; } = WindowsTerminalPreference.Auto;
    public bool FetchLocalProjectsBeforeStatus { get; set; } = true;
    public int LocalProjectsFetchIntervalMinutes { get; set; } = 5;
    public bool AutoSyncLocalProjects { get; set; }
    public bool ShowDirtyFilesInMenu { get; set; } = true;
    public bool EnableResponseCache { get; set; } = true;
    public string? GitHubArchiveDatabasePath { get; set; }
    public int RepositoryDisplayLimit { get; set; } = 6;
    public RepositoryMenuScope RepositoryMenuScope { get; set; } = RepositoryMenuScope.All;
    public RepositorySortKey RepositorySortKey { get; set; } = RepositorySortKey.Activity;
    public bool IncludeForkedRepositories { get; set; }
    public bool IncludeArchivedRepositories { get; set; }
    public List<string> RepositoryOwnerFilter { get; set; } = [];
    public bool ShowOnlyRepositoriesWithIssues { get; set; }
    public bool ShowOnlyRepositoriesWithPullRequests { get; set; }
    public WindowsHeatmapDisplay HeatmapDisplay { get; set; } = WindowsHeatmapDisplay.RowAndSubmenu;
    public WindowsHeatmapSpan HeatmapSpan { get; set; } = WindowsHeatmapSpan.TwelveMonths;
    public WindowsActivityScope ActivityScope { get; set; } = WindowsActivityScope.MyActivity;
    public bool ShowRateLimits { get; set; } = true;
    public bool ShowContributionSummary { get; set; } = true;
    public List<string> ActionsMonitoredOwners { get; set; } = [];
    public WindowsActionsPlanTier ActionsPlanTier { get; set; } = WindowsActionsPlanTier.Free;
    public bool DiagnosticsEnabled { get; set; }
    public WindowsLogVerbosity LoggingVerbosity { get; set; } = WindowsLogVerbosity.Info;
    public bool FileLoggingEnabled { get; set; }
    public bool EnableGitHubReferenceMonitor { get; set; }
    public WindowsMenuCustomization MenuCustomization { get; set; } = new();
    public bool EnablePullRequestNotifications { get; set; }
    public bool EnablePullRequestNewNotifications { get; set; } = true;
    public bool EnablePullRequestUpdateNotifications { get; set; } = true;
    public bool EnablePullRequestReviewRequestNotifications { get; set; }
    public bool EnablePullRequestCommentNotifications { get; set; }
    public PullRequestNotificationClickAction PullRequestNotificationClickAction { get; set; } = PullRequestNotificationClickAction.OpenInBrowser;
    public bool ShowActionsUsage { get; set; }
    public List<RepositoryRef> Repositories { get; set; } = [];
    public Dictionary<string, List<RepositoryRef>> RepositoriesByAccount { get; set; } = [];

    internal WindowsAccountProfile GetActiveAccount()
    {
        return Accounts.FirstOrDefault(account => string.Equals(account.Id, ActiveAccountId, StringComparison.OrdinalIgnoreCase)) ??
            Accounts.FirstOrDefault() ??
            WindowsAccountProfile.FromLegacy(this);
    }

    internal List<RepositoryRef> GetActiveRepositories()
    {
        var account = GetActiveAccount();
        if (RepositoriesByAccount.TryGetValue(account.Id, out var repositories))
        {
            return repositories;
        }
        if (Repositories.Count > 0)
        {
            RepositoriesByAccount[account.Id] = Repositories;
            return Repositories;
        }

        repositories = [];
        RepositoriesByAccount[account.Id] = repositories;
        return repositories;
    }
}

internal sealed class WindowsAccountProfile
{
    public const string DefaultId = "default";

    public string Id { get; set; } = DefaultId;
    public string Label { get; set; } = "Default";
    public string GitHubHost { get; set; } = "github.com";
    public string TokenEnvironmentVariable { get; set; } = "REPOBAR_GITHUB_TOKEN";
    public string GitHubOAuthClientId { get; set; } = WindowsOAuthClient.DefaultClientId;
    public string GitHubOAuthClientSecretEnvironmentVariable { get; set; } = WindowsOAuthClient.DefaultClientSecretEnvironmentVariable;

    public string DisplayName => string.IsNullOrWhiteSpace(Label) ? Id : Label;
    public bool IsValid => !string.IsNullOrWhiteSpace(Id);

    public static WindowsAccountProfile FromLegacy(WindowsSettings settings)
    {
        return new WindowsAccountProfile
        {
            Id = DefaultId,
            Label = "Default",
            GitHubHost = settings.GitHubHost,
            TokenEnvironmentVariable = settings.TokenEnvironmentVariable,
            GitHubOAuthClientId = settings.GitHubOAuthClientId,
            GitHubOAuthClientSecretEnvironmentVariable = settings.GitHubOAuthClientSecretEnvironmentVariable,
        };
    }
}

internal sealed class RepositoryRef
{
    public string Owner { get; set; } = "";
    public string Name { get; set; } = "";
    public RepositoryVisibility Visibility { get; set; } = RepositoryVisibility.Pinned;

    public string FullName => $"{Owner}/{Name}";

    public bool IsValid => !string.IsNullOrWhiteSpace(Owner) && !string.IsNullOrWhiteSpace(Name);
    public bool IsVisible => Visibility != RepositoryVisibility.Hidden;
}

internal enum RepositoryVisibility
{
    Visible,
    Pinned,
    Hidden,
}

internal enum RepositoryMenuScope
{
    All,
    Pinned,
    Local,
    Work,
}

internal enum RepositorySortKey
{
    Activity,
    Issues,
    PullRequests,
    Stars,
    Name,
}

internal enum WindowsHeatmapDisplay
{
    Hidden,
    Row,
    Submenu,
    RowAndSubmenu,
}

internal enum WindowsHeatmapSpan
{
    OneMonth,
    ThreeMonths,
    SixMonths,
    TwelveMonths,
}

internal enum WindowsActivityScope
{
    AllActivity,
    MyActivity,
}

internal enum WindowsActionsPlanTier
{
    Free,
    Pro,
    Team,
    Enterprise,
}

internal enum WindowsTerminalPreference
{
    Auto,
    WindowsTerminal,
    PowerShell,
    CommandPrompt,
}

internal static class WindowsHeatmapSettingsLabels
{
    public static string DisplayName(this WindowsHeatmapDisplay display)
    {
        return display switch
        {
            WindowsHeatmapDisplay.Hidden => "Hidden",
            WindowsHeatmapDisplay.Row => "Tray row",
            WindowsHeatmapDisplay.Submenu => "Repository submenu",
            _ => "Tray row and submenu",
        };
    }

    public static string DisplayName(this WindowsHeatmapSpan span)
    {
        return span switch
        {
            WindowsHeatmapSpan.OneMonth => "1 month",
            WindowsHeatmapSpan.ThreeMonths => "3 months",
            WindowsHeatmapSpan.SixMonths => "6 months",
            _ => "12 months",
        };
    }

    public static int Weeks(this WindowsHeatmapSpan span)
    {
        return span switch
        {
            WindowsHeatmapSpan.OneMonth => 4,
            WindowsHeatmapSpan.ThreeMonths => 13,
            WindowsHeatmapSpan.SixMonths => 26,
            _ => 52,
        };
    }

    public static bool ShowsRow(this WindowsHeatmapDisplay display)
    {
        return display is WindowsHeatmapDisplay.Row or WindowsHeatmapDisplay.RowAndSubmenu;
    }

    public static bool ShowsSubmenu(this WindowsHeatmapDisplay display)
    {
        return display is WindowsHeatmapDisplay.Submenu or WindowsHeatmapDisplay.RowAndSubmenu;
    }
}

internal static class WindowsActivityScopeLabels
{
    public static string DisplayName(this WindowsActivityScope scope)
    {
        return scope switch
        {
            WindowsActivityScope.AllActivity => "All activity",
            _ => "My activity",
        };
    }
}

internal static class WindowsActionsPlanTierLabels
{
    public static string DisplayName(this WindowsActionsPlanTier tier)
    {
        return tier switch
        {
            WindowsActionsPlanTier.Pro => "Pro",
            WindowsActionsPlanTier.Team => "Team",
            WindowsActionsPlanTier.Enterprise => "Enterprise",
            _ => "Free",
        };
    }

    public static int IncludedMinutesPerMonth(this WindowsActionsPlanTier tier)
    {
        return tier switch
        {
            WindowsActionsPlanTier.Free => 2000,
            WindowsActionsPlanTier.Pro => 3000,
            WindowsActionsPlanTier.Team => 3000,
            WindowsActionsPlanTier.Enterprise => 50000,
            _ => 2000,
        };
    }

    public static double IncludedStorageGb(this WindowsActionsPlanTier tier)
    {
        return tier switch
        {
            WindowsActionsPlanTier.Free => 0.5,
            WindowsActionsPlanTier.Pro => 1,
            WindowsActionsPlanTier.Team => 2,
            WindowsActionsPlanTier.Enterprise => 50,
            _ => 0.5,
        };
    }

    public static int ConcurrentJobs(this WindowsActionsPlanTier tier)
    {
        return tier switch
        {
            WindowsActionsPlanTier.Free => 20,
            WindowsActionsPlanTier.Pro => 40,
            WindowsActionsPlanTier.Team => 60,
            WindowsActionsPlanTier.Enterprise => 500,
            _ => 20,
        };
    }
}

internal static class WindowsTerminalPreferenceLabels
{
    public static string DisplayName(this WindowsTerminalPreference preference)
    {
        return preference switch
        {
            WindowsTerminalPreference.WindowsTerminal => "Windows Terminal",
            WindowsTerminalPreference.PowerShell => "PowerShell",
            WindowsTerminalPreference.CommandPrompt => "Command Prompt",
            _ => "Auto",
        };
    }
}

internal static class RepositorySortKeyLabels
{
    public static string DisplayName(this RepositorySortKey sortKey)
    {
        return sortKey switch
        {
            RepositorySortKey.Issues => "Most issues",
            RepositorySortKey.PullRequests => "Most PRs",
            RepositorySortKey.Stars => "Most stars",
            RepositorySortKey.Name => "Repository name",
            _ => "Latest activity",
        };
    }
}

internal static class RepositoryMenuScopeLabels
{
    public static string DisplayName(this RepositoryMenuScope scope)
    {
        return scope switch
        {
            RepositoryMenuScope.Pinned => "Pinned",
            RepositoryMenuScope.Local => "Local",
            RepositoryMenuScope.Work => "Work",
            _ => "All",
        };
    }
}

internal enum PullRequestNotificationClickAction
{
    OpenInBrowser,
    OpenIssueNavigator,
}

internal enum WindowsLogVerbosity
{
    Error,
    Warning,
    Info,
    Debug,
    Trace,
}

internal static class WindowsLogVerbosityLabels
{
    public static string DisplayName(this WindowsLogVerbosity verbosity)
    {
        return verbosity switch
        {
            WindowsLogVerbosity.Error => "Errors only",
            WindowsLogVerbosity.Warning => "Warnings",
            WindowsLogVerbosity.Debug => "Debug",
            WindowsLogVerbosity.Trace => "Trace",
            _ => "Info",
        };
    }
}

internal static class PullRequestNotificationClickActionLabels
{
    public static string DisplayName(this PullRequestNotificationClickAction action)
    {
        return action switch
        {
            PullRequestNotificationClickAction.OpenIssueNavigator => "Issue Navigator",
            _ => "Default browser",
        };
    }
}

internal sealed class WindowsSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    internal WindowsSettingsStore(string settingsPath, WindowsSettings settings)
    {
        SettingsPath = settingsPath;
        Settings = settings;
    }

    public string SettingsPath { get; }
    public WindowsSettings Settings { get; }
    public IReadOnlyList<RepositoryRef> VisibleRepositories => Settings.GetActiveRepositories()
        .Select((repository, index) => new { Repository = repository, Index = index })
        .Where(item => item.Repository.IsVisible)
        .OrderBy(item => item.Repository.Visibility == RepositoryVisibility.Pinned ? 0 : 1)
        .ThenBy(item => item.Index)
        .Select(item => item.Repository)
        .ToArray();

    public static WindowsSettingsStore LoadOrCreate()
    {
        var settingsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "RepoBar");
        Directory.CreateDirectory(settingsDirectory);

        var settingsPath = Path.Combine(settingsDirectory, "windows-settings.json");
        if (!File.Exists(settingsPath))
        {
            var sampleSettings = new WindowsSettings
            {
                LocalProjectsRoot = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    "Projects"),
                Repositories =
                [
                    new RepositoryRef { Owner = "steipete", Name = "RepoBar", Visibility = RepositoryVisibility.Pinned },
                ],
            };
            NormalizeSettings(sampleSettings);
            File.WriteAllText(settingsPath, JsonSerializer.Serialize(sampleSettings, JsonOptions));
            return new WindowsSettingsStore(settingsPath, sampleSettings);
        }

        var rawSettings = File.ReadAllText(settingsPath);
        var settings = JsonSerializer.Deserialize<WindowsSettings>(rawSettings, JsonOptions) ?? new WindowsSettings();
        NormalizeSettings(settings);
        return new WindowsSettingsStore(settingsPath, settings);
    }

    internal static void NormalizeSettings(WindowsSettings settings)
    {
        settings.GitHubHost = GitHubHost.Normalize(settings.GitHubHost);
        if (string.IsNullOrWhiteSpace(settings.GitHubOAuthClientId))
        {
            settings.GitHubOAuthClientId = WindowsOAuthClient.DefaultClientId;
        }
        if (string.IsNullOrWhiteSpace(settings.GitHubOAuthClientSecretEnvironmentVariable))
        {
            settings.GitHubOAuthClientSecretEnvironmentVariable = WindowsOAuthClient.DefaultClientSecretEnvironmentVariable;
        }
        settings.Accounts ??= [];
        if (settings.Accounts.Count == 0)
        {
            settings.Accounts.Add(WindowsAccountProfile.FromLegacy(settings));
        }

        settings.Accounts = settings.Accounts
            .Where(account => account.IsValid)
            .Select(NormalizeAccount)
            .GroupBy(account => account.Id, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToList();
        if (settings.Accounts.Count == 0)
        {
            settings.Accounts.Add(WindowsAccountProfile.FromLegacy(settings));
        }
        settings.ActiveAccountId = SanitizeAccountId(settings.ActiveAccountId);
        if (settings.Accounts.All(account => !string.Equals(account.Id, settings.ActiveAccountId, StringComparison.OrdinalIgnoreCase)))
        {
            settings.ActiveAccountId = settings.Accounts[0].Id;
        }

        var active = settings.GetActiveAccount();
        settings.GitHubHost = active.GitHubHost;
        settings.TokenEnvironmentVariable = active.TokenEnvironmentVariable;
        settings.GitHubOAuthClientId = active.GitHubOAuthClientId;
        settings.GitHubOAuthClientSecretEnvironmentVariable = active.GitHubOAuthClientSecretEnvironmentVariable;

        if (string.IsNullOrWhiteSpace(settings.LocalProjectsRoot))
        {
            settings.LocalProjectsRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                "Projects");
        }
        settings.LocalProjectsMaxDepth = Math.Clamp(settings.LocalProjectsMaxDepth, 0, 8);
        settings.LocalWorktreeFolderName = string.IsNullOrWhiteSpace(settings.LocalWorktreeFolderName)
            ? ".work"
            : settings.LocalWorktreeFolderName.Trim();
        settings.RefreshIntervalMinutes = Math.Clamp(settings.RefreshIntervalMinutes, 1, 60);
        settings.LocalProjectsFetchIntervalMinutes = Math.Clamp(settings.LocalProjectsFetchIntervalMinutes, 1, 60);
        settings.RepositoryDisplayLimit = Math.Clamp(settings.RepositoryDisplayLimit, 1, 100);
        settings.RepositoryOwnerFilter = NormalizeRepositoryOwnerFilter(settings.RepositoryOwnerFilter);
        settings.ActionsMonitoredOwners = NormalizeRepositoryOwnerFilter(settings.ActionsMonitoredOwners);
        settings.ActionsPlanTier = Enum.IsDefined(settings.ActionsPlanTier) ? settings.ActionsPlanTier : WindowsActionsPlanTier.Free;
        settings.LoggingVerbosity = Enum.IsDefined(settings.LoggingVerbosity) ? settings.LoggingVerbosity : WindowsLogVerbosity.Info;
        settings.MenuCustomization ??= new WindowsMenuCustomization();
        settings.MenuCustomization.Normalize();
        settings.GitHubArchiveDatabasePath = string.IsNullOrWhiteSpace(settings.GitHubArchiveDatabasePath)
            ? null
            : settings.GitHubArchiveDatabasePath.Trim();
        settings.Repositories = NormalizeRepositoryList(settings.Repositories);
        settings.RepositoriesByAccount ??= [];
        settings.RepositoriesByAccount = settings.RepositoriesByAccount
            .Where(pair => !string.IsNullOrWhiteSpace(pair.Key))
            .GroupBy(pair => SanitizeAccountId(pair.Key), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                group => group.Key,
                group => NormalizeRepositoryList(group.First().Value),
                StringComparer.OrdinalIgnoreCase);
        if (!settings.RepositoriesByAccount.ContainsKey(active.Id) && settings.Repositories.Count > 0)
        {
            settings.RepositoriesByAccount[active.Id] = NormalizeRepositoryList(settings.Repositories);
        }
        foreach (var account in settings.Accounts)
        {
            settings.RepositoriesByAccount.TryAdd(account.Id, []);
        }

        settings.Repositories = CloneRepositoryList(settings.GetActiveRepositories());
    }

    internal static List<RepositoryRef> NormalizeRepositoryList(IEnumerable<RepositoryRef>? repositories)
    {
        return (repositories ?? Enumerable.Empty<RepositoryRef>())
            .Where(repository => repository.IsValid)
            .Select(repository => new RepositoryRef
            {
                Owner = repository.Owner.Trim(),
                Name = repository.Name.Trim(),
                Visibility = repository.Visibility,
            })
            .GroupBy(repository => repository.FullName, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToList();
    }

    private static List<RepositoryRef> CloneRepositoryList(IEnumerable<RepositoryRef> repositories)
    {
        return repositories
            .Select(repository => new RepositoryRef
            {
                Owner = repository.Owner,
                Name = repository.Name,
                Visibility = repository.Visibility,
            })
            .ToList();
    }

    private static WindowsAccountProfile NormalizeAccount(WindowsAccountProfile account)
    {
        return new WindowsAccountProfile
        {
            Id = SanitizeAccountId(account.Id),
            Label = string.IsNullOrWhiteSpace(account.Label) ? account.Id.Trim() : account.Label.Trim(),
            GitHubHost = GitHubHost.Normalize(account.GitHubHost),
            TokenEnvironmentVariable = string.IsNullOrWhiteSpace(account.TokenEnvironmentVariable)
                ? "REPOBAR_GITHUB_TOKEN"
                : account.TokenEnvironmentVariable.Trim(),
            GitHubOAuthClientId = string.IsNullOrWhiteSpace(account.GitHubOAuthClientId)
                ? WindowsOAuthClient.DefaultClientId
                : account.GitHubOAuthClientId.Trim(),
            GitHubOAuthClientSecretEnvironmentVariable = string.IsNullOrWhiteSpace(account.GitHubOAuthClientSecretEnvironmentVariable)
                ? WindowsOAuthClient.DefaultClientSecretEnvironmentVariable
                : account.GitHubOAuthClientSecretEnvironmentVariable.Trim(),
        };
    }

    internal static string SanitizeAccountId(string value)
    {
        var candidate = string.Concat(value.Trim().ToLowerInvariant().Select(character =>
            char.IsAsciiLetterOrDigit(character) || character is '-' or '_' ? character : '-')).Trim('-');
        return string.IsNullOrWhiteSpace(candidate) ? WindowsAccountProfile.DefaultId : candidate;
    }

    internal static List<string> NormalizeRepositoryOwnerFilter(IEnumerable<string>? owners)
    {
        return (owners ?? Enumerable.Empty<string>())
            .Select(owner => owner.Trim().ToLowerInvariant())
            .Where(owner => !string.IsNullOrWhiteSpace(owner))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(owner => owner, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public void SetVisibility(string fullName, RepositoryVisibility visibility)
    {
        var parts = fullName.Split('/', 2, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length != 2)
        {
            return;
        }

        var repositories = Settings.GetActiveRepositories();
        var repository = repositories.FirstOrDefault(existing =>
            string.Equals(existing.FullName, fullName, StringComparison.OrdinalIgnoreCase));
        if (repository == null)
        {
            repository = new RepositoryRef { Owner = parts[0], Name = parts[1] };
            repositories.Add(repository);
        }

        repository.Visibility = visibility;
        Settings.Repositories = CloneRepositoryList(repositories);
        Save();
    }

    public bool CanMoveRepository(string fullName, int offset)
    {
        return FindMoveTarget(fullName, offset) != null;
    }

    public bool MoveRepository(string fullName, int offset)
    {
        var target = FindMoveTarget(fullName, offset);
        if (target == null)
        {
            return false;
        }

        var repositories = Settings.GetActiveRepositories();
        (repositories[target.Value.FromIndex], repositories[target.Value.ToIndex]) =
            (repositories[target.Value.ToIndex], repositories[target.Value.FromIndex]);
        Settings.Repositories = CloneRepositoryList(repositories);
        Save();
        return true;
    }

    public void ReplaceRepositories(IEnumerable<RepositoryRef> repositories)
    {
        var normalized = NormalizeRepositoryList(repositories);
        Settings.RepositoriesByAccount[Settings.GetActiveAccount().Id] = normalized;
        Settings.Repositories = CloneRepositoryList(normalized);
        Save();
    }

    private (int FromIndex, int ToIndex)? FindMoveTarget(string fullName, int offset)
    {
        if (offset == 0)
        {
            return null;
        }

        var visible = Settings.GetActiveRepositories()
            .Select((repository, index) => new { Repository = repository, Index = index })
            .Where(item => item.Repository.IsVisible)
            .OrderBy(item => item.Repository.Visibility == RepositoryVisibility.Pinned ? 0 : 1)
            .ThenBy(item => item.Index)
            .ToArray();
        var currentDisplayIndex = Array.FindIndex(visible, item =>
            string.Equals(item.Repository.FullName, fullName, StringComparison.OrdinalIgnoreCase));
        if (currentDisplayIndex < 0)
        {
            return null;
        }

        var targetDisplayIndex = currentDisplayIndex + offset;
        if (targetDisplayIndex < 0 || targetDisplayIndex >= visible.Length)
        {
            return null;
        }

        var current = visible[currentDisplayIndex];
        var target = visible[targetDisplayIndex];
        if (current.Repository.Visibility != target.Repository.Visibility)
        {
            return null;
        }

        return (current.Index, target.Index);
    }

    public bool SetActiveAccount(string accountId)
    {
        var normalizedId = SanitizeAccountId(accountId);
        var account = Settings.Accounts.FirstOrDefault(existing =>
            string.Equals(existing.Id, normalizedId, StringComparison.OrdinalIgnoreCase));
        if (account == null)
        {
            return false;
        }

        if (string.Equals(Settings.ActiveAccountId, account.Id, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        Settings.ActiveAccountId = account.Id;
        NormalizeSettings(Settings);
        Save();
        return true;
    }

    public bool SetRepositoryMenuScope(RepositoryMenuScope scope)
    {
        if (!Enum.IsDefined(scope) || Settings.RepositoryMenuScope == scope)
        {
            return false;
        }

        Settings.RepositoryMenuScope = scope;
        Save();
        return true;
    }

    public bool SetRepositorySortKey(RepositorySortKey sortKey)
    {
        if (!Enum.IsDefined(sortKey) || Settings.RepositorySortKey == sortKey)
        {
            return false;
        }

        Settings.RepositorySortKey = sortKey;
        Save();
        return true;
    }

    public bool SetRepositoryOwnerFilter(IEnumerable<string> owners)
    {
        var normalized = NormalizeRepositoryOwnerFilter(owners);
        if (Settings.RepositoryOwnerFilter.SequenceEqual(normalized, StringComparer.OrdinalIgnoreCase))
        {
            return false;
        }

        Settings.RepositoryOwnerFilter = normalized;
        Save();
        return true;
    }

    public void Save()
    {
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(Settings, JsonOptions));
    }

    public string? ResolveToken()
    {
        var account = Settings.GetActiveAccount();
        var credentialToken = new WindowsCredentialStore(account.GitHubHost, account.Id).ReadToken();
        if (!string.IsNullOrWhiteSpace(credentialToken))
        {
            return credentialToken;
        }

        if (!string.IsNullOrWhiteSpace(account.TokenEnvironmentVariable))
        {
            var configuredToken = Environment.GetEnvironmentVariable(account.TokenEnvironmentVariable);
            if (!string.IsNullOrWhiteSpace(configuredToken))
            {
                return configuredToken;
            }
        }

        var repoBarToken = Environment.GetEnvironmentVariable("REPOBAR_GITHUB_TOKEN");
        if (!string.IsNullOrWhiteSpace(repoBarToken))
        {
            return repoBarToken;
        }

        var githubToken = Environment.GetEnvironmentVariable("GITHUB_TOKEN");
        if (!string.IsNullOrWhiteSpace(githubToken))
        {
            return githubToken;
        }

        var ghToken = Environment.GetEnvironmentVariable("GH_TOKEN");
        return string.IsNullOrWhiteSpace(ghToken) ? null : ghToken;
    }

    internal IReadOnlyList<string> ActiveAccountStoredCredentialTargetNames
    {
        get
        {
            var account = Settings.GetActiveAccount();
            return
            [
                WindowsCredentialStore.BuildTargetName(account.GitHubHost, account.Id),
                WindowsCredentialStore.BuildOAuthTargetName(account.GitHubHost, account.Id),
            ];
        }
    }

    public void ClearActiveAccountStoredCredentials()
    {
        var account = Settings.GetActiveAccount();
        new WindowsCredentialStore(account.GitHubHost, account.Id).ClearToken();
        new WindowsOAuthTokenStore(account.GitHubHost, account.Id).ClearTokens();
    }
}

internal static class WindowsRepositoryDisplay
{
    public static IReadOnlyList<RepositoryStatus> Apply(IReadOnlyList<RepositoryStatus> statuses, WindowsSettings settings)
    {
        var pinnedOrder = settings.GetActiveRepositories()
            .Where(repository => repository.Visibility == RepositoryVisibility.Pinned)
            .Select((repository, index) => (repository.FullName, index))
            .GroupBy(pair => pair.FullName, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToDictionary(pair => pair.FullName, pair => pair.index, StringComparer.OrdinalIgnoreCase);

        if (settings.RepositoryMenuScope == RepositoryMenuScope.Pinned)
        {
            return statuses
                .Where(status => pinnedOrder.ContainsKey(status.Repository.FullName))
                .OrderBy(status => pinnedOrder[status.Repository.FullName])
                .Take(Math.Clamp(settings.RepositoryDisplayLimit, 1, 100))
                .ToArray();
        }

        if (settings.RepositoryMenuScope == RepositoryMenuScope.Local)
        {
            return statuses
                .Where(status => status.LocalStatus != null)
                .OrderBy(status => status.LocalStatus?.DisplayName ?? status.Repository.FullName, StringComparer.OrdinalIgnoreCase)
                .Take(Math.Clamp(settings.RepositoryDisplayLimit, 1, 100))
                .ToArray();
        }

        var pinned = statuses
            .Where(status => pinnedOrder.ContainsKey(status.Repository.FullName))
            .OrderBy(status => pinnedOrder[status.Repository.FullName]);
        var normal = Sort(
            statuses
                .Where(status => !pinnedOrder.ContainsKey(status.Repository.FullName))
                .Where(status => MatchesDisplayFilter(status, settings)),
            settings.RepositorySortKey);

        return pinned
            .Concat(normal)
            .Take(Math.Clamp(settings.RepositoryDisplayLimit, 1, 100))
            .ToArray();
    }

    private static IOrderedEnumerable<RepositoryStatus> Sort(IEnumerable<RepositoryStatus> statuses, RepositorySortKey sortKey)
    {
        return sortKey switch
        {
            RepositorySortKey.Issues => statuses
                .OrderByDescending(status => status.IssueCount)
                .ThenBy(status => status.Repository.FullName, StringComparer.OrdinalIgnoreCase),
            RepositorySortKey.PullRequests => statuses
                .OrderByDescending(status => status.PullRequestCount)
                .ThenBy(status => status.Repository.FullName, StringComparer.OrdinalIgnoreCase),
            RepositorySortKey.Stars => statuses
                .OrderByDescending(status => status.Stars)
                .ThenBy(status => status.Repository.FullName, StringComparer.OrdinalIgnoreCase),
            RepositorySortKey.Name => statuses
                .OrderBy(status => status.Repository.FullName, StringComparer.OrdinalIgnoreCase),
            _ => statuses
                .OrderByDescending(status => status.PushedAt ?? DateTimeOffset.MinValue)
                .ThenBy(status => status.Repository.FullName, StringComparer.OrdinalIgnoreCase),
        };
    }

    private static bool MatchesDisplayFilter(RepositoryStatus status, WindowsSettings settings)
    {
        if (settings.RepositoryOwnerFilter.Count > 0 &&
            !settings.RepositoryOwnerFilter.Contains(status.Repository.Owner, StringComparer.OrdinalIgnoreCase))
        {
            return false;
        }

        var onlyWithIssues = settings.ShowOnlyRepositoriesWithIssues || settings.RepositoryMenuScope == RepositoryMenuScope.Work;
        var onlyWithPullRequests = settings.ShowOnlyRepositoriesWithPullRequests || settings.RepositoryMenuScope == RepositoryMenuScope.Work;
        if (!onlyWithIssues && !onlyWithPullRequests)
        {
            return true;
        }

        return (onlyWithIssues && status.IssueCount > 0) ||
            (onlyWithPullRequests && status.PullRequestCount > 0);
    }
}
