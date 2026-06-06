using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsDiagnosticsReportTests
{
    [Fact]
    public void Diagnostics_report_includes_debug_state_without_tokens()
    {
        Environment.SetEnvironmentVariable("SECRET_TOKEN_ENV", "super-secret-token");
        var settings = new WindowsSettings
        {
            ActiveAccountId = "work",
            Accounts =
            [
                new WindowsAccountProfile
                {
                    Id = "work",
                    Label = "Work",
                    GitHubHost = "github.example.com",
                    TokenEnvironmentVariable = "SECRET_TOKEN_ENV",
                },
            ],
            GitHubArchiveDatabasePath = Path.Combine(Path.GetTempPath(), $"repobar-archive-{Guid.NewGuid():N}.sqlite"),
            RefreshIntervalMinutes = 7,
            CheckForUpdatesAutomatically = false,
            RepositoryMenuScope = RepositoryMenuScope.Local,
            RepositorySortKey = RepositorySortKey.Name,
            RepositoryDisplayLimit = 9,
            DiscoverLocalProjects = true,
            LocalProjectsRoot = "C:/Projects",
            LocalProjectsMaxDepth = 4,
            FetchLocalProjectsBeforeStatus = true,
            LocalProjectsFetchIntervalMinutes = 3,
            AutoSyncLocalProjects = true,
            ShowDirtyFilesInMenu = false,
            ShowActionsUsage = true,
            ActionsMonitoredOwners = ["owner", "steipete"],
            EnableGitHubReferenceMonitor = true,
            EnablePullRequestNotifications = true,
            PullRequestNotificationClickAction = PullRequestNotificationClickAction.OpenIssueNavigator,
            DiagnosticsEnabled = true,
            LoggingVerbosity = WindowsLogVerbosity.Debug,
            FileLoggingEnabled = true,
            Repositories =
            [
                new RepositoryRef { Owner = "owner", Name = "one", Visibility = RepositoryVisibility.Pinned },
                new RepositoryRef { Owner = "owner", Name = "hidden", Visibility = RepositoryVisibility.Hidden },
            ],
        };
        try
        {
            WindowsSettingsStore.NormalizeSettings(settings);
            var settingsStore = new WindowsSettingsStore("C:/Users/example/AppData/Roaming/RepoBar/windows-settings.json", settings);
            var status = new RepositoryStatus(
                new RepositoryRef { Owner = "owner", Name = "one" },
                Stars: 1,
                Forks: 2,
                IssueCount: 3,
                PullRequestCount: 4,
                DefaultBranch: "main",
                PushedAt: null,
                LatestRun: null,
                LatestRelease: null,
                RecentLists: RecentRepositoryLists.Empty,
                Traffic: null,
                Heatmap: null,
                Changelog: null,
                LocalStatus: null,
                ErrorMessage: null);
            var localIndex = new LocalGitIndex([
                new LocalGitRepositoryStatus(
                    Path: "C:/Projects/one",
                    Name: "one",
                    FullName: "owner/one",
                    Branch: "main",
                    IsClean: true,
                    AheadCount: 0,
                    BehindCount: 0,
                    SyncState: LocalSyncState.Synced,
                    DirtyCounts: LocalDirtyCounts.Empty,
                    DirtyFiles: [],
                    WorktreeName: null,
                    UpstreamBranch: "origin/main"),
            ]);
            var rateLimit = new GitHubRateLimitSnapshot(5000, 4999, DateTimeOffset.Parse("2026-06-06T12:00:00Z"), "core");

            var report = WindowsDiagnosticsReport.Capture(
                settingsStore,
                [status],
                localIndex,
                [rateLimit],
                "rate limited");
            var text = report.ClipboardText();

            Assert.Contains("RepoBar Windows diagnostics", text);
            Assert.Contains("github_host: github.example.com", text);
            Assert.Contains("active_account: Work (work)", text);
            Assert.Contains("configured_repositories: 2", text);
            Assert.Contains("visible_repositories: 1", text);
            Assert.Contains("loaded_repositories: 1", text);
            Assert.Contains("local_repositories: 1", text);
            Assert.Contains("refresh_interval_minutes: 7", text);
            Assert.Contains("check_for_updates_automatically: False", text);
            Assert.Contains("repository_menu_scope: local", text);
            Assert.Contains("repository_sort_key: name", text);
            Assert.Contains("repository_display_limit: 9", text);
            Assert.Contains("discover_local_projects: True", text);
            Assert.Contains("local_projects_root: C:/Projects", text);
            Assert.Contains("local_projects_max_depth: 4", text);
            Assert.Contains("fetch_local_projects_before_status: True", text);
            Assert.Contains("local_projects_fetch_interval_minutes: 3", text);
            Assert.Contains("auto_sync_local_projects: True", text);
            Assert.Contains("show_dirty_files_in_menu: False", text);
            Assert.Contains("diagnostics_enabled: True", text);
            Assert.Contains("logging_verbosity: debug", text);
            Assert.Contains("file_logging_enabled: True", text);
            Assert.Contains("show_actions_usage: True", text);
            Assert.Contains("actions_monitored_owners: owner, steipete", text);
            Assert.Contains("watch_clipboard_references: True", text);
            Assert.Contains("pr_notifications_enabled: True", text);
            Assert.Contains("pr_notification_click_action: openissuenavigator", text);
            Assert.Contains("last_error: rate limited", text);
            Assert.Contains("core: 4999/5000", text);
            Assert.DoesNotContain("super-secret-token", text);

            var summary = report.SummaryText();
            Assert.Contains("Repository menu: Local scope, Repository name sort, limit 9", summary);
            Assert.Contains("Local projects: enabled at C:/Projects, fetch enabled every 3 minutes, auto-sync enabled", summary);
            Assert.Contains("PR notifications: enabled, click opens Issue Navigator", summary);
        }
        finally
        {
            Environment.SetEnvironmentVariable("SECRET_TOKEN_ENV", null);
        }
    }
}
