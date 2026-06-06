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
    public async Task Repository_client_tracks_rate_limit_headers()
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

        var statuses = await client.LoadRepositoriesAsync(
            [new RepositoryRef { Owner = "owner", Name = "name" }],
            LocalGitIndex.Empty,
            CancellationToken.None);

        Assert.Single(statuses);
        Assert.Equal(42, statuses[0].Traffic?.Views);
        Assert.Equal(7, statuses[0].Heatmap?.TotalCommits);
        Assert.Equal("1.2.3", statuses[0].Changelog?.Headline);
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
    public void Rate_limit_snapshot_detects_active_blockers()
    {
        var reset = DateTimeOffset.UtcNow.AddMinutes(20);
        var snapshot = new GitHubRateLimitSnapshot(5000, 0, reset, "core");

        Assert.True(snapshot.IsBlocked(DateTimeOffset.UtcNow));
        Assert.Contains("blocked", snapshot.CompactText(DateTimeOffset.UtcNow));
    }

    private static HttpResponseMessage JsonResponse(string json)
    {
        return new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
    }

    private static HttpResponseMessage ChangelogResponse(string markdown)
    {
        var content = Convert.ToBase64String(Encoding.UTF8.GetBytes(markdown));
        return JsonResponse($$"""{"encoding":"base64","content":"{{content}}"}""");
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
