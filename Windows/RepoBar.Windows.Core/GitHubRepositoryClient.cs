using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace RepoBar.Windows;

internal sealed class GitHubRepositoryClient : IDisposable
{
    private static readonly Regex LastPageRegex = new(@"[?&]page=(\d+)[^>]*>\s*;\s*rel=""last""", RegexOptions.Compiled);

    private readonly HttpClient _httpClient;
    private readonly string _host;

    public GitHubRepositoryClient(WindowsSettings settings, string? token)
    {
        _host = string.IsNullOrWhiteSpace(settings.GitHubHost) ? "github.com" : settings.GitHubHost.Trim();
        var apiRoot = string.Equals(_host, "github.com", StringComparison.OrdinalIgnoreCase)
            ? "https://api.github.com/"
            : $"https://{_host}/api/v3/";

        _httpClient = new HttpClient { BaseAddress = new Uri(apiRoot) };
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("RepoBar-Windows/0.1");
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        _httpClient.DefaultRequestHeaders.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");

        if (!string.IsNullOrWhiteSpace(token))
        {
            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
    }

    public async Task<IReadOnlyList<RepositoryStatus>> LoadRepositoriesAsync(
        IReadOnlyList<RepositoryRef> repositories,
        LocalGitIndex localGitIndex,
        CancellationToken cancellationToken)
    {
        var results = new List<RepositoryStatus>(repositories.Count);
        foreach (var repository in repositories)
        {
            results.Add(await LoadRepositoryAsync(repository, localGitIndex.Find(repository), cancellationToken).ConfigureAwait(false));
        }

        return results;
    }

    public Uri BuildWebUri(RepositoryRef repository, string? path = null)
    {
        var basePath = $"{repository.Owner}/{repository.Name}";
        var suffix = string.IsNullOrWhiteSpace(path) ? "" : $"/{path.TrimStart('/')}";
        return new Uri($"https://{_host}/{basePath}{suffix}");
    }

    private async Task<RepositoryStatus> LoadRepositoryAsync(
        RepositoryRef repository,
        LocalGitRepositoryStatus? localStatus,
        CancellationToken cancellationToken)
    {
        try
        {
            var repoJson = await ReadJsonAsync(
                $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}",
                cancellationToken).ConfigureAwait(false);
            using var repoDocument = JsonDocument.Parse(repoJson);
            var repoRoot = repoDocument.RootElement;

            var openIssuesAndPulls = repoRoot.GetProperty("open_issues_count").GetInt32();
            var stars = repoRoot.GetProperty("stargazers_count").GetInt32();
            var forks = repoRoot.GetProperty("forks_count").GetInt32();
            var defaultBranch = repoRoot.GetProperty("default_branch").GetString() ?? "main";
            var pushedAt = TryGetDateTimeOffset(repoRoot, "pushed_at");

            var pullCount = await LoadPullRequestCountAsync(repository, cancellationToken).ConfigureAwait(false);
            var latestRun = await LoadLatestWorkflowRunAsync(repository, defaultBranch, cancellationToken).ConfigureAwait(false);
            var latestRelease = await LoadLatestReleaseAsync(repository, cancellationToken).ConfigureAwait(false);
            var recentLists = await LoadRecentListsAsync(repository, cancellationToken).ConfigureAwait(false);

            return new RepositoryStatus(
                repository,
                stars,
                forks,
                Math.Max(0, openIssuesAndPulls - pullCount),
                pullCount,
                defaultBranch,
                pushedAt,
                latestRun,
                latestRelease,
                recentLists,
                localStatus,
                ErrorMessage: null);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return RepositoryStatus.Failed(repository, localStatus, exception.Message);
        }
    }

