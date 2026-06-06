using System.Net;
using System.Text;
using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class GitHubAccountInsightClientTests
{
    [Fact]
    public async Task LoadAsync_reads_viewer_contribution_summary()
    {
        using var client = new GitHubAccountInsightClient(
            new WindowsSettings(),
            token: "token",
            new StubHandler(request =>
            {
                Assert.Equal("/graphql", request.RequestUri?.AbsolutePath);
                return JsonResponse("""
                    {
                      "data": {
                        "viewer": {
                          "login": "octocat",
                          "name": "Octo Cat",
                          "url": "https://github.com/octocat",
                          "contributionsCollection": {
                            "totalCommitContributions": 12,
                            "totalIssueContributions": 3,
                            "totalPullRequestContributions": 4,
                            "totalPullRequestReviewContributions": 5,
                            "contributionCalendar": {
                              "totalContributions": 24,
                              "weeks": [
                                {
                                  "firstDay": "2026-05-17",
                                  "contributionDays": [
                                    {"date": "2026-05-17", "contributionCount": 0},
                                    {"date": "2026-05-18", "contributionCount": 0}
                                  ]
                                },
                                {
                                  "firstDay": "2026-05-24",
                                  "contributionDays": [
                                    {"date": "2026-05-24", "contributionCount": 2},
                                    {"date": "2026-05-25", "contributionCount": 3},
                                    {"date": "2026-05-26", "contributionCount": 0}
                                  ]
                                }
                              ]
                            }
                          }
                        }
                      }
                    }
                    """);
            }));

        var account = await client.LoadAsync(CancellationToken.None);

        Assert.NotNull(account);
        Assert.Equal("octocat", account.Login);
        Assert.Equal("Octo Cat (@octocat)  24 contributions", account.DisplayText);
        Assert.Equal(12, account.CommitContributions);
        Assert.Equal(4, account.PullRequestContributions);
        Assert.Equal(5, account.PullRequestReviewContributions);
        Assert.Equal(3, account.IssueContributions);
        Assert.Equal(2, account.ContributionWeeks.Count);
        Assert.Equal(5, account.ContributionWeeks[1].TotalContributions);
        Assert.Equal(".#", account.ContributionHeatmapPreview);
        Assert.Equal("2 active days  1/2 active weeks  .#", account.ContributionHeatmapDisplayText);
    }

    [Fact]
    public async Task LoadAsync_returns_null_when_viewer_is_unavailable()
    {
        using var client = new GitHubAccountInsightClient(
            new WindowsSettings(),
            token: null,
            new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.Unauthorized)));

        Assert.Null(await client.LoadAsync(CancellationToken.None));
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
