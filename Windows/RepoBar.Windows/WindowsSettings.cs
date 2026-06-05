using System.Text.Json;
using System.Text.Json.Serialization;

namespace RepoBar.Windows;

internal sealed class WindowsSettings
{
    public string GitHubHost { get; set; } = "github.com";
    public string TokenEnvironmentVariable { get; set; } = "REPOBAR_GITHUB_TOKEN";
    public int RefreshIntervalMinutes { get; set; } = 5;
    public bool OpenMenuOnLeftClick { get; set; } = true;
    public bool DiscoverLocalProjects { get; set; } = true;
    public string? LocalProjectsRoot { get; set; }
    public int LocalProjectsMaxDepth { get; set; } = 3;
    public List<RepositoryRef> Repositories { get; set; } = [];
}

internal sealed class RepositoryRef
{
    public string Owner { get; set; } = "";
    public string Name { get; set; } = "";
    public RepositoryVisibility Visibility { get; set; } = RepositoryVisibility.Pinned;

    public string FullName => $"{Owner}/{Name}";

    public bool IsValid => !string.IsNullOrWhiteSpace(Owner) && !string.IsNullOrWhiteSpace(Name);
    public bool IsVisible => Visibility != RepositoryVisibility.Hidden;
}

internal enum RepositoryVisibility
{
    Visible,
    Pinned,
    Hidden,
}

internal sealed class WindowsSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private WindowsSettingsStore(string settingsPath, WindowsSettings settings)
    {
        SettingsPath = settingsPath;
        Settings = settings;
    }

    public string SettingsPath { get; }
    public WindowsSettings Settings { get; }
    public IReadOnlyList<RepositoryRef> VisibleRepositories => Settings.Repositories
        .Where(repository => repository.IsVisible)
        .OrderBy(repository => repository.Visibility == RepositoryVisibility.Pinned ? 0 : 1)
        .ThenBy(repository => repository.FullName, StringComparer.OrdinalIgnoreCase)
        .ToArray();

    public static WindowsSettingsStore LoadOrCreate()
    {
        var settingsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "RepoBar");
        Directory.CreateDirectory(settingsDirectory);

        var settingsPath = Path.Combine(settingsDirectory, "windows-settings.json");
        if (!File.Exists(settingsPath))
        {
            var sampleSettings = new WindowsSettings
            {
                LocalProjectsRoot = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    "Projects"),
                Repositories =
                [
                    new RepositoryRef { Owner = "steipete", Name = "RepoBar", Visibility = RepositoryVisibility.Pinned },
                ],
            };
            File.WriteAllText(settingsPath, JsonSerializer.Serialize(sampleSettings, JsonOptions));
            return new WindowsSettingsStore(settingsPath, sampleSettings);
        }

        var rawSettings = File.ReadAllText(settingsPath);
        var settings = JsonSerializer.Deserialize<WindowsSettings>(rawSettings, JsonOptions) ?? new WindowsSettings();
        if (string.IsNullOrWhiteSpace(settings.LocalProjectsRoot))
        {
            settings.LocalProjectsRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                "Projects");
        }
        settings.LocalProjectsMaxDepth = Math.Clamp(settings.LocalProjectsMaxDepth, 0, 8);
        settings.Repositories ??= [];
        settings.Repositories = settings.Repositories
            .Where(repository => repository.IsValid)
            .Select(repository => new RepositoryRef
            {
                Owner = repository.Owner.Trim(),
                Name = repository.Name.Trim(),
                Visibility = repository.Visibility,
            })
            .ToList();

        return new WindowsSettingsStore(settingsPath, settings);
    }

    public void SetVisibility(string fullName, RepositoryVisibility visibility)
    {
        var parts = fullName.Split('/', 2, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length != 2)
        {
            return;
        }

        var repository = Settings.Repositories.FirstOrDefault(existing =>
            string.Equals(existing.FullName, fullName, StringComparison.OrdinalIgnoreCase));
        if (repository == null)
        {
            repository = new RepositoryRef { Owner = parts[0], Name = parts[1] };
            Settings.Repositories.Add(repository);
        }

        repository.Visibility = visibility;
        Save();
    }

    public void Save()
    {
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(Settings, JsonOptions));
    }

    public string? ResolveToken()
    {
        if (!string.IsNullOrWhiteSpace(Settings.TokenEnvironmentVariable))
        {
            var configuredToken = Environment.GetEnvironmentVariable(Settings.TokenEnvironmentVariable);
            if (!string.IsNullOrWhiteSpace(configuredToken))
            {
                return configuredToken;
            }
        }

        var repoBarToken = Environment.GetEnvironmentVariable("REPOBAR_GITHUB_TOKEN");
        if (!string.IsNullOrWhiteSpace(repoBarToken))
        {
            return repoBarToken;
        }

        var githubToken = Environment.GetEnvironmentVariable("GITHUB_TOKEN");
        if (!string.IsNullOrWhiteSpace(githubToken))
        {
            return githubToken;
        }

        var ghToken = Environment.GetEnvironmentVariable("GH_TOKEN");
        return string.IsNullOrWhiteSpace(ghToken) ? null : ghToken;
    }
}
