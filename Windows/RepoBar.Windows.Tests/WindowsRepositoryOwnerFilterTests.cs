using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsRepositoryOwnerFilterTests
{
    [Fact]
    public void IsOnlyViewer_matches_single_owner_case_insensitively()
    {
        Assert.True(WindowsRepositoryOwnerFilter.IsOnlyViewer(["octocat"], "OctoCat"));
        Assert.False(WindowsRepositoryOwnerFilter.IsOnlyViewer(["octocat", "other"], "octocat"));
        Assert.False(WindowsRepositoryOwnerFilter.IsOnlyViewer(["octocat"], null));
    }

    [Fact]
    public void ToggleOnlyViewer_sets_or_clears_viewer_filter()
    {
        Assert.Equal(["octocat"], WindowsRepositoryOwnerFilter.ToggleOnlyViewer([], " octocat "));
        Assert.Empty(WindowsRepositoryOwnerFilter.ToggleOnlyViewer(["OCTOCAT"], "octocat"));
    }
}
