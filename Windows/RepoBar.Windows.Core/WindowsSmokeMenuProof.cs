namespace RepoBar.Windows;

internal static class WindowsSmokeMenuProof
{
    private static readonly WindowsSmokeMenuRequirement[] RequiredMainMenuItems =
    [
        Exact("Refresh now"),
        Prefix("Repository scope:"),
        Prefix("Repository sort:"),
        Prefix("My repositories"),
        Exact("Diagnostics"),
        Exact("Issue Navigator"),
        Prefix("Account:"),
        Exact("Log out"),
        Exact("Preferences"),
        Exact("About RepoBar"),
        Exact("Check for updates"),
        Exact("Copy update diagnostics"),
        Exact("Open settings file"),
        Exact("Clear response cache"),
        Exact("Quit RepoBar"),
    ];

    private static readonly WindowsSmokeMenuRequirement[] RequiredRepositoryMenuItems =
    [
        Exact("Open repository"),
        Exact("Open issues"),
        Exact("Open pull requests"),
        Exact("Open Actions"),
        Exact("Open folder"),
        Exact("Open in terminal"),
        Prefix("Branch:"),
        Exact("Fetch"),
        Exact("Sync"),
        Exact("Rebase onto upstream"),
        Exact("Reset to upstream..."),
        Exact("Branches"),
        Exact("Worktrees"),
        Exact("Issues"),
        Exact("Pull Requests"),
        Exact("Releases"),
        Exact("CI Runs"),
        Exact("Tags"),
        Exact("Commits"),
        Exact("Contributors"),
        Exact("Activity"),
        Exact("Discussions"),
        Prefix("CI:"),
        Prefix("Stars:"),
        Prefix("Default branch:"),
        Exact("Unpin"),
        Exact("Set Visible"),
        Exact("Hide"),
        Exact("Move up"),
        Exact("Move down"),
    ];

    public static IReadOnlyList<string> MissingMainMenuItems(IEnumerable<string?> renderedLabels)
    {
        return MissingItems(renderedLabels, RequiredMainMenuItems);
    }

    public static IReadOnlyList<string> MissingRepositoryMenuItems(IEnumerable<string?> renderedLabels)
    {
        return MissingItems(renderedLabels, RequiredRepositoryMenuItems);
    }

    private static IReadOnlyList<string> MissingItems(
        IEnumerable<string?> renderedLabels,
        IReadOnlyList<WindowsSmokeMenuRequirement> requirements)
    {
        var labels = renderedLabels
            .Where(label => !string.IsNullOrWhiteSpace(label))
            .Select(label => label!.Trim())
            .ToArray();
        return requirements
            .Where(requirement => !labels.Any(requirement.Matches))
            .Select(requirement => requirement.DisplayName)
            .ToArray();
    }

    private static WindowsSmokeMenuRequirement Exact(string label)
    {
        return new WindowsSmokeMenuRequirement(label, MatchPrefix: false);
    }

    private static WindowsSmokeMenuRequirement Prefix(string label)
    {
        return new WindowsSmokeMenuRequirement(label, MatchPrefix: true);
    }
}

internal readonly record struct WindowsSmokeMenuRequirement(string DisplayName, bool MatchPrefix)
{
    public bool Matches(string label)
    {
        return MatchPrefix
            ? label.StartsWith(DisplayName, StringComparison.OrdinalIgnoreCase)
            : string.Equals(label, DisplayName, StringComparison.OrdinalIgnoreCase);
    }
}

internal sealed record RenderedMenuSnapshot(
    IReadOnlyList<string> TopLevelItems,
    IReadOnlyList<string> RepositoryMenuItems);
