using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class PullRequestNotificationTrackerTests
{
    [Fact]
    public void StatePathForSettings_scopes_by_host_and_account()
    {
        var root = Path.Combine(Path.GetTempPath(), $"repobar-pr-notifications-{Guid.NewGuid():N}");
        var github = new WindowsSettings
        {
            ActiveAccountId = "work",
            Accounts = [Account("work", "github.com")],
        };
        var enterprise = new WindowsSettings
        {
            ActiveAccountId = "work",
            Accounts = [Account("work", "ghe.example.com")],
        };
        WindowsSettingsStore.NormalizeSettings(github);
        WindowsSettingsStore.NormalizeSettings(enterprise);

        var githubPath = PullRequestNotificationTracker.StatePathForSettings(github, root);
        var enterprisePath = PullRequestNotificationTracker.StatePathForSettings(enterprise, root);

        Assert.Contains($"{Path.DirectorySeparatorChar}accounts{Path.DirectorySeparatorChar}", githubPath);
        Assert.NotEqual(githubPath, enterprisePath);
        Assert.Contains(GitHubResponseCache.SafeScope("github.com", "work"), githubPath);
        Assert.Contains(GitHubResponseCache.SafeScope("ghe.example.com", "work"), enterprisePath);
    }

    [Fact]
    public void Account_scoped_state_keeps_notification_baselines_separate()
    {
        var root = Path.Combine(Path.GetTempPath(), $"repobar-pr-notifications-{Guid.NewGuid():N}");
        try
        {
            var settings = new WindowsSettings
            {
                ActiveAccountId = "default",
                Accounts =
                [
                    Account("default", "github.com"),
                    Account("work", "github.com"),
                ],
            };
            WindowsSettingsStore.NormalizeSettings(settings);
            var defaultTracker = new PullRequestNotificationTracker(PullRequestNotificationTracker.StatePathForSettings(settings, root));
            Assert.Empty(defaultTracker.DetectEvents("steipete/RepoBar", [
                Pull("#1 First", 1, "2026-06-06T10:00:00Z"),
            ], NotificationSettings()));

            settings.ActiveAccountId = "work";
            WindowsSettingsStore.NormalizeSettings(settings);
            var workTracker = new PullRequestNotificationTracker(PullRequestNotificationTracker.StatePathForSettings(settings, root));
            Assert.Empty(workTracker.DetectEvents("steipete/RepoBar", [
                Pull("#1 First", 1, "2026-06-06T10:00:00Z"),
            ], NotificationSettings()));

            var workEvents = workTracker.DetectEvents("steipete/RepoBar", [
                Pull("#2 Second", 2, "2026-06-06T10:05:00Z"),
                Pull("#1 First", 1, "2026-06-06T10:00:00Z"),
            ], NotificationSettings());
            var defaultEvents = defaultTracker.DetectEvents("steipete/RepoBar", [
                Pull("#2 Second", 2, "2026-06-06T10:05:00Z"),
                Pull("#1 First", 1, "2026-06-06T10:00:00Z"),
            ], NotificationSettings());

            Assert.Single(workEvents);
            Assert.Single(defaultEvents);
            Assert.NotEqual(defaultTracker.StatePath, workTracker.StatePath);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void ClearForSettings_removes_only_active_account_notification_state()
    {
        var root = Path.Combine(Path.GetTempPath(), $"repobar-pr-notifications-{Guid.NewGuid():N}");
        try
        {
            var settings = new WindowsSettings
            {
                ActiveAccountId = "default",
                Accounts =
                [
                    Account("default", "github.com"),
                    Account("work", "github.com"),
                ],
            };
            WindowsSettingsStore.NormalizeSettings(settings);

            var defaultPath = PullRequestNotificationTracker.StatePathForSettings(settings, root);
            var defaultTracker = new PullRequestNotificationTracker(defaultPath);
            defaultTracker.DetectEvents("steipete/RepoBar", [
                Pull("#1 First", 1, "2026-06-06T10:00:00Z"),
            ], NotificationSettings());

            settings.ActiveAccountId = "work";
            WindowsSettingsStore.NormalizeSettings(settings);
            var workPath = PullRequestNotificationTracker.StatePathForSettings(settings, root);
            var workTracker = new PullRequestNotificationTracker(workPath);
            workTracker.DetectEvents("steipete/RepoBar", [
                Pull("#2 Second", 2, "2026-06-06T10:00:00Z"),
            ], NotificationSettings());

            PullRequestNotificationTracker.ClearForSettings(settings, root);

            Assert.True(File.Exists(defaultPath));
            Assert.False(File.Exists(workPath));
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void DetectNewPullRequests_seeds_then_reports_only_new_items()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"repobar-pr-notifications-{Guid.NewGuid():N}");
        try
        {
            var statePath = Path.Combine(directory, "state.json");
            var tracker = new PullRequestNotificationTracker(statePath);
            var first = new[]
            {
                new GitHubListItem("#1 First", "https://github.com/o/r/pull/1", null),
            };

            Assert.Empty(tracker.DetectNewPullRequests("o/r", first));
            Assert.Empty(tracker.DetectNewPullRequests("o/r", first));

            var second = new[]
            {
                new GitHubListItem("#2 Second", "https://github.com/o/r/pull/2", null),
                new GitHubListItem("#1 First", "https://github.com/o/r/pull/1", null),
            };
            var newPulls = tracker.DetectNewPullRequests("o/r", second);

            Assert.Single(newPulls);
            Assert.Equal("#2 Second", newPulls[0].Title);
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public void DetectNewPullRequests_keeps_seen_state_when_refresh_returns_empty()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"repobar-pr-notifications-{Guid.NewGuid():N}");
        try
        {
            var statePath = Path.Combine(directory, "state.json");
            var tracker = new PullRequestNotificationTracker(statePath);
            var first = new[]
            {
                new GitHubListItem("#1 First", "https://github.com/o/r/pull/1", null),
            };

            Assert.Empty(tracker.DetectNewPullRequests("o/r", first));
            Assert.Empty(tracker.DetectNewPullRequests("o/r", []));
            Assert.Empty(tracker.DetectNewPullRequests("o/r", first));
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public void DetectEvents_reports_updates_review_requests_and_comments_when_enabled()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"repobar-pr-notifications-{Guid.NewGuid():N}");
        try
        {
            var statePath = Path.Combine(directory, "state.json");
            var tracker = new PullRequestNotificationTracker(statePath);
            var settings = NotificationSettings();

            Assert.Empty(tracker.DetectEvents("o/r", [
                Pull("#1 First", 1, "2026-06-06T10:00:00Z", comments: 1),
                Pull("#2 Second", 2, "2026-06-06T10:00:00Z"),
                Pull("#3 Third", 3, "2026-06-06T10:00:00Z"),
            ], settings));

            var events = tracker.DetectEvents("o/r", [
                Pull("#1 First", 1, "2026-06-06T10:10:00Z", comments: 1),
                Pull("#2 Second", 2, "2026-06-06T10:00:00Z", requestedReviewers: ["octo"]),
                Pull("#3 Third", 3, "2026-06-06T10:00:00Z", comments: 2, reviewComments: 1),
            ], settings);

            Assert.Equal(
                [
                    PullRequestNotificationEventKind.PullRequestUpdated,
                    PullRequestNotificationEventKind.ReviewRequested,
                    PullRequestNotificationEventKind.NewComment,
                ],
                events.Select(item => item.Kind));
            Assert.Equal("Review requested from octo", events[1].Detail);
            Assert.Equal("3 new comments", events[2].Detail);
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public void DetectEvents_reports_pull_request_state_changes_as_updates()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"repobar-pr-notifications-{Guid.NewGuid():N}");
        try
        {
            var statePath = Path.Combine(directory, "state.json");
            var tracker = new PullRequestNotificationTracker(statePath);
            var settings = NotificationSettings();

            Assert.Empty(tracker.DetectEvents("o/r", [
                Pull("#1 First", 1, "2026-06-06T10:00:00Z", state: "open"),
                Pull("#2 Second", 2, "2026-06-06T10:00:00Z", state: "closed"),
                Pull("#3 Third", 3, "2026-06-06T10:00:00Z", state: "open"),
            ], settings));

            var events = tracker.DetectEvents("o/r", [
                Pull("#1 First", 1, "2026-06-06T10:00:00Z", state: "closed"),
                Pull("#2 Second", 2, "2026-06-06T10:00:00Z", state: "open"),
                Pull("#3 Third", 3, "2026-06-06T10:00:00Z", state: "closed", mergedAt: "2026-06-06T10:05:00Z"),
            ], settings);

            Assert.Equal(
                [
                    "PR closed",
                    "PR reopened",
                    "PR merged",
                ],
                events.Select(item => item.Detail));
            Assert.All(events, item => Assert.Equal(PullRequestNotificationEventKind.PullRequestUpdated, item.Kind));
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public void DetectEvents_keeps_state_change_when_comment_notification_also_matches()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"repobar-pr-notifications-{Guid.NewGuid():N}");
        try
        {
            var statePath = Path.Combine(directory, "state.json");
            var tracker = new PullRequestNotificationTracker(statePath);
            var settings = NotificationSettings();

            Assert.Empty(tracker.DetectEvents("o/r", [
                Pull("#1 First", 1, "2026-06-06T10:00:00Z", comments: 1, state: "open"),
            ], settings));

            var events = tracker.DetectEvents("o/r", [
                Pull("#1 First", 1, "2026-06-06T10:05:00Z", comments: 2, state: "closed"),
            ], settings);

            Assert.Equal(
                [
                    PullRequestNotificationEventKind.PullRequestUpdated,
                    PullRequestNotificationEventKind.NewComment,
                ],
                events.Select(item => item.Kind));
            Assert.Equal("PR closed", events[0].Detail);
            Assert.Equal("1 new comment", events[1].Detail);
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public void DetectEvents_loads_legacy_seen_url_state()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"repobar-pr-notifications-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(directory);
            var statePath = Path.Combine(directory, "state.json");
            File.WriteAllText(statePath, """
                {
                  "o/r": ["https://github.com/o/r/pull/1"]
                }
                """);
            var tracker = new PullRequestNotificationTracker(statePath);

            var events = tracker.DetectEvents("o/r", [
                Pull("#1 First", 1, "2026-06-06T10:00:00Z"),
                Pull("#2 Second", 2, "2026-06-06T10:00:00Z"),
            ], NotificationSettings());

            Assert.Single(events);
            Assert.Equal(PullRequestNotificationEventKind.NewPullRequest, events[0].Kind);
            Assert.Equal("#2 Second", events[0].Pull.Title);
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    private static WindowsSettings NotificationSettings()
    {
        return new WindowsSettings
        {
            EnablePullRequestNewNotifications = true,
            EnablePullRequestUpdateNotifications = true,
            EnablePullRequestReviewRequestNotifications = true,
            EnablePullRequestCommentNotifications = true,
        };
    }

    private static WindowsAccountProfile Account(string id, string host)
    {
        return new WindowsAccountProfile
        {
            Id = id,
            Label = id,
            GitHubHost = host,
        };
    }

    private static GitHubListItem Pull(
        string title,
        int number,
        string updatedAt,
        int comments = 0,
        int reviewComments = 0,
        string[]? requestedReviewers = null,
        string[]? requestedTeams = null,
        string state = "open",
        string? mergedAt = null)
    {
        return new GitHubListItem(
            title,
            $"https://github.com/o/r/pull/{number}",
            null,
            new PullRequestNotificationSnapshot(
                DateTimeOffset.Parse(updatedAt),
                comments,
                reviewComments,
                requestedReviewers ?? [],
                requestedTeams ?? [],
                state,
                mergedAt == null ? null : DateTimeOffset.Parse(mergedAt)));
    }
}
