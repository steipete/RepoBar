using System.Text.Json;

namespace RepoBar.Windows;

internal sealed class PullRequestNotificationTracker
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    private readonly string _statePath;
    private readonly Dictionary<string, HashSet<string>> _seenByRepository;

    public PullRequestNotificationTracker(string statePath)
    {
        _statePath = statePath;
        Directory.CreateDirectory(Path.GetDirectoryName(_statePath) ?? ".");
        _seenByRepository = LoadState(statePath);
    }

    public static PullRequestNotificationTracker CreateDefault()
    {
        var statePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "RepoBar",
            "pull-request-notifications.json");
        return new PullRequestNotificationTracker(statePath);
    }

    public IReadOnlyList<GitHubListItem> DetectNewPullRequests(string repositoryFullName, IReadOnlyList<GitHubListItem> currentPulls)
    {
        if (currentPulls.Count == 0)
        {
            return [];
        }

        var currentKeys = currentPulls
            .Select(KeyForPull)
            .Where(key => !string.IsNullOrWhiteSpace(key))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        if (!_seenByRepository.TryGetValue(repositoryFullName, out var seen))
        {
            _seenByRepository[repositoryFullName] = currentKeys;
            Save();
            return [];
        }

        var newPulls = currentPulls
            .Where(pull => !seen.Contains(KeyForPull(pull)))
            .ToArray();

        _seenByRepository[repositoryFullName] = currentKeys;
        Save();
        return newPulls;
    }

    private static string KeyForPull(GitHubListItem pull)
    {
        return string.IsNullOrWhiteSpace(pull.Url) ? pull.Title : pull.Url;
    }

    private void Save()
    {
        var serializable = _seenByRepository.ToDictionary(
            pair => pair.Key,
            pair => pair.Value.OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray(),
            StringComparer.OrdinalIgnoreCase);
        File.WriteAllText(_statePath, JsonSerializer.Serialize(serializable, JsonOptions));
    }

    private static Dictionary<string, HashSet<string>> LoadState(string statePath)
    {
        if (!File.Exists(statePath))
        {
            return new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        }

        try
        {
            var raw = File.ReadAllText(statePath);
            var decoded = JsonSerializer.Deserialize<Dictionary<string, string[]>>(raw, JsonOptions) ?? [];
            return decoded.ToDictionary(
                pair => pair.Key,
                pair => pair.Value.ToHashSet(StringComparer.OrdinalIgnoreCase),
                StringComparer.OrdinalIgnoreCase);
        }
        catch
        {
            return new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        }
    }
}
