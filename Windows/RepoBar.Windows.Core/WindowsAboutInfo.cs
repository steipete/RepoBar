namespace RepoBar.Windows;

internal sealed record WindowsAboutInfo(
    string AppName,
    string Version,
    string Description,
    IReadOnlyList<WindowsAboutLink> Links)
{
    public static WindowsAboutInfo Current()
    {
        return new WindowsAboutInfo(
            "RepoBar Windows",
            WindowsUpdateChecker.CurrentVersion(),
            "Native taskbar tray companion for GitHub repository status.",
            DefaultLinks);
    }

    public static IReadOnlyList<WindowsAboutLink> DefaultLinks { get; } =
    [
        new("GitHub", "https://github.com/steipete/RepoBar"),
        new("Website", "https://repobar.app"),
        new("Issue Tracker", "https://github.com/steipete/RepoBar/issues"),
        new("Email", "mailto:peter@steipete.me"),
    ];
}

internal sealed record WindowsAboutLink(string Label, string Url);