    private async Task<int> LoadPullRequestCountAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        using var response = await _httpClient.GetAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/pulls?state=open&per_page=1",
            cancellationToken).ConfigureAwait(false);
        await EnsureSuccessAsync(response, cancellationToken).ConfigureAwait(false);

        if (TryGetLastPage(response, out var pageCount))
        {
            return pageCount;
        }

        var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        return document.RootElement.ValueKind == JsonValueKind.Array ? document.RootElement.GetArrayLength() : 0;
    }

    private async Task<WorkflowRunStatus?> LoadLatestWorkflowRunAsync(
        RepositoryRef repository,
        string defaultBranch,
        CancellationToken cancellationToken)
    {
        try
        {
            using var response = await _httpClient.GetAsync(
                $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/actions/runs?branch={Uri.EscapeDataString(defaultBranch)}&per_page=1",
                cancellationToken).ConfigureAwait(false);
            if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound)
            {
                return null;
            }

            await EnsureSuccessAsync(response, cancellationToken).ConfigureAwait(false);
            var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            using var document = JsonDocument.Parse(json);
            var runs = document.RootElement.GetProperty("workflow_runs");
            if (runs.ValueKind != JsonValueKind.Array || runs.GetArrayLength() == 0)
            {
                return null;
            }

            var run = runs[0];
            return new WorkflowRunStatus(
                run.GetProperty("status").GetString() ?? "unknown",
                TryGetString(run, "conclusion"),
                TryGetString(run, "html_url"),
                TryGetDateTimeOffset(run, "updated_at"));
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return new WorkflowRunStatus("unknown", "unavailable", null, null);
        }
    }

    private async Task<ReleaseStatus?> LoadLatestReleaseAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        try
        {
            using var response = await _httpClient.GetAsync(
                $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/releases/latest",
                cancellationToken).ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                return null;
            }

            await EnsureSuccessAsync(response, cancellationToken).ConfigureAwait(false);
            var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            using var document = JsonDocument.Parse(json);
            var release = document.RootElement;
            return new ReleaseStatus(
                release.GetProperty("tag_name").GetString() ?? "",
                TryGetString(release, "html_url"),
                TryGetDateTimeOffset(release, "published_at"));
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return null;
        }
    }

    private async Task<RecentRepositoryLists> LoadRecentListsAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var issues = await LoadRecentIssuesAsync(repository, cancellationToken).ConfigureAwait(false);
        var pulls = await LoadRecentPullsAsync(repository, cancellationToken).ConfigureAwait(false);
        var releases = await LoadRecentReleasesAsync(repository, cancellationToken).ConfigureAwait(false);
        var branches = await LoadRecentBranchesAsync(repository, cancellationToken).ConfigureAwait(false);
        var tags = await LoadRecentTagsAsync(repository, cancellationToken).ConfigureAwait(false);
        var commits = await LoadRecentCommitsAsync(repository, cancellationToken).ConfigureAwait(false);
        return new RecentRepositoryLists(issues, pulls, releases, branches, tags, commits);
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentIssuesAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/issues?state=open&sort=updated&direction=desc&per_page=10",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateArray()
            .Where(issue => !issue.TryGetProperty("pull_request", out _))
            .Take(5)
            .Select(issue => new GitHubListItem(
                $"#{issue.GetProperty("number").GetInt32()} {TryGetString(issue, "title") ?? "Untitled issue"}",
                TryGetString(issue, "html_url"),
                Metadata(TryGetNestedString(issue, "user", "login"), TryGetDateTimeOffset(issue, "updated_at"))))
            .ToArray();
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentPullsAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/pulls?state=open&sort=updated&direction=desc&per_page=5",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateArray()
            .Select(pull => new GitHubListItem(
                $"#{pull.GetProperty("number").GetInt32()} {TryGetString(pull, "title") ?? "Untitled pull request"}",
                TryGetString(pull, "html_url"),
                Metadata(TryGetNestedString(pull, "user", "login"), TryGetDateTimeOffset(pull, "updated_at"))))
            .ToArray();
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentReleasesAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/releases?per_page=5",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateArray()
            .Select(release => new GitHubListItem(
                TryGetString(release, "name") is { Length: > 0 } name ? name : TryGetString(release, "tag_name") ?? "Release",
                TryGetString(release, "html_url"),
                Metadata(TryGetString(release, "tag_name"), TryGetDateTimeOffset(release, "published_at"))))
            .ToArray();
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentBranchesAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/branches?per_page=5",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateArray()
            .Select(branch =>
            {
                var name = TryGetString(branch, "name") ?? "branch";
                return new GitHubListItem(
                    name,
                    BuildWebUri(repository, $"tree/{Uri.EscapeDataString(name)}").ToString(),
                    ShortSha(TryGetNestedString(branch, "commit", "sha")));
            })
            .ToArray();
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentTagsAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/tags?per_page=5",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateArray()
            .Select(tag =>
            {
                var name = TryGetString(tag, "name") ?? "tag";
                return new GitHubListItem(
                    name,
                    BuildWebUri(repository, $"releases/tag/{Uri.EscapeDataString(name)}").ToString(),
                    ShortSha(TryGetNestedString(tag, "commit", "sha")));
            })
            .ToArray();
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentCommitsAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/commits?per_page=5",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateArray()
            .Select(commit =>
            {
                var message = TryGetNestedString(commit, "commit", "message") ?? "Commit";
                var firstLine = message.Split('\n', 2)[0].Trim();
                return new GitHubListItem(
                    $"{ShortSha(TryGetString(commit, "sha"))} {firstLine}",
                    TryGetString(commit, "html_url"),
                    Metadata(TryGetNestedString(commit, "commit", "author", "name"), TryGetNestedDateTimeOffset(commit, "commit", "author", "date")));
            })
            .ToArray();
    }

    private async Task<string> ReadJsonAsync(string path, CancellationToken cancellationToken)
    {
        using var response = await _httpClient.GetAsync(path, cancellationToken).ConfigureAwait(false);
        await EnsureSuccessAsync(response, cancellationToken).ConfigureAwait(false);
        return await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task<string?> TryReadJsonAsync(string path, CancellationToken cancellationToken)
    {
        try
        {
            return await ReadJsonAsync(path, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return null;
        }
    }

    private static async Task EnsureSuccessAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }

        var message = response.ReasonPhrase ?? response.StatusCode.ToString();
        try
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(body))
            {
                using var document = JsonDocument.Parse(body);
                if (document.RootElement.TryGetProperty("message", out var githubMessage))
                {
                    message = githubMessage.GetString() ?? message;
                }
            }
        }
        catch
        {
            // Keep the HTTP status text when GitHub returns a non-JSON error.
        }

        throw new HttpRequestException(message, null, response.StatusCode);
    }

    private static bool TryGetLastPage(HttpResponseMessage response, out int pageCount)
    {
        pageCount = 0;
        if (!response.Headers.TryGetValues("Link", out var values))
        {
            return false;
        }

        var linkHeader = string.Join(",", values);
        var match = LastPageRegex.Match(linkHeader);
        return match.Success && int.TryParse(match.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out pageCount);
    }

    private static string? TryGetString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    private static string? TryGetNestedString(JsonElement element, params string[] path)
    {
        var current = element;
        foreach (var part in path)
        {
            if (!current.TryGetProperty(part, out current))
            {
                return null;
            }
        }

        return current.ValueKind == JsonValueKind.String ? current.GetString() : null;
    }

    private static DateTimeOffset? TryGetDateTimeOffset(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) &&
            property.ValueKind == JsonValueKind.String &&
            DateTimeOffset.TryParse(property.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var value)
                ? value
                : null;
    }

    private static DateTimeOffset? TryGetNestedDateTimeOffset(JsonElement element, params string[] path)
    {
        var current = element;
        foreach (var part in path)
        {
            if (!current.TryGetProperty(part, out current))
            {
                return null;
            }
        }

        return current.ValueKind == JsonValueKind.String &&
            DateTimeOffset.TryParse(current.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var value)
                ? value
                : null;
    }

    private static string? Metadata(string? actor, DateTimeOffset? date)
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(actor))
        {
            parts.Add(actor);
        }
        if (date != null)
        {
            parts.Add(date.Value.LocalDateTime.ToString("g", CultureInfo.CurrentCulture));
        }
        return parts.Count == 0 ? null : string.Join(" - ", parts);
    }

    private static string? ShortSha(string? sha)
    {
        return string.IsNullOrWhiteSpace(sha) ? null : sha[..Math.Min(7, sha.Length)];
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}

