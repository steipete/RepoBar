using System.Text.RegularExpressions;

namespace RepoBar.Windows;

internal static partial class GitHubReferenceNavigator
{
    public static IReadOnlyList<GitHubReferenceMatch> FindReferences(
        string text,
        string host,
        string? defaultRepositoryFullName)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return [];
        }

        var matches = new List<GitHubReferenceMatch>();
        var claimedSpans = new List<RangeSpan>();
        foreach (Match match in GitHubUrlRegex().Matches(text))
        {
            matches.Add(new GitHubReferenceMatch(
                $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}",
                int.Parse(match.Groups["number"].Value),
                match.Groups["kind"].Value,
                match.Value,
                GitHubHost.Normalize(match.Groups["host"].Value)));
            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        foreach (Match match in OwnerRepoNumberRegex().Matches(text))
        {
            matches.Add(new GitHubReferenceMatch(
                $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}",
                int.Parse(match.Groups["number"].Value),
                NormalizeKind(match.Groups["kind"].Value),
                match.Value));
            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        if (!string.IsNullOrWhiteSpace(defaultRepositoryFullName))
        {
            foreach (Match match in BareNumberRegex().Matches(text))
            {
                if (claimedSpans.Any(span => span.Contains(match.Index)))
                {
                    continue;
                }

                matches.Add(new GitHubReferenceMatch(
                    defaultRepositoryFullName,
                    int.Parse(match.Groups["number"].Value),
                    "issues",
                    match.Value));
            }
        }

        return matches
            .GroupBy(reference => $"{reference.Host ?? GitHubHost.Normalize(host)}:{reference.RepositoryFullName}#{reference.Number}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .OrderBy(reference => reference.RepositoryFullName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(reference => reference.Number)
            .ToArray();
    }

    public static Uri BuildUri(GitHubReferenceMatch reference, string host)
    {
        var normalizedHost = GitHubHost.Normalize(reference.Host ?? host);
        var pathKind = IsPullRequestKind(reference.Kind)
                ? "pull"
                : "issues";
        return new Uri($"https://{normalizedHost}/{reference.RepositoryFullName}/{pathKind}/{reference.Number}");
    }

    private static string NormalizeKind(string value)
    {
        return IsPullRequestKind(value) ? "pull" : "issues";
    }

    private static bool IsPullRequestKind(string value)
    {
        return string.Equals(value, "pr", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pull", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pulls", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pull request", StringComparison.OrdinalIgnoreCase);
    }

    [GeneratedRegex(@"https?://(?<host>[^/\s]+)/(?<owner>[^/\s]+)/(?<repo>[^/\s]+)/(?<kind>issues|pull|pulls)/(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex GitHubUrlRegex();

    [GeneratedRegex(@"(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)\s*(?:(?<kind>PR|pull request|issue)\s*#?|#)(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex OwnerRepoNumberRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])#(?<number>\d+)\b")]
    private static partial Regex BareNumberRegex();

    private readonly record struct RangeSpan(int Start, int End)
    {
        public bool Contains(int index)
        {
            return index >= Start && index < End;
        }
    }
}

internal sealed record GitHubReferenceMatch(string RepositoryFullName, int Number, string Kind, string RawText, string? Host = null)
{
    public string DisplayText => $"{RepositoryFullName} #{Number}";
}
