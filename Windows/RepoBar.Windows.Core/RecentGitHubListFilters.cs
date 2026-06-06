namespace RepoBar.Windows;

internal enum RecentIssueListFilter
{
    All,
    Mine,
}

internal enum RecentPullRequestListFilter
{
    All,
    Mine,
    Commented,
    Reviewed,
}

internal static class RecentGitHubListFilters
{
    public static IReadOnlyList<GitHubListItem> Issues(
        IReadOnlyList<GitHubListItem> issues,
        RecentIssueListFilter filter,
        string? viewerLogin)
    {
        return filter switch
        {
            RecentIssueListFilter.Mine => issues
                .Where(issue => IsMine(issue, viewerLogin))
                .ToArray(),
            _ => issues,
        };
    }

    public static IReadOnlyList<GitHubListItem> IssuesWithLabel(IReadOnlyList<GitHubListItem> issues, string labelName)
    {
        if (string.IsNullOrWhiteSpace(labelName))
        {
            return [];
        }

        return issues
            .Where(issue => issue.LabelNames?.Any(label => IsSameLabel(label, labelName)) == true)
            .ToArray();
    }

    public static IReadOnlyList<string> IssueLabels(IReadOnlyList<GitHubListItem> issues)
    {
        return issues
            .SelectMany(issue => issue.LabelNames ?? [])
            .Select(label => label.Trim())
            .Where(label => label.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(label => label, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public static IReadOnlyList<GitHubListItem> PullRequests(
        IReadOnlyList<GitHubListItem> pullRequests,
        RecentPullRequestListFilter filter,
        string? viewerLogin)
    {
        return filter switch
        {
            RecentPullRequestListFilter.Mine => pullRequests
                .Where(pullRequest => IsAuthor(pullRequest, viewerLogin))
                .ToArray(),
            RecentPullRequestListFilter.Commented => pullRequests
                .Where(pullRequest => pullRequest.PullRequestSnapshot?.CommentCount > 0 || pullRequest.CommentCount > 0)
                .ToArray(),
            RecentPullRequestListFilter.Reviewed => pullRequests
                .Where(pullRequest => pullRequest.PullRequestSnapshot?.ReviewCommentCount > 0)
                .ToArray(),
            _ => pullRequests,
        };
    }

    private static bool IsMine(GitHubListItem item, string? viewerLogin)
    {
        if (IsAuthor(item, viewerLogin))
        {
            return true;
        }

        if (string.IsNullOrWhiteSpace(viewerLogin) || item.AssigneeLogins == null)
        {
            return false;
        }

        return item.AssigneeLogins.Any(assignee => IsSameLogin(assignee, viewerLogin));
    }

    private static bool IsAuthor(GitHubListItem item, string? viewerLogin)
    {
        return IsSameLogin(item.AuthorLogin, viewerLogin);
    }

    private static bool IsSameLogin(string? lhs, string? rhs)
    {
        return !string.IsNullOrWhiteSpace(lhs) &&
            !string.IsNullOrWhiteSpace(rhs) &&
            string.Equals(lhs.Trim(), rhs.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsSameLabel(string? lhs, string? rhs)
    {
        return !string.IsNullOrWhiteSpace(lhs) &&
            !string.IsNullOrWhiteSpace(rhs) &&
            string.Equals(lhs.Trim(), rhs.Trim(), StringComparison.OrdinalIgnoreCase);
    }
}
