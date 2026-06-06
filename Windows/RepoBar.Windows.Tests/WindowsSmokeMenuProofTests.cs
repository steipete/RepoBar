using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsSmokeMenuProofTests
{
    [Fact]
    public void MissingMainMenuItems_accepts_dynamic_rendered_labels()
    {
        var missing = WindowsSmokeMenuProof.MissingMainMenuItems(
        [
            "Refresh now",
            "Repository scope: Local",
            "Repository sort: Activity",
            "My repositories: octocat",
            "Diagnostics",
            "Issue Navigator",
            "Account: Work",
            "Log out",
            "Preferences",
            "About RepoBar",
            "Check for updates",
            "Copy update diagnostics",
            "Open settings file",
            "Clear response cache",
            "Quit RepoBar",
        ]);

        Assert.Empty(missing);
    }

    [Fact]
    public void MissingRepositoryMenuItems_accepts_rendered_local_repository_menu()
    {
        var missing = WindowsSmokeMenuProof.MissingRepositoryMenuItems(
        [
            "Open repository",
            "Open issues",
            "Open pull requests",
            "Open Actions",
            "Open folder",
            "Open in terminal",
            "Branch: main",
            "Fetch",
            "Sync",
            "Rebase onto upstream",
            "Reset to upstream...",
            "Branches",
            "Worktrees",
            "Issues",
            "Pull Requests",
            "Releases",
            "CI Runs",
            "Tags",
            "Commits",
            "Contributors",
            "Activity",
            "Discussions",
            "CI: success",
            "Stars: 10  Forks: 2",
            "Default branch: main",
            "Unpin",
            "Set Visible",
            "Hide",
            "Move up",
            "Move down",
        ]);

        Assert.Empty(missing);
    }

    [Fact]
    public void MissingItems_reports_unrendered_required_items()
    {
        var missing = WindowsSmokeMenuProof.MissingMainMenuItems(["Refresh now"]);

        Assert.Contains("Diagnostics", missing);
        Assert.Contains("Copy update diagnostics", missing);
        Assert.Contains("Quit RepoBar", missing);
    }
}
