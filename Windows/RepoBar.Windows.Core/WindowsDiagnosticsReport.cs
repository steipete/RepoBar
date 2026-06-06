using System.Globalization;
using System.Text;

namespace RepoBar.Windows;

internal sealed record WindowsDiagnosticsReport(
    DateTimeOffset CapturedAt,
    string SettingsPath,
    string GitHubHost,
    string ActiveAccountId,
    string ActiveAccountLabel,
    int ConfiguredRepositoryCount,
    int VisibleRepositoryCount,
    int LoadedRepositoryCount,
    int LocalRepositoryCount,
    string? LastError,
    int RefreshIntervalMinutes,
    bool CheckForUpdatesAutomatically,
    RepositoryMenuScope RepositoryMenuScope,
    RepositorySortKey RepositorySortKey,
    int RepositoryDisplayLimit,
    bool DiscoverLocalProjects,
    string? LocalProjectsRoot,
    int LocalProjectsMaxDepth,
    bool FetchLocalProjectsBeforeStatus,
    int LocalProjectsFetchIntervalMinutes,
    bool AutoSyncLocalProjects,
    bool ShowDirtyFilesInMenu,
    bool DiagnosticsEnabled,
    WindowsLogVerbosity LoggingVerbosity,
    bool FileLoggingEnabled,
    string? LogFilePath,
    bool LogFileExists,
    bool ShowActionsUsage,
    IReadOnlyList<string> ActionsMonitoredOwners,
    bool EnableGitHubReferenceMonitor,
    bool EnablePullRequestNotifications,
    PullRequestNotificationClickAction PullRequestNotificationClickAction,
    string CacheDirectory,
    int CacheEntryCount,
    string? ArchiveDatabasePath,
    bool ArchiveDatabaseExists,
    IReadOnlyList<GitHubRateLimitSnapshot> RateLimits)
{
    public string ClipboardText()
    {
        var lines = new List<string>
        {
            "RepoBar Windows diagnostics",
            $"captured_at: {CapturedAt:O}",
            $"settings_path: {SettingsPath}",
            $"github_host: {GitHubHost}",
            $"active_account: {ActiveAccountLabel} ({ActiveAccountId})",
            $"configured_repositories: {ConfiguredRepositoryCount.ToString(CultureInfo.InvariantCulture)}",
            $"visible_repositories: {VisibleRepositoryCount.ToString(CultureInfo.InvariantCulture)}",
            $"loaded_repositories: {LoadedRepositoryCount.ToString(CultureInfo.InvariantCulture)}",
            $"local_repositories: {LocalRepositoryCount.ToString(CultureInfo.InvariantCulture)}",
            $"refresh_interval_minutes: {RefreshIntervalMinutes.ToString(CultureInfo.InvariantCulture)}",
            $"check_for_updates_automatically: {CheckForUpdatesAutomatically}",
            $"repository_menu_scope: {RepositoryMenuScope.ToString().ToLowerInvariant()}",
            $"repository_sort_key: {RepositorySortKey.ToString().ToLowerInvariant()}",
            $"repository_display_limit: {RepositoryDisplayLimit.ToString(CultureInfo.InvariantCulture)}",
            $"discover_local_projects: {DiscoverLocalProjects}",
            $"local_projects_root: {LocalProjectsRoot ?? "(none)"}",
            $"local_projects_max_depth: {LocalProjectsMaxDepth.ToString(CultureInfo.InvariantCulture)}",
            $"fetch_local_projects_before_status: {FetchLocalProjectsBeforeStatus}",
            $"local_projects_fetch_interval_minutes: {LocalProjectsFetchIntervalMinutes.ToString(CultureInfo.InvariantCulture)}",
            $"auto_sync_local_projects: {AutoSyncLocalProjects}",
            $"show_dirty_files_in_menu: {ShowDirtyFilesInMenu}",
            $"diagnostics_enabled: {DiagnosticsEnabled}",
            $"logging_verbosity: {LoggingVerbosity.ToString().ToLowerInvariant()}",
            $"file_logging_enabled: {FileLoggingEnabled}",
            $"log_file: {LogFilePath ?? "(disabled)"}",
            $"log_file_exists: {LogFileExists}",
            $"show_actions_usage: {ShowActionsUsage}",
            $"actions_monitored_owners: {FormatList(ActionsMonitoredOwners)}",
            $"watch_clipboard_references: {EnableGitHubReferenceMonitor}",
            $"pr_notifications_enabled: {EnablePullRequestNotifications}",
            $"pr_notification_click_action: {PullRequestNotificationClickAction.ToString().ToLowerInvariant()}",
            $"cache_directory: {CacheDirectory}",
            $"cache_entries: {CacheEntryCount.ToString(CultureInfo.InvariantCulture)}",
            $"archive_database: {ArchiveDatabasePath ?? "(none)"}",
            $"archive_database_exists: {ArchiveDatabaseExists}",
            $"last_error: {LastError ?? "(none)"}",
        };

        if (RateLimits.Count == 0)
        {
            lines.Add("rate_limits: (none captured)");
        }
        else
        {
            lines.Add("rate_limits:");
            lines.AddRange(RateLimits.Select(snapshot => $"  - {snapshot.DisplayText}"));
        }

        return string.Join(Environment.NewLine, lines);
    }

    public string SummaryText()
    {
        var builder = new StringBuilder();
        builder.AppendLine($"Captured: {CapturedAt.LocalDateTime:G}");
        builder.AppendLine($"Account: {ActiveAccountLabel} ({ActiveAccountId})");
        builder.AppendLine($"GitHub host: {GitHubHost}");
        builder.AppendLine($"Repositories: {LoadedRepositoryCount} loaded / {VisibleRepositoryCount} visible / {ConfiguredRepositoryCount} configured");
        builder.AppendLine($"Local repositories: {LocalRepositoryCount}");
        builder.AppendLine($"Refresh: every {RefreshIntervalMinutes} minutes, updates {(CheckForUpdatesAutomatically ? "automatic" : "manual")}");
        builder.AppendLine($"Repository menu: {RepositoryMenuScope.DisplayName()} scope, {RepositorySortKey.DisplayName()} sort, limit {RepositoryDisplayLimit}");
        builder.AppendLine($"Local projects: {(DiscoverLocalProjects ? "enabled" : "disabled")} at {LocalProjectsRoot ?? "none"}, fetch {(FetchLocalProjectsBeforeStatus ? "enabled" : "disabled")} every {LocalProjectsFetchIntervalMinutes} minutes, auto-sync {(AutoSyncLocalProjects ? "enabled" : "disabled")}");
        builder.AppendLine($"Clipboard references: {(EnableGitHubReferenceMonitor ? "enabled" : "disabled")}");
        builder.AppendLine($"PR notifications: {(EnablePullRequestNotifications ? "enabled" : "disabled")}, click opens {PullRequestNotificationClickAction.DisplayName()}");
        builder.AppendLine($"Actions usage: {(ShowActionsUsage ? "enabled" : "disabled")} ({FormatList(ActionsMonitoredOwners)})");
        builder.AppendLine($"Diagnostics: {(DiagnosticsEnabled ? "enabled" : "disabled")}");
        builder.AppendLine($"Logging: {LoggingVerbosity.DisplayName()}, file {(FileLoggingEnabled ? "enabled" : "disabled")}");
        builder.AppendLine($"Log file: {LogFilePath ?? "disabled"} ({(LogFileExists ? "present" : "missing")})");
        builder.AppendLine($"Cache entries: {CacheEntryCount}");
        builder.AppendLine($"Archive DB: {(ArchiveDatabasePath == null ? "none" : ArchiveDatabaseExists ? "present" : "missing")}");
        builder.AppendLine($"Last error: {LastError ?? "none"}");
        builder.AppendLine();
        builder.AppendLine("Rate limits:");
        if (RateLimits.Count == 0)
        {
            builder.AppendLine("  none captured");
        }
        else
        {
            foreach (var snapshot in RateLimits)
            {
                builder.AppendLine($"  {snapshot.DisplayText}");
            }
        }

        return builder.ToString();
    }

    public static WindowsDiagnosticsReport Capture(
        WindowsSettingsStore settingsStore,
        IReadOnlyList<RepositoryStatus> statuses,
        LocalGitIndex localGitIndex,
        IReadOnlyList<GitHubRateLimitSnapshot> rateLimits,
        string? lastError)
    {
        var settings = settingsStore.Settings;
        var activeAccount = settings.GetActiveAccount();
        var archivePath = string.IsNullOrWhiteSpace(settings.GitHubArchiveDatabasePath)
            ? null
            : Environment.ExpandEnvironmentVariables(settings.GitHubArchiveDatabasePath);
        return new WindowsDiagnosticsReport(
            DateTimeOffset.UtcNow,
            settingsStore.SettingsPath,
            settings.GitHubHost,
            settings.ActiveAccountId,
            activeAccount.DisplayName,
            settings.GetActiveRepositories().Count,
            settingsStore.VisibleRepositories.Count,
            statuses.Count,
            localGitIndex.Repositories.Count,
            string.IsNullOrWhiteSpace(lastError) ? null : lastError,
            settings.RefreshIntervalMinutes,
            settings.CheckForUpdatesAutomatically,
            settings.RepositoryMenuScope,
            settings.RepositorySortKey,
            settings.RepositoryDisplayLimit,
            settings.DiscoverLocalProjects,
            settings.LocalProjectsRoot,
            settings.LocalProjectsMaxDepth,
            settings.FetchLocalProjectsBeforeStatus,
            settings.LocalProjectsFetchIntervalMinutes,
            settings.AutoSyncLocalProjects,
            settings.ShowDirtyFilesInMenu,
            settings.DiagnosticsEnabled,
            settings.LoggingVerbosity,
            settings.FileLoggingEnabled,
            WindowsDiagnosticsLogger.LogFilePath ?? WindowsDiagnosticsLogger.DefaultLogFilePath(),
            File.Exists(WindowsDiagnosticsLogger.LogFilePath ?? WindowsDiagnosticsLogger.DefaultLogFilePath()),
            settings.ShowActionsUsage,
            settings.ActionsMonitoredOwners.ToArray(),
            settings.EnableGitHubReferenceMonitor,
            settings.EnablePullRequestNotifications,
            settings.PullRequestNotificationClickAction,
            GitHubResponseCache.DirectoryForSettings(settings),
            GitHubResponseCache.EntryCountForSettings(settings),
            archivePath,
            archivePath != null && File.Exists(archivePath),
            rateLimits.ToArray());
    }

    private static string FormatList(IReadOnlyList<string> values)
    {
        return values.Count == 0 ? "(none)" : string.Join(", ", values);
    }
}
