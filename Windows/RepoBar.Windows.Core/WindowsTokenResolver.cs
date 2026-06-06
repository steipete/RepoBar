namespace RepoBar.Windows;

internal static class WindowsTokenResolver
{
    public static async Task<string?> ResolveAsync(
        WindowsSettings settings,
        string? fallbackToken,
        CancellationToken cancellationToken)
    {
        var oauthStore = new WindowsOAuthTokenStore(settings.GitHubHost);
        var tokens = oauthStore.ReadTokens();
        if (tokens != null)
        {
            if (tokens.ShouldRefresh(DateTimeOffset.UtcNow))
            {
                try
                {
                    using var client = new WindowsOAuthClient();
                    tokens = await client.RefreshAsync(settings, tokens, cancellationToken).ConfigureAwait(false);
                    oauthStore.SaveTokens(tokens);
                }
                catch when (!string.IsNullOrWhiteSpace(fallbackToken))
                {
                    return fallbackToken;
                }
            }

            if (!string.IsNullOrWhiteSpace(tokens.AccessToken))
            {
                return tokens.AccessToken;
            }
        }

        return fallbackToken;
    }
}
