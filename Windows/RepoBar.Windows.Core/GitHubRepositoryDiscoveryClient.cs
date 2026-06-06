using System.Net.Http.Headers;
using System.Text.Json;

namespace RepoBar.Windows;

internal sealed class GitHubRepositoryDiscoveryClient : IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly WindowsSettings _settings;

    public GitHubRepositoryDiscoveryClient(WindowsSettings settings, string? token)
        : this(settings, token, new HttpClientHandler())
    {
    }

    internal GitHubRepositoryDiscoveryClient(WindowsSettings settings, string? token, HttpMessageHandler handler)
    {
        _settings = settings;
        var host = GitHubHost.Normalize(settings.GitHubHost);
        var apiRoot = string.Equals(host, "github.com", StringComparison.OrdinalIgnoreCase)
            ? "https://api.github.com/"
            : $"https://{host}/api/v3/";

        _httpClient = new HttpClient(handler) { BaseAddress = new Uri(apiRoot) };
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("RepoBar-Windows/0.1");
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        _httpClient.DefaultRequestHeaders.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");
        if (!string.IsNullOrWhiteSpace(token))
        {
            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
    }

    public async Task<IReadOnlyList<RepositorySearchResult>> LoadAccessibleRepositoriesAsync(
        CancellationToken cancellationToken,
        string? query = null)
    {
        var results = new List<RepositorySearchResult>();
        var page = 1;
        while (page <= 3)
        {
            using var response = await _httpClient.GetAsync(
                $"user/repos?visibility=all&affiliation=owner,collaborator,organization_member&sort=updated&per_page=100&page={page}",
                cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                break;
            }

            var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Array || document.RootElement.GetArrayLength() == 0)
            {
                break;
            }

            foreach (var repository in document.RootElement.EnumerateArray().Select(ParseRepository))
            {
                if (repository != null)
                {
                    results.Add(repository);
                }
            }
            page++;
        }

        return results
            .GroupBy(repository => repository!.FullName, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First()!)
            .Where(repository => !repository.IsFork || _settings.IncludeForkedRepositories)
            .Where(repository => !repository.IsArchived || _settings.IncludeArchivedRepositories)
            .Where(repository => repository.Matches(query))
            .OrderByDescending(repository => repository.PushedAt ?? DateTimeOffset.MinValue)
            .ThenBy(repository => repository.FullName, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static RepositorySearchResult? ParseRepository(JsonElement repository)
    {
        var fullName = TryGetString(repository, "full_name");
        if (string.IsNullOrWhiteSpace(fullName))
        {
            return null;
        }

        var parts = fullName.Split('/', 2, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length != 2)
        {
            return null;
        }

        return new RepositorySearchResult(
            parts[0],
            parts[1],
            TryGetString(repository, "description"),
            TryGetDateTimeOffset(repository, "pushed_at"),
            TryGetBool(repository, "fork"),
            TryGetBool(repository, "archived"));
    }

    private static string? TryGetString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    private static DateTimeOffset? TryGetDateTimeOffset(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) &&
            property.ValueKind == JsonValueKind.String &&
            DateTimeOffset.TryParse(property.GetString(), out var value)
                ? value
                : null;
    }

    private static bool TryGetBool(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) &&
            property.ValueKind is JsonValueKind.True or JsonValueKind.False &&
            property.GetBoolean();
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}

internal sealed record RepositorySearchResult(
    string Owner,
    string Name,
    string? Description,
    DateTimeOffset? PushedAt,
    bool IsFork = false,
    bool IsArchived = false)
{
    public string FullName => $"{Owner}/{Name}";

    public bool Matches(string? query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return true;
        }

        var value = query.Trim();
        return FullName.Contains(value, StringComparison.OrdinalIgnoreCase) ||
            Owner.Contains(value, StringComparison.OrdinalIgnoreCase) ||
            Name.Contains(value, StringComparison.OrdinalIgnoreCase) ||
            (Description?.Contains(value, StringComparison.OrdinalIgnoreCase) == true);
    }
}
