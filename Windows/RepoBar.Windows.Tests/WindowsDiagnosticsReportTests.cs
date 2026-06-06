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
            Assert.Contains("last_error: rate limited", text);
            Assert.Contains("core: 4999/5000", text);
            Assert.DoesNotContain("super-secret-token", text);
        }
        finally
        {
            Environment.SetEnvironmentVariable("SECRET_TOKEN_ENV", null);
        }
    }
}
