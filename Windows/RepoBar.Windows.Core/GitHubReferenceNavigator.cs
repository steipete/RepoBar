using System.Text.RegularExpressions;

namespace RepoBar.Windows;

internal static partial class GitHubReferenceNavigator
{
    public static IReadOnlyList<GitHubReferenceMatch> FindReferences(
        string text,
        string host,
        string? defaultRepositoryFullName,
        IEnumerable<string>? knownRepositoryFullNames = null)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return [];
        }

        var matches = new List<GitHubReferenceCandidate>();
        var claimedSpans = new List<RangeSpan>();
        var uniqueRepositoriesByName = UniqueRepositoriesByName(defaultRepositoryFullName, knownRepositoryFullNames);
        foreach (Match match in GitHubActionsRunUrlRegex().Matches(text))
        {
            matches.Add(new GitHubReferenceCandidate(
                match.Index,
                new GitHubReferenceMatch(
                    $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}",
                    long.Parse(match.Groups["number"].Value),
                    "actions",
                    match.Value,
                    GitHubHost.Normalize(match.Groups["host"].Value))));
            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        foreach (Match match in OwnerRepoSeriesRegex().Matches(text))
        {
            var repositoryFullName = $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}";
            var kind = NormalizeKind(match.Groups["kind"].Value);
            var startNumber = long.Parse(match.Groups["number"].Value);
            matches.Add(new GitHubReferenceCandidate(
                match.Groups["number"].Index,
                new GitHubReferenceMatch(
                    repositoryFullName,
                    startNumber,
                    kind,
                    match.Groups["number"].Value)));

            foreach (var number in ExpandSeriesNumbers(match.Groups["tail"], startNumber))
            {
                matches.Add(new GitHubReferenceCandidate(
                    number.Index,
                    new GitHubReferenceMatch(
                        repositoryFullName,
                        number.Value,
                        kind,
                        number.Value.ToString())));
            }

            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        foreach (Match match in GitHubUrlRegex().Matches(text))
        {
            matches.Add(new GitHubReferenceCandidate(
                match.Index,
                new GitHubReferenceMatch(
                    $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}",
                    long.Parse(match.Groups["number"].Value),
                    match.Groups["kind"].Value,
                    match.Value,
                    GitHubHost.Normalize(match.Groups["host"].Value))));
            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        foreach (Match match in OwnerRepoNumberRegex().Matches(text))
        {
            matches.Add(new GitHubReferenceCandidate(
                match.Index,
                new GitHubReferenceMatch(
                    $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}",
                    long.Parse(match.Groups["number"].Value),
                    NormalizeKind(match.Groups["kind"].Value),
                    match.Value)));
            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        foreach (Match match in RepositoryNameNumberRegex().Matches(text))
        {
            if (claimedSpans.Any(span => span.Contains(match.Index)))
            {
                continue;
            }

            var repositoryName = match.Groups["repo"].Value;
            if (uniqueRepositoriesByName.TryGetValue(repositoryName, out var repositoryFullName))
            {
                matches.Add(new GitHubReferenceCandidate(
                    match.Index,
                    new GitHubReferenceMatch(
                        repositoryFullName,
                        long.Parse(match.Groups["number"].Value),
                        "issues",
                        match.Value)));
            }

            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        if (!string.IsNullOrWhiteSpace(defaultRepositoryFullName))
        {
            foreach (Match match in KindedBareNumberRegex().Matches(text))
            {
                if (claimedSpans.Any(span => span.Contains(match.Index)))
                {
                    continue;
                }

                foreach (Capture number in match.Groups["number"].Captures)
                {
                    matches.Add(new GitHubReferenceCandidate(
                        number.Index,
                        new GitHubReferenceMatch(
                            defaultRepositoryFullName,
                            long.Parse(number.Value),
                            NormalizeKind(match.Groups["kind"].Value),
                            number.Value)));
                }

                claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
            }

            foreach (Match match in BareNumberRegex().Matches(text))
            {
                if (claimedSpans.Any(span => span.Contains(match.Index)))
                {
                    continue;
                }

                matches.Add(new GitHubReferenceCandidate(
                    match.Index,
                    new GitHubReferenceMatch(
                        defaultRepositoryFullName,
                        long.Parse(match.Groups["number"].Value),
                        "issues",
                        match.Value)));
            }
        }

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        return matches
            .OrderBy(candidate => candidate.Index)
            .Select(candidate => candidate.Reference)
            .Where(reference => seen.Add(DedupeKey(reference, host)))
            .ToArray();
    }

    public static Uri BuildUri(GitHubReferenceMatch reference, string host)
    {
        var normalizedHost = GitHubHost.Normalize(reference.Host ?? host);
        var pathKind = PathKind(reference.Kind);
        return new Uri($"https://{normalizedHost}/{reference.RepositoryFullName}/{pathKind}/{reference.Number}");
    }

    private static string NormalizeKind(string value)
    {
        return IsPullRequestKind(value) ? "pull" : "issues";
    }

    private static Dictionary<string, string> UniqueRepositoriesByName(
        string? defaultRepositoryFullName,
        IEnumerable<string>? knownRepositoryFullNames)
    {
        var repositories = (knownRepositoryFullNames ?? [])
            .Append(defaultRepositoryFullName)
            .Where(repository => !string.IsNullOrWhiteSpace(repository))
            .Select(repository => repository!)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(repository => new
            {
                FullName = repository,
                Name = RepositoryName(repository),
            })
            .Where(repository => !string.IsNullOrWhiteSpace(repository.Name))
            .GroupBy(repository => repository.Name, StringComparer.OrdinalIgnoreCase);

        return repositories
            .Where(group => group.Count() == 1)
            .ToDictionary(
                group => group.Key,
                group => group.Single().FullName,
                StringComparer.OrdinalIgnoreCase);
    }

    private static string? RepositoryName(string repositoryFullName)
    {
        var parts = repositoryFullName.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return parts.Length == 2 ? parts[1] : null;
    }

    private static IEnumerable<SeriesNumber> ExpandSeriesNumbers(Group tail, long startNumber)
    {
        var previous = startNumber;
        foreach (Match token in SeriesTokenRegex().Matches(tail.Value))
        {
            var separator = token.Groups["separator"].Value;
            var next = long.Parse(token.Groups["number"].Value);
            var index = tail.Index + token.Groups["number"].Index;
            if (separator == "-" && next > previous)
            {
                for (var number = previous + 1; number <= next; number++)
                {
                    yield return new SeriesNumber(number, index);
                }
            }
            else
            {
                yield return new SeriesNumber(next, index);
            }

            previous = next;
        }
    }

    private static bool IsPullRequestKind(string value)
    {
        return string.Equals(value, "pr", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pull", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pulls", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pull request", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsWorkflowRunKind(string value)
    {
        return string.Equals(value, "actions", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "workflowRun", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "workflow-run", StringComparison.OrdinalIgnoreCase);
    }

    private static string PathKind(string kind)
    {
        if (IsWorkflowRunKind(kind))
        {
            return "actions/runs";
        }

        return IsPullRequestKind(kind) ? "pull" : "issues";
    }

    private static string DedupeKey(GitHubReferenceMatch reference, string host)
    {
        var kind = IsWorkflowRunKind(reference.Kind) ? "actions" : "issue";
        return $"{reference.Host ?? GitHubHost.Normalize(host)}:{reference.RepositoryFullName}:{kind}#{reference.Number}";
    }

    [GeneratedRegex(@"https?://(?<host>[^/\s]+)/(?<owner>[^/\s]+)/(?<repo>[^/\s]+)/actions/runs/(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex GitHubActionsRunUrlRegex();

    [GeneratedRegex(@"https?://(?<host>[^/\s]+)/(?<owner>[^/\s]+)/(?<repo>[^/\s]+)/(?<kind>issues|pull|pulls)/(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex GitHubUrlRegex();

    [GeneratedRegex(@"(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)\s*(?:(?<kind>PR|pull request|issue)\s*)?#(?<number>\d+)(?<tail>(?:\s*(?:-|/|,|and)\s*#?\d+)+)\b", RegexOptions.IgnoreCase)]
    private static partial Regex OwnerRepoSeriesRegex();

    [GeneratedRegex(@"(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)\s*(?:(?<kind>PR|pull request|issue)\s*#?|#)(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex OwnerRepoNumberRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])(?<repo>[A-Za-z0-9_.-]+)#(?<number>\d+)\b", RegexOptions.IgnoreCase)]
    private static partial Regex RepositoryNameNumberRegex();

    [GeneratedRegex(@"(?<separator>-|/|,|and)\s*#?(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex SeriesTokenRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])(?<kind>PR|pull request|issue)\s+#?(?<number>\d+)(?:\s*(?:,|and)\s*#?(?<number>\d+))*\b", RegexOptions.IgnoreCase)]
    private static partial Regex KindedBareNumberRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])#(?<number>\d+)\b")]
    private static partial Regex BareNumberRegex();

    private readonly record struct RangeSpan(int Start, int End)
    {
        public bool Contains(int index)
        {
            return index >= Start && index < End;
        }
    }

    private readonly record struct GitHubReferenceCandidate(int Index, GitHubReferenceMatch Reference);

    private readonly record struct SeriesNumber(long Value, int Index);
}

internal sealed record GitHubReferenceMatch(string RepositoryFullName, long Number, string Kind, string RawText, string? Host = null)
{
    public string DisplayText => $"{RepositoryFullName} #{Number}";
}
