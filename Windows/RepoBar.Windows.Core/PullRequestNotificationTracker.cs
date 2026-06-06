using System.Text.Json;

namespace RepoBar.Windows;

internal sealed class PullRequestNotificationTracker
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    private readonly string _statePath;
    private readonly Dictionary<string, Dictionary<string, PullRequestNotificationSnapshot>> _snapshotsByRepository;

    public PullRequestNotificationTracker(string statePath)
    {
        _statePath = statePath;
        Directory.CreateDirectory(Path.GetDirectoryName(_statePath) ?? ".");
        _snapshotsByRepository = LoadState(statePath);
    }

    public string StatePath => _statePath;

    public static PullRequestNotificationTracker CreateDefault()
    {
        return new PullRequestNotificationTracker(DefaultStatePath());
    }

    public static PullRequestNotificationTracker CreateForSettings(WindowsSettings settings)
    {
        return new PullRequestNotificationTracker(StatePathForSettings(settings));
    }

    public static string DefaultStatePath()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "RepoBar",
            "pull-request-notifications.json");
    }

    public static string StatePathForSettings(WindowsSettings settings)
    {
        return StatePathForSettings(
            settings,
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "RepoBar",
                "pull-request-notifications"));
    }

    internal static string StatePathForSettings(WindowsSettings settings, string rootDirectory)
    {
        var account = settings.GetActiveAccount();
        return Path.Combine(
            rootDirectory,
            "accounts",
            GitHubResponseCache.SafeScope(account.GitHubHost, account.Id),
            "pull-request-notifications.json");
    }

    public IReadOnlyList<PullRequestNotificationEvent> DetectEvents(
        string repositoryFullName,
        IReadOnlyList<GitHubListItem> currentPulls,
        WindowsSettings settings)
    {
        if (currentPulls.Count == 0)
        {
            return [];
        }

        var currentSnapshots = currentPulls
            .Where(pull => !string.IsNullOrWhiteSpace(KeyForPull(pull)))
            .GroupBy(KeyForPull, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                group => group.Key,
                group => SnapshotForPull(group.First()),
                StringComparer.OrdinalIgnoreCase);

        if (!_snapshotsByRepository.TryGetValue(repositoryFullName, out var previousSnapshots))
        {
            _snapshotsByRepository[repositoryFullName] = currentSnapshots;
            Save();
            return [];
        }

        var events = new List<PullRequestNotificationEvent>();
        foreach (var pull in currentPulls)
        {
            var key = KeyForPull(pull);
            if (string.IsNullOrWhiteSpace(key))
            {
                continue;
            }

            var current = SnapshotForPull(pull);
            if (!previousSnapshots.TryGetValue(key, out var previous))
            {
                if (settings.EnablePullRequestNewNotifications)
                {
                    events.Add(new PullRequestNotificationEvent(PullRequestNotificationEventKind.NewPullRequest, pull, null));
                }
                continue;
            }

            var emittedSpecificEvent = false;
            var stateChangeDetail = StateChangeDetail(previous, current);
            if (settings.EnablePullRequestUpdateNotifications && stateChangeDetail != null)
            {
                emittedSpecificEvent = true;
                events.Add(new PullRequestNotificationEvent(
                    PullRequestNotificationEventKind.PullRequestUpdated,
                    pull,
                    stateChangeDetail));
            }

            var reviewRequestDetail = ReviewRequestDetail(previous, current);
            if (settings.EnablePullRequestReviewRequestNotifications && reviewRequestDetail != null)
            {
                emittedSpecificEvent = true;
                events.Add(new PullRequestNotificationEvent(PullRequestNotificationEventKind.ReviewRequested, pull, reviewRequestDetail));
            }

            var newComments = Math.Max(0, current.CommentCount - previous.CommentCount) +
                Math.Max(0, current.ReviewCommentCount - previous.ReviewCommentCount);
            if (settings.EnablePullRequestCommentNotifications && newComments > 0)
            {
                emittedSpecificEvent = true;
                events.Add(new PullRequestNotificationEvent(
                    PullRequestNotificationEventKind.NewComment,
                    pull,
                    newComments == 1 ? "1 new comment" : $"{newComments:n0} new comments"));
            }

            if (settings.EnablePullRequestUpdateNotifications &&
                !emittedSpecificEvent &&
                current.UpdatedAt != null &&
                previous.UpdatedAt != null &&
                current.UpdatedAt > previous.UpdatedAt)
            {
                events.Add(new PullRequestNotificationEvent(
                    PullRequestNotificationEventKind.PullRequestUpdated,
                    pull,
                    "Updated"));
            }
        }

        _snapshotsByRepository[repositoryFullName] = currentSnapshots;
        Save();
        return events;
    }

    public IReadOnlyList<GitHubListItem> DetectNewPullRequests(string repositoryFullName, IReadOnlyList<GitHubListItem> currentPulls)
    {
        var settings = new WindowsSettings
        {
            EnablePullRequestNewNotifications = true,
            EnablePullRequestUpdateNotifications = false,
            EnablePullRequestReviewRequestNotifications = false,
            EnablePullRequestCommentNotifications = false,
        };
        return DetectEvents(repositoryFullName, currentPulls, settings)
            .Where(notification => notification.Kind == PullRequestNotificationEventKind.NewPullRequest)
            .Select(notification => notification.Pull)
            .ToArray();
    }

    private static PullRequestNotificationSnapshot SnapshotForPull(GitHubListItem pull)
    {
        return pull.PullRequestSnapshot ?? new PullRequestNotificationSnapshot(null, 0, 0, [], []);
    }

    private static string KeyForPull(GitHubListItem pull)
    {
        return string.IsNullOrWhiteSpace(pull.Url) ? pull.Title : pull.Url;
    }

    private void Save()
    {
        File.WriteAllText(
            _statePath,
            JsonSerializer.Serialize(new PullRequestNotificationState(_snapshotsByRepository), JsonOptions));
    }

    private static Dictionary<string, Dictionary<string, PullRequestNotificationSnapshot>> LoadState(string statePath)
    {
        if (!File.Exists(statePath))
        {
            return new Dictionary<string, Dictionary<string, PullRequestNotificationSnapshot>>(StringComparer.OrdinalIgnoreCase);
        }

        try
        {
            var raw = File.ReadAllText(statePath);
            var decoded = JsonSerializer.Deserialize<PullRequestNotificationState>(raw, JsonOptions);
            if (decoded?.Repositories != null)
            {
                return decoded.Repositories.ToDictionary(
                    pair => pair.Key,
                    pair => pair.Value.ToDictionary(
                        snapshot => snapshot.Key,
                        snapshot => snapshot.Value,
                        StringComparer.OrdinalIgnoreCase),
                    StringComparer.OrdinalIgnoreCase);
            }
        }
        catch (JsonException)
        {
        }

        try
        {
            var raw = File.ReadAllText(statePath);
            var legacy = JsonSerializer.Deserialize<Dictionary<string, string[]>>(raw, JsonOptions) ?? [];
            return legacy.ToDictionary(
                pair => pair.Key,
                pair => pair.Value
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToDictionary(
                        key => key,
                        _ => new PullRequestNotificationSnapshot(null, 0, 0, [], []),
                        StringComparer.OrdinalIgnoreCase),
                StringComparer.OrdinalIgnoreCase);
        }
        catch
        {
            return new Dictionary<string, Dictionary<string, PullRequestNotificationSnapshot>>(StringComparer.OrdinalIgnoreCase);
        }
    }

    private static string? ReviewRequestDetail(PullRequestNotificationSnapshot previous, PullRequestNotificationSnapshot current)
    {
        var addedReviewers = Normalize(current.RequestedReviewerLogins)
            .Except(Normalize(previous.RequestedReviewerLogins), StringComparer.OrdinalIgnoreCase);
        var addedTeams = Normalize(current.RequestedTeamNames)
            .Except(Normalize(previous.RequestedTeamNames), StringComparer.OrdinalIgnoreCase)
            .Select(team => $"@{team}");
        var added = addedReviewers.Concat(addedTeams).OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray();
        if (added.Length == 0)
        {
            return null;
        }

        return added.Length == 1
            ? $"Review requested from {added[0]}"
            : $"Review requested from {added.Length:n0} reviewers";
    }

    private static string? StateChangeDetail(PullRequestNotificationSnapshot previous, PullRequestNotificationSnapshot current)
    {
        if (current.MergedAt != null && previous.MergedAt == null)
        {
            return "PR merged";
        }
        if (IsClosed(previous.State) && IsOpen(current.State))
        {
            return "PR reopened";
        }
        if (IsOpen(previous.State) && IsClosed(current.State))
        {
            return "PR closed";
        }

        return null;
    }

    private static bool IsOpen(string? state)
    {
        return string.Equals(state, "open", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsClosed(string? state)
    {
        return string.Equals(state, "closed", StringComparison.OrdinalIgnoreCase);
    }

    private static string[] Normalize(IEnumerable<string> values)
    {
        return values
            .Select(value => value.Trim().ToLowerInvariant())
            .Where(value => value.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }
}

internal sealed record PullRequestNotificationState(
    Dictionary<string, Dictionary<string, PullRequestNotificationSnapshot>> Repositories);

internal sealed record PullRequestNotificationSnapshot(
    DateTimeOffset? UpdatedAt,
    int CommentCount,
    int ReviewCommentCount,
    string[] RequestedReviewerLogins,
    string[] RequestedTeamNames,
    string State = "open",
    DateTimeOffset? MergedAt = null);

internal sealed record PullRequestNotificationEvent(
    PullRequestNotificationEventKind Kind,
    GitHubListItem Pull,
    string? Detail);

internal enum PullRequestNotificationEventKind
{
    NewPullRequest,
    PullRequestUpdated,
    ReviewRequested,
    NewComment,
}

internal static class PullRequestNotificationEventKindLabels
{
    public static string DisplayName(this PullRequestNotificationEventKind kind)
    {
        return kind switch
        {
            PullRequestNotificationEventKind.PullRequestUpdated => "updated pull request",
            PullRequestNotificationEventKind.ReviewRequested => "review request",
            PullRequestNotificationEventKind.NewComment => "pull request comment",
            _ => "pull request",
        };
    }
}
