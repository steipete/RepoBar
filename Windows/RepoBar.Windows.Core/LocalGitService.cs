using System.Diagnostics;
using System.Text.RegularExpressions;

namespace RepoBar.Windows;

internal sealed class LocalGitService
{
    private static readonly Regex AheadBehindRegex = new(@"ahead (?<ahead>\d+)|behind (?<behind>\d+)", RegexOptions.Compiled);
    private readonly Dictionary<string, DateTimeOffset> _lastFetchByPath = new(StringComparer.OrdinalIgnoreCase);

    public async Task<LocalGitIndex> LoadIndexAsync(WindowsSettings settings, CancellationToken cancellationToken)
    {
        if (!settings.DiscoverLocalProjects || string.IsNullOrWhiteSpace(settings.LocalProjectsRoot))
        {
            return LocalGitIndex.Empty;
        }

        var root = ExpandPath(settings.LocalProjectsRoot);
        if (!Directory.Exists(root))
        {
            return LocalGitIndex.Empty;
        }

        var roots = DiscoverRepositoryRoots(root, settings.LocalProjectsMaxDepth);
        var statuses = new List<LocalGitRepositoryStatus>(roots.Count);
        var autoSyncedStatuses = new List<LocalGitRepositoryStatus>();
        var now = DateTimeOffset.UtcNow;
        foreach (var repoRoot in roots)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (ShouldFetchBeforeStatus(repoRoot, settings, now))
            {
                var fetch = await RunGitAsync(repoRoot, ["fetch", "--prune", "--quiet"], cancellationToken).ConfigureAwait(false);
                if (fetch.Success)
                {
                    RecordFetch(repoRoot, now);
                }
            }

            var status = await LoadStatusAsync(repoRoot, cancellationToken).ConfigureAwait(false);
            if (settings.AutoSyncLocalProjects && status?.CanFastForward == true)
            {
                var sync = await FastForwardAsync(repoRoot, cancellationToken).ConfigureAwait(false);
                if (sync.Success)
                {
                    status = await LoadStatusAsync(repoRoot, cancellationToken).ConfigureAwait(false);
                    if (status != null)
                    {
                        autoSyncedStatuses.Add(status);
                    }
                }
            }

            if (status != null)
            {
                statuses.Add(status);
            }
        }

