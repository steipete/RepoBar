using System.Diagnostics;
using System.Text.RegularExpressions;

namespace RepoBar.Windows;

internal sealed class LocalGitService
{
    private static readonly Regex AheadBehindRegex = new(@"ahead (?<ahead>\d+)|behind (?<behind>\d+)", RegexOptions.Compiled);

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
        foreach (var repoRoot in roots)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var status = await LoadStatusAsync(repoRoot, cancellationToken).ConfigureAwait(false);
            if (status != null)
            {
                statuses.Add(status);
            }
        }

        return new LocalGitIndex(statuses.OrderBy(status => status.DisplayName, StringComparer.OrdinalIgnoreCase).ToList());
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

    private static async Task<string?> TryGitAsync(string workingDirectory, string[] arguments, CancellationToken cancellationToken)
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
                return null;
            }

            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            var stdout = await stdoutTask.ConfigureAwait(false);
            _ = await stderrTask.ConfigureAwait(false);
            return process.ExitCode == 0 ? stdout : null;
        }
        catch
        {
            return null;
        }
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

    private static string ExpandPath(string path)
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
}
