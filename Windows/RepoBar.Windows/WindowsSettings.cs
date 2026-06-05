using System.Text.Json;

namespace RepoBar.Windows;

internal sealed class WindowsSettings
{
    public string GitHubHost { get; set; } = "github.com";
    public string TokenEnvironmentVariable { get; set; } = "REPOBAR_GITHUB_TOKEN";
    public int RefreshIntervalMinutes { get; set; } = 5;
    public bool OpenMenuOnLeftClick { get; set; } = true;
    public List<RepositoryRef> Repositories { get; set; } = [];
}

internal sealed class RepositoryRef
{
    public string Owner { get; set; } = "";
    public string Name { get; set; } = "";

    public string FullName => $"{Owner}/{Name}";

    public bool IsValid => !string.IsNullOrWhiteSpace(Owner) && !string.IsNullOrWhiteSpace(Name);
}

internal sealed class WindowsSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    private WindowsSettingsStore(string settingsPath, WindowsSettings settings)
    {
        SettingsPath = settingsPath;
        Settings = settings;
    }

    public string SettingsPath { get; }
    public WindowsSettings Settings { get; }

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
                Repositories =
                [
                    new RepositoryRef { Owner = "steipete", Name = "RepoBar" },
                ],
            };
            File.WriteAllText(settingsPath, JsonSerializer.Serialize(sampleSettings, JsonOptions));
            return new WindowsSettingsStore(settingsPath, sampleSettings);
        }

        var rawSettings = File.ReadAllText(settingsPath);
        var settings = JsonSerializer.Deserialize<WindowsSettings>(rawSettings, JsonOptions) ?? new WindowsSettings();
        settings.Repositories ??= [];
        settings.Repositories = settings.Repositories
            .Where(repository => repository.IsValid)
            .Select(repository => new RepositoryRef
            {
                Owner = repository.Owner.Trim(),
                Name = repository.Name.Trim(),
            })
            .ToList();

        return new WindowsSettingsStore(settingsPath, settings);
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