        return new LocalGitIndex(
            statuses.OrderBy(status => status.DisplayName, StringComparer.OrdinalIgnoreCase).ToList(),
            autoSyncedStatuses.OrderBy(status => status.DisplayName, StringComparer.OrdinalIgnoreCase).ToList());
    }

    internal static IReadOnlyList<string> DiscoverRepositoryRoots(string root, int maxDepth)
    {
        var results = new List<string>();
        Walk(root, Math.Max(0, maxDepth));
        return results;

        void Walk(string directory, int remainingDepth)
        {
            var gitMarker = Path.Combine(directory, ".git");
            if (Directory.Exists(gitMarker) || File.Exists(gitMarker))
            {
                results.Add(directory);
                return;
            }

            if (remainingDepth <= 0)
            {
                return;
            }

            IEnumerable<string> children;
            try
            {
                children = Directory.EnumerateDirectories(directory)
                    .Where(child => !IsIgnoredDirectoryName(Path.GetFileName(child)))
                    .ToArray();
            }
            catch
            {
                return;
            }

            foreach (var child in children)
            {
                Walk(child, remainingDepth - 1);
            }
        }
    }

    internal async Task<LocalGitRepositoryStatus?> LoadStatusAsync(string repoRoot, CancellationToken cancellationToken)
    {
        var branchOutput = await TryGitAsync(repoRoot, ["status", "--porcelain=v1", "-b"], cancellationToken).ConfigureAwait(false);
        if (branchOutput == null)
        {
            return null;
        }

        var lines = branchOutput.Split(["\r\n", "\n"], StringSplitOptions.None)
            .Where(line => line.Length > 0)
            .ToArray();
        var header = lines.FirstOrDefault(line => line.StartsWith("## ", StringComparison.Ordinal));
        var branch = ParseBranch(header);
        var upstream = ParseUpstream(header);
        var (ahead, behind) = ParseAheadBehind(header);
        var dirtyLines = lines.Where(line => !line.StartsWith("## ", StringComparison.Ordinal)).ToArray();
        var dirtyCounts = ParseDirtyCounts(dirtyLines);
        var dirtyFiles = dirtyLines.Select(ParseDirtyFile).Where(file => file.Length > 0).Take(8).ToArray();
        var isClean = dirtyLines.Length == 0;
        var remote = await TryGitAsync(repoRoot, ["remote", "get-url", "origin"], cancellationToken).ConfigureAwait(false);
        var fullName = remote == null ? null : TryParseGitHubFullName(remote.Trim());

        return new LocalGitRepositoryStatus(
            Path.GetFullPath(repoRoot),
            fullName?.Split('/').LastOrDefault() ?? Path.GetFileName(repoRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)),
            fullName,
            branch,
            isClean,
            ahead,
            behind,
            ResolveSyncState(isClean, ahead, behind),
            dirtyCounts,
            dirtyFiles,
            WorktreeName(repoRoot),
            upstream);
    }

    internal async Task<LocalGitActionResult> FetchAsync(string repoRoot, CancellationToken cancellationToken)
    {
        var result = await RunGitAsync(repoRoot, ["fetch", "--prune"], cancellationToken).ConfigureAwait(false);
        if (result.Success)
        {
            RecordFetch(repoRoot, DateTimeOffset.UtcNow);
        }

        return result;
    }

    internal async Task<LocalGitActionResult> FastForwardAsync(string repoRoot, CancellationToken cancellationToken)
    {
        return await RunGitAsync(repoRoot, ["pull", "--ff-only"], cancellationToken).ConfigureAwait(false);
    }

    internal async Task<LocalGitActionResult> SyncAsync(string repoRoot, CancellationToken cancellationToken)
    {
        var fetch = await FetchAsync(repoRoot, cancellationToken).ConfigureAwait(false);
        if (!fetch.Success)
        {
            return fetch;
        }

        var status = await LoadStatusAsync(repoRoot, cancellationToken).ConfigureAwait(false);
        if (status == null)
        {
            return new LocalGitActionResult(false, "", "Could not read local git status after fetch.");
        }
        if (!status.IsClean)
        {
            return new LocalGitActionResult(false, "", "Repository has local changes. Commit, stash, or reset before syncing.");
        }

        if (status.SyncState is LocalSyncState.Behind or LocalSyncState.Diverged)
        {
            var rebase = await RunGitAsync(repoRoot, ["pull", "--rebase", "--autostash"], cancellationToken).ConfigureAwait(false);
            if (!rebase.Success)
            {
                return rebase;
            }
        }

        status = await LoadStatusAsync(repoRoot, cancellationToken).ConfigureAwait(false);
        if (status?.SyncState == LocalSyncState.Ahead)
        {
            var push = await RunGitAsync(repoRoot, ["push"], cancellationToken).ConfigureAwait(false);
            if (!push.Success)
            {
                return push;
            }
        }

        return new LocalGitActionResult(true, "Synced local repository.", "");
    }

    internal async Task<LocalGitActionResult> RebaseAsync(string repoRoot, CancellationToken cancellationToken)
    {
        var fetch = await FetchAsync(repoRoot, cancellationToken).ConfigureAwait(false);
        if (!fetch.Success)
        {
            return fetch;
        }

        return await RunGitAsync(repoRoot, ["rebase", "--autostash", "@{u}"], cancellationToken).ConfigureAwait(false);
    }

    internal async Task<LocalGitActionResult> HardResetToUpstreamAsync(string repoRoot, CancellationToken cancellationToken)
    {
        var fetch = await FetchAsync(repoRoot, cancellationToken).ConfigureAwait(false);
        if (!fetch.Success)
        {
            return fetch;
        }

        return await RunGitAsync(repoRoot, ["reset", "--hard", "@{u}"], cancellationToken).ConfigureAwait(false);
    }

    internal async Task<IReadOnlyList<LocalGitWorktree>> ListWorktreesAsync(string repoRoot, CancellationToken cancellationToken)
    {
        var output = await TryGitAsync(repoRoot, ["worktree", "list", "--porcelain"], cancellationToken).ConfigureAwait(false);
        return output == null ? [] : ParseWorktrees(output);
    }

    internal async Task<IReadOnlyList<LocalGitBranch>> ListBranchesAsync(string repoRoot, CancellationToken cancellationToken)
    {
        var output = await TryGitAsync(repoRoot, ["branch", "--format=%(refname:short)"], cancellationToken).ConfigureAwait(false);
        if (output == null)
        {
            return [];
        }

        var current = await TryGitAsync(repoRoot, ["branch", "--show-current"], cancellationToken).ConfigureAwait(false);
        return ParseBranches(output, current);
    }

    internal async Task<LocalGitActionResult> SwitchBranchAsync(string repoRoot, string branch, CancellationToken cancellationToken)
    {
        return await RunGitAsync(repoRoot, ["switch", branch], cancellationToken).ConfigureAwait(false);
    }

    internal async Task<LocalGitActionResult> CloneRepositoryAsync(string remoteUrl, string destination, CancellationToken cancellationToken)
    {
        var parent = Path.GetDirectoryName(destination);
        if (string.IsNullOrWhiteSpace(parent))
        {
            return new LocalGitActionResult(false, "", "Checkout destination is invalid.");
        }

        try
        {
            Directory.CreateDirectory(parent);
            if (Directory.Exists(destination) || File.Exists(destination))
            {
                return new LocalGitActionResult(false, "", $"{destination} already exists.");
            }
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return new LocalGitActionResult(false, "", exception.Message);
        }

        return await RunGitAsync(parent, ["clone", remoteUrl, destination], cancellationToken).ConfigureAwait(false);
    }

    internal async Task<LocalGitActionResult> CreateWorktreeAsync(string repoRoot, string destination, string branch, CancellationToken cancellationToken)
    {
        var parent = Path.GetDirectoryName(destination);
        if (string.IsNullOrWhiteSpace(parent))
        {
            return new LocalGitActionResult(false, "", "Worktree destination is invalid.");
        }

        try
        {
            Directory.CreateDirectory(parent);
            if (Directory.Exists(destination) || File.Exists(destination))
            {
                return new LocalGitActionResult(false, "", $"{destination} already exists.");
            }
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return new LocalGitActionResult(false, "", exception.Message);
        }

        return await RunGitAsync(repoRoot, ["worktree", "add", "-b", branch, destination], cancellationToken).ConfigureAwait(false);
    }

    private static async Task<string?> TryGitAsync(string workingDirectory, string[] arguments, CancellationToken cancellationToken)
    {
        var result = await RunGitAsync(workingDirectory, arguments, cancellationToken).ConfigureAwait(false);
        return result.Success ? result.Output : null;
    }

    internal bool ShouldFetchBeforeStatus(string repoRoot, WindowsSettings settings, DateTimeOffset now)
    {
        if (!settings.FetchLocalProjectsBeforeStatus)
        {
            return false;
        }

        var interval = TimeSpan.FromMinutes(Math.Clamp(settings.LocalProjectsFetchIntervalMinutes, 1, 60));
        return !_lastFetchByPath.TryGetValue(NormalizeRepoPath(repoRoot), out var lastFetch) || now - lastFetch >= interval;
    }

    internal void RecordFetch(string repoRoot, DateTimeOffset fetchedAt)
    {
        _lastFetchByPath[NormalizeRepoPath(repoRoot)] = fetchedAt;
    }

    private static string NormalizeRepoPath(string repoRoot)
    {
        return Path.GetFullPath(ExpandPath(repoRoot));
    }

    private static async Task<LocalGitActionResult> RunGitAsync(string workingDirectory, string[] arguments, CancellationToken cancellationToken)
    {
        try
        {
            var startInfo = new ProcessStartInfo("git")
            {
                WorkingDirectory = workingDirectory,
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            foreach (var argument in arguments)
            {
                startInfo.ArgumentList.Add(argument);
            }

            using var process = Process.Start(startInfo);
            if (process == null)
            {
                return new LocalGitActionResult(false, "", "Failed to start git.");
            }

            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            var stdout = await stdoutTask.ConfigureAwait(false);
            var stderr = await stderrTask.ConfigureAwait(false);
            return new LocalGitActionResult(process.ExitCode == 0, stdout, stderr);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return new LocalGitActionResult(false, "", exception.Message);
        }
    }

    internal static IReadOnlyList<LocalGitWorktree> ParseWorktrees(string porcelain)
    {
        var worktrees = new List<LocalGitWorktree>();
        string? path = null;
        string? branch = null;
        string? head = null;
        var isBare = false;

        foreach (var line in porcelain.Split(["\r\n", "\n"], StringSplitOptions.None))
        {
            if (line.StartsWith("worktree ", StringComparison.Ordinal))
            {
                Flush();
                path = line["worktree ".Length..].Trim();
            }
            else if (line.StartsWith("branch ", StringComparison.Ordinal))
            {
                branch = line["branch ".Length..].Trim();
                const string refsHeads = "refs/heads/";
                if (branch.StartsWith(refsHeads, StringComparison.Ordinal))
                {
                    branch = branch[refsHeads.Length..];
                }
            }
            else if (line.StartsWith("HEAD ", StringComparison.Ordinal))
            {
                head = line["HEAD ".Length..].Trim();
            }
            else if (line == "bare")
            {
                isBare = true;
            }
        }

        Flush();
        return worktrees;

        void Flush()
        {
            if (!string.IsNullOrWhiteSpace(path))
            {
                worktrees.Add(new LocalGitWorktree(path, branch, head, isBare));
            }

            path = null;
            branch = null;
            head = null;
            isBare = false;
        }
    }

    internal static IReadOnlyList<LocalGitBranch> ParseBranches(string output, string? currentBranch)
    {
        var current = currentBranch?.Trim();
        return output.Split(["\r\n", "\n"], StringSplitOptions.RemoveEmptyEntries)
            .Select(branch => branch.Trim())
            .Where(branch => branch.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(branch => new LocalGitBranch(branch, string.Equals(branch, current, StringComparison.OrdinalIgnoreCase)))
            .OrderByDescending(branch => branch.IsCurrent)
            .ThenBy(branch => branch.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    internal static string CheckoutDestination(string localProjectsRoot, string repositoryName)
    {
        return Path.Combine(ExpandPath(localProjectsRoot), SanitizePathSegment(repositoryName, "repository"));
    }

    internal static string WorktreeDestination(string repoRoot, string worktreeFolderName, string branchName)
    {
        var folder = string.IsNullOrWhiteSpace(worktreeFolderName) ? ".work" : worktreeFolderName.Trim();
        var parent = IsHomeRelativePath(folder) || Path.IsPathRooted(folder)
            ? ExpandPath(folder)
            : Path.Combine(repoRoot, folder);
        return Path.Combine(parent, SanitizePathSegment(branchName, "worktree"));
    }

    internal static string SanitizePathSegment(string value, string fallback)
    {
        var invalid = Path.GetInvalidFileNameChars().Append(Path.DirectorySeparatorChar).Append(Path.AltDirectorySeparatorChar).Distinct().ToArray();
        var safeName = string.Join("_", value.Split(invalid, StringSplitOptions.RemoveEmptyEntries)).Trim();
        return string.IsNullOrWhiteSpace(safeName) ? fallback : safeName;
    }

    internal static string? TryParseGitHubFullName(string remote)
    {
        var normalized = remote.Trim();
        if (normalized.EndsWith(".git", StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized[..^4];
        }

        if (Uri.TryCreate(normalized, UriKind.Absolute, out var uri))
        {
            var parts = uri.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
            return parts.Length >= 2 ? $"{parts[^2]}/{parts[^1]}" : null;
        }

        var marker = normalized.IndexOf(':', StringComparison.Ordinal);
        if (marker >= 0 && normalized[..marker].Contains('@'))
        {
            var path = normalized[(marker + 1)..].Trim('/');
            var parts = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
            return parts.Length >= 2 ? $"{parts[^2]}/{parts[^1]}" : null;
        }

        return null;
    }

    private static string ParseBranch(string? header)
    {
        if (string.IsNullOrWhiteSpace(header))
        {
            return "unknown";
        }

        var value = header[3..];
        var separator = value.IndexOf("...", StringComparison.Ordinal);
        if (separator >= 0)
        {
            value = value[..separator];
        }
        var space = value.IndexOf(' ');
        if (space >= 0)
        {
            value = value[..space];
        }
        return string.IsNullOrWhiteSpace(value) ? "unknown" : value.Trim();
    }

    private static string? ParseUpstream(string? header)
    {
        if (string.IsNullOrWhiteSpace(header))
        {
            return null;
        }

        var separator = header.IndexOf("...", StringComparison.Ordinal);
        if (separator < 0)
        {
            return null;
        }

        var upstream = header[(separator + 3)..];
        var space = upstream.IndexOf(' ');
        if (space >= 0)
        {
            upstream = upstream[..space];
        }
        return upstream.Trim('[', ']', ' ');
    }

    private static (int? ahead, int? behind) ParseAheadBehind(string? header)
    {
        if (string.IsNullOrWhiteSpace(header))
        {
            return (null, null);
        }

        int? ahead = null;
        int? behind = null;
        foreach (Match match in AheadBehindRegex.Matches(header))
        {
            if (match.Groups["ahead"].Success)
            {
                ahead = int.Parse(match.Groups["ahead"].Value);
            }
            if (match.Groups["behind"].Success)
            {
                behind = int.Parse(match.Groups["behind"].Value);
            }
        }

        return (ahead ?? 0, behind ?? 0);
    }

    private static LocalDirtyCounts ParseDirtyCounts(IEnumerable<string> dirtyLines)
    {
        var added = 0;
        var modified = 0;
        var deleted = 0;
        foreach (var line in dirtyLines)
        {
            var status = line.Length >= 2 ? line[..2] : line;
            if (status.Contains('A') || status.Contains('?'))
            {
                added++;
            }
            if (status.Contains('M') || status.Contains('R') || status.Contains('C'))
            {
                modified++;
            }
            if (status.Contains('D'))
            {
                deleted++;
            }
        }
        return new LocalDirtyCounts(added, modified, deleted);
    }

    private static string ParseDirtyFile(string line)
    {
        return line.Length > 3 ? line[3..].Trim() : "";
    }

    private static LocalSyncState ResolveSyncState(bool isClean, int? ahead, int? behind)
    {
        if (!isClean)
        {
            return LocalSyncState.Dirty;
        }
        if (ahead == null || behind == null)
        {
            return LocalSyncState.Unknown;
        }
        if (ahead == 0 && behind == 0)
        {
            return LocalSyncState.Synced;
        }
        if (behind > 0 && ahead == 0)
        {
            return LocalSyncState.Behind;
        }
        if (ahead > 0 && behind == 0)
        {
            return LocalSyncState.Ahead;
        }
        return LocalSyncState.Diverged;
    }

    private static string? WorktreeName(string repoRoot)
    {
        var parent = Directory.GetParent(repoRoot);
        return parent?.Name.Contains("worktree", StringComparison.OrdinalIgnoreCase) == true
            ? Path.GetFileName(repoRoot)
            : null;
    }

    private static bool IsIgnoredDirectoryName(string name)
    {
        return name is ".git" or ".build" or ".swiftpm" or "node_modules" or ".cache" or ".Trash";
    }

    internal static string ExpandPath(string path)
    {
        if (path == "~")
        {
            return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }
        if (path.StartsWith("~/", StringComparison.Ordinal) || path.StartsWith("~\\", StringComparison.Ordinal))
        {
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), path[2..]);
        }
        return Environment.ExpandEnvironmentVariables(path);
    }

    private static bool IsHomeRelativePath(string path)
    {
        return path == "~" || path.StartsWith("~/", StringComparison.Ordinal) || path.StartsWith("~\\", StringComparison.Ordinal);
    }
}
