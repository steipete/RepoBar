using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace RepoBar.Windows;

internal sealed class GitHubActionsInsightClient : IDisposable
{
    private static readonly string[] QueuedStatuses = ["queued", "waiting", "pending"];
    private readonly HttpClient _httpClient;
    private readonly List<GitHubRateLimitSnapshot> _rateLimits = [];

    public GitHubActionsInsightClient(WindowsSettings settings, string? token)
        : this(settings, token, new HttpClientHandler())
    {
    }

    internal GitHubActionsInsightClient(WindowsSettings settings, string? token, HttpMessageHandler handler)
    {
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

    public async Task<ActionsInsights> LoadAsync(
        IReadOnlyList<RepositoryRef> repositories,
        CancellationToken cancellationToken)
    {
        var results = new List<RepositoryActionsInsight>(repositories.Count);
        foreach (var repository in repositories)
        {
            results.Add(await LoadRepositoryAsync(repository, cancellationToken).ConfigureAwait(false));
        }

        var billing = await LoadBillingUsageAsync(repositories, cancellationToken).ConfigureAwait(false);
        return new ActionsInsights(results, billing, DateTimeOffset.UtcNow, GitHubRateLimitSnapshot.LatestByResource(_rateLimits));
    }

    private async Task<RepositoryActionsInsight> LoadRepositoryAsync(
        RepositoryRef repository,
        CancellationToken cancellationToken)
    {
        try
        {
            var inProgress = await LoadWorkflowRunCountAsync(repository, "in_progress", cancellationToken).ConfigureAwait(false);
            var queued = 0;
            foreach (var status in QueuedStatuses)
            {
                queued += await LoadWorkflowRunCountAsync(repository, status, cancellationToken).ConfigureAwait(false);
            }

            var runners = await LoadRunnersAsync(repository, cancellationToken).ConfigureAwait(false);
            return new RepositoryActionsInsight(repository, new ActionsQueueCounts(inProgress, queued), runners, ErrorMessage: null);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return new RepositoryActionsInsight(repository, ActionsQueueCounts.Empty, ActionsRunnerFleet.Empty, exception.Message);
        }
    }

    private async Task<int> LoadWorkflowRunCountAsync(
        RepositoryRef repository,
        string status,
        CancellationToken cancellationToken)
    {
        using var response = await _httpClient.GetAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/actions/runs?status={Uri.EscapeDataString(status)}&per_page=1",
            cancellationToken).ConfigureAwait(false);
        CaptureRateLimit(response);
        if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound)
        {
            return 0;
        }

        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        return document.RootElement.TryGetProperty("total_count", out var totalCount) &&
            totalCount.ValueKind == JsonValueKind.Number
                ? totalCount.GetInt32()
                : 0;
    }

    private async Task<ActionsRunnerFleet> LoadRunnersAsync(
        RepositoryRef repository,
        CancellationToken cancellationToken)
    {
        using var response = await _httpClient.GetAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/actions/runners?per_page=100",
            cancellationToken).ConfigureAwait(false);
        CaptureRateLimit(response);
        if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound)
        {
            return ActionsRunnerFleet.Empty;
        }

        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        var totalCount = document.RootElement.TryGetProperty("total_count", out var total) &&
            total.ValueKind == JsonValueKind.Number
                ? total.GetInt32()
                : 0;
        ActionsRunnerSummary[] runners = document.RootElement.TryGetProperty("runners", out var runnersElement) &&
            runnersElement.ValueKind == JsonValueKind.Array
                ? runnersElement.EnumerateArray().Select(ParseRunner).Where(runner => runner != null).Cast<ActionsRunnerSummary>().ToArray()
                : [];
        return new ActionsRunnerFleet(totalCount, runners);
    }

    private async Task<ActionsBillingUsage?> LoadBillingUsageAsync(
        IReadOnlyList<RepositoryRef> repositories,
        CancellationToken cancellationToken)
    {
        var owners = repositories
            .Select(repository => repository.Owner)
            .Where(owner => !string.IsNullOrWhiteSpace(owner))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(8)
            .ToArray();
        if (owners.Length == 0)
        {
            return null;
        }

        var items = new List<ActionsBillingUsageItem>();
        foreach (var owner in owners)
        {
            var ownerItems = await TryLoadBillingUsageForOwnerAsync(owner, isOrg: false, cancellationToken).ConfigureAwait(false) ??
                await TryLoadBillingUsageForOwnerAsync(owner, isOrg: true, cancellationToken).ConfigureAwait(false);
            if (ownerItems != null)
            {
                items.AddRange(ownerItems);
            }
        }

        return items.Count == 0 ? null : new ActionsBillingUsage(items);
    }

    private async Task<IReadOnlyList<ActionsBillingUsageItem>?> TryLoadBillingUsageForOwnerAsync(
        string owner,
        bool isOrg,
        CancellationToken cancellationToken)
    {
        var pathPrefix = isOrg ? "organizations" : "users";
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"{pathPrefix}/{Uri.EscapeDataString(owner)}/settings/billing/usage?product=actions");
        request.Headers.TryAddWithoutValidation("X-GitHub-Api-Version", "2026-03-10");

        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        CaptureRateLimit(response);
        if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.Unauthorized or HttpStatusCode.NotFound)
        {
            return null;
        }

        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("usageItems", out var usageItems) ||
            usageItems.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return usageItems.EnumerateArray()
            .Select(ParseBillingUsageItem)
            .Where(item => item != null)
            .Cast<ActionsBillingUsageItem>()
            .ToArray();
    }

    private static ActionsRunnerSummary? ParseRunner(JsonElement runner)
    {
        if (!runner.TryGetProperty("id", out var idProperty) ||
            idProperty.ValueKind != JsonValueKind.Number)
        {
            return null;
        }

        string[] labels = runner.TryGetProperty("labels", out var labelsElement) &&
            labelsElement.ValueKind == JsonValueKind.Array
                ? labelsElement.EnumerateArray()
                    .Select(label => TryGetString(label, "name"))
                    .Where(label => !string.IsNullOrWhiteSpace(label))
                    .Cast<string>()
                    .ToArray()
                : [];
        var id = idProperty.GetInt64();
        return new ActionsRunnerSummary(
            id,
            TryGetString(runner, "name") ?? $"runner-{id}",
            TryGetString(runner, "os") ?? "unknown",
            TryGetString(runner, "status") ?? "unknown",
            runner.TryGetProperty("busy", out var busy) && busy.ValueKind is JsonValueKind.True,
            labels);
    }

    private static string? TryGetString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    private static double TryGetDouble(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.Number
            ? property.GetDouble()
            : 0;
    }

    private static ActionsBillingUsageItem? ParseBillingUsageItem(JsonElement item)
    {
        var date = TryGetString(item, "date");
        var sku = TryGetString(item, "sku") ?? "";
        var unitType = TryGetString(item, "unitType") ?? "";
        if (string.IsNullOrWhiteSpace(date) && string.IsNullOrWhiteSpace(sku))
        {
            return null;
        }

        return new ActionsBillingUsageItem(
            date ?? "",
            sku,
            TryGetDouble(item, "quantity"),
            unitType,
            TryGetDouble(item, "netAmount"),
            TryGetString(item, "organizationName"),
            TryGetString(item, "repositoryName"));
    }

    private void CaptureRateLimit(HttpResponseMessage response)
    {
        if (GitHubRateLimitSnapshot.FromHeaders(response) is { } snapshot)
        {
            _rateLimits.Add(snapshot);
        }
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}

