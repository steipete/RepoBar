using System.Net;
using System.Text;
using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class GitHubActionsInsightClientTests
{
    [Fact]
    public async Task LoadAsync_reads_queue_counts_and_repository_runners()
    {
        var handler = new StubHandler(request =>
        {
            var path = request.RequestUri?.PathAndQuery ?? "";
            return path switch
            {
                "/repos/owner/name/actions/runs?status=in_progress&per_page=1" => JsonResponse("""{"total_count":2}"""),
                "/repos/owner/name/actions/runs?status=queued&per_page=1" => JsonResponse("""{"total_count":3}"""),
                "/repos/owner/name/actions/runs?status=waiting&per_page=1" => JsonResponse("""{"total_count":1}"""),
                "/repos/owner/name/actions/runs?status=pending&per_page=1" => JsonResponse("""{"total_count":0}"""),
                "/repos/owner/name/actions/runners?per_page=100" => JsonResponse("""
                    {
                      "total_count": 2,
                      "runners": [
                        {"id":1,"name":"win-large","os":"Windows","status":"online","busy":true,"labels":[{"name":"self-hosted"},{"name":"Windows"}]},
                        {"id":2,"name":"linux-idle","os":"Linux","status":"offline","busy":false,"labels":[]}
                      ]
                    }
                    """),
                "/users/owner/settings/billing/usage?product=actions" => JsonResponse("""
                    {
                      "usageItems": [
                        {"date":"2026-06-01","sku":"ACTIONS_WINDOWS","quantity":120.5,"unitType":"minutes","netAmount":1.25,"organizationName":null,"repositoryName":"owner/name"},
                        {"date":"2026-06-01","sku":"ACTIONS_LINUX","quantity":30,"unitType":"minutes","netAmount":0,"organizationName":null,"repositoryName":"owner/name"}
                      ]
                    }
                    """),
                "/orgs/owner/actions/cache/usage" => JsonResponse("""
                    {
                      "total_active_caches_count": 3,
                      "total_active_caches_size_in_bytes": 10485760
                    }
                    """),
                _ => new HttpResponseMessage(HttpStatusCode.NotFound),
            };
        });
        using var client = new GitHubActionsInsightClient(
            new WindowsSettings
            {
                ActionsPlanTier = WindowsActionsPlanTier.Team,
            },
            token: "token",
            handler);

        var insights = await client.LoadAsync([new RepositoryRef { Owner = "owner", Name = "name" }], CancellationToken.None);

        var repository = Assert.Single(insights.Repositories);
        Assert.Equal(2, repository.Queue.InProgressCount);
        Assert.Equal(4, repository.Queue.QueuedCount);
        Assert.Equal(2, repository.Runners.TotalCount);
        Assert.Equal(1, repository.Runners.OnlineCount);
        Assert.Equal(1, repository.Runners.BusyCount);
        Assert.Equal("win-large  Windows  busy  self-hosted, Windows", repository.Runners.Runners[0].DisplayText);
        Assert.Contains("2 running", insights.DisplayText);
        Assert.Contains("4 queued", insights.DisplayText);
        Assert.Contains("1/2 runners", insights.DisplayText);
        Assert.Contains("Team plan", insights.DisplayText);
        Assert.NotNull(insights.Billing);
        Assert.Equal(150.5, insights.Billing.TotalMinutes);
        Assert.Equal(3000, insights.IncludedMinutesPerMonth);
        Assert.Equal(2850, insights.RemainingIncludedMinutes);
        Assert.Equal(60, insights.ConcurrentJobs);
        Assert.Equal(1.25, insights.Billing.TotalNetAmount);
        Assert.Equal(120.5, insights.Billing.MinutesByOs["Windows"]);
        Assert.Contains("$1.25", insights.DisplayText);
        var cacheUsage = Assert.Single(insights.CacheUsage);
        Assert.Equal("owner", cacheUsage.Owner);
        Assert.Equal(3, cacheUsage.TotalCachesCount);
        Assert.Equal(10d, cacheUsage.CacheSizeMb);
        Assert.Contains("10 MB cache", insights.DisplayText);
        var rateLimit = Assert.Single(insights.RateLimits);
        Assert.Equal("core", rateLimit.Resource);
        Assert.Equal(4997, rateLimit.Remaining);
    }

    [Fact]
    public async Task LoadAsync_treats_forbidden_actions_surfaces_as_empty()
    {
        using var client = new GitHubActionsInsightClient(
            new WindowsSettings(),
            token: null,
            new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.Forbidden)));

        var insights = await client.LoadAsync([new RepositoryRef { Owner = "owner", Name = "private" }], CancellationToken.None);

        var repository = Assert.Single(insights.Repositories);
        Assert.Null(repository.ErrorMessage);
        Assert.Equal(0, repository.Queue.InProgressCount);
        Assert.Equal(0, repository.Queue.QueuedCount);
        Assert.Equal(0, repository.Runners.TotalCount);
        Assert.Equal("idle", repository.DisplayText);
    }

    [Fact]
    public async Task LoadAsync_uses_configured_monitored_owners_for_owner_usage()
    {
        var handler = new StubHandler(request =>
        {
            var path = request.RequestUri?.PathAndQuery ?? "";
            return path switch
            {
                "/repos/repo-owner/name/actions/runs?status=in_progress&per_page=1" => JsonResponse("""{"total_count":0}"""),
                "/repos/repo-owner/name/actions/runs?status=queued&per_page=1" => JsonResponse("""{"total_count":0}"""),
                "/repos/repo-owner/name/actions/runs?status=waiting&per_page=1" => JsonResponse("""{"total_count":0}"""),
                "/repos/repo-owner/name/actions/runs?status=pending&per_page=1" => JsonResponse("""{"total_count":0}"""),
                "/repos/repo-owner/name/actions/runners?per_page=100" => JsonResponse("""{"total_count":0,"runners":[]}"""),
                "/users/actions-org/settings/billing/usage?product=actions" => new HttpResponseMessage(HttpStatusCode.NotFound),
                "/organizations/actions-org/settings/billing/usage?product=actions" => JsonResponse("""
                    {
                      "usageItems": [
                        {"date":"2026-06-01","sku":"ACTIONS_LINUX","quantity":42,"unitType":"minutes","netAmount":0,"organizationName":"actions-org","repositoryName":null}
                      ]
                    }
                    """),
                "/orgs/actions-org/actions/cache/usage" => JsonResponse("""
                    {
                      "total_active_caches_count": 1,
                      "total_active_caches_size_in_bytes": 2097152
                    }
                    """),
                var unexpected when unexpected.Contains("repo-owner", StringComparison.OrdinalIgnoreCase) &&
                    (unexpected.Contains("billing", StringComparison.OrdinalIgnoreCase) || unexpected.Contains("cache", StringComparison.OrdinalIgnoreCase)) =>
                    new HttpResponseMessage(HttpStatusCode.InternalServerError),
                _ => new HttpResponseMessage(HttpStatusCode.NotFound),
            };
        });
        using var client = new GitHubActionsInsightClient(
            new WindowsSettings
            {
                ActionsMonitoredOwners = [" actions-org ", "actions-org"],
            },
            token: "token",
            handler);

        var insights = await client.LoadAsync([new RepositoryRef { Owner = "repo-owner", Name = "name" }], CancellationToken.None);

        Assert.Equal(42, insights.Billing?.TotalMinutes);
        var cacheUsage = Assert.Single(insights.CacheUsage);
        Assert.Equal("actions-org", cacheUsage.Owner);
        Assert.Equal(2d, cacheUsage.CacheSizeMb);
    }

    private static HttpResponseMessage JsonResponse(string json)
    {
        var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
        response.Headers.TryAddWithoutValidation("X-RateLimit-Limit", "5000");
        response.Headers.TryAddWithoutValidation("X-RateLimit-Remaining", "4997");
        response.Headers.TryAddWithoutValidation("X-RateLimit-Resource", "core");
        return response;
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