internal sealed record RepositoryStatus(
    RepositoryRef Repository,
    int Stars,
    int Forks,
    int IssueCount,
    int PullRequestCount,
    string DefaultBranch,
    DateTimeOffset? PushedAt,
    WorkflowRunStatus? LatestRun,
    ReleaseStatus? LatestRelease,
    RecentRepositoryLists RecentLists,
    LocalGitRepositoryStatus? LocalStatus,
    string? ErrorMessage)
{
    public static RepositoryStatus Failed(RepositoryRef repository, LocalGitRepositoryStatus? localStatus, string errorMessage)
    {
        return new RepositoryStatus(repository, 0, 0, 0, 0, "", null, null, null, RecentRepositoryLists.Empty, localStatus, errorMessage);
    }

    public TrayHealth Health
    {
        get
        {
            if (ErrorMessage != null)
            {
                return TrayHealth.Failing;
            }

            if (LatestRun == null)
            {
                return TrayHealth.Unknown;
            }

            if (string.Equals(LatestRun.Status, "completed", StringComparison.OrdinalIgnoreCase))
            {
                return string.Equals(LatestRun.Conclusion, "success", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(LatestRun.Conclusion, "skipped", StringComparison.OrdinalIgnoreCase)
                        ? TrayHealth.Healthy
                        : TrayHealth.Failing;
            }

            return TrayHealth.Busy;
        }
    }
}

internal sealed record WorkflowRunStatus(string Status, string? Conclusion, string? Url, DateTimeOffset? UpdatedAt)
{
    public string DisplayText => string.Equals(Status, "completed", StringComparison.OrdinalIgnoreCase)
        ? Conclusion ?? Status
        : Status;
}

internal sealed record ReleaseStatus(string TagName, string? Url, DateTimeOffset? PublishedAt);

internal sealed record GitHubListItem(string Title, string? Url, string? Subtitle);

internal sealed record RecentRepositoryLists(
    IReadOnlyList<GitHubListItem> Issues,
    IReadOnlyList<GitHubListItem> Pulls,
    IReadOnlyList<GitHubListItem> Releases,
    IReadOnlyList<GitHubListItem> Branches,
    IReadOnlyList<GitHubListItem> Tags,
    IReadOnlyList<GitHubListItem> Commits)
{
    public static readonly RecentRepositoryLists Empty = new([], [], [], [], [], []);
}

internal enum TrayHealth
{
    Unknown,
    Healthy,
    Busy,
    Failing,
}