internal sealed record ActionsInsights(
    IReadOnlyList<RepositoryActionsInsight> Repositories,
    ActionsBillingUsage? Billing,
    DateTimeOffset FetchedAt,
    IReadOnlyList<GitHubRateLimitSnapshot> RateLimits)
{
    public static readonly ActionsInsights Empty = new([], null, DateTimeOffset.MinValue, []);

    public int RunningCount => Repositories.Sum(repository => repository.Queue.InProgressCount);
    public int QueuedCount => Repositories.Sum(repository => repository.Queue.QueuedCount);
    public int RunnerCount => Repositories.Sum(repository => repository.Runners.TotalCount);
    public int OnlineRunnerCount => Repositories.Sum(repository => repository.Runners.OnlineCount);
    public int BusyRunnerCount => Repositories.Sum(repository => repository.Runners.BusyCount);
    public bool HasData => Repositories.Count > 0;

    public string DisplayText
    {
        get
        {
            var queue = $"{RunningCount:n0} running";
            if (QueuedCount > 0)
            {
                queue += $"  {QueuedCount:n0} queued";
            }

            var runners = RunnerCount > 0
                ? $"  {OnlineRunnerCount:n0}/{RunnerCount:n0} runners"
                : "";
            var billing = Billing == null ? "" : $"  {Billing.DisplayText}";
            return $"Actions: {queue}{runners}{billing}";
        }
    }
}

