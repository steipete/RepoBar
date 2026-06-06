using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace RepoBar.Windows;

internal sealed class WindowsTokenValidator : IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly string? _token;

    public WindowsTokenValidator(WindowsSettings settings, string? token)
        : this(settings, token, new HttpClientHandler())
    {
    }

    internal WindowsTokenValidator(WindowsSettings settings, string? token, HttpMessageHandler handler)
    {
        var host = GitHubHost.Normalize(settings.GitHubHost);
        var apiRoot = string.Equals(host, "github.com", StringComparison.OrdinalIgnoreCase)
            ? "https://api.github.com/"
            : $"https://{host}/api/v3/";

        _token = token;
        _httpClient = new HttpClient(handler) { BaseAddress = new Uri(apiRoot) };
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("RepoBar-Windows/0.1");
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        _httpClient.DefaultRequestHeaders.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");
        if (!string.IsNullOrWhiteSpace(token))
        {
            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
    }

    public async Task<WindowsTokenValidationResult> ValidateAsync(CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_token))
        {
            return new WindowsTokenValidationResult(false, "No GitHub token available.", null);
        }

        using var response = await _httpClient.GetAsync("user", cancellationToken).ConfigureAwait(false);
        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
        {
            return new WindowsTokenValidationResult(false, $"GitHub rejected the token: HTTP {(int)response.StatusCode}.", null);
        }

        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        var login = document.RootElement.TryGetProperty("login", out var loginElement) &&
            loginElement.ValueKind == JsonValueKind.String
                ? loginElement.GetString()
                : null;
        return new WindowsTokenValidationResult(
            true,
            string.IsNullOrWhiteSpace(login) ? "GitHub token is valid." : $"GitHub token is valid for {login}.",
            login);
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}

internal sealed record WindowsTokenValidationResult(bool IsValid, string Message, string? Login);
