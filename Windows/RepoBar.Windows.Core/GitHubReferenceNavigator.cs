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
        AddRepositoryHeadingReferences(text, matches, claimedSpans);
        AddPrimaryUrlListShortcutClaims(text, claimedSpans);

        foreach (Match match in GitHubCommitUrlRegex().Matches(text))
        {
            matches.Add(new GitHubReferenceCandidate(
                match.Index,
                new GitHubReferenceMatch(
                    $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}",
                    0,
                    "commit",
                    match.Value,
                    GitHubHost.Normalize(match.Groups["host"].Value),
                    NormalizeHash(match.Groups["hash"].Value))));
            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

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

        foreach (Match match in RepositoryColonKindedSeriesRegex().Matches(text))
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
                        number.Kind ?? kind,
                        number.Value.ToString())));
            }

            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        foreach (Match match in OwnerRepoKindedSeriesRegex().Matches(text))
        {
            if (claimedSpans.Any(span => span.Contains(match.Index)))
            {
                continue;
            }

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
                        number.Kind ?? kind,
                        number.Value.ToString())));
            }

            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        foreach (Match match in OwnerRepoSeriesRegex().Matches(text))
        {
            if (claimedSpans.Any(span => span.Contains(match.Index)))
            {
                continue;
            }

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
                        number.Kind ?? kind,
                        number.Value.ToString())));
            }

            claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
        }

        foreach (Match match in GitHubUrlRegex().Matches(text))
        {
            if (claimedSpans.Any(span => span.Contains(match.Index)))
            {
                continue;
            }

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
            if (claimedSpans.Any(span => span.Contains(match.Index)))
            {
                continue;
            }

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
            foreach (Match match in DirectBareNumberRegex().Matches(text))
            {
                if (string.IsNullOrEmpty(match.Groups["prefix"].Value) && match.Groups["number"].Value.Length >= 7)
                {
                    continue;
                }

                matches.Add(new GitHubReferenceCandidate(
                    match.Groups["number"].Index,
                    new GitHubReferenceMatch(
                        defaultRepositoryFullName,
                        long.Parse(match.Groups["number"].Value),
                        "issues",
                        match.Value)));
                claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
            }

            foreach (Match match in CommitHashRegex().Matches(text))
            {
                if (!HasCommitContext(text, match) || claimedSpans.Any(span => span.Contains(match.Index)))
                {
                    continue;
                }

                matches.Add(new GitHubReferenceCandidate(
                    match.Index,
                    new GitHubReferenceMatch(
                        defaultRepositoryFullName,
                        0,
                        "commit",
                        match.Value,
                        Identifier: NormalizeHash(match.Groups["hash"].Value))));
                claimedSpans.Add(new RangeSpan(match.Index, match.Index + match.Length));
            }

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

    private static void AddRepositoryHeadingReferences(
        string text,
        List<GitHubReferenceCandidate> matches,
        List<RangeSpan> claimedSpans)
    {
        string? headingRepository = null;
        var headingIndent = 0;
        var previousHeadingChildHadCommitContext = false;
        var previousHeadingChildHadIssueReferenceContext = false;
        string? pendingHeadingRepository = null;
        var pendingHeadingIndent = 0;
        var lineStart = 0;
        while (lineStart <= text.Length)
        {
            var lineEnd = text.IndexOf('\n', lineStart);
            if (lineEnd < 0)
            {
                lineEnd = text.Length;
            }

            var line = text[lineStart..lineEnd].TrimEnd('\r');
            var indent = LeadingWhitespace(line);
            foreach (Match match in GroupedRepositoryLineRegex().Matches(line))
            {
                var repositoryFullName = $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}";
                foreach (Match number in BareNumberRegex().Matches(match.Groups["refs"].Value))
                {
                    var index = lineStart + match.Groups["refs"].Index + number.Groups["number"].Index;
                    AddCandidateIfUnclaimed(
                        matches,
                        claimedSpans,
                        index,
                        number.Length,
                        new GitHubReferenceMatch(
                            repositoryFullName,
                            long.Parse(number.Groups["number"].Value),
                            "issues",
                            number.Value));
                }
            }

            if (!string.IsNullOrWhiteSpace(pendingHeadingRepository))
            {
                if (string.IsNullOrWhiteSpace(line) || indent <= pendingHeadingIndent)
                {
                    pendingHeadingRepository = null;
                }
                else if (RepositoryCountSummaryLineRegex().IsMatch(line))
                {
                    headingRepository = pendingHeadingRepository;
                    headingIndent = pendingHeadingIndent;
                    pendingHeadingRepository = null;
                    previousHeadingChildHadCommitContext = false;
                    previousHeadingChildHadIssueReferenceContext = false;

                    if (lineEnd == text.Length)
                    {
                        break;
                    }

                    lineStart = lineEnd + 1;
                    continue;
                }
                else
                {
                    pendingHeadingRepository = null;
                }
            }

            var isHeadingChild = !string.IsNullOrWhiteSpace(headingRepository) && indent > headingIndent;
            if (isHeadingChild)
            {
                AddExplicitRepositoryLineReferences(line, lineStart, matches, claimedSpans);

                var headingChildHasCommitContext = HasCommitContext(line);
                var headingChildHasIssueReferenceContext = HeadingChildHasIssueReferenceContext(line);
                if (previousHeadingChildHadCommitContext || headingChildHasCommitContext)
                {
                    foreach (Match match in CommitHashRegex().Matches(line))
                    {
                        var index = lineStart + match.Index;
                        AddCandidateIfUnclaimed(
                            matches,
                            claimedSpans,
                            index,
                            match.Length,
                            new GitHubReferenceMatch(
                                headingRepository,
                                0,
                                "commit",
                                match.Value,
                                Identifier: NormalizeHash(match.Groups["hash"].Value)));
                    }
                }

                foreach (Match match in KindedBareNumberRegex().Matches(line))
                {
                    var index = lineStart + match.Index;
                    if (claimedSpans.Any(span => span.Contains(index)))
                    {
                        continue;
                    }

                    foreach (Capture number in match.Groups["number"].Captures)
                    {
                        matches.Add(new GitHubReferenceCandidate(
                            lineStart + number.Index,
                            new GitHubReferenceMatch(
                                headingRepository,
                                long.Parse(number.Value),
                                NormalizeKind(match.Groups["kind"].Value),
                                number.Value)));
                    }

                    claimedSpans.Add(new RangeSpan(index, index + match.Length));
                }

                foreach (Match match in BareIssueSeriesRegex().Matches(line))
                {
                    var index = lineStart + match.Groups["number"].Index;
                    if (claimedSpans.Any(span => span.Contains(index)))
                    {
                        continue;
                    }

                    var startNumber = long.Parse(match.Groups["number"].Value);
                    matches.Add(new GitHubReferenceCandidate(
                        index,
                        new GitHubReferenceMatch(
                            headingRepository,
                            startNumber,
                            "issues",
                            match.Groups["number"].Value)));

                    foreach (var number in ExpandSeriesNumbers(match.Groups["tail"], startNumber))
                    {
                        matches.Add(new GitHubReferenceCandidate(
                            lineStart + number.Index,
                            new GitHubReferenceMatch(
                                headingRepository,
                                number.Value,
                                number.Kind ?? "issues",
                                number.Value.ToString())));
                    }

                    claimedSpans.Add(new RangeSpan(lineStart + match.Index, lineStart + match.Index + match.Length));
                }

                if (previousHeadingChildHadIssueReferenceContext)
                {
                    foreach (Match match in BackReferenceBareIssueSeriesRegex().Matches(line))
                    {
                        var index = lineStart + match.Groups["number"].Index;
                        if (claimedSpans.Any(span => span.Contains(index)))
                        {
                            continue;
                        }

                        var startNumber = long.Parse(match.Groups["number"].Value);
                        matches.Add(new GitHubReferenceCandidate(
                            index,
                            new GitHubReferenceMatch(
                                headingRepository,
                                startNumber,
                                "issues",
                                match.Groups["number"].Value)));

                        foreach (var number in ExpandSeriesNumbers(match.Groups["tail"], startNumber))
                        {
                            matches.Add(new GitHubReferenceCandidate(
                                lineStart + number.Index,
                                new GitHubReferenceMatch(
                                    headingRepository,
                                    number.Value,
                                    number.Kind ?? "issues",
                                    number.Value.ToString())));
                        }

                        claimedSpans.Add(new RangeSpan(lineStart + match.Index, lineStart + match.Index + match.Length));
                    }
                }

                foreach (Match match in BareNumberRegex().Matches(line))
                {
                    var index = lineStart + match.Index;
                    AddCandidateIfUnclaimed(
                        matches,
                        claimedSpans,
                        index,
                        match.Length,
                        new GitHubReferenceMatch(
                            headingRepository,
                            long.Parse(match.Groups["number"].Value),
                            "issues",
                            match.Value));
                }

                previousHeadingChildHadCommitContext = headingChildHasCommitContext;
                previousHeadingChildHadIssueReferenceContext = headingChildHasIssueReferenceContext;
            }
            else
            {
                headingRepository = null;
                previousHeadingChildHadCommitContext = false;
                previousHeadingChildHadIssueReferenceContext = false;
            }

            var heading = RepositoryCountHeadingRegex().Match(line);
            if (heading.Success)
            {
                headingRepository = $"{heading.Groups["owner"].Value}/{heading.Groups["repo"].Value}";
                headingIndent = indent;
                previousHeadingChildHadCommitContext = false;
                previousHeadingChildHadIssueReferenceContext = false;
                pendingHeadingRepository = null;
                claimedSpans.Add(new RangeSpan(lineStart + heading.Index, lineStart + heading.Index + heading.Length));
            }
            else if (!isHeadingChild)
            {
                var repositoryOnlyHeading = RepositoryOnlyHeadingRegex().Match(line);
                if (repositoryOnlyHeading.Success)
                {
                    headingRepository = null;
                    pendingHeadingRepository = $"{repositoryOnlyHeading.Groups["owner"].Value}/{repositoryOnlyHeading.Groups["repo"].Value}";
                    pendingHeadingIndent = indent;
                    previousHeadingChildHadCommitContext = false;
                    previousHeadingChildHadIssueReferenceContext = false;
                }
            }

            if (lineEnd == text.Length)
            {
                break;
            }

            lineStart = lineEnd + 1;
        }
    }

    private static void AddPrimaryUrlListShortcutClaims(string text, List<RangeSpan> claimedSpans)
    {
        var lines = EnumerateLines(text);
        var shortcutNumbers = new HashSet<long>();
        for (var i = 0; i < lines.Count; i++)
        {
            var lineInfo = lines[i];
            var primary = PrimaryUrlListItemRegex().Match(lineInfo.Text);
            if (!primary.Success)
            {
                continue;
            }

            var number = long.Parse(primary.Groups["number"].Value);
            var matchingUrl = GitHubUrlRegex().Matches(lineInfo.Text)
                .Any(url => long.Parse(url.Groups["number"].Value) == number);
            for (var next = i + 1; !matchingUrl && next < lines.Count; next++)
            {
                var candidate = lines[next];
                if (string.IsNullOrWhiteSpace(candidate.Text))
                {
                    break;
                }

                if (LeadingWhitespace(candidate.Text) <= lineInfo.Indent)
                {
                    break;
                }

                matchingUrl = GitHubUrlRegex().Matches(candidate.Text)
                    .Any(url => long.Parse(url.Groups["number"].Value) == number);
            }

            if (matchingUrl)
            {
                shortcutNumbers.Add(number);
                ClaimBareNumbersInPrimaryUrlItem(lines, i, claimedSpans);
            }
        }

        if (shortcutNumbers.Count == 0)
        {
            return;
        }

        foreach (var lineInfo in lines)
        {
            foreach (Match match in OwnerRepoNumberRegex().Matches(lineInfo.Text))
            {
                if (shortcutNumbers.Contains(long.Parse(match.Groups["number"].Value)))
                {
                    claimedSpans.Add(new RangeSpan(lineInfo.Start + match.Index, lineInfo.Start + match.Index + match.Length));
                }
            }
        }
    }

    private static void ClaimBareNumbersInPrimaryUrlItem(
        IReadOnlyList<LineInfo> lines,
        int primaryLineIndex,
        List<RangeSpan> claimedSpans)
    {
        var primaryLine = lines[primaryLineIndex];
        for (var i = primaryLineIndex; i < lines.Count; i++)
        {
            var lineInfo = lines[i];
            if (i > primaryLineIndex)
            {
                if (string.IsNullOrWhiteSpace(lineInfo.Text))
                {
                    break;
                }

                if (lineInfo.Indent <= primaryLine.Indent)
                {
                    break;
                }
            }

            foreach (Match match in BareNumberRegex().Matches(lineInfo.Text))
            {
                claimedSpans.Add(new RangeSpan(lineInfo.Start + match.Index, lineInfo.Start + match.Index + match.Length));
            }
        }
    }

    private static void AddExplicitRepositoryLineReferences(
        string line,
        int lineStart,
        List<GitHubReferenceCandidate> matches,
        List<RangeSpan> claimedSpans)
    {
        foreach (Match match in OwnerRepoKindedSeriesRegex().Matches(line))
        {
            if (claimedSpans.Any(span => span.Contains(lineStart + match.Index)))
            {
                continue;
            }

            var repositoryFullName = $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}";
            var kind = NormalizeKind(match.Groups["kind"].Value);
            var startNumber = long.Parse(match.Groups["number"].Value);
            matches.Add(new GitHubReferenceCandidate(
                lineStart + match.Groups["number"].Index,
                new GitHubReferenceMatch(
                    repositoryFullName,
                    startNumber,
                    kind,
                    match.Groups["number"].Value)));

            foreach (var number in ExpandSeriesNumbers(match.Groups["tail"], startNumber))
            {
                matches.Add(new GitHubReferenceCandidate(
                    lineStart + number.Index,
                    new GitHubReferenceMatch(
                        repositoryFullName,
                        number.Value,
                        number.Kind ?? kind,
                        number.Value.ToString())));
            }

            claimedSpans.Add(new RangeSpan(lineStart + match.Index, lineStart + match.Index + match.Length));
        }

        foreach (Match match in OwnerRepoSeriesRegex().Matches(line))
        {
            if (claimedSpans.Any(span => span.Contains(lineStart + match.Index)))
            {
                continue;
            }

            var repositoryFullName = $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}";
            var kind = NormalizeKind(match.Groups["kind"].Value);
            var startNumber = long.Parse(match.Groups["number"].Value);
            matches.Add(new GitHubReferenceCandidate(
                lineStart + match.Groups["number"].Index,
                new GitHubReferenceMatch(
                    repositoryFullName,
                    startNumber,
                    kind,
                    match.Groups["number"].Value)));

            foreach (var number in ExpandSeriesNumbers(match.Groups["tail"], startNumber))
            {
                matches.Add(new GitHubReferenceCandidate(
                    lineStart + number.Index,
                    new GitHubReferenceMatch(
                        repositoryFullName,
                        number.Value,
                        number.Kind ?? kind,
                        number.Value.ToString())));
            }

            claimedSpans.Add(new RangeSpan(lineStart + match.Index, lineStart + match.Index + match.Length));
        }

        foreach (Match match in OwnerRepoNumberRegex().Matches(line))
        {
            if (claimedSpans.Any(span => span.Contains(lineStart + match.Index)))
            {
                continue;
            }

            matches.Add(new GitHubReferenceCandidate(
                lineStart + match.Groups["number"].Index,
                new GitHubReferenceMatch(
                    $"{match.Groups["owner"].Value}/{match.Groups["repo"].Value}",
                    long.Parse(match.Groups["number"].Value),
                    NormalizeKind(match.Groups["kind"].Value),
                    match.Value)));
            claimedSpans.Add(new RangeSpan(lineStart + match.Index, lineStart + match.Index + match.Length));
        }
    }

    private static void AddCandidateIfUnclaimed(
        List<GitHubReferenceCandidate> matches,
        List<RangeSpan> claimedSpans,
        int index,
        int length,
        GitHubReferenceMatch reference)
    {
        if (claimedSpans.Any(span => span.Contains(index)))
        {
            return;
        }

        matches.Add(new GitHubReferenceCandidate(index, reference));
        claimedSpans.Add(new RangeSpan(index, index + length));
    }

    private static int LeadingWhitespace(string line)
    {
        var count = 0;
        while (count < line.Length && char.IsWhiteSpace(line[count]))
        {
            count++;
        }

        return count;
    }

    private static IReadOnlyList<LineInfo> EnumerateLines(string text)
    {
        var lines = new List<LineInfo>();
        var lineStart = 0;
        while (lineStart <= text.Length)
        {
            var lineEnd = text.IndexOf('\n', lineStart);
            if (lineEnd < 0)
            {
                lineEnd = text.Length;
            }

            var line = text[lineStart..lineEnd].TrimEnd('\r');
            lines.Add(new LineInfo(lineStart, line, LeadingWhitespace(line)));

            if (lineEnd == text.Length)
            {
                break;
            }

            lineStart = lineEnd + 1;
        }

        return lines;
    }

    public static Uri BuildUri(GitHubReferenceMatch reference, string host)
    {
        var normalizedHost = GitHubHost.Normalize(reference.Host ?? host);
        var pathKind = PathKind(reference.Kind);
        return new Uri($"https://{normalizedHost}/{reference.RepositoryFullName}/{pathKind}/{reference.ReferenceValue}");
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
            var kind = token.Groups["kind"].Success ? NormalizeKind(token.Groups["kind"].Value) : null;
            if (separator == "-" && next > previous)
            {
                for (var number = previous + 1; number <= next; number++)
                {
                    yield return new SeriesNumber(number, index, kind);
                }
            }
            else
            {
                yield return new SeriesNumber(next, index, kind);
            }

            previous = next;
        }
    }

    private static bool IsPullRequestKind(string value)
    {
        return string.Equals(value, "pr", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "prs", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pull", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pulls", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pull request", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "pull requests", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsWorkflowRunKind(string value)
    {
        return string.Equals(value, "actions", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "workflowRun", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "workflow-run", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsCommitKind(string value)
    {
        return string.Equals(value, "commit", StringComparison.OrdinalIgnoreCase);
    }

    private static string PathKind(string kind)
    {
        if (IsWorkflowRunKind(kind))
        {
            return "actions/runs";
        }

        if (IsCommitKind(kind))
        {
            return "commit";
        }

        return IsPullRequestKind(kind) ? "pull" : "issues";
    }

    private static string DedupeKey(GitHubReferenceMatch reference, string host)
    {
        var kind = IsWorkflowRunKind(reference.Kind) ? "actions" : IsCommitKind(reference.Kind) ? "commit" : "issue";
        return $"{reference.Host ?? GitHubHost.Normalize(host)}:{reference.RepositoryFullName}:{kind}#{reference.ReferenceValue}";
    }

    private static bool HasCommitContext(string text, Match match)
    {
        return string.Equals(text.Trim(), match.Value, StringComparison.OrdinalIgnoreCase) ||
            HasCommitContext(text);
    }

    private static bool HasCommitContext(string text)
    {
        return
            text.Contains("commit", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("hash", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("sha", StringComparison.OrdinalIgnoreCase);
    }

    private static bool HeadingChildHasIssueReferenceContext(string text)
    {
        var lastSentence = LastNonEmptySentence(text);
        return !string.IsNullOrWhiteSpace(lastSentence) &&
            !IsIssueCountSummary(lastSentence) &&
            HasIssueReferenceContext(lastSentence);
    }

    private static string? LastNonEmptySentence(string text)
    {
        return text
            .Split(new[] { '.', '!', '?' }, StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .LastOrDefault();
    }

    private static bool HasIssueReferenceContext(string text)
    {
        return IssueReferenceContextRegex().IsMatch(text) ||
            text.Contains("pull request", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("security fix", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("fix/enhancement", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsIssueCountSummary(string text)
    {
        return IssueCountSummaryRegex().IsMatch(text) ||
            RepositoryCountSummaryLineRegex().IsMatch(text);
    }

    private static string NormalizeHash(string value)
    {
        return value.ToLowerInvariant();
    }

    [GeneratedRegex(@"https?://(?<host>[^/\s]+)/(?<owner>[^/\s]+)/(?<repo>[^/\s]+)/(?:commits?|pull/\d+/changes)/(?<hash>[0-9a-f]{7,40})", RegexOptions.IgnoreCase)]
    private static partial Regex GitHubCommitUrlRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+):\s*(?<refs>#\d+(?:\s*(?:,|and)\s*#?\d+)*)\b", RegexOptions.IgnoreCase)]
    private static partial Regex GroupedRepositoryLineRegex();

    [GeneratedRegex(@"^\s*(?:(?:[-*]|\d+[.)])\s*)?(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+):\s*(?:(?:\d+\s+(?:issues?|PRs?|pull requests?))(?:\s*/\s*)?)+$", RegexOptions.IgnoreCase)]
    private static partial Regex RepositoryCountHeadingRegex();

    [GeneratedRegex(@"^\s*(?:(?:[-*]|\d+[.)])\s*)?(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)\s*$", RegexOptions.IgnoreCase)]
    private static partial Regex RepositoryOnlyHeadingRegex();

    [GeneratedRegex(@"^\s*(?:[-*]\s*)?(?:(?:\d+\s+(?:issues?|PRs?|pull requests?))(?:\s*/\s*)?)+$", RegexOptions.IgnoreCase)]
    private static partial Regex RepositoryCountSummaryLineRegex();

    [GeneratedRegex(@"https?://(?<host>[^/\s]+)/(?<owner>[^/\s]+)/(?<repo>[^/\s]+)/actions/runs/(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex GitHubActionsRunUrlRegex();

    [GeneratedRegex(@"https?://(?<host>[^/\s]+)/(?<owner>[^/\s]+)/(?<repo>[^/\s]+)/(?<kind>issues|pull|pulls)/(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex GitHubUrlRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+):[ \t]*(?<kind>PRs?|pull requests?|issues?)[ \t]+#?(?<number>\d+)(?<tail>(?:[ \t]*(?:,|and)[ \t]*(?:(?:PRs?|pull requests?|issues?)[ \t]+)?#?\d+)*)\b", RegexOptions.IgnoreCase)]
    private static partial Regex RepositoryColonKindedSeriesRegex();

    [GeneratedRegex(@"(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)[ \t]+(?<kind>PRs?|pull requests?|issues?)[ \t]+#?(?<number>\d+)(?<tail>(?:[ \t]*(?:,|and)[ \t]*(?:(?:PRs?|pull requests?|issues?)[ \t]+)?#?\d+)*)\b", RegexOptions.IgnoreCase)]
    private static partial Regex OwnerRepoKindedSeriesRegex();

    [GeneratedRegex(@"(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)[ \t]*(?:(?<kind>PR|pull request|issue)[ \t]*)?#(?<number>\d+)(?<tail>(?:[ \t]*(?:-|/|,|and)[ \t]*(?:(?:PR|pull request|issue)[ \t]+)?#?\d+)+)\b", RegexOptions.IgnoreCase)]
    private static partial Regex OwnerRepoSeriesRegex();

    [GeneratedRegex(@"(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)[ \t]*(?:(?<kind>PR|pull request|issue)[ \t]*#?|gh-|#)(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex OwnerRepoNumberRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])(?<repo>[A-Za-z0-9_.-]+)#(?<number>\d+)\b", RegexOptions.IgnoreCase)]
    private static partial Regex RepositoryNameNumberRegex();

    [GeneratedRegex(@"(?<separator>-|/|,|and)[ \t]*(?:(?<kind>PRs?|pull requests?|issues?)[ \t]+)?#?(?<number>\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex SeriesTokenRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])(?<kind>PRs?|pull requests?|issues?)\s+#?(?<number>\d+)(?:\s*(?:,|and)\s*#?(?<number>\d+))*\b", RegexOptions.IgnoreCase)]
    private static partial Regex KindedBareNumberRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])#(?<number>\d+)(?<tail>(?:\s*(?:-|/|,|and)\s*#?\d+)+)\b", RegexOptions.IgnoreCase)]
    private static partial Regex BareIssueSeriesRegex();

    [GeneratedRegex(@"^\s*(?:[-*]\s*)?(?:that|this|it|they|these|those)\s+(?:(?:is|are|was|were)\s+)?#?(?<number>\d+)(?<tail>(?:\s*(?:-|/|,|and)\s*#?\d+)*)\b", RegexOptions.IgnoreCase)]
    private static partial Regex BackReferenceBareIssueSeriesRegex();

    [GeneratedRegex(@"^\s*(?<prefix>gh-|#)?(?<number>\d+)\.?\s*$", RegexOptions.IgnoreCase)]
    private static partial Regex DirectBareNumberRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9])(?<hash>[0-9a-f]{7,40})(?![A-Za-z0-9])", RegexOptions.IgnoreCase)]
    private static partial Regex CommitHashRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9_/.-])#(?<number>\d+)\b")]
    private static partial Regex BareNumberRegex();

    [GeneratedRegex(@"^\s*(?:(?:[-*]|\d+[.)])\s*)?(?<ref>#(?<number>\d+))\b")]
    private static partial Regex PrimaryUrlListItemRegex();

    [GeneratedRegex(@"\b(?:prs?|issues?|pull)\b", RegexOptions.IgnoreCase)]
    private static partial Regex IssueReferenceContextRegex();

    [GeneratedRegex(@"^\s*(?:open|closed)\s+(?:prs?|issues?)\s*:\s*\d*\.?\s*$", RegexOptions.IgnoreCase)]
    private static partial Regex IssueCountSummaryRegex();

    private readonly record struct RangeSpan(int Start, int End)
    {
        public bool Contains(int index)
        {
            return index >= Start && index < End;
        }
    }

    private readonly record struct GitHubReferenceCandidate(int Index, GitHubReferenceMatch Reference);

    private readonly record struct SeriesNumber(long Value, int Index, string? Kind);

    private readonly record struct LineInfo(int Start, string Text, int Indent);
}

internal sealed record GitHubReferenceMatch(string RepositoryFullName, long Number, string Kind, string RawText, string? Host = null, string? Identifier = null)
{
    public string ReferenceValue => Identifier ?? Number.ToString();

    public string ReferenceLabel => string.Equals(Kind, "commit", StringComparison.OrdinalIgnoreCase)
        ? $"@{ReferenceValue[..Math.Min(10, ReferenceValue.Length)]}"
        : string.Equals(Kind, "actions", StringComparison.OrdinalIgnoreCase)
            ? $"run {ReferenceValue}"
            : $"#{ReferenceValue}";

    public string DisplayText => $"{RepositoryFullName} {ReferenceLabel}";
}
