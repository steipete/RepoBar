using System.Net;
using System.Text;
using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class GitHubRepositoryDiscoveryClientTests
{
    [Fact]
    public async Task LoadAccessibleRepositories_reads_and_deduplicates_user_repositories()
    {
        var handler = new StubHandler(request =>
        {
            var path = request.RequestUri?.PathAndQuery ?? "";
            return path switch
            {
                "/user/repos?visibility=all&affiliation=owner,collaborator,organization_member&sort=updated&per_page=100&page=1" => JsonResponse("""
                    [
                      {"full_name":"owner/one","description":"first","pushed_at":"2026-06-01T00:00:00Z"},
                      {"full_name":"owner/two","description":"second","pushed_at":"2026-06-02T00:00:00Z"}
                    ]
                    """),
                "/user/repos?visibility=all&affiliation=owner,collaborator,organization_member&sort=updated&per_page=100&page=2" => JsonResponse("""
                    [
                      {"full_name":"owner/one","description":"duplicate","pushed_at":"2026-06-03T00:00:00Z"}
                    ]
                    """),
                _ => JsonResponse("[]"),
            };
        });
        using var client = new GitHubRepositoryDiscoveryClient(new WindowsSettings(), token: null, handler);

        var repositories = await client.LoadAccessibleRepositoriesAsync(CancellationToken.None);

        Assert.Equal(2, repositories.Count);
        Assert.Equal("owner/two", repositories[0].FullName);
        Assert.Equal("owner/one", repositories[1].FullName);
    }

    [Fact]
    public async Task LoadAccessibleRepositories_filters_by_query_before_adding_repositories()
    {
        var handler = new StubHandler(request =>
        {
            var path = request.RequestUri?.PathAndQuery ?? "";
            return path switch
            {
                "/user/repos?visibility=all&affiliation=owner,collaborator,organization_member&sort=updated&per_page=100&page=1" => JsonResponse("""
                    [
                      {"full_name":"owner/one","description":"calendar heatmap","pushed_at":"2026-06-01T00:00:00Z"},
                      {"full_name":"owner/two","description":"issue browser","pushed_at":"2026-06-02T00:00:00Z"},
                      {"full_name":"other/three","description":"settings","pushed_at":"2026-06-03T00:00:00Z"}
                    ]
                    """),
                _ => JsonResponse("[]"),
            };
        });
        using var client = new GitHubRepositoryDiscoveryClient(new WindowsSettings(), token: null, handler);

        var repositories = await client.LoadAccessibleRepositoriesAsync(CancellationToken.None, "browser");

        var repository = Assert.Single(repositories);
        Assert.Equal("owner/two", repository.FullName);
    }

    [Fact]
    public async Task LoadAccessibleRepositories_filters_forked_and_archived_repositories_by_settings()
    {
        static StubHandler Handler()
        {
            return new StubHandler(request =>
            {
                var path = request.RequestUri?.PathAndQuery ?? "";
                return path switch
                {
                    "/user/repos?visibility=all&affiliation=owner,collaborator,organization_member&sort=updated&per_page=100&page=1" => JsonResponse("""
                        [
                          {"full_name":"owner/main","description":"main","pushed_at":"2026-06-03T00:00:00Z","fork":false,"archived":false},
                          {"full_name":"owner/fork","description":"fork","pushed_at":"2026-06-02T00:00:00Z","fork":true,"archived":false},
                          {"full_name":"owner/archived","description":"archived","pushed_at":"2026-06-01T00:00:00Z","fork":false,"archived":true}
                        ]
                        """),
                    _ => JsonResponse("[]"),
                };
            });
        }

        using var filteredClient = new GitHubRepositoryDiscoveryClient(new WindowsSettings(), token: null, Handler());

        var filtered = await filteredClient.LoadAccessibleRepositoriesAsync(CancellationToken.None);

        var repository = Assert.Single(filtered);
        Assert.Equal("owner/main", repository.FullName);

        using var unfilteredClient = new GitHubRepositoryDiscoveryClient(
            new WindowsSettings
            {
                IncludeForkedRepositories = true,
                IncludeArchivedRepositories = true,
            },
            token: null,
            Handler());

        var unfiltered = await unfilteredClient.LoadAccessibleRepositoriesAsync(CancellationToken.None);

        Assert.Equal(["owner/main", "owner/fork", "owner/archived"], unfiltered.Select(item => item.FullName));
    }

    [Theory]
    [InlineData("owner/one")]
    [InlineData("one")]
    [InlineData("calendar")]
    public void RepositorySearchResult_matches_full_name_name_and_description(string query)
    {
        var repository = new RepositorySearchResult("owner", "one", "calendar heatmap", DateTimeOffset.UtcNow);

        Assert.True(repository.Matches(query));
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
