using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Globalization;

namespace RepoBar.Windows;

internal sealed class GitHubAccountInsightClient : IDisposable
{
    private readonly HttpClient _graphQlClient;
    private readonly List<GitHubRateLimitSnapshot> _rateLimits = [];

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
                    weeks {
                      firstDay
                      contributionDays {
                        date
                        contributionCount
                      }
                    }
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
        CaptureRateLimit(response);
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
            TryGetNestedInt32(viewer, "contributionsCollection", "totalPullRequestReviewContributions") ?? 0,
            ParseContributionWeeks(viewer),
            GitHubRateLimitSnapshot.LatestByResource(_rateLimits));
    }

    private void CaptureRateLimit(HttpResponseMessage response)
    {
        if (GitHubRateLimitSnapshot.FromHeaders(response) is { } snapshot)
        {
            _rateLimits.Add(snapshot);
        }
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

    private static IReadOnlyList<GitHubContributionWeek> ParseContributionWeeks(JsonElement viewer)
    {
        if (!TryGetNestedProperty(viewer, out var weeks, "contributionsCollection", "contributionCalendar", "weeks") ||
            weeks.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        var result = new List<GitHubContributionWeek>();
        foreach (var week in weeks.EnumerateArray())
        {
            if (week.ValueKind != JsonValueKind.Object ||
                !week.TryGetProperty("contributionDays", out var daysElement) ||
                daysElement.ValueKind != JsonValueKind.Array)
            {
                continue;
            }

            var days = daysElement.EnumerateArray()
                .Select(ParseContributionDay)
                .Where(day => day != null)
                .Cast<GitHubContributionDay>()
                .OrderBy(day => day.Date)
                .ToArray();
            if (days.Length == 0)
            {
                continue;
            }

            var firstDay = TryGetDateOnly(week, "firstDay") ?? days[0].Date;
            result.Add(new GitHubContributionWeek(firstDay, days));
        }

        return result
            .OrderBy(week => week.FirstDay)
            .ToArray();
    }

    private static GitHubContributionDay? ParseContributionDay(JsonElement day)
    {
        if (day.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var date = TryGetDateOnly(day, "date");
        if (date == null)
        {
            return null;
        }

        var count = day.TryGetProperty("contributionCount", out var countElement) &&
            countElement.ValueKind == JsonValueKind.Number
                ? countElement.GetInt32()
                : 0;
        return new GitHubContributionDay(date.Value, Math.Max(0, count));
    }

    private static DateOnly? TryGetDateOnly(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        var raw = property.GetString();
        if (DateOnly.TryParseExact(raw, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
        {
            return date;
        }

        return DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var timestamp)
            ? DateOnly.FromDateTime(timestamp.UtcDateTime)
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
    int PullRequestReviewContributions,
    IReadOnlyList<GitHubContributionWeek> ContributionWeeks,
    IReadOnlyList<GitHubRateLimitSnapshot> RateLimits)
{
    private static readonly char[] HeatmapBuckets = ['.', ':', '-', '=', '+', '*', '#'];

    public string DisplayName => string.IsNullOrWhiteSpace(Name) ? Login : Name!;
    public string DisplayText => $"{DisplayName} (@{Login})  {TotalContributions:n0} contributions";
    public int ActiveContributionDays => ContributionWeeks.Sum(week => week.ActiveDays);
    public int ActiveContributionWeeks => ContributionWeeks.Count(week => week.TotalContributions > 0);
    public string ContributionHeatmapPreview => BuildContributionHeatmapPreview();
    public string ContributionHeatmapDisplayText => ContributionWeeks.Count == 0
        ? "No contribution heatmap"
        : $"{ActiveContributionDays:n0} active days  {ActiveContributionWeeks:n0}/{ContributionWeeks.Count:n0} active weeks  {ContributionHeatmapPreview}";

    private string BuildContributionHeatmapPreview()
    {
        if (ContributionWeeks.Count == 0)
        {
            return "";
        }

        var weeks = ContributionWeeks.TakeLast(26).ToArray();
        var max = Math.Max(1, weeks.Max(week => week.TotalContributions));
        return string.Concat(weeks.Select(week =>
        {
            if (week.TotalContributions <= 0)
            {
                return HeatmapBuckets[0];
            }

            var bucket = 1 + (int)Math.Floor((double)week.TotalContributions / max * (HeatmapBuckets.Length - 2));
            return HeatmapBuckets[Math.Clamp(bucket, 1, HeatmapBuckets.Length - 1)];
        }));
    }
}

internal sealed record GitHubContributionWeek(DateOnly FirstDay, IReadOnlyList<GitHubContributionDay> Days)
{
    public int TotalContributions => Days.Sum(day => day.Count);
    public int ActiveDays => Days.Count(day => day.Count > 0);
    public string DisplayText => $"{FirstDay.ToString("MMM d", CultureInfo.CurrentCulture)}: {TotalContributions:n0} contributions";
}

internal sealed record GitHubContributionDay(DateOnly Date, int Count);
