namespace RepoBar.Windows;

internal static class GitHubHost
{
    public static string Normalize(string? value)
    {
        var host = string.IsNullOrWhiteSpace(value) ? "github.com" : value.Trim();
        if (Uri.TryCreate(host, UriKind.Absolute, out var uri) && !string.IsNullOrWhiteSpace(uri.Host))
        {
            host = uri.IsDefaultPort ? uri.Host : $"{uri.Host}:{uri.Port}";
        }
        else
        {
            host = host.Split(['/', '\\', '?', '#'], 2, StringSplitOptions.RemoveEmptyEntries)[0];
        }

        host = host.Trim().TrimEnd('/');
        return string.IsNullOrWhiteSpace(host) ? "github.com" : host.ToLowerInvariant();
    }

    public static string GitHubAppInstallUrl(string? value, string appSlug = "repobar")
    {
        var host = Normalize(value);
        var escapedSlug = Uri.EscapeDataString(string.IsNullOrWhiteSpace(appSlug) ? "repobar" : appSlug.Trim());
        var path = host == "github.com" ? "apps" : "github-apps";
        return $"https://{host}/{path}/{escapedSlug}/installations/new";
    }
}
