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
                "/repos/owner/name/releases/latest" => new HttpResponseMessage(HttpStatusCode.NotFound),
                _ => JsonResponse("[]"),
            };
            response.Headers.TryAddWithoutValidation("X-RateLimit-Limit", "5000");
            response.Headers.TryAddWithoutValidation("X-RateLimit-Remaining", "4999");
            response.Headers.TryAddWithoutValidation("X-RateLimit-Resource", "core");
            return response;
        });
        var settings = new WindowsSettings { EnableResponseCache = false };
        using var client = new GitHubRepositoryClient(settings, token: null, handler, cache: null);

        var statuses = await client.LoadRepositoriesAsync(
            [new RepositoryRef { Owner = "owner", Name = "name" }],
            LocalGitIndex.Empty,
            CancellationToken.None);

        Assert.Single(statuses);
        Assert.NotNull(client.LastRateLimit);
        Assert.Equal(4999, client.LastRateLimit.Remaining);
        Assert.Contains("4999/5000", client.LastRateLimit.DisplayText);
    }

    private static HttpResponseMessage JsonResponse(string json)
    {
        return new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
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
