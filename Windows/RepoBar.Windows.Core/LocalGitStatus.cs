namespace RepoBar.Windows;

internal sealed record LocalGitRepositoryStatus(
    string Path,
    string Name,
    string? FullName,
    string Branch,
    bool IsClean,
    int? AheadCount,
    int? BehindCount,
    LocalSyncState SyncState,
    LocalDirtyCounts DirtyCounts,
    IReadOnlyList<string> DirtyFiles,
    string? WorktreeName,
    string? UpstreamBranch,
    string? GitHubHost = null)
{
    public string DisplayName => FullName ?? Name;
    public bool CanFastForward => IsClean && SyncState == LocalSyncState.Behind;
    public bool HasUpstream => !string.IsNullOrWhiteSpace(UpstreamBranch);
    public bool CanSync => IsClean && HasUpstream && SyncState is
        LocalSyncState.Behind or LocalSyncState.Ahead or LocalSyncState.Diverged;
    public bool CanRebase => IsClean && HasUpstream && SyncState is
        LocalSyncState.Behind or LocalSyncState.Diverged;
    public bool CanResetToUpstream => HasUpstream && SyncState is
        not LocalSyncState.Synced and not LocalSyncState.Unknown;

    public string SyncDetail => SyncState switch
    {
        LocalSyncState.Synced => "Up to date",
        LocalSyncState.Behind => BehindCount is int behind ? $"Behind {behind}" : "Behind",
        LocalSyncState.Ahead => AheadCount is int ahead ? $"Ahead {ahead}" : "Ahead",
        LocalSyncState.Diverged => $"Diverged +{AheadCount ?? 0}/-{BehindCount ?? 0}",
        LocalSyncState.Dirty => DirtyCounts.IsEmpty ? "Dirty" : $"Dirty ({DirtyCounts.Summary})",
        _ => "No upstream",
    };

    public IReadOnlyList<string> DirtyFilesForMenu(WindowsSettings settings)
    {
        return settings.ShowDirtyFilesInMenu ? DirtyFiles.Take(3).ToArray() : [];
    }
}

internal sealed record LocalDirtyCounts(int Added, int Modified, int Deleted)
{
    public static readonly LocalDirtyCounts Empty = new(0, 0, 0);

    public bool IsEmpty => Added == 0 && Modified == 0 && Deleted == 0;

    public string Summary
    {
        get
        {
            var parts = new List<string>();
            if (Added > 0)
            {
                parts.Add($"+{Added}");
            }
            if (Deleted > 0)
            {
                parts.Add($"-{Deleted}");
            }
            if (Modified > 0)
            {
                parts.Add($"~{Modified}");
            }
            return string.Join(" ", parts);
        }
    }
}

internal enum LocalSyncState
{
    Synced,
    Behind,
    Ahead,
    Diverged,
    Dirty,
    Unknown,
}

internal sealed class LocalGitIndex
{
    private readonly string? _activeGitHubHost;
    private readonly Dictionary<string, LocalGitRepositoryStatus> _byFullName;
    private readonly Dictionary<string, LocalGitRepositoryStatus> _byScopedFullName;
    private readonly Dictionary<string, LocalGitRepositoryStatus> _byName;

    public LocalGitIndex(IReadOnlyList<LocalGitRepositoryStatus> repositories)
        : this(repositories, [], null)
    {
    }

    public LocalGitIndex(
        IReadOnlyList<LocalGitRepositoryStatus> repositories,
        IReadOnlyList<LocalGitRepositoryStatus> autoSyncedRepositories,
        string? activeGitHubHost = null)
    {
        Repositories = repositories;
        AutoSyncedRepositories = autoSyncedRepositories;
        _activeGitHubHost = string.IsNullOrWhiteSpace(activeGitHubHost) ? null : GitHubHost.Normalize(activeGitHubHost);
        _byScopedFullName = repositories
            .Where(repository => !string.IsNullOrWhiteSpace(repository.FullName) && !string.IsNullOrWhiteSpace(repository.GitHubHost))
            .GroupBy(repository => ScopedFullNameKey(repository.GitHubHost!, repository.FullName!), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => PreferPrimary(group), StringComparer.OrdinalIgnoreCase);
        _byFullName = repositories
            .Where(repository => !string.IsNullOrWhiteSpace(repository.FullName) &&
                (_activeGitHubHost == null || string.IsNullOrWhiteSpace(repository.GitHubHost)))
            .GroupBy(repository => repository.FullName!, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => PreferPrimary(group), StringComparer.OrdinalIgnoreCase);
        _byName = repositories
            .Where(repository => _activeGitHubHost == null || string.IsNullOrWhiteSpace(repository.GitHubHost))
            .GroupBy(repository => repository.Name, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => PreferPrimary(group), StringComparer.OrdinalIgnoreCase);
    }

    public static readonly LocalGitIndex Empty = new([]);

    public IReadOnlyList<LocalGitRepositoryStatus> Repositories { get; }
    public IReadOnlyList<LocalGitRepositoryStatus> AutoSyncedRepositories { get; }

    public LocalGitRepositoryStatus? Find(RepositoryRef repository)
    {
        if (_activeGitHubHost != null &&
            _byScopedFullName.TryGetValue(ScopedFullNameKey(_activeGitHubHost, repository.FullName), out var scopedMatch))
        {
            return scopedMatch;
        }

        if (_byFullName.TryGetValue(repository.FullName, out var fullNameMatch))
        {
            return fullNameMatch;
        }

        return _byName.TryGetValue(repository.Name, out var nameMatch) ? nameMatch : null;
    }

    private static LocalGitRepositoryStatus PreferPrimary(IEnumerable<LocalGitRepositoryStatus> repositories)
    {
        return repositories
            .OrderBy(repository => repository.WorktreeName is null ? 0 : 1)
            .ThenBy(repository => repository.Path, StringComparer.OrdinalIgnoreCase)
            .First();
    }

    private static string ScopedFullNameKey(string gitHubHost, string fullName)
    {
        return $"{GitHubHost.Normalize(gitHubHost)}/{fullName}";
    }
}

internal static class LocalGitSyncNotification
{
    public static string Body(IReadOnlyList<LocalGitRepositoryStatus> repositories)
    {
        return repositories.Count switch
        {
            0 => "",
            1 => $"Synced {repositories[0].DisplayName} ({repositories[0].Branch})",
            _ => $"Synced {repositories.Count:n0} local repositories.",
        };
    }
}

internal sealed record LocalGitScanSummary(string? Root, int RepositoryCount, bool RootExists)
{
    public string DisplayText => Root switch
    {
        null => "Choose a local projects folder.",
        _ when !RootExists => "Folder not found.",
        _ when RepositoryCount == 0 => "No repositories found.",
        _ when RepositoryCount == 1 => "Found 1 local repository.",
        _ => $"Found {RepositoryCount:n0} local repositories.",
    };
}

internal sealed record LocalGitWorktree(string Path, string? Branch, string? Head, bool IsBare);

internal sealed record LocalGitBranch(string Name, bool IsCurrent);

internal sealed record GitHubRemoteRef(string Host, string FullName);

internal sealed record LocalGitActionResult(bool Success, string Output, string Error)
{
    public string DisplayText
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(Output))
            {
                return Output.Trim();
            }
            if (!string.IsNullOrWhiteSpace(Error))
            {
                return Error.Trim();
            }
            return Success ? "OK" : "Git command failed";
        }
    }
}