internal sealed record RepositoryActionsInsight(
    RepositoryRef Repository,
    ActionsQueueCounts Queue,
    ActionsRunnerFleet Runners,
    string? ErrorMessage)
{
    public string DisplayText
    {
        get
        {
            if (ErrorMessage != null)
            {
                return $"unavailable: {ErrorMessage}";
            }

            var pieces = new List<string>();
            if (Queue.InProgressCount > 0)
            {
                pieces.Add($"{Queue.InProgressCount:n0} running");
            }
            if (Queue.QueuedCount > 0)
            {
                pieces.Add($"{Queue.QueuedCount:n0} queued");
            }
            if (Runners.TotalCount > 0)
            {
                pieces.Add($"{Runners.OnlineCount:n0}/{Runners.TotalCount:n0} runners");
            }

            return pieces.Count == 0 ? "idle" : string.Join("  ", pieces);
        }
    }
}

internal sealed record ActionsQueueCounts(int InProgressCount, int QueuedCount)
{
    public static readonly ActionsQueueCounts Empty = new(0, 0);
}

internal sealed record ActionsRunnerFleet(int TotalCount, IReadOnlyList<ActionsRunnerSummary> Runners)
{
    public static readonly ActionsRunnerFleet Empty = new(0, []);
    public int OnlineCount => Runners.Count(runner => string.Equals(runner.Status, "online", StringComparison.OrdinalIgnoreCase));
    public int BusyCount => Runners.Count(runner => runner.Busy);
    public int OfflineCount => Runners.Count(runner => string.Equals(runner.Status, "offline", StringComparison.OrdinalIgnoreCase));
}

internal sealed record ActionsRunnerSummary(long Id, string Name, string Os, string Status, bool Busy, IReadOnlyList<string> Labels)
{
    public string DisplayText
    {
        get
        {
            var state = Busy ? "busy" : Status;
            var labels = Labels.Count == 0 ? "" : $"  {string.Join(", ", Labels.Take(3))}";
            return $"{Name}  {Os}  {state}{labels}";
        }
    }
}

internal sealed record ActionsBillingUsage(IReadOnlyList<ActionsBillingUsageItem> Items)
{
    public double TotalMinutes => Items
        .Where(item => string.Equals(item.UnitType, "minutes", StringComparison.OrdinalIgnoreCase))
        .Sum(item => item.Quantity);

    public double TotalNetAmount => Items.Sum(item => item.NetAmount);

    public string DisplayText => TotalNetAmount > 0
        ? $"{TotalMinutes:n0}m  ${TotalNetAmount:n2}"
        : $"{TotalMinutes:n0}m";

    public IReadOnlyDictionary<string, double> MinutesByOs => Items
        .Where(item => string.Equals(item.UnitType, "minutes", StringComparison.OrdinalIgnoreCase))
        .GroupBy(item => OsLabel(item.Sku), StringComparer.OrdinalIgnoreCase)
        .ToDictionary(group => group.Key, group => group.Sum(item => item.Quantity), StringComparer.OrdinalIgnoreCase);

    private static string OsLabel(string sku)
    {
        var upper = sku.ToUpperInvariant();
        if (upper.Contains("MACOS", StringComparison.Ordinal) || upper.Contains("MAC_OS", StringComparison.Ordinal))
        {
            return "macOS";
        }
        if (upper.Contains("WINDOWS", StringComparison.Ordinal))
        {
            return "Windows";
        }
        if (upper.Contains("LINUX", StringComparison.Ordinal) || upper.Contains("UBUNTU", StringComparison.Ordinal))
        {
            return "Linux";
        }

        return string.IsNullOrWhiteSpace(sku) ? "Other" : sku;
    }
}

internal sealed record ActionsBillingUsageItem(
    string Date,
    string Sku,
    double Quantity,
    string UnitType,
    double NetAmount,
    string? OrganizationName,
    string? RepositoryName);
