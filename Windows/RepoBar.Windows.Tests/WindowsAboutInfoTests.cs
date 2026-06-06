using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsAboutInfoTests
{
    [Fact]
    public void Current_includes_support_links_matching_about_surface()
    {
        var info = WindowsAboutInfo.Current();

        Assert.Equal("RepoBar Windows", info.AppName);
        Assert.False(string.IsNullOrWhiteSpace(info.Version));
        Assert.Contains("GitHub repository status", info.Description);
        Assert.Contains(info.Links, link => link is { Label: "GitHub", Url: "https://github.com/steipete/RepoBar" });
        Assert.Contains(info.Links, link => link is { Label: "Website", Url: "https://repobar.app" });
        Assert.Contains(info.Links, link => link is { Label: "Issue Tracker", Url: "https://github.com/steipete/RepoBar/issues" });
        Assert.Contains(info.Links, link => link is { Label: "Email", Url: "mailto:peter@steipete.me" });
    }
}
