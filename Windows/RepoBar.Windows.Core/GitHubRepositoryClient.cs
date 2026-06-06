using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace RepoBar.Windows;

internal sealed class GitHubRepositoryClient : IDisposable
{
    internal const string SmokeForceArchiveFallbackEnvironmentVariable = "REPOBAR_WINDOWS_SMOKE_FORCE_ARCHIVE_FALLBACK";

    private static readonly Regex LastPageRegex = new(@"[?&]page=(\d+)[^>]*>\s*;\s*rel=""last""", RegexOptions.Compiled);

    private readonly HttpClient _httpClient;
    private readonly HttpClient _graphQlClient;
    private readonly WindowsSettings _settings;
    private readonly string _host;
    private readonly GitHubResponseCache? _cache;
    private readonly WindowsGitHubArchiveReader? _archiveReader;

    public GitHubRepositoryClient(WindowsSettings settings, string? token)
        : this(
            settings,
            token,
            new HttpClientHandler(),
            new HttpClientHandler(),
            settings.EnableResponseCache ? GitHubResponseCache.CreateDefault() : null)
    {
    }

    internal GitHubRepositoryClient(
        WindowsSettings settings,
        string? token,
        HttpMessageHandler messageHandler,
        HttpMessageHandler graphQlMessageHandler,
        GitHubResponseCache? cache)
    {
        _settings = settings;
        _host = GitHubHost.Normalize(settings.GitHubHost);
        var apiRoot = string.Equals(_host, "github.com", StringComparison.OrdinalIgnoreCase)
            ? "https://api.github.com/"
            : $"https://{_host}/api/v3/";
        var graphQlRoot = string.Equals(_host, "github.com", StringComparison.OrdinalIgnoreCase)
            ? "https://api.github.com/"
            : $"https://{_host}/api/";

        _cache = cache;
        _archiveReader = WindowsGitHubArchiveReader.FromSettings(settings);
        _httpClient = new HttpClient(messageHandler) { BaseAddress = new Uri(apiRoot) };
        _graphQlClient = new HttpClient(graphQlMessageHandler) { BaseAddress = new Uri(graphQlRoot) };
        ConfigureGitHubClient(_httpClient, token);
        ConfigureGitHubClient(_graphQlClient, token);
    }

