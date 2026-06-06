using System.Net;
using System.Text;
using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsTokenValidatorTests
{
    [Fact]
    public async Task ValidateAsync_returns_login_for_valid_token()
    {
        HttpRequestMessage? captured = null;
        using var validator = new WindowsTokenValidator(
            new WindowsSettings(),
            "token",
            new StubHandler(request =>
            {
                captured = request;
                return JsonResponse("""{"login":"octocat"}""");
            }));

        var result = await validator.ValidateAsync(CancellationToken.None);

        Assert.True(result.IsValid);
        Assert.Equal("octocat", result.Login);
        Assert.Contains("octocat", result.Message);
        Assert.Equal("https://api.github.com/user", captured?.RequestUri?.ToString());
        Assert.Equal("Bearer", captured?.Headers.Authorization?.Scheme);
        Assert.Equal("token", captured?.Headers.Authorization?.Parameter);
    }

    [Fact]
    public async Task ValidateAsync_skips_network_when_token_is_missing()
    {
        var called = false;
        using var validator = new WindowsTokenValidator(
            new WindowsSettings(),
            token: null,
            new StubHandler(_ =>
            {
                called = true;
                return JsonResponse("{}");
            }));

        var result = await validator.ValidateAsync(CancellationToken.None);

        Assert.False(result.IsValid);
        Assert.False(called);
        Assert.Contains("No GitHub token", result.Message);
    }

    [Fact]
    public async Task ValidateAsync_reports_rejected_token_without_throwing()
    {
        using var validator = new WindowsTokenValidator(
            new WindowsSettings(),
            "bad-token",
            new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.Unauthorized)));

        var result = await validator.ValidateAsync(CancellationToken.None);

        Assert.False(result.IsValid);
        Assert.Contains("401", result.Message);
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
