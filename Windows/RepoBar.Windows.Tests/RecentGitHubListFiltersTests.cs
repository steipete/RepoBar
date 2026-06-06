using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class RecentGitHubListFiltersTests
{
    [Fact]
    public void Issues_filters_mine_by_author_or_assignee()
    {
        var issues = new[]
        {
            new GitHubListItem("#1 Mine", null, null, AuthorLogin: "octocat"),
            new GitHubListItem("#2 Assigned", null, null, AssigneeLogins: ["octocat"]),
            new GitHubListItem("#3 Other", null, null, AuthorLogin: "hubot", AssigneeLogins: ["someone"]),
        };

        var filtered = RecentGitHubListFilters.Issues(issues, RecentIssueListFilter.Mine, "OctoCat");

        Assert.Equal(["#1 Mine", "#2 Assigned"], filtered.Select(item => item.Title));
    }

    [Fact]
    public void PullRequests_filters_mine_commented_and_reviewed()
    {
        var pullRequests = new[]
        {
            Pull("#1 Mine", "octocat", comments: 0, reviewComments: 0),
            Pull("#2 Commented", "hubot", comments: 2, reviewComments: 0),
            Pull("#3 Reviewed", "hubot", comments: 0, reviewComments: 3),
            Pull("#4 Quiet", "hubot", comments: 0, reviewComments: 0),
        };

        Assert.Equal(
            ["#1 Mine"],
            RecentGitHubListFilters.PullRequests(pullRequests, RecentPullRequestListFilter.Mine, "OCTOCAT").Select(item => item.Title));
        Assert.Equal(
            ["#2 Commented"],
            RecentGitHubListFilters.PullRequests(pullRequests, RecentPullRequestListFilter.Commented, "octocat").Select(item => item.Title));
        Assert.Equal(
            ["#3 Reviewed"],
            RecentGitHubListFilters.PullRequests(pullRequests, RecentPullRequestListFilter.Reviewed, "octocat").Select(item => item.Title));
    }

    private static GitHubListItem Pull(string title, string author, int comments, int reviewComments)
    {
        return new GitHubListItem(
            title,
            null,
            null,
            new PullRequestNotificationSnapshot(null, comments, reviewComments, [], []),
            AuthorLogin: author,
            CommentCount: comments);
    }
}
