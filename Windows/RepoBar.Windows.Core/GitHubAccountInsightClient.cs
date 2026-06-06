using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace RepoBar.Windows;

internal sealed class GitHubAccountInsightClient : IDisposable
{
    private readonly HttpClient _graphQlClient;

    public GitHubAccountInsightClient(WindowsSettings settings, string? token)
        : this(settings, token, new HttpClientHandler())
    {
    }

    internal GitHubAccountInsightClient(WindowsSettings settings, string? token, HttpMessageHandler handler)
    {
        var host = GitHubHost.Normalize(settings.GitHubHost);
        var graphQlRoot = string.Equals(host, "github.com", StringComparison.OrdinalIgnoreCase)
            ? "https://api.github.com/"
            : $"https://{host}/api/";

        _graphQlClient = new HttpClient(handler) { BaseAddress = new Uri(graphQlRoot) };
        _graphQlClient.DefaultRequestHeaders.UserAgent.ParseAdd("RepoBar-Windows/0.1");
        _graphQlClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        _graphQlClient.DefaultRequestHeaders.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");
        if (!string.IsNullOrWhiteSpace(token))
        {
            _graphQlClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
    }

    public async Task<GitHubAccountInsight?> LoadAsync(CancellationToken cancellationToken)
    {
        const string query = """
            query RepoBarViewerContributionSummary {
              viewer {
                login
                name
                url
                contributionsCollection {
                  totalCommitContributions
                  totalIssueContributions
                  totalPullRequestContributions
                  totalPullRequestReviewContributions
                  contributionCalendar {
                    totalContributions
                  }
                }
              }
            }
            """;

        var body = JsonSerializer.Serialize(new { query });
        using var request = new HttpRequestMessage(HttpMethod.Post, "graphql")
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
        using var response = await _graphQlClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.Unauthorized or HttpStatusCode.NotFound)
        {
            return null;
        }

        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        if (document.RootElement.TryGetProperty("errors", out var errors) &&
            errors.ValueKind == JsonValueKind.Array &&
            errors.GetArrayLength() > 0)
        {
            return null;
        }

        if (!TryGetNestedProperty(document.RootElement, out var viewer, "data", "viewer") ||
            viewer.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var login = TryGetString(viewer, "login");
        if (string.IsNullOrWhiteSpace(login))
        {
            return null;
        }

        return new GitHubAccountInsight(
            login,
            TryGetString(viewer, "name"),
            TryGetString(viewer, "url"),
            TryGetNestedInt32(viewer, "contributionsCollection", "contributionCalendar", "totalContributions") ?? 0,
            TryGetNestedInt32(viewer, "contributionsCollection", "totalCommitContributions") ?? 0,
            TryGetNestedInt32(viewer, "contributionsCollection", "totalIssueContributions") ?? 0,
            TryGetNestedInt32(viewer, "contributionsCollection", "totalPullRequestContributions") ?? 0,
            TryGetNestedInt32(viewer, "contributionsCollection", "totalPullRequestReviewContributions") ?? 0);
    }

    private static bool TryGetNestedProperty(JsonElement element, out JsonElement value, params string[] path)
    {
        value = element;
        foreach (var part in path)
        {
            if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty(part, out value))
            {
                value = default;
                return false;
            }
        }

        return true;
    }

    private static int? TryGetNestedInt32(JsonElement element, params string[] path)
    {
        return TryGetNestedProperty(element, out var value, path) && value.ValueKind == JsonValueKind.Number
            ? value.GetInt32()
            : null;
    }

    private static string? TryGetString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    public void Dispose()
    {
        _graphQlClient.Dispose();
    }
}

internal sealed record GitHubAccountInsight(
    string Login,
    string? Name,
    string? Url,
    int TotalContributions,
    int CommitContributions,
    int IssueContributions,
    int PullRequestContributions,
    int PullRequestReviewContributions)
{
    public string DisplayName => string.IsNullOrWhiteSpace(Name) ? Login : Name!;
    public string DisplayText => $"{DisplayName} (@{Login})  {TotalContributions:n0} contributions";
}
