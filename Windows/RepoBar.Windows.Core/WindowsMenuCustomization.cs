namespace RepoBar.Windows;

internal sealed class WindowsMenuCustomization
{
    public List<WindowsMainMenuItem> HiddenMainMenuItems { get; set; } = [];
    public List<WindowsMainMenuItem> MainMenuOrder { get; set; } = DefaultMainMenuOrder.ToList();
    public List<WindowsRepositoryMenuItem> HiddenRepositoryMenuItems { get; set; } = [];
    public List<WindowsRepositoryMenuItem> RepositoryMenuOrder { get; set; } = DefaultRepositoryMenuOrder.ToList();

    public static IReadOnlyList<WindowsMainMenuItem> DefaultMainMenuOrder { get; } =
    [
        WindowsMainMenuItem.RefreshNow,
        WindowsMainMenuItem.ContributionSummary,
        WindowsMainMenuItem.ActionsUsage,
        WindowsMainMenuItem.RateLimits,
        WindowsMainMenuItem.IssueNavigator,
        WindowsMainMenuItem.LogOut,
        WindowsMainMenuItem.Preferences,
        WindowsMainMenuItem.CheckForUpdates,
        WindowsMainMenuItem.OpenSettingsFile,
        WindowsMainMenuItem.Quit,
    ];

    public static IReadOnlyList<WindowsRepositoryMenuItem> DefaultRepositoryMenuOrder { get; } =
    [
        WindowsRepositoryMenuItem.OpenRepository,
        WindowsRepositoryMenuItem.OpenIssues,
        WindowsRepositoryMenuItem.OpenPullRequests,
        WindowsRepositoryMenuItem.OpenActions,
        WindowsRepositoryMenuItem.Checkout,
        WindowsRepositoryMenuItem.RecentIssues,
        WindowsRepositoryMenuItem.RecentPullRequests,
        WindowsRepositoryMenuItem.Releases,
        WindowsRepositoryMenuItem.CiRuns,
        WindowsRepositoryMenuItem.Branches,
        WindowsRepositoryMenuItem.Tags,
        WindowsRepositoryMenuItem.Commits,
        WindowsRepositoryMenuItem.Contributors,
        WindowsRepositoryMenuItem.Activity,
        WindowsRepositoryMenuItem.Discussions,
        WindowsRepositoryMenuItem.LatestRelease,
        WindowsRepositoryMenuItem.StatusDetails,
        WindowsRepositoryMenuItem.Traffic,
        WindowsRepositoryMenuItem.Heatmap,
        WindowsRepositoryMenuItem.Changelog,
        WindowsRepositoryMenuItem.LocalStatus,
        WindowsRepositoryMenuItem.PushedAt,
        WindowsRepositoryMenuItem.Visibility,
    ];

    public void Normalize()
    {
        MainMenuOrder = NormalizedOrder(MainMenuOrder, DefaultMainMenuOrder);
        RepositoryMenuOrder = NormalizedOrder(RepositoryMenuOrder, DefaultRepositoryMenuOrder);
        HiddenMainMenuItems = NormalizedHidden(HiddenMainMenuItems, DefaultMainMenuOrder)
            .Where(item => !item.IsRequired())
            .ToList();
        HiddenRepositoryMenuItems = NormalizedHidden(HiddenRepositoryMenuItems, DefaultRepositoryMenuOrder);
    }

    public WindowsMenuCustomization Copy()
    {
        return new WindowsMenuCustomization
        {
            HiddenMainMenuItems = HiddenMainMenuItems.ToList(),
            MainMenuOrder = MainMenuOrder.ToList(),
            HiddenRepositoryMenuItems = HiddenRepositoryMenuItems.ToList(),
            RepositoryMenuOrder = RepositoryMenuOrder.ToList(),
        };
    }

    public IReadOnlyList<WindowsMainMenuItem> VisibleMainMenuItems()
    {
        var hidden = HiddenMainMenuItems.ToHashSet();
        return MainMenuOrder.Where(item => !hidden.Contains(item) || item.IsRequired()).ToArray();
    }

    public IReadOnlyList<WindowsRepositoryMenuItem> VisibleRepositoryMenuItems()
    {
        var hidden = HiddenRepositoryMenuItems.ToHashSet();
        return RepositoryMenuOrder.Where(item => !hidden.Contains(item)).ToArray();
    }

    public bool IsMainMenuItemVisible(WindowsMainMenuItem item)
    {
        return item.IsRequired() || !HiddenMainMenuItems.Contains(item);
    }

    public bool IsRepositoryMenuItemVisible(WindowsRepositoryMenuItem item)
    {
        return !HiddenRepositoryMenuItems.Contains(item);
    }

