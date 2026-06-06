using System.Net;
using System.Text;
using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class GitHubResponseCacheTests
{
    [Fact]
    public void Cache_round_trips_json_and_etag()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"repobar-cache-{Guid.NewGuid():N}");
        try
        {
            var cache = new GitHubResponseCache(directory);

            cache.Write("repos/owner/name", "\"etag-1\"", """{"ok":true}""");
            var entry = cache.Read("repos/owner/name");

            Assert.NotNull(entry);
            Assert.Equal("\"etag-1\"", entry.ETag);
            Assert.Equal("""{"ok":true}""", entry.Json);
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public void Cache_clear_removes_only_cache_json_entries()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"repobar-cache-{Guid.NewGuid():N}");
        try
        {
            var cache = new GitHubResponseCache(directory);
            cache.Write("repos/owner/one", "\"etag-1\"", """{"ok":1}""");
            cache.Write("repos/owner/two", "\"etag-2\"", """{"ok":2}""");
            File.WriteAllText(Path.Combine(directory, "notes.txt"), "keep");

            var deleted = cache.Clear();

            Assert.Equal(2, deleted);
            Assert.Null(cache.Read("repos/owner/one"));
            Assert.Null(cache.Read("repos/owner/two"));
            Assert.True(File.Exists(Path.Combine(directory, "notes.txt")));
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public void Account_scoped_cache_directory_uses_host_and_account()
    {
        var github = new WindowsSettings
        {
            ActiveAccountId = "work",
            Accounts = [Account("work", "github.com")],
        };
        var enterprise = new WindowsSettings
        {
            ActiveAccountId = "work",
            Accounts = [Account("work", "ghe.example.com")],
        };
        WindowsSettingsStore.NormalizeSettings(github);
        WindowsSettingsStore.NormalizeSettings(enterprise);

        var githubDirectory = GitHubResponseCache.DirectoryForSettings(github);
        var enterpriseDirectory = GitHubResponseCache.DirectoryForSettings(enterprise);

        Assert.Contains($"{Path.DirectorySeparatorChar}accounts{Path.DirectorySeparatorChar}", githubDirectory);
        Assert.NotEqual(githubDirectory, enterpriseDirectory);
        Assert.Contains(GitHubResponseCache.SafeScope("github.com", "work"), githubDirectory);
        Assert.Contains(GitHubResponseCache.SafeScope("ghe.example.com", "work"), enterpriseDirectory);
    }

    [Fact]
    public void Clear_for_settings_removes_only_active_account_cache_entries()
    {
        var settings = new WindowsSettings
        {
            ActiveAccountId = "default",
            Accounts =
            [
                Account("default", "github.com"),
                Account("work", "github.com"),
            ],
        };
        WindowsSettingsStore.NormalizeSettings(settings);

        var defaultDirectory = GitHubResponseCache.DirectoryForSettings(settings);
        var defaultCache = GitHubResponseCache.CreateForSettings(settings);
        defaultCache.Write("repos/personal/project", "\"etag-default\"", """{"owner":"personal"}""");

        settings.ActiveAccountId = "work";
        WindowsSettingsStore.NormalizeSettings(settings);
        var workDirectory = GitHubResponseCache.DirectoryForSettings(settings);
        var workCache = GitHubResponseCache.CreateForSettings(settings);
        workCache.Write("repos/work/project", "\"etag-work\"", """{"owner":"work"}""");

        try
        {
            var deleted = GitHubResponseCache.ClearForSettings(settings);

            Assert.Equal(1, deleted);
            Assert.Null(workCache.Read("repos/work/project"));
            Assert.NotNull(defaultCache.Read("repos/personal/project"));
        }
        finally
        {
            DeleteDirectory(defaultDirectory);
            DeleteDirectory(workDirectory);
        }
    }

    [Fact]
    public async Task Repository_client_combines_github_and_local_status_with_rate_limit_headers()
    {
        var handler = new StubHandler(request =>
        {
            var path = request.RequestUri?.PathAndQuery ?? "";
            var response = path switch
            {
                "/repos/owner/name" => JsonResponse("""
                    {
                      "open_issues_count": 0,
                      "stargazers_count": 10,
                      "forks_count": 2,
                      "default_branch": "main",
                      "pushed_at": "2026-06-01T00:00:00Z"
                    }
                    """),
                "/repos/owner/name/actions/runs?branch=main&per_page=1" => JsonResponse("""{"workflow_runs":[]}"""),
                "/repos/owner/name/actions/runs?per_page=5" => JsonResponse("""{"workflow_runs":[]}"""),
                "/repos/owner/name/releases/latest" => new HttpResponseMessage(HttpStatusCode.NotFound),
                "/repos/owner/name/traffic/views" => JsonResponse("""{"count":42,"uniques":12}"""),
                "/repos/owner/name/traffic/clones" => JsonResponse("""{"count":8,"uniques":3}"""),
                "/repos/owner/name/stats/commit_activity" => JsonResponse("""
                    [
                      {"week": 1780272000, "total": 0, "days": [0,0,0,0,0,0,0]},
                      {"week": 1780876800, "total": 7, "days": [1,1,1,1,1,1,1]}
                    ]
                    """),
                "/repos/owner/name/contents/CHANGELOG.md?ref=main" => ChangelogResponse("## 1.2.3\n- shipped"),
                "/repos/owner/name/events?per_page=10" => JsonResponse("""
                    [
                      {
                        "type": "PushEvent",
                        "created_at": "2026-06-01T12:00:00Z",
                        "actor": { "login": "alice" },
                        "payload": {
                          "ref": "refs/heads/main",
                          "head": "abcdef123456",
                          "commits": [{"sha":"abcdef1"}]
                        }
                      },
                      {
                        "type": "IssuesEvent",
                        "created_at": "2026-06-01T11:00:00Z",
                        "actor": { "login": "bob" },
                        "payload": {
                          "action": "opened",
                          "issue": {
                            "number": 42,
                            "title": "Crash",
                            "html_url": "https://github.com/owner/name/issues/42"
                          }
                        }
                      }
                    ]
                    """),
                _ => JsonResponse("[]"),
            };
            response.Headers.TryAddWithoutValidation("X-RateLimit-Limit", "5000");
            response.Headers.TryAddWithoutValidation("X-RateLimit-Remaining", "4999");
            response.Headers.TryAddWithoutValidation("X-RateLimit-Resource", "core");
            return response;
        });
        var settings = new WindowsSettings { EnableResponseCache = false };
        using var client = new GitHubRepositoryClient(settings, token: null, handler, new StubHandler(request =>
            JsonResponse("""
                {
                  "data": {
                    "repository": {
                      "discussions": {
                        "nodes": [
                          {
                            "title": "Roadmap",
                            "url": "https://github.com/owner/name/discussions/1",
                            "updatedAt": "2026-06-01T13:00:00Z",
                            "author": { "login": "carol" }
                          }
                        ]
                      }
                    }
                  }
                }
                """)), cache: null);

        var localStatus = new LocalGitRepositoryStatus(
            Path: @"C:\Projects\name",
            Name: "name",
            FullName: "owner/name",
            Branch: "feature/windows",
            IsClean: false,
            AheadCount: 1,
            BehindCount: 2,
            SyncState: LocalSyncState.Diverged,
            DirtyCounts: new LocalDirtyCounts(1, 1, 0),
            DirtyFiles: ["README.md", "Windows/RepoBar.Windows/Program.cs"],
            WorktreeName: "feature/windows",
            UpstreamBranch: "origin/main");

        var statuses = await client.LoadRepositoriesAsync(
            [new RepositoryRef { Owner = "owner", Name = "name" }],
            new LocalGitIndex([localStatus]),
            CancellationToken.None);

        Assert.Single(statuses);
        Assert.Equal(42, statuses[0].Traffic?.Views);
        Assert.Equal(7, statuses[0].Heatmap?.TotalCommits);
        Assert.Equal("1.2.3", statuses[0].Changelog?.Headline);
        Assert.NotNull(statuses[0].LocalStatus);
        Assert.Equal("feature/windows", statuses[0].LocalStatus?.Branch);
        Assert.Equal(LocalSyncState.Diverged, statuses[0].LocalStatus?.SyncState);
        Assert.Equal("+1 ~1", statuses[0].LocalStatus?.DirtyCounts.Summary);
        Assert.Equal("Diverged +1/-2", statuses[0].LocalStatus?.SyncDetail);
        Assert.False(statuses[0].LocalStatus?.CanFastForward);
        Assert.Contains(statuses[0].RecentLists.Activity, item => item.Title == "Pushed 1 commit to main");
        Assert.Contains(statuses[0].RecentLists.Activity, item => item.Title.Contains("opened Issue #42", StringComparison.Ordinal));
        Assert.Contains(statuses[0].RecentLists.Discussions, item => item.Title == "Roadmap");
        Assert.NotNull(client.LastRateLimit);
        Assert.Equal(4999, client.LastRateLimit.Remaining);
        Assert.Contains("4999/5000", client.LastRateLimit.DisplayText);
        Assert.Equal(100, client.LastRateLimit.PercentRemaining);
        Assert.Contains("100%", client.LastRateLimit.CompactText(DateTimeOffset.UtcNow));
    }

    [Fact]
    public async Task Repository_client_loads_all_state_recent_pulls_for_notifications()
    {
        var requestedPaths = new List<string>();
        var handler = new StubHandler(request =>
        {
            var path = request.RequestUri?.PathAndQuery ?? "";
            requestedPaths.Add(path);
            return path switch
            {
                "/repos/owner/name/issues?state=open&sort=updated&direction=desc&per_page=10" => JsonResponse("""
                    [
                      {
                        "number": 7,
                        "title": "Track Windows filters",
                        "html_url": "https://github.com/owner/name/issues/7",
                        "user": { "login": "octocat" },
                        "updated_at": "2026-06-06T09:05:00Z",
                        "comments": 4,
                        "assignees": [{ "login": "alice" }],
                        "labels": [{ "name": "windows" }]
                      }
                    ]
                    """),
                "/repos/owner/name/pulls?state=all&sort=updated&direction=desc&per_page=5" => JsonResponse("""
                    [
                      {
                        "number": 12,
                        "title": "Ship Windows state notifications",
                        "html_url": "https://github.com/owner/name/pull/12",
                        "user": { "login": "alice" },
                        "updated_at": "2026-06-06T10:05:00Z",
                        "comments": 2,
                        "review_comments": 3,
                        "requested_reviewers": [{ "login": "bob" }],
                        "requested_teams": [{ "slug": "triage" }],
                        "state": "closed",
                        "merged_at": "2026-06-06T10:10:00Z"
                      }
                    ]
                    """),
                _ => MinimalRepositoryResponse(path),
            };
        });
        var settings = new WindowsSettings
        {
            EnableResponseCache = false,
            HeatmapDisplay = WindowsHeatmapDisplay.Hidden,
        };
        using var client = new GitHubRepositoryClient(
            settings,
            token: null,
            handler,
            EmptyGraphQlHandler(),
            cache: null);

        var statuses = await client.LoadRepositoriesAsync(
            [new RepositoryRef { Owner = "owner", Name = "name" }],
            LocalGitIndex.Empty,
            CancellationToken.None);

        var status = Assert.Single(statuses);
        var issue = Assert.Single(status.RecentLists.Issues);
        Assert.Contains("/repos/owner/name/issues?state=open&sort=updated&direction=desc&per_page=10", requestedPaths);
        Assert.Equal("octocat", issue.AuthorLogin);
        Assert.Equal(4, issue.CommentCount);
        Assert.Equal(["alice"], issue.AssigneeLogins ?? []);
        Assert.Equal(["windows"], issue.LabelNames ?? []);

        var pull = Assert.Single(status.RecentLists.Pulls);
        Assert.NotNull(pull.PullRequestSnapshot);
        var snapshot = pull.PullRequestSnapshot!;
        Assert.Contains("/repos/owner/name/pulls?state=all&sort=updated&direction=desc&per_page=5", requestedPaths);
        Assert.Equal("alice", pull.AuthorLogin);
        Assert.Equal(2, pull.CommentCount);
        Assert.Equal("closed", snapshot.State);
        Assert.Equal(DateTimeOffset.Parse("2026-06-06T10:10:00Z"), snapshot.MergedAt);
        Assert.Equal(2, snapshot.CommentCount);
        Assert.Equal(3, snapshot.ReviewCommentCount);
        Assert.Equal(["bob"], snapshot.RequestedReviewerLogins);
        Assert.Equal(["triage"], snapshot.RequestedTeamNames);
    }

    [Fact]
    public async Task Repository_client_skips_heatmap_request_when_heatmap_is_hidden()
    {
        var heatmapCalls = 0;
        var handler = new StubHandler(request =>
        {
            var path = request.RequestUri?.PathAndQuery ?? "";
            if (path == "/repos/owner/name/stats/commit_activity")
            {
                heatmapCalls++;
                return JsonResponse("""[]""");
            }

            return MinimalRepositoryResponse(path);
        });
        var settings = new WindowsSettings
        {
            EnableResponseCache = false,
            HeatmapDisplay = WindowsHeatmapDisplay.Hidden,
        };
        using var client = new GitHubRepositoryClient(
            settings,
            token: null,
            handler,
            EmptyGraphQlHandler(),
            cache: null);

        var statuses = await client.LoadRepositoriesAsync(
            [new RepositoryRef { Owner = "owner", Name = "name" }],
            LocalGitIndex.Empty,
            CancellationToken.None);

        Assert.Single(statuses);
        Assert.Null(statuses[0].Heatmap);
        Assert.Equal(0, heatmapCalls);
    }

    [Fact]
    public async Task Repository_client_limits_heatmap_to_configured_recent_window()
    {
        var handler = new StubHandler(request =>
        {
            var path = request.RequestUri?.PathAndQuery ?? "";
            if (path == "/repos/owner/name/stats/commit_activity")
            {
                return JsonResponse("""
                    [
                      {"week": 1773014400, "total": 50},
                      {"week": 1773619200, "total": 1},
                      {"week": 1774224000, "total": 1},
                      {"week": 1774828800, "total": 1},
                      {"week": 1775433600, "total": 1}
                    ]
                    """);
            }

            return MinimalRepositoryResponse(path);
        });
        var settings = new WindowsSettings
        {
            EnableResponseCache = false,
            HeatmapSpan = WindowsHeatmapSpan.OneMonth,
        };
        using var client = new GitHubRepositoryClient(
            settings,
            token: null,
            handler,
            EmptyGraphQlHandler(),
            cache: null);

        var statuses = await client.LoadRepositoriesAsync(
            [new RepositoryRef { Owner = "owner", Name = "name" }],
            LocalGitIndex.Empty,
            CancellationToken.None);

        Assert.Single(statuses);
        Assert.Equal(4, statuses[0].Heatmap?.TotalCommits);
        Assert.Equal(4, statuses[0].Heatmap?.ActiveWeeks);
        Assert.Equal(WindowsHeatmapSpan.OneMonth, statuses[0].Heatmap?.Span);
        Assert.Contains("1 month", statuses[0].Heatmap?.DisplayText);
    }

    [Fact]
    public void Rate_limit_snapshot_detects_active_blockers()
    {
        var reset = DateTimeOffset.UtcNow.AddMinutes(20);
        var snapshot = new GitHubRateLimitSnapshot(5000, 0, reset, "core");

        Assert.True(snapshot.IsBlocked(DateTimeOffset.UtcNow));
        Assert.Contains("blocked", snapshot.CompactText(DateTimeOffset.UtcNow));
    }

    [Fact]
    public void Rate_limit_snapshot_keeps_latest_snapshot_per_resource()
    {
        var snapshots = GitHubRateLimitSnapshot.LatestByResource(
        [
            new GitHubRateLimitSnapshot(5000, 4999, null, "core"),
            new GitHubRateLimitSnapshot(5000, 4998, null, "graphql"),
            new GitHubRateLimitSnapshot(5000, 4000, null, "core"),
        ]);

        Assert.Equal(2, snapshots.Count);
        Assert.Equal(4000, snapshots.Single(snapshot => snapshot.Resource == "core").Remaining);
        Assert.Equal(4998, snapshots.Single(snapshot => snapshot.Resource == "graphql").Remaining);
    }

    private static HttpResponseMessage JsonResponse(string json)
    {
        return new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
    }

    private static HttpResponseMessage MinimalRepositoryResponse(string path)
    {
        return path switch
        {
            "/repos/owner/name" => JsonResponse("""
                {
                  "open_issues_count": 0,
                  "stargazers_count": 0,
                  "forks_count": 0,
                  "default_branch": "main",
                  "pushed_at": "2026-06-01T00:00:00Z"
                }
                """),
            "/repos/owner/name/actions/runs?branch=main&per_page=1" => JsonResponse("""{"workflow_runs":[]}"""),
            "/repos/owner/name/actions/runs?per_page=5" => JsonResponse("""{"workflow_runs":[]}"""),
            "/repos/owner/name/releases/latest" => new HttpResponseMessage(HttpStatusCode.NotFound),
            "/repos/owner/name/traffic/views" => new HttpResponseMessage(HttpStatusCode.NotFound),
            "/repos/owner/name/traffic/clones" => new HttpResponseMessage(HttpStatusCode.NotFound),
            "/repos/owner/name/contents/CHANGELOG.md?ref=main" => new HttpResponseMessage(HttpStatusCode.NotFound),
            "/repos/owner/name/contents/CHANGELOG?ref=main" => new HttpResponseMessage(HttpStatusCode.NotFound),
            _ => JsonResponse("[]"),
        };
    }

    private static StubHandler EmptyGraphQlHandler()
    {
        return new StubHandler(_ => JsonResponse("""
            {
              "data": {
                "repository": {
                  "discussions": {
                    "nodes": []
                  }
                }
              }
            }
            """));
    }

    private static HttpResponseMessage ChangelogResponse(string markdown)
    {
        var content = Convert.ToBase64String(Encoding.UTF8.GetBytes(markdown));
        return JsonResponse($$"""{"encoding":"base64","content":"{{content}}"}""");
    }

    private static WindowsAccountProfile Account(string id, string host)
    {
        return new WindowsAccountProfile
        {
            Id = id,
            Label = id,
            GitHubHost = host,
        };
    }

    private static void DeleteDirectory(string directory)
    {
        if (Directory.Exists(directory))
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _handler;

        public StubHandler(Func<HttpRequestMessage, HttpResponseMessage> handler)
        {
            _handler = handler;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            return Task.FromResult(_handler(request));
        }
    }
}
