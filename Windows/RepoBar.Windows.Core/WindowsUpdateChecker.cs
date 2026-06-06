using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace RepoBar.Windows;

internal sealed class WindowsUpdateChecker : IDisposable
{
    private static readonly Regex VersionTokenRegex = new(@"\d+(?:\.\d+){0,3}", RegexOptions.Compiled);
    private readonly HttpClient _httpClient;

    public WindowsUpdateChecker()
        : this(new HttpClientHandler())
    {
    }

    internal WindowsUpdateChecker(HttpMessageHandler handler)
    {
        _httpClient = new HttpClient(handler) { BaseAddress = new Uri("https://api.github.com/") };
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("RepoBar-Windows/0.1");
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        _httpClient.DefaultRequestHeaders.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");
    }

    public async Task<WindowsUpdateStatus> CheckLatestAsync(string currentVersion, CancellationToken cancellationToken)
    {
        using var response = await _httpClient.GetAsync("repos/steipete/RepoBar/releases/latest", cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        var tag = TryGetString(document.RootElement, "tag_name") ?? "";
        var url = TryGetString(document.RootElement, "html_url");
        var installerUrl = FindWindowsInstallerUrl(document.RootElement);
        var latestVersion = NormalizeVersion(tag);
        var normalizedCurrent = NormalizeVersion(currentVersion);
        var isNewer = latestVersion != null &&
            normalizedCurrent != null &&
            latestVersion.CompareTo(normalizedCurrent) > 0;

        return new WindowsUpdateStatus(currentVersion, tag, url, installerUrl, isNewer);
    }

    public static string CurrentVersion()
    {
        var entry = Assembly.GetEntryAssembly();
        var informational = entry?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        if (!string.IsNullOrWhiteSpace(informational))
        {
            return informational.Split('+', 2)[0];
        }

        return entry?.GetName().Version?.ToString() ?? "0.0.0";
    }

    internal static Version? NormalizeVersion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var match = VersionTokenRegex.Match(value);
        if (!match.Success)
        {
            return null;
        }

        var parts = match.Value.Split('.').Select(int.Parse).ToList();
        while (parts.Count < 2)
        {
            parts.Add(0);
        }

        return parts.Count switch
        {
            2 => new Version(parts[0], parts[1]),
            3 => new Version(parts[0], parts[1], parts[2]),
            _ => new Version(parts[0], parts[1], parts[2], parts[3]),
        };
    }

    private static string? TryGetString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    internal static string? FindWindowsInstallerUrl(JsonElement release)
    {
        if (!release.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        return assets.EnumerateArray()
            .Select(asset => new ReleaseAsset(
                TryGetString(asset, "name") ?? "",
                TryGetString(asset, "browser_download_url")))
            .Where(asset => !string.IsNullOrWhiteSpace(asset.Url))
            .OrderByDescending(asset => asset.Score)
            .FirstOrDefault(asset => asset.Score > 0)
            ?.Url;
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}

internal sealed record WindowsUpdateStatus(string CurrentVersion, string LatestTag, string? ReleaseUrl, string? InstallerUrl, bool IsNewer)
{
    public string? PreferredUpdateUrl => InstallerUrl ?? ReleaseUrl;

    public string DisplayText => IsNewer
        ? $"RepoBar {LatestTag} is available"
        : $"RepoBar is up to date ({CurrentVersion})";
}

internal sealed record ReleaseAsset(string Name, string? Url)
{
    public int Score
    {
        get
        {
            var lower = Name.ToLowerInvariant();
            if (!lower.Contains("windows", StringComparison.Ordinal) && !lower.Contains("win-", StringComparison.Ordinal) && !lower.Contains("win_", StringComparison.Ordinal))
            {
                return 0;
            }

            if (lower.EndsWith(".msi", StringComparison.Ordinal))
            {
                return 40;
            }
            if (lower.EndsWith(".exe", StringComparison.Ordinal))
            {
                return 30;
            }
            if (lower.EndsWith(".zip", StringComparison.Ordinal))
            {
                return 20;
            }

            return 10;
        }
    }
}
