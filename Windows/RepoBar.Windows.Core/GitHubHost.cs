namespace RepoBar.Windows;

internal static class GitHubHost
{
    public static string Normalize(string? value)
    {
        var host = string.IsNullOrWhiteSpace(value) ? "github.com" : value.Trim();
        if (Uri.TryCreate(host, UriKind.Absolute, out var uri) && !string.IsNullOrWhiteSpace(uri.Host))
        {
            host = uri.Host;
        }

        host = host.Trim().TrimEnd('/');
        return string.IsNullOrWhiteSpace(host) ? "github.com" : host.ToLowerInvariant();
    }
}
