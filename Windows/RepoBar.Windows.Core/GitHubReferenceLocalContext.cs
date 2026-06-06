namespace RepoBar.Windows;

internal static class GitHubReferenceLocalContext
{
    public static string? RepositoryContext(string text, LocalGitIndex localGitIndex, string activeGitHubHost)
    {
        if (string.IsNullOrWhiteSpace(text) || localGitIndex.Repositories.Count == 0)
        {
            return null;
        }

        var activeHost = GitHubHost.Normalize(activeGitHubHost);
        var normalizedText = NormalizePathText(text);
        var matches = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var repository in localGitIndex.Repositories)
        {
            if (string.IsNullOrWhiteSpace(repository.FullName) || string.IsNullOrWhiteSpace(repository.Path))
            {
                continue;
            }

            if (!string.IsNullOrWhiteSpace(repository.GitHubHost) &&
                !string.Equals(GitHubHost.Normalize(repository.GitHubHost), activeHost, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var normalizedPath = NormalizePathText(repository.Path);
            if (ContainsPath(normalizedText, normalizedPath) && seen.Add(repository.FullName))
            {
                matches.Add(repository.FullName);
            }
        }

        return matches.Count == 1 ? matches[0] : null;
    }

    public static IReadOnlyList<string> KnownRepositories(WindowsSettings settings, LocalGitIndex localGitIndex)
    {
        var activeHost = GitHubHost.Normalize(settings.GitHubHost);
        return settings.GetActiveRepositories()
            .Where(repository => repository.IsVisible)
            .Select(repository => repository.FullName)
            .Concat(localGitIndex.Repositories
                .Where(repository => !string.IsNullOrWhiteSpace(repository.FullName) &&
                    (string.IsNullOrWhiteSpace(repository.GitHubHost) ||
                        string.Equals(GitHubHost.Normalize(repository.GitHubHost), activeHost, StringComparison.OrdinalIgnoreCase)))
                .Select(repository => repository.FullName!))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static string NormalizePathText(string value)
    {
        return value.Replace('\\', '/').Trim();
    }

    private static bool ContainsPath(string text, string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        var index = 0;
        while (index < text.Length)
        {
            index = text.IndexOf(path, index, StringComparison.OrdinalIgnoreCase);
            if (index < 0)
            {
                return false;
            }

            var end = index + path.Length;
            if (IsPathBoundary(text, index - 1) && IsPathBoundary(text, end))
            {
                return true;
            }

            index = end;
        }

        return false;
    }

    private static bool IsPathBoundary(string text, int index)
    {
        if (index < 0 || index >= text.Length)
        {
            return true;
        }

        var value = text[index];
        return char.IsWhiteSpace(value) || value is '"' or '\'' or '`' or '<' or '>' or '(' or ')' or '[' or ']' or '{' or '}' or '|' or '\u00b7' or ':' or ';' or ',';
    }
}
