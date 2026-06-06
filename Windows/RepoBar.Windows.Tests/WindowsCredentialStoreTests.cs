using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsCredentialStoreTests
{
    [Theory]
    [InlineData("github.com", "RepoBar.Windows:github.com")]
    [InlineData("GitHub.EXAMPLE.com", "RepoBar.Windows:github.example.com")]
    [InlineData("https://github.example.com", "RepoBar.Windows:github.example.com")]
    public void BuildTargetName_normalizes_host(string host, string expected)
    {
        Assert.Equal(expected, WindowsCredentialStore.BuildTargetName(host));
    }

    [Fact]
    public void BuildTargetName_includes_non_default_account_id()
    {
        Assert.Equal(
            "RepoBar.Windows:github.com:work-account",
            WindowsCredentialStore.BuildTargetName("github.com", "Work Account"));
    }

    [Theory]
    [InlineData("github.com", "RepoBar.Windows.OAuth:github.com")]
    [InlineData("https://github.example.com/org/repo", "RepoBar.Windows.OAuth:github.example.com")]
    public void BuildOAuthTargetName_separates_oauth_tokens_from_pat_tokens(string host, string expected)
    {
        Assert.Equal(expected, WindowsCredentialStore.BuildOAuthTargetName(host));
    }

    [Fact]
    public void BuildOAuthTargetName_includes_non_default_account_id()
    {
        Assert.Equal(
            "RepoBar.Windows.OAuth:github.com:work",
            WindowsCredentialStore.BuildOAuthTargetName("github.com", "work"));
    }

    [Fact]
    public void OAuthTokenStore_serializes_access_refresh_and_expiry()
    {
        var expires = DateTimeOffset.Parse("2026-06-06T12:00:00Z");
        var tokens = new WindowsOAuthTokens("access", "refresh", expires);

        var roundTrip = WindowsOAuthTokenStore.Deserialize(WindowsOAuthTokenStore.Serialize(tokens));

        Assert.Equal(tokens, roundTrip);
        Assert.False(tokens.ShouldRefresh(expires.AddMinutes(-2)));
        Assert.True(tokens.ShouldRefresh(expires.AddSeconds(-30)));
    }

    [Fact]
    public void ReadToken_returns_null_off_windows()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        Assert.Null(new WindowsCredentialStore("github.com").ReadToken());
    }

    [Fact]
    public void ClearActiveAccountStoredCredentials_targets_active_account_pat_and_oauth_tokens()
    {
        var settings = new WindowsSettings
        {
            ActiveAccountId = "work",
            Accounts =
            [
                new WindowsAccountProfile
                {
                    Id = "default",
                    Label = "Default",
                    GitHubHost = "github.com",
                },
                new WindowsAccountProfile
                {
                    Id = "work",
                    Label = "Work",
                    GitHubHost = "github.enterprise.test",
                },
            ],
        };
        WindowsSettingsStore.NormalizeSettings(settings);
        var store = new WindowsSettingsStore(Path.Combine(Path.GetTempPath(), "repobar-settings-test.json"), settings);

        Assert.Equal(
            [
                "RepoBar.Windows:github.enterprise.test:work",
                "RepoBar.Windows.OAuth:github.enterprise.test:work",
            ],
            store.ActiveAccountStoredCredentialTargetNames);
        var exception = Record.Exception(store.ClearActiveAccountStoredCredentials);

        Assert.Null(exception);
    }

    [Fact]
    public void PullRequestNotificationClickAction_defaults_to_browser_and_labels_for_preferences()
    {
        var settings = new WindowsSettings();

        Assert.Equal(PullRequestNotificationClickAction.OpenInBrowser, settings.PullRequestNotificationClickAction);
        Assert.Equal("Default browser", PullRequestNotificationClickAction.OpenInBrowser.DisplayName());
        Assert.Equal("Issue Navigator", PullRequestNotificationClickAction.OpenIssueNavigator.DisplayName());
    }

    [Theory]
    [InlineData(null, "github.com")]
    [InlineData("", "github.com")]
    [InlineData("GitHub.EXAMPLE.com/", "github.example.com")]
    [InlineData("https://github.example.com/org/repo", "github.example.com")]
    public void Normalize_host_accepts_urls_and_plain_hosts(string? host, string expected)
    {
        Assert.Equal(expected, GitHubHost.Normalize(host));
    }

    [Fact]
    public void NormalizeSettings_migrates_legacy_account_fields_and_mirrors_active_account()
    {
        var settings = new WindowsSettings
        {
            GitHubHost = "GitHub.EXAMPLE.com/",
            TokenEnvironmentVariable = "LEGACY_TOKEN",
            GitHubOAuthClientId = "legacy-client",
            GitHubOAuthClientSecretEnvironmentVariable = "LEGACY_SECRET",
            Accounts =
            [
                new WindowsAccountProfile
                {
                    Id = "Work Account",
                    Label = "Work",
                    GitHubHost = "https://github.enterprise.test/org",
                    TokenEnvironmentVariable = "WORK_TOKEN",
                    GitHubOAuthClientId = "work-client",
                    GitHubOAuthClientSecretEnvironmentVariable = "WORK_SECRET",
                },
            ],
            ActiveAccountId = "work-account",
            LocalWorktreeFolderName = "",
        };

        WindowsSettingsStore.NormalizeSettings(settings);

        Assert.Equal("work-account", settings.ActiveAccountId);
        Assert.Equal("github.enterprise.test", settings.GitHubHost);
        Assert.Equal("WORK_TOKEN", settings.TokenEnvironmentVariable);
        Assert.Equal("work-client", settings.GitHubOAuthClientId);
        Assert.Equal("WORK_SECRET", settings.GitHubOAuthClientSecretEnvironmentVariable);
        Assert.Equal("work-account", settings.GetActiveAccount().Id);
        Assert.Equal(".work", settings.LocalWorktreeFolderName);
    }

    [Fact]
    public void SetActiveAccount_persists_active_profile_and_mirrors_legacy_fields()
    {
        var settingsPath = Path.Combine(Path.GetTempPath(), $"repobar-settings-{Guid.NewGuid():N}.json");
        try
        {
            var settings = new WindowsSettings
            {
                ActiveAccountId = "default",
                Accounts =
                [
                    new WindowsAccountProfile
                    {
                        Id = "default",
                        Label = "Default",
                        GitHubHost = "github.com",
                        TokenEnvironmentVariable = "DEFAULT_TOKEN",
                    },
                    new WindowsAccountProfile
                    {
                        Id = "Work Account",
                        Label = "Work",
                        GitHubHost = "https://github.enterprise.test/org",
                        TokenEnvironmentVariable = "WORK_TOKEN",
                        GitHubOAuthClientId = "work-client",
                        GitHubOAuthClientSecretEnvironmentVariable = "WORK_SECRET",
                    },
                ],
            };
            WindowsSettingsStore.NormalizeSettings(settings);
            var store = new WindowsSettingsStore(settingsPath, settings);

            Assert.True(store.SetActiveAccount("work account"));

            Assert.Equal("work-account", settings.ActiveAccountId);
            Assert.Equal("github.enterprise.test", settings.GitHubHost);
            Assert.Equal("WORK_TOKEN", settings.TokenEnvironmentVariable);
            Assert.Equal("work-client", settings.GitHubOAuthClientId);
            Assert.Equal("WORK_SECRET", settings.GitHubOAuthClientSecretEnvironmentVariable);
            Assert.Contains("\"activeAccountId\": \"work-account\"", File.ReadAllText(settingsPath));
        }
        finally
        {
            if (File.Exists(settingsPath))
            {
                File.Delete(settingsPath);
            }
        }
    }
}
