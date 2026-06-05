using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace RepoBar.Windows;

internal sealed class GitHubResponseCache
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    private readonly string _cacheDirectory;

    public GitHubResponseCache(string cacheDirectory)
    {
        _cacheDirectory = cacheDirectory;
        Directory.CreateDirectory(_cacheDirectory);
    }

    public static GitHubResponseCache CreateDefault()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "RepoBar",
            "cache",
            "github");
        return new GitHubResponseCache(directory);
    }

    public GitHubCachedResponse? Read(string key)
    {
        var path = PathForKey(key);
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<GitHubCachedResponse>(json, JsonOptions);
        }
        catch
        {
            return null;
        }
    }

    public void Write(string key, string? etag, string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return;
        }

        var entry = new GitHubCachedResponse(etag, DateTimeOffset.UtcNow, json);
        File.WriteAllText(PathForKey(key), JsonSerializer.Serialize(entry, JsonOptions));
    }

    private string PathForKey(string key)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(key));
        var fileName = Convert.ToHexString(bytes).ToLowerInvariant() + ".json";
        return Path.Combine(_cacheDirectory, fileName);
    }
}

internal sealed record GitHubCachedResponse(string? ETag, DateTimeOffset StoredAt, string Json);

internal sealed record GitHubRateLimitSnapshot(
    int? Limit,
    int? Remaining,
    DateTimeOffset? ResetAt,
    string? Resource)
{
    public static GitHubRateLimitSnapshot? FromHeaders(HttpResponseMessage response)
    {
        var limit = TryReadInt(response, "X-RateLimit-Limit");
        var remaining = TryReadInt(response, "X-RateLimit-Remaining");
        var resetAt = TryReadReset(response);
        var resource = TryReadString(response, "X-RateLimit-Resource");
        return limit == null && remaining == null && resetAt == null && resource == null
            ? null
            : new GitHubRateLimitSnapshot(limit, remaining, resetAt, resource);
    }

    public string DisplayText
    {
        get
        {
            var remaining = Remaining?.ToString() ?? "?";
            var limit = Limit?.ToString() ?? "?";
            var reset = ResetAt == null ? null : $"resets {ResetAt.Value.LocalDateTime:g}";
            var resource = string.IsNullOrWhiteSpace(Resource) ? "core" : Resource;
            return reset == null
                ? $"{resource}: {remaining}/{limit}"
                : $"{resource}: {remaining}/{limit}, {reset}";
        }
    }

    private static int? TryReadInt(HttpResponseMessage response, string name)
    {
        return response.Headers.TryGetValues(name, out var values) &&
            int.TryParse(values.FirstOrDefault(), out var value)
                ? value
                : null;
    }

    private static string? TryReadString(HttpResponseMessage response, string name)
    {
        return response.Headers.TryGetValues(name, out var values) ? values.FirstOrDefault() : null;
    }

    private static DateTimeOffset? TryReadReset(HttpResponseMessage response)
    {
        if (!response.Headers.TryGetValues("X-RateLimit-Reset", out var values) ||
            !long.TryParse(values.FirstOrDefault(), out var seconds))
        {
            return null;
        }

        return DateTimeOffset.FromUnixTimeSeconds(seconds);
    }
}
