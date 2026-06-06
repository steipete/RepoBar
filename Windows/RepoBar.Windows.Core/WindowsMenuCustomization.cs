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
        WindowsMainMenuItem.GlobalCommits,
        WindowsMainMenuItem.GlobalActivity,
        WindowsMainMenuItem.ActionsUsage,
        WindowsMainMenuItem.RateLimits,
        WindowsMainMenuItem.RepositoryScope,
        WindowsMainMenuItem.RepositorySort,
        WindowsMainMenuItem.MyRepositories,
        WindowsMainMenuItem.Diagnostics,
        WindowsMainMenuItem.IssueNavigator,
        WindowsMainMenuItem.AccountSwitcher,
        WindowsMainMenuItem.LogOut,
        WindowsMainMenuItem.Preferences,
        WindowsMainMenuItem.About,
        WindowsMainMenuItem.CheckForUpdates,
        WindowsMainMenuItem.CopyUpdateDiagnostics,
        WindowsMainMenuItem.OpenSettingsFile,
        WindowsMainMenuItem.ClearResponseCache,
        WindowsMainMenuItem.Quit,
    ];

    public static IReadOnlyList<WindowsRepositoryMenuItem> DefaultRepositoryMenuOrder { get; } =
    [
        WindowsRepositoryMenuItem.OpenRepository,
        WindowsRepositoryMenuItem.OpenIssues,
        WindowsRepositoryMenuItem.OpenPullRequests,
        WindowsRepositoryMenuItem.OpenActions,
        WindowsRepositoryMenuItem.LatestRelease,
        WindowsRepositoryMenuItem.Changelog,
        WindowsRepositoryMenuItem.OpenFolder,
        WindowsRepositoryMenuItem.OpenTerminal,
        WindowsRepositoryMenuItem.Checkout,
        WindowsRepositoryMenuItem.LocalStatus,
        WindowsRepositoryMenuItem.RecentIssues,
        WindowsRepositoryMenuItem.RecentPullRequests,
        WindowsRepositoryMenuItem.Releases,
        WindowsRepositoryMenuItem.CiRuns,
        WindowsRepositoryMenuItem.Discussions,
        WindowsRepositoryMenuItem.Branches,
        WindowsRepositoryMenuItem.Tags,
        WindowsRepositoryMenuItem.Contributors,
        WindowsRepositoryMenuItem.StatusDetails,
        WindowsRepositoryMenuItem.Traffic,
        WindowsRepositoryMenuItem.Heatmap,
        WindowsRepositoryMenuItem.PushedAt,
        WindowsRepositoryMenuItem.Commits,
        WindowsRepositoryMenuItem.Activity,
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

    public IReadOnlyList<WindowsRepositoryMenuBlock> VisibleRepositoryMenuBlocks()
    {
        return VisibleRepositoryMenuItems()
            .GroupAdjacent(item => item.Group())
            .Select(group => new WindowsRepositoryMenuBlock(group.Key, group.Items))
            .ToArray();
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
    GlobalCommits,
    GlobalActivity,
    ActionsUsage,
    RateLimits,
    RepositoryScope,
    RepositorySort,
    MyRepositories,
    Diagnostics,
    IssueNavigator,
    AccountSwitcher,
    LogOut,
    Preferences,
    About,
    CheckForUpdates,
    CopyUpdateDiagnostics,
    OpenSettingsFile,
    ClearResponseCache,
    Quit,
}

internal enum WindowsRepositoryMenuItem
{
    OpenRepository,
    OpenIssues,
    OpenPullRequests,
    OpenActions,
    OpenFolder,
    OpenTerminal,
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

internal enum WindowsRepositoryMenuGroup
{
    Open,
    Local,
    Lists,
    Status,
    Commits,
    Activity,
    Manage,
}

internal sealed record WindowsRepositoryMenuBlock(
    WindowsRepositoryMenuGroup Group,
    IReadOnlyList<WindowsRepositoryMenuItem> Items);

internal static class WindowsMenuCustomizationLabels
{
    public static string DisplayName(this WindowsMainMenuItem item)
    {
        return item switch
        {
            WindowsMainMenuItem.RefreshNow => "Refresh now",
            WindowsMainMenuItem.ContributionSummary => "Contribution summary",
            WindowsMainMenuItem.GlobalCommits => "Commits",
            WindowsMainMenuItem.GlobalActivity => "Activity",
            WindowsMainMenuItem.ActionsUsage => "Actions usage",
            WindowsMainMenuItem.RateLimits => "Rate limits",
            WindowsMainMenuItem.RepositoryScope => "Repository scope",
            WindowsMainMenuItem.RepositorySort => "Repository sort",
            WindowsMainMenuItem.MyRepositories => "My repositories",
            WindowsMainMenuItem.Diagnostics => "Diagnostics",
            WindowsMainMenuItem.IssueNavigator => "Issue Navigator",
            WindowsMainMenuItem.AccountSwitcher => "Account switcher",
            WindowsMainMenuItem.LogOut => "Log out",
            WindowsMainMenuItem.Preferences => "Preferences",
            WindowsMainMenuItem.About => "About RepoBar",
            WindowsMainMenuItem.CheckForUpdates => "Check for updates",
            WindowsMainMenuItem.CopyUpdateDiagnostics => "Copy update diagnostics",
            WindowsMainMenuItem.OpenSettingsFile => "Open settings file",
            WindowsMainMenuItem.ClearResponseCache => "Clear response cache",
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
            WindowsRepositoryMenuItem.OpenFolder => "Open folder",
            WindowsRepositoryMenuItem.OpenTerminal => "Open in terminal",
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

    public static WindowsRepositoryMenuGroup Group(this WindowsRepositoryMenuItem item)
    {
        return item switch
        {
            WindowsRepositoryMenuItem.OpenRepository or
                WindowsRepositoryMenuItem.OpenIssues or
                WindowsRepositoryMenuItem.OpenPullRequests or
                WindowsRepositoryMenuItem.OpenActions or
                WindowsRepositoryMenuItem.LatestRelease or
                WindowsRepositoryMenuItem.Changelog => WindowsRepositoryMenuGroup.Open,
            WindowsRepositoryMenuItem.OpenFolder or
                WindowsRepositoryMenuItem.OpenTerminal or
                WindowsRepositoryMenuItem.Checkout or
                WindowsRepositoryMenuItem.LocalStatus => WindowsRepositoryMenuGroup.Local,
            WindowsRepositoryMenuItem.RecentIssues or
                WindowsRepositoryMenuItem.RecentPullRequests or
                WindowsRepositoryMenuItem.Releases or
                WindowsRepositoryMenuItem.CiRuns or
                WindowsRepositoryMenuItem.Branches or
                WindowsRepositoryMenuItem.Tags or
                WindowsRepositoryMenuItem.Contributors or
                WindowsRepositoryMenuItem.Discussions => WindowsRepositoryMenuGroup.Lists,
            WindowsRepositoryMenuItem.StatusDetails or
                WindowsRepositoryMenuItem.Traffic or
                WindowsRepositoryMenuItem.Heatmap or
                WindowsRepositoryMenuItem.PushedAt => WindowsRepositoryMenuGroup.Status,
            WindowsRepositoryMenuItem.Commits => WindowsRepositoryMenuGroup.Commits,
            WindowsRepositoryMenuItem.Activity => WindowsRepositoryMenuGroup.Activity,
            WindowsRepositoryMenuItem.Visibility => WindowsRepositoryMenuGroup.Manage,
            _ => WindowsRepositoryMenuGroup.Open,
        };
    }

    public static bool IsRequired(this WindowsMainMenuItem item)
    {
        return item is WindowsMainMenuItem.Preferences or WindowsMainMenuItem.About or WindowsMainMenuItem.Quit;
    }
}

internal sealed record AdjacentGroup<TKey, TItem>(TKey Key, IReadOnlyList<TItem> Items)
    where TKey : notnull;

internal static class WindowsMenuGrouping
{
    public static IReadOnlyList<AdjacentGroup<TKey, TItem>> GroupAdjacent<TItem, TKey>(
        this IEnumerable<TItem> items,
        Func<TItem, TKey> keySelector)
        where TKey : notnull
    {
        var groups = new List<AdjacentGroup<TKey, TItem>>();
        var currentKey = default(TKey)!;
        List<TItem>? currentItems = null;
        var hasCurrent = false;

        foreach (var item in items)
        {
            var key = keySelector(item);
            if (!hasCurrent || !EqualityComparer<TKey>.Default.Equals(currentKey, key))
            {
                if (currentItems != null)
                {
                    groups.Add(new AdjacentGroup<TKey, TItem>(currentKey, currentItems));
                }

                currentKey = key;
                currentItems = [];
                hasCurrent = true;
            }

            currentItems!.Add(item);
        }

        if (currentItems != null)
        {
            groups.Add(new AdjacentGroup<TKey, TItem>(currentKey, currentItems));
        }

        return groups;
    }
}
