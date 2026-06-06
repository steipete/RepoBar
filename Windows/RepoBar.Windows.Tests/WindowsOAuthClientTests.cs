using System.Net;
using System.Text;
using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsOAuthClientTests
{
    [Fact]
    public void BuildAuthorizeUri_uses_github_app_pkce_flow_without_repo_scope()
    {
        var uri = WindowsOAuthClient.BuildAuthorizeUri(
            "github.com",
            new Uri("http://127.0.0.1:53682/callback"),
            "state-1",
            "challenge-1",
            scope: null);

        Assert.Equal("https://github.com/login/oauth/authorize", uri.GetLeftPart(UriPartial.Path));
        Assert.Contains($"client_id={WindowsOAuthClient.DefaultClientId}", uri.Query);
        Assert.Contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A53682%2Fcallback", uri.Query);
        Assert.Contains("code_challenge_method=S256", uri.Query);
        Assert.DoesNotContain("scope=", uri.Query);
    }

    [Fact]
    public void CreateCodeChallenge_matches_pkce_reference_vector()
    {
        var challenge = WindowsOAuthClient.CreateCodeChallenge(
            "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk");

        Assert.Equal("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", challenge);
    }

    [Fact]
    public void ParseTokenResponse_reads_github_snake_case_fields()
    {
        var now = DateTimeOffset.Parse("2026-06-06T12:00:00Z");

        var tokens = WindowsOAuthClient.ParseTokenResponse(
            """{"access_token":"access","refresh_token":"refresh","expires_in":3600,"token_type":"bearer"}""",
            now);

        Assert.Equal("access", tokens.AccessToken);
        Assert.Equal("refresh", tokens.RefreshToken);
        Assert.Equal(now.AddHours(1), tokens.ExpiresAt);
    }

    [Fact]
    public async Task RefreshAsync_posts_refresh_grant_and_preserves_existing_refresh_token()
    {
        HttpRequestMessage? captured = null;
        string? capturedForm = null;
        using var httpClient = new HttpClient(new StubHandler(request =>
        {
            captured = request;
            capturedForm = request.Content?.ReadAsStringAsync().GetAwaiter().GetResult();
            return JsonResponse("""{"access_token":"new-access","expires_in":7200,"token_type":"bearer"}""");
        }));
        using var client = new WindowsOAuthClient(
            httpClient,
            _ => { },
            _ => new WindowsOAuthClientCredentials("client-id", "client-secret"));

        var tokens = await client.RefreshAsync(
            new WindowsSettings(),
            new WindowsOAuthTokens("old-access", "old-refresh", DateTimeOffset.UtcNow.AddMinutes(-5)),
            CancellationToken.None);

        Assert.Equal("new-access", tokens.AccessToken);
        Assert.Equal("old-refresh", tokens.RefreshToken);
        Assert.Equal("https://github.com/login/oauth/access_token", captured?.RequestUri?.ToString());
        Assert.NotNull(capturedForm);
        Assert.Contains("grant_type=refresh_token", capturedForm);
        Assert.Contains("refresh_token=old-refresh", capturedForm);
    }

    [Fact]
    public void ResolveCredentials_uses_configured_secret_environment_variable()
    {
        var variable = $"REPOBAR_TEST_SECRET_{Guid.NewGuid():N}";
        Environment.SetEnvironmentVariable(variable, "secret-value");
        try
        {
            var credentials = WindowsOAuthClient.ResolveCredentials(new WindowsSettings
            {
                GitHubOAuthClientId = "client-id",
                GitHubOAuthClientSecretEnvironmentVariable = variable,
            });

            Assert.Equal("client-id", credentials.ClientId);
            Assert.Equal("secret-value", credentials.ClientSecret);
        }
        finally
        {
            Environment.SetEnvironmentVariable(variable, null);
        }
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
