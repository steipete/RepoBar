using System.Text.Json;

namespace RepoBar.Windows;

internal sealed record WindowsOAuthTokens(
    string AccessToken,
    string RefreshToken,
    DateTimeOffset? ExpiresAt)
{
    public bool ShouldRefresh(DateTimeOffset now)
    {
        return !string.IsNullOrWhiteSpace(RefreshToken) &&
            ExpiresAt is { } expiresAt &&
            expiresAt <= now.AddMinutes(1);
    }
}

internal sealed class WindowsOAuthTokenStore
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly WindowsCredentialStore _credentialStore;

    public WindowsOAuthTokenStore(string gitHubHost)
    {
        _credentialStore = WindowsCredentialStore.CreateOAuthStore(gitHubHost);
    }

    public string TargetName => _credentialStore.TargetName;

    public WindowsOAuthTokens? ReadTokens()
    {
        var json = _credentialStore.ReadToken();
        return string.IsNullOrWhiteSpace(json) ? null : Deserialize(json);
    }

    public void SaveTokens(WindowsOAuthTokens tokens)
    {
        _credentialStore.SaveToken(Serialize(tokens));
    }

    public void ClearTokens()
    {
        _credentialStore.ClearToken();
    }

    internal static string Serialize(WindowsOAuthTokens tokens)
    {
        return JsonSerializer.Serialize(tokens, JsonOptions);
    }

    internal static WindowsOAuthTokens? Deserialize(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<WindowsOAuthTokens>(json, JsonOptions);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
