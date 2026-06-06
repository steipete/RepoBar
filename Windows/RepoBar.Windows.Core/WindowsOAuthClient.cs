using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace RepoBar.Windows;

internal sealed class WindowsOAuthClient : IDisposable
{
    public const string DefaultClientId = "Iv23liGm2arUyotWSjwJ";
    public const string DefaultClientSecretEnvironmentVariable = "REPOBAR_GITHUB_CLIENT_SECRET";
    public const int DefaultLoopbackPort = 53682;

    private readonly HttpClient _httpClient;
    private readonly Action<Uri> _openBrowser;
    private readonly Func<WindowsSettings, WindowsOAuthClientCredentials> _credentialsProvider;

    public WindowsOAuthClient()
        : this(new HttpClient(), OpenBrowser, ResolveCredentials)
    {
    }

    internal WindowsOAuthClient(
        HttpClient httpClient,
        Action<Uri> openBrowser,
        Func<WindowsSettings, WindowsOAuthClientCredentials>? credentialsProvider = null)
    {
        _httpClient = httpClient;
        _openBrowser = openBrowser;
        _credentialsProvider = credentialsProvider ?? ResolveCredentials;
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }

    public async Task<WindowsOAuthTokens> LoginAsync(WindowsSettings settings, CancellationToken cancellationToken)
    {
        var account = settings.GetActiveAccount();
        var verifier = CreateCodeVerifier();
        var state = CreateCodeVerifier();
        var redirect = new Uri($"http://127.0.0.1:{DefaultLoopbackPort}/callback");
        var credentials = _credentialsProvider(settings);
        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{DefaultLoopbackPort}/");
        listener.Start();

        _openBrowser(BuildAuthorizeUri(account.GitHubHost, redirect, state, CreateCodeChallenge(verifier), scope: null, credentials.ClientId));

        var context = await listener.GetContextAsync().WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var request = context.Request;
            if (!string.Equals(request.Url?.AbsolutePath, "/callback", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("GitHub OAuth returned an unexpected callback path.");
            }
            if (!string.Equals(request.QueryString["state"], state, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("GitHub OAuth state did not match.");
            }

            var code = request.QueryString["code"];
            if (string.IsNullOrWhiteSpace(code))
            {
                throw new InvalidOperationException("GitHub OAuth did not return an authorization code.");
            }

            var tokens = await ExchangeCodeAsync(account.GitHubHost, credentials, code, redirect, verifier, cancellationToken).ConfigureAwait(false);
            await WriteBrowserResponseAsync(context.Response, "RepoBar sign-in complete. You can close this tab.", cancellationToken)
                .ConfigureAwait(false);
            return tokens;
        }
        catch
        {
            await WriteBrowserResponseAsync(context.Response, "RepoBar sign-in failed. Return to RepoBar for details.", cancellationToken)
                .ConfigureAwait(false);
            throw;
        }
        finally
        {
            listener.Stop();
        }
    }

    public async Task<WindowsOAuthTokens> RefreshAsync(
        WindowsSettings settings,
        WindowsOAuthTokens tokens,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(tokens.RefreshToken))
        {
            return tokens;
        }

        var account = settings.GetActiveAccount();
        var credentials = _credentialsProvider(settings);
        var values = new Dictionary<string, string>
        {
            ["client_id"] = credentials.ClientId,
            ["client_secret"] = credentials.ClientSecret,
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = tokens.RefreshToken,
        };
        using var request = new HttpRequestMessage(HttpMethod.Post, BuildTokenUri(account.GitHubHost))
        {
            Content = new FormUrlEncodedContent(values),
        };
        request.Headers.Accept.ParseAdd("application/json");
        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"GitHub OAuth refresh failed: HTTP {(int)response.StatusCode}");
        }

        var refreshed = ParseTokenResponse(body, DateTimeOffset.UtcNow);
        return refreshed.RefreshToken.Length == 0 ? refreshed with { RefreshToken = tokens.RefreshToken } : refreshed;
    }

    internal static Uri BuildAuthorizeUri(
        string gitHubHost,
        Uri redirectUri,
        string state,
        string codeChallenge,
        string? scope,
        string? clientId = null)
    {
        var builder = new UriBuilder(BuildWebRoot(gitHubHost))
        {
            Path = "login/oauth/authorize",
        };
        var query = new List<string>
        {
            Pair("client_id", string.IsNullOrWhiteSpace(clientId) ? DefaultClientId : clientId),
            Pair("redirect_uri", redirectUri.ToString()),
            Pair("state", state),
            Pair("code_challenge", codeChallenge),
            Pair("code_challenge_method", "S256"),
        };
        if (!string.IsNullOrWhiteSpace(scope))
        {
            query.Add(Pair("scope", scope));
        }
        builder.Query = string.Join("&", query);
        return builder.Uri;
    }

    internal static Uri BuildTokenUri(string gitHubHost)
    {
        var builder = new UriBuilder(BuildWebRoot(gitHubHost))
        {
            Path = "login/oauth/access_token",
        };
        return builder.Uri;
    }

    internal static WindowsOAuthTokens ParseTokenResponse(string json, DateTimeOffset now)
    {
        var response = JsonSerializer.Deserialize<TokenResponse>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web))
            ?? throw new InvalidOperationException("GitHub OAuth returned an empty token response.");
        if (string.IsNullOrWhiteSpace(response.AccessToken))
        {
            throw new InvalidOperationException("GitHub OAuth did not return an access token.");
        }

        return new WindowsOAuthTokens(
            response.AccessToken,
            response.RefreshToken ?? "",
            response.ExpiresIn == null ? null : now.AddSeconds(response.ExpiresIn.Value));
    }

    internal static string CreateCodeChallenge(string verifier)
    {
        var hash = SHA256.HashData(Encoding.ASCII.GetBytes(verifier));
        return Base64Url(hash);
    }

    private async Task<WindowsOAuthTokens> ExchangeCodeAsync(
        string gitHubHost,
        WindowsOAuthClientCredentials credentials,
        string code,
        Uri redirectUri,
        string verifier,
        CancellationToken cancellationToken)
    {
        var values = new Dictionary<string, string>
        {
            ["client_id"] = credentials.ClientId,
            ["client_secret"] = credentials.ClientSecret,
            ["code"] = code,
            ["redirect_uri"] = redirectUri.ToString(),
            ["grant_type"] = "authorization_code",
            ["code_verifier"] = verifier,
        };
        using var request = new HttpRequestMessage(HttpMethod.Post, BuildTokenUri(gitHubHost))
        {
            Content = new FormUrlEncodedContent(values),
        };
        request.Headers.Accept.ParseAdd("application/json");

        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"GitHub OAuth failed: HTTP {(int)response.StatusCode}");
        }

        return ParseTokenResponse(body, DateTimeOffset.UtcNow);
    }

    private static Uri BuildWebRoot(string gitHubHost)
    {
        return new Uri($"https://{GitHubHost.Normalize(gitHubHost)}");
    }

    private static string CreateCodeVerifier()
    {
        return Base64Url(RandomNumberGenerator.GetBytes(32));
    }

    private static string Base64Url(byte[] bytes)
    {
        return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    private static string Pair(string key, string value)
    {
        return $"{Uri.EscapeDataString(key)}={Uri.EscapeDataString(value)}";
    }

    private static async Task WriteBrowserResponseAsync(
        HttpListenerResponse response,
        string message,
        CancellationToken cancellationToken)
    {
        if (!response.OutputStream.CanWrite)
        {
            return;
        }

        var bytes = Encoding.UTF8.GetBytes($"<!doctype html><title>RepoBar</title><p>{WebUtility.HtmlEncode(message)}</p>");
        response.ContentType = "text/html; charset=utf-8";
        response.ContentLength64 = bytes.Length;
        await response.OutputStream.WriteAsync(bytes, cancellationToken).ConfigureAwait(false);
        response.Close();
    }

    private static void OpenBrowser(Uri uri)
    {
        Process.Start(new ProcessStartInfo(uri.ToString()) { UseShellExecute = true });
    }

    private sealed class TokenResponse
    {
        [JsonPropertyName("access_token")]
        public string AccessToken { get; set; } = "";

        [JsonPropertyName("refresh_token")]
        public string? RefreshToken { get; set; }

        [JsonPropertyName("expires_in")]
        public int? ExpiresIn { get; set; }
    }

    internal static WindowsOAuthClientCredentials ResolveCredentials(WindowsSettings settings)
    {
        var account = settings.GetActiveAccount();
        var clientId = string.IsNullOrWhiteSpace(account.GitHubOAuthClientId)
            ? DefaultClientId
            : account.GitHubOAuthClientId.Trim();
        var secretEnv = string.IsNullOrWhiteSpace(account.GitHubOAuthClientSecretEnvironmentVariable)
            ? DefaultClientSecretEnvironmentVariable
            : account.GitHubOAuthClientSecretEnvironmentVariable.Trim();
        var clientSecret = Environment.GetEnvironmentVariable(secretEnv);
        if (string.IsNullOrWhiteSpace(clientSecret) && !string.Equals(secretEnv, DefaultClientSecretEnvironmentVariable, StringComparison.Ordinal))
        {
            clientSecret = Environment.GetEnvironmentVariable(DefaultClientSecretEnvironmentVariable);
        }
        if (string.IsNullOrWhiteSpace(clientSecret))
        {
            throw new InvalidOperationException($"Set {secretEnv} before signing in with the RepoBar GitHub App.");
        }

        return new WindowsOAuthClientCredentials(clientId, clientSecret.Trim());
    }
}

internal sealed record WindowsOAuthClientCredentials(string ClientId, string ClientSecret);
