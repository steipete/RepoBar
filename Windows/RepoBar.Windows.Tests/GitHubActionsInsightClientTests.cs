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
                _ => new HttpResponseMessage(HttpStatusCode.NotFound),
            };
        });
        using var client = new GitHubActionsInsightClient(new WindowsSettings(), token: "token", handler);

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
