using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class PullRequestNotificationTrackerTests
{
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
}
