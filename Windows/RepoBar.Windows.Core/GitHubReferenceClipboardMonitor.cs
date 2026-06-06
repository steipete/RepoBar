namespace RepoBar.Windows;

internal sealed class GitHubReferenceClipboardMonitor
{
    private string? _lastClipboardText;
    private string? _lastReferenceKey;
    private bool _hasBaseline;

    public GitHubReferenceClipboardNotification? Observe(string? clipboardText, WindowsSettings settings)
    {
        if (!settings.EnableGitHubReferenceMonitor)
        {
            Reset();
            return null;
        }

        if (string.Equals(_lastClipboardText, clipboardText, StringComparison.Ordinal))
        {
            return null;
        }

        _lastClipboardText = clipboardText;
        if (!_hasBaseline)
        {
            _hasBaseline = true;
            return null;
        }

        if (string.IsNullOrWhiteSpace(clipboardText))
        {
            _lastReferenceKey = null;
            return null;
        }

        var references = GitHubReferenceNavigator.FindReferences(
            clipboardText,
            settings.GitHubHost,
            DefaultRepository(settings));
        if (references.Count == 0)
        {
            _lastReferenceKey = null;
            return null;
        }

        var referenceKey = string.Join("|", references.Select(reference =>
            string.Join(
                ":",
                reference.Host?.ToLowerInvariant() ?? GitHubHost.Normalize(settings.GitHubHost),
                reference.RepositoryFullName.ToLowerInvariant(),
                reference.Kind.ToLowerInvariant(),
                reference.Number)));
        if (string.Equals(referenceKey, _lastReferenceKey, StringComparison.Ordinal))
        {
            return null;
        }

        _lastReferenceKey = referenceKey;
        return new GitHubReferenceClipboardNotification(
            clipboardText,
            references,
            DisplayText(references));
    }

    public void Reset()
    {
        _lastClipboardText = null;
        _lastReferenceKey = null;
        _hasBaseline = false;
    }

    private static string? DefaultRepository(WindowsSettings settings)
    {
        return settings.GetActiveRepositories()
            .Where(repository => repository.IsVisible)
            .OrderBy(repository => repository.Visibility == RepositoryVisibility.Pinned ? 0 : 1)
            .ThenBy(repository => repository.FullName, StringComparer.OrdinalIgnoreCase)
            .Select(repository => repository.FullName)
            .FirstOrDefault();
    }

    private static string DisplayText(IReadOnlyList<GitHubReferenceMatch> references)
    {
        if (references.Count == 1)
        {
            var reference = references[0];
            return $"{reference.RepositoryFullName} #{reference.Number}";
        }

        return $"{references.Count:n0} GitHub references copied";
    }
}

internal sealed record GitHubReferenceClipboardNotification(
    string IssueNavigatorText,
    IReadOnlyList<GitHubReferenceMatch> References,
    string DisplayText);