    private static List<T> NormalizedOrder<T>(IEnumerable<T>? order, IReadOnlyList<T> defaults)
        where T : struct, Enum
    {
        var allowed = defaults.ToHashSet();
        var seen = new HashSet<T>();
        var result = new List<T>();
        foreach (var item in order ?? [])
        {
            if (allowed.Contains(item) && seen.Add(item))
            {
                result.Add(item);
            }
        }
        foreach (var item in defaults)
        {
            if (seen.Add(item))
            {
                result.Add(item);
            }
        }
        return result;
    }

    private static List<T> NormalizedHidden<T>(IEnumerable<T>? hidden, IReadOnlyList<T> defaults)
        where T : struct, Enum
    {
        var allowed = defaults.ToHashSet();
        var seen = new HashSet<T>();
        var result = new List<T>();
        foreach (var item in hidden ?? [])
        {
            if (allowed.Contains(item) && seen.Add(item))
            {
                result.Add(item);
            }
        }
        return result;
    }
}

internal enum WindowsMainMenuItem
{
    RefreshNow,
    ContributionSummary,
    ActionsUsage,
    RateLimits,
    IssueNavigator,
    LogOut,
    Preferences,
    CheckForUpdates,
    OpenSettingsFile,
    Quit,
}

internal enum WindowsRepositoryMenuItem
{
    OpenRepository,
    OpenIssues,
    OpenPullRequests,
    OpenActions,
    Checkout,
    RecentIssues,
    RecentPullRequests,
    Releases,
    CiRuns,
    Branches,
    Tags,
    Commits,
    Contributors,
    Activity,
    Discussions,
    LatestRelease,
    StatusDetails,
    Traffic,
    Heatmap,
    Changelog,
    LocalStatus,
    PushedAt,
    Visibility,
}

internal static class WindowsMenuCustomizationLabels
{
    public static string DisplayName(this WindowsMainMenuItem item)
    {
        return item switch
        {
            WindowsMainMenuItem.RefreshNow => "Refresh now",
            WindowsMainMenuItem.ContributionSummary => "Contribution summary",
            WindowsMainMenuItem.ActionsUsage => "Actions usage",
            WindowsMainMenuItem.RateLimits => "Rate limits",
            WindowsMainMenuItem.IssueNavigator => "Issue Navigator",
            WindowsMainMenuItem.LogOut => "Log out",
            WindowsMainMenuItem.Preferences => "Preferences",
            WindowsMainMenuItem.CheckForUpdates => "Check for updates",
            WindowsMainMenuItem.OpenSettingsFile => "Open settings file",
            WindowsMainMenuItem.Quit => "Quit RepoBar",
            _ => item.ToString(),
        };
    }

    public static string DisplayName(this WindowsRepositoryMenuItem item)
    {
        return item switch
        {
            WindowsRepositoryMenuItem.OpenRepository => "Open repository",
            WindowsRepositoryMenuItem.OpenIssues => "Open issues",
            WindowsRepositoryMenuItem.OpenPullRequests => "Open pull requests",
            WindowsRepositoryMenuItem.OpenActions => "Open Actions",
            WindowsRepositoryMenuItem.Checkout => "Checkout locally",
            WindowsRepositoryMenuItem.RecentIssues => "Recent issues",
            WindowsRepositoryMenuItem.RecentPullRequests => "Recent pull requests",
            WindowsRepositoryMenuItem.Releases => "Releases",
            WindowsRepositoryMenuItem.CiRuns => "CI runs",
            WindowsRepositoryMenuItem.Branches => "Branches",
            WindowsRepositoryMenuItem.Tags => "Tags",
            WindowsRepositoryMenuItem.Commits => "Commits",
            WindowsRepositoryMenuItem.Contributors => "Contributors",
            WindowsRepositoryMenuItem.Activity => "Activity",
            WindowsRepositoryMenuItem.Discussions => "Discussions",
            WindowsRepositoryMenuItem.LatestRelease => "Latest release",
            WindowsRepositoryMenuItem.StatusDetails => "Status details",
            WindowsRepositoryMenuItem.Traffic => "Traffic",
            WindowsRepositoryMenuItem.Heatmap => "Heatmap",
            WindowsRepositoryMenuItem.Changelog => "Changelog",
            WindowsRepositoryMenuItem.LocalStatus => "Local status",
            WindowsRepositoryMenuItem.PushedAt => "Pushed at",
            WindowsRepositoryMenuItem.Visibility => "Visibility controls",
            _ => item.ToString(),
        };
    }

    public static bool IsRequired(this WindowsMainMenuItem item)
    {
        return item is WindowsMainMenuItem.Preferences or WindowsMainMenuItem.Quit;
    }
}