    private static void ConfigureGitHubClient(HttpClient client, string? token)
    {
        client.DefaultRequestHeaders.UserAgent.ParseAdd("RepoBar-Windows/0.1");
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        client.DefaultRequestHeaders.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");
        if (!string.IsNullOrWhiteSpace(token))
        {
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
    }

    public GitHubRateLimitSnapshot? LastRateLimit { get; private set; }

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
            var traffic = await LoadTrafficAsync(repository, cancellationToken).ConfigureAwait(false);
            var heatmap = await LoadHeatmapAsync(repository, cancellationToken).ConfigureAwait(false);
            var changelog = await LoadChangelogAsync(repository, defaultBranch, cancellationToken).ConfigureAwait(false);

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
                traffic,
                heatmap,
                changelog,
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
        var workflowRuns = await LoadRecentWorkflowRunsAsync(repository, cancellationToken).ConfigureAwait(false);
        var branches = await LoadRecentBranchesAsync(repository, cancellationToken).ConfigureAwait(false);
        var tags = await LoadRecentTagsAsync(repository, cancellationToken).ConfigureAwait(false);
        var commits = await LoadRecentCommitsAsync(repository, cancellationToken).ConfigureAwait(false);
        var contributors = await LoadRecentContributorsAsync(repository, cancellationToken).ConfigureAwait(false);
        var activity = await LoadRecentActivityAsync(repository, cancellationToken).ConfigureAwait(false);
        var discussions = await LoadRecentDiscussionsAsync(repository, cancellationToken).ConfigureAwait(false);
        return new RecentRepositoryLists(issues, pulls, releases, workflowRuns, branches, tags, commits, contributors, activity, discussions);
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentIssuesAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/issues?state=open&sort=updated&direction=desc&per_page=10",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return _archiveReader?.RecentIssues(repository, 5) ?? [];
        }

        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.EnumerateArray()
                .Where(issue => !issue.TryGetProperty("pull_request", out _))
                .Take(5)
                .Select(issue =>
                {
                    var author = TryGetNestedString(issue, "user", "login");
                    return new GitHubListItem(
                        $"#{issue.GetProperty("number").GetInt32()} {TryGetString(issue, "title") ?? "Untitled issue"}",
                        TryGetString(issue, "html_url"),
                        Metadata(author, TryGetDateTimeOffset(issue, "updated_at")),
                        AuthorLogin: author,
                        AssigneeLogins: TryGetStringArray(issue, "assignees", "login"),
                        LabelNames: TryGetStringArray(issue, "labels", "name"),
                        CommentCount: TryGetInt32(issue, "comments") ?? 0);
                })
                .ToArray();
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return _archiveReader?.RecentIssues(repository, 5) ?? [];
        }
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentPullsAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/pulls?state=all&sort=updated&direction=desc&per_page=5",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return _archiveReader?.RecentPulls(repository, 5) ?? [];
        }

        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.EnumerateArray()
                .Select(pull =>
                {
                    var author = TryGetNestedString(pull, "user", "login");
                    var snapshot = PullRequestSnapshotFor(pull);
                    return new GitHubListItem(
                        $"#{pull.GetProperty("number").GetInt32()} {TryGetString(pull, "title") ?? "Untitled pull request"}",
                        TryGetString(pull, "html_url"),
                        Metadata(author, TryGetDateTimeOffset(pull, "updated_at")),
                        snapshot,
                        AuthorLogin: author,
                        CommentCount: snapshot.CommentCount);
                })
                .ToArray();
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return _archiveReader?.RecentPulls(repository, 5) ?? [];
        }
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

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentWorkflowRunsAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/actions/runs?per_page=5",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind != JsonValueKind.Object ||
            !document.RootElement.TryGetProperty("workflow_runs", out var runs) ||
            runs.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return runs.EnumerateArray()
            .Select(run =>
            {
                var name = TryGetString(run, "name") ?? "Workflow";
                var status = TryGetString(run, "status") ?? "unknown";
                var conclusion = TryGetString(run, "conclusion");
                var displayStatus = string.Equals(status, "completed", StringComparison.OrdinalIgnoreCase)
                    ? conclusion ?? status
                    : status;
                return new GitHubListItem(
                    $"{name}: {displayStatus}",
                    TryGetString(run, "html_url"),
                    Metadata(TryGetNestedString(run, "head_commit", "author", "name"), TryGetDateTimeOffset(run, "updated_at")));
            })
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
                var committedAt = TryGetNestedDateTimeOffset(commit, "commit", "author", "date");
                return new GitHubListItem(
                    $"{ShortSha(TryGetString(commit, "sha"))} {firstLine}",
                    TryGetString(commit, "html_url"),
                    Metadata(TryGetNestedString(commit, "commit", "author", "name"), committedAt),
                    AuthorLogin: TryGetNestedString(commit, "author", "login"),
                    UpdatedAt: committedAt);
            })
            .ToArray();
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentContributorsAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/contributors?per_page=5",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateArray()
            .Select(contributor =>
            {
                var login = TryGetString(contributor, "login") ?? "contributor";
                var count = contributor.TryGetProperty("contributions", out var contributions) && contributions.ValueKind == JsonValueKind.Number
                    ? $"{contributions.GetInt32()} commits"
                    : null;
                return new GitHubListItem(
                    login,
                    TryGetString(contributor, "html_url"),
                    count);
            })
            .ToArray();
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentActivityAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/events?per_page=10",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return document.RootElement.EnumerateArray()
            .Select(activity => BuildActivityItem(repository, activity))
            .Where(item => item != null)
            .Take(5)
            .Cast<GitHubListItem>()
            .ToArray();
    }

    private async Task<IReadOnlyList<GitHubListItem>> LoadRecentDiscussionsAsync(
        RepositoryRef repository,
        CancellationToken cancellationToken)
    {
        const string query = """
            query RepoBarDiscussions($owner: String!, $name: String!) {
              repository(owner: $owner, name: $name) {
                discussions(first: 5, orderBy: {field: UPDATED_AT, direction: DESC}) {
                  nodes {
                    title
                    url
                    updatedAt
                    author {
                      login
                    }
                  }
                }
              }
            }
            """;

        var body = JsonSerializer.Serialize(new
        {
            query,
            variables = new { owner = repository.Owner, name = repository.Name },
        });
        using var request = new HttpRequestMessage(HttpMethod.Post, "graphql")
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };

        try
        {
            using var response = await _graphQlClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            LastRateLimit = GitHubRateLimitSnapshot.FromHeaders(response) ?? LastRateLimit;
            if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound)
            {
                return [];
            }

            await EnsureSuccessAsync(response, cancellationToken).ConfigureAwait(false);
            var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.TryGetProperty("errors", out var errors) &&
                errors.ValueKind == JsonValueKind.Array &&
                errors.GetArrayLength() > 0)
            {
                return [];
            }

            if (!TryGetNestedProperty(document.RootElement, out var nodes, "data", "repository", "discussions", "nodes") ||
                nodes.ValueKind != JsonValueKind.Array)
            {
                return [];
            }

            return nodes.EnumerateArray()
                .Select(node => new GitHubListItem(
                    TryGetString(node, "title") ?? "Discussion",
                    TryGetString(node, "url"),
                    Metadata(TryGetNestedString(node, "author", "login"), TryGetDateTimeOffset(node, "updatedAt"))))
                .ToArray();
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return [];
        }
    }

    private GitHubListItem? BuildActivityItem(RepositoryRef repository, JsonElement activity)
    {
        var type = TryGetString(activity, "type") ?? "Event";
        var actor = TryGetNestedString(activity, "actor", "login");
        var createdAt = TryGetDateTimeOffset(activity, "created_at");
        var payload = activity.TryGetProperty("payload", out var payloadElement) &&
            payloadElement.ValueKind == JsonValueKind.Object
                ? payloadElement
                : default;

        return type switch
        {
            "PushEvent" => BuildPushActivity(repository, payload, actor, createdAt),
            "PullRequestEvent" => BuildNumberedActivity(payload, "pull_request", "PR", actor, createdAt),
            "IssuesEvent" => BuildNumberedActivity(payload, "issue", "Issue", actor, createdAt),
            "ReleaseEvent" => BuildReleaseActivity(payload, actor, createdAt),
            "CreateEvent" => new GitHubListItem(
                $"Created {TryGetPayloadString(payload, "ref_type") ?? "ref"} {TryGetPayloadString(payload, "ref") ?? ""}".Trim(),
                BuildWebUri(repository).ToString(),
                Metadata(actor, createdAt),
                AuthorLogin: actor,
                UpdatedAt: createdAt),
            _ => new GitHubListItem(
                type.EndsWith("Event", StringComparison.Ordinal) ? type[..^5] : type,
                BuildWebUri(repository).ToString(),
                Metadata(actor, createdAt),
                AuthorLogin: actor,
                UpdatedAt: createdAt),
        };
    }

    private GitHubListItem BuildPushActivity(
        RepositoryRef repository,
        JsonElement payload,
        string? actor,
        DateTimeOffset? createdAt)
    {
        var commitCount = payload.ValueKind == JsonValueKind.Object &&
            payload.TryGetProperty("commits", out var commits) &&
            commits.ValueKind == JsonValueKind.Array
            ? commits.GetArrayLength()
            : 0;
        var branch = TryGetPayloadString(payload, "ref")?.Split('/').LastOrDefault() ?? "branch";
        var head = TryGetPayloadString(payload, "head");
        return new GitHubListItem(
            $"Pushed {commitCount} commit{(commitCount == 1 ? "" : "s")} to {branch}",
            head == null ? BuildWebUri(repository).ToString() : BuildWebUri(repository, $"commit/{head}").ToString(),
            Metadata(actor, createdAt),
            AuthorLogin: actor,
            UpdatedAt: createdAt);
    }

    private static GitHubListItem? BuildNumberedActivity(
        JsonElement payload,
        string payloadName,
        string label,
        string? actor,
        DateTimeOffset? createdAt)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty(payloadName, out var item) ||
            item.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var action = TryGetString(payload, "action") ?? "updated";
        var number = item.TryGetProperty("number", out var numberElement) && numberElement.ValueKind == JsonValueKind.Number
            ? numberElement.GetInt32()
            : 0;
        var title = TryGetString(item, "title");
        var url = TryGetString(item, "html_url");
        var subject = number > 0 ? $"{label} #{number}" : label;
        return new GitHubListItem(
            $"{action} {subject}{(string.IsNullOrWhiteSpace(title) ? "" : $": {title}")}",
            url,
            Metadata(actor, createdAt),
            AuthorLogin: actor,
            UpdatedAt: createdAt);
    }

    private static GitHubListItem? BuildReleaseActivity(JsonElement payload, string? actor, DateTimeOffset? createdAt)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("release", out var release) ||
            release.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var action = TryGetString(payload, "action") ?? "published";
        var name = TryGetString(release, "name") ?? TryGetString(release, "tag_name") ?? "release";
        return new GitHubListItem(
            $"{action} release {name}",
            TryGetString(release, "html_url"),
            Metadata(actor, createdAt),
            AuthorLogin: actor,
            UpdatedAt: createdAt);
    }

    private static string? TryGetPayloadString(JsonElement payload, string propertyName)
    {
        return payload.ValueKind == JsonValueKind.Object ? TryGetString(payload, propertyName) : null;
    }

    private async Task<TrafficStatus?> LoadTrafficAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        var views = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/traffic/views",
            cancellationToken).ConfigureAwait(false);
        var clones = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/traffic/clones",
            cancellationToken).ConfigureAwait(false);
        if (views == null && clones == null)
        {
            return null;
        }

        var (viewCount, viewUniques) = ParseTrafficCounts(views);
        var (cloneCount, cloneUniques) = ParseTrafficCounts(clones);
        if (viewCount == null && viewUniques == null && cloneCount == null && cloneUniques == null)
        {
            return null;
        }

        return new TrafficStatus(viewCount, viewUniques, cloneCount, cloneUniques);
    }

    private async Task<HeatmapStatus?> LoadHeatmapAsync(RepositoryRef repository, CancellationToken cancellationToken)
    {
        if (_settings.HeatmapDisplay == WindowsHeatmapDisplay.Hidden)
        {
            return null;
        }

        var json = await TryReadJsonAsync(
            $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/stats/commit_activity",
            cancellationToken).ConfigureAwait(false);
        if (json == null)
        {
            return null;
        }

        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        var totalCommits = 0;
        var activeWeeks = 0;
        DateTimeOffset? firstWeek = null;
        DateTimeOffset? lastWeek = null;
        var weeks = document.RootElement.EnumerateArray()
            .Where(week => week.ValueKind == JsonValueKind.Object)
            .ToArray();
        foreach (var week in weeks.TakeLast(_settings.HeatmapSpan.Weeks()))
        {
            var weekTotal = week.TryGetProperty("total", out var total) && total.ValueKind == JsonValueKind.Number
                ? total.GetInt32()
                : 0;
            totalCommits += weekTotal;
            if (weekTotal > 0)
            {
                activeWeeks++;
            }
            if (week.TryGetProperty("week", out var weekStart) && weekStart.ValueKind == JsonValueKind.Number)
            {
                var date = DateTimeOffset.FromUnixTimeSeconds(weekStart.GetInt64());
                firstWeek ??= date;
                lastWeek = date;
            }
        }

        return new HeatmapStatus(totalCommits, activeWeeks, firstWeek, lastWeek, _settings.HeatmapSpan);
    }

    private async Task<ChangelogStatus?> LoadChangelogAsync(
        RepositoryRef repository,
        string defaultBranch,
        CancellationToken cancellationToken)
    {
        foreach (var fileName in new[] { "CHANGELOG.md", "CHANGELOG" })
        {
            var json = await TryReadJsonAsync(
                $"repos/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}/contents/{fileName}?ref={Uri.EscapeDataString(defaultBranch)}",
                cancellationToken).ConfigureAwait(false);
            if (json == null)
            {
                continue;
            }

            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                continue;
            }

            var content = TryGetString(document.RootElement, "content");
            var encoding = TryGetString(document.RootElement, "encoding");
            if (!string.Equals(encoding, "base64", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(content))
            {
                continue;
            }

            string markdown;
            try
            {
                var base64 = new string(content.Where(character => !char.IsWhiteSpace(character)).ToArray());
                markdown = Encoding.UTF8.GetString(Convert.FromBase64String(base64));
            }
            catch
            {
                continue;
            }

            var headline = ParseChangelogHeadline(markdown);
            return headline == null
                ? null
                : new ChangelogStatus(headline, BuildWebUri(repository, $"blob/{Uri.EscapeDataString(defaultBranch)}/{fileName}").ToString());
        }

        return null;
    }

    private async Task<string> ReadJsonAsync(string path, CancellationToken cancellationToken)
    {
        var cached = _cache?.Read(path);
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        if (!string.IsNullOrWhiteSpace(cached?.ETag))
        {
            request.Headers.TryAddWithoutValidation("If-None-Match", cached.ETag);
        }

        try
        {
            using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            LastRateLimit = GitHubRateLimitSnapshot.FromHeaders(response) ?? LastRateLimit;
            if (response.StatusCode == HttpStatusCode.NotModified && cached != null)
            {
                return cached.Json;
            }

            await EnsureSuccessAsync(response, cancellationToken).ConfigureAwait(false);
            var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            _cache?.Write(path, response.Headers.ETag?.Tag, json);
            return json;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            if (cached != null)
            {
                return cached.Json;
            }

            throw;
        }
    }

    private async Task<string?> TryReadJsonAsync(string path, CancellationToken cancellationToken)
    {
        if (ShouldForceSmokeArchiveFallback(path))
        {
            return null;
        }

        try
        {
            return await ReadJsonAsync(path, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return null;
        }
    }

    private static bool ShouldForceSmokeArchiveFallback(string path)
    {
        if (!string.Equals(
            Environment.GetEnvironmentVariable(SmokeForceArchiveFallbackEnvironmentVariable),
            "1",
            StringComparison.Ordinal))
        {
            return false;
        }

        return path.Contains("/issues?state=open&sort=updated&direction=desc&per_page=10", StringComparison.Ordinal) ||
            path.Contains("/pulls?state=all&sort=updated&direction=desc&per_page=5", StringComparison.Ordinal);
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

    private static bool TryGetNestedProperty(JsonElement element, out JsonElement value, params string[] path)
    {
        value = element;
        foreach (var part in path)
        {
            if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty(part, out value))
            {
                return false;
            }
        }

        return true;
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

    private static PullRequestNotificationSnapshot PullRequestSnapshotFor(JsonElement pull)
    {
        return new PullRequestNotificationSnapshot(
            TryGetDateTimeOffset(pull, "updated_at"),
            TryGetInt32(pull, "comments") ?? 0,
            TryGetInt32(pull, "review_comments") ?? 0,
            TryGetStringArray(pull, "requested_reviewers", "login"),
            TryGetStringArray(pull, "requested_teams", "slug"),
            TryGetString(pull, "state") ?? "open",
            TryGetDateTimeOffset(pull, "merged_at"));
    }

    private static int? TryGetInt32(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.Number
            ? property.GetInt32()
            : null;
    }

    private static string[] TryGetStringArray(JsonElement element, string propertyName, string itemPropertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return property.EnumerateArray()
            .Select(item => TryGetString(item, itemPropertyName))
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Cast<string>()
            .ToArray();
    }

    private static string? ShortSha(string? sha)
    {
        return string.IsNullOrWhiteSpace(sha) ? null : sha[..Math.Min(7, sha.Length)];
    }

    private static (int? count, int? uniques) ParseTrafficCounts(string? json)
    {
        if (json == null)
        {
            return (null, null);
        }

        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind != JsonValueKind.Object)
        {
            return (null, null);
        }

        int? count = document.RootElement.TryGetProperty("count", out var countProperty) &&
            countProperty.ValueKind == JsonValueKind.Number
                ? countProperty.GetInt32()
                : null;
        int? uniques = document.RootElement.TryGetProperty("uniques", out var uniquesProperty) &&
            uniquesProperty.ValueKind == JsonValueKind.Number
                ? uniquesProperty.GetInt32()
                : null;
        return (count, uniques);
    }

    internal static string? ParseChangelogHeadline(string markdown)
    {
        foreach (var line in markdown.Split(["\r\n", "\n"], StringSplitOptions.None))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("## ", StringComparison.Ordinal))
            {
                return trimmed.TrimStart('#', ' ').Trim();
            }
        }

        return null;
    }

    public void Dispose()
    {
        _httpClient.Dispose();
        _graphQlClient.Dispose();
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
    TrafficStatus? Traffic,
    HeatmapStatus? Heatmap,
    ChangelogStatus? Changelog,
    LocalGitRepositoryStatus? LocalStatus,
    string? ErrorMessage)
{
    public static RepositoryStatus Failed(RepositoryRef repository, LocalGitRepositoryStatus? localStatus, string errorMessage)
    {
        return new RepositoryStatus(repository, 0, 0, 0, 0, "", null, null, null, RecentRepositoryLists.Empty, null, null, null, localStatus, errorMessage);
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

internal sealed record TrafficStatus(int? Views, int? UniqueViews, int? Clones, int? UniqueClones)
{
    public string DisplayText
    {
        get
        {
            var views = Views == null ? null : $"{Views:n0} views";
            var viewUniques = UniqueViews == null ? null : $"{UniqueViews:n0} unique";
            var clones = Clones == null ? null : $"{Clones:n0} clones";
            var cloneUniques = UniqueClones == null ? null : $"{UniqueClones:n0} unique";
            return string.Join("  ", new[] { JoinPair(views, viewUniques), JoinPair(clones, cloneUniques) }
                .Where(part => !string.IsNullOrWhiteSpace(part)));
        }
    }

    private static string? JoinPair(string? first, string? second)
    {
        return first == null ? null : second == null ? first : $"{first}, {second}";
    }
}

internal sealed record HeatmapStatus(int TotalCommits, int ActiveWeeks, DateTimeOffset? FirstWeek, DateTimeOffset? LastWeek, WindowsHeatmapSpan Span)
{
    public string DisplayText => LastWeek == null
        ? $"{TotalCommits:n0} commits"
        : $"{TotalCommits:n0} commits across {ActiveWeeks:n0} active weeks ({Span.DisplayName()})";
}

internal sealed record ChangelogStatus(string Headline, string Url);

internal sealed record GitHubListItem(
    string Title,
    string? Url,
    string? Subtitle,
    PullRequestNotificationSnapshot? PullRequestSnapshot = null,
    string? AuthorLogin = null,
    string[]? AssigneeLogins = null,
    string[]? LabelNames = null,
    int? CommentCount = null,
    DateTimeOffset? UpdatedAt = null);

internal sealed record RecentRepositoryLists(
    IReadOnlyList<GitHubListItem> Issues,
    IReadOnlyList<GitHubListItem> Pulls,
    IReadOnlyList<GitHubListItem> Releases,
    IReadOnlyList<GitHubListItem> WorkflowRuns,
    IReadOnlyList<GitHubListItem> Branches,
    IReadOnlyList<GitHubListItem> Tags,
    IReadOnlyList<GitHubListItem> Commits,
    IReadOnlyList<GitHubListItem> Contributors,
    IReadOnlyList<GitHubListItem> Activity,
    IReadOnlyList<GitHubListItem> Discussions)
{
    public static readonly RecentRepositoryLists Empty = new([], [], [], [], [], [], [], [], [], []);
}

internal enum TrayHealth
{
    Unknown,
    Healthy,
    Busy,
    Failing,
}
