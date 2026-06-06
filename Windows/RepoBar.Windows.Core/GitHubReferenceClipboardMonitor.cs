namespace RepoBar.Windows;

internal sealed class GitHubReferenceClipboardMonitor
{
    private string? _lastClipboardText;
    private string? _lastReferenceKey;
    private bool _hasBaseline;

    public GitHubReferenceClipboardNotification? Observe(
        string? clipboardText,
        WindowsSettings settings,
        LocalGitIndex? localGitIndex = null)
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
            DefaultRepository(clipboardText, settings, localGitIndex ?? LocalGitIndex.Empty),
            GitHubReferenceLocalContext.KnownRepositories(settings, localGitIndex ?? LocalGitIndex.Empty));
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
                reference.ReferenceValue.ToLowerInvariant())));
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

    private static string? DefaultRepository(string text, WindowsSettings settings, LocalGitIndex localGitIndex)
    {
        var localContext = GitHubReferenceLocalContext.RepositoryContext(text, localGitIndex, settings.GitHubHost);
        if (!string.IsNullOrWhiteSpace(localContext))
        {
            return localContext;
        }

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
            return references[0].DisplayText;
        }

        return $"{references.Count:n0} GitHub references copied";
    }
}

internal sealed record GitHubReferenceClipboardNotification(
    string IssueNavigatorText,
    IReadOnlyList<GitHubReferenceMatch> References,
    string DisplayText);
