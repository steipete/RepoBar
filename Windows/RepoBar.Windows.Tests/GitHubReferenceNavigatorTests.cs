using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class GitHubReferenceNavigatorTests
{
    [Fact]
    public void FindReferences_resolves_common_reference_shapes()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            https://github.com/steipete/RepoBar/pull/12
            openclaw/openclaw issue #34
            openclaw/openclaw PR #35
            see #56
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Equal(4, references.Count);
        Assert.Contains(references, reference => reference.RepositoryFullName == "steipete/RepoBar" && reference.Number == 12);
        Assert.Contains(references, reference => reference.RepositoryFullName == "openclaw/openclaw" && reference.Number == 34);
        Assert.Contains(references, reference => reference.RepositoryFullName == "openclaw/openclaw" && reference.Number == 35 && reference.Kind == "pull");
        Assert.Contains(references, reference => reference.RepositoryFullName == "steipete/RepoBar" && reference.Number == 56);
    }

    [Fact]
    public void BuildUri_preserves_pull_references()
    {
        var uri = GitHubReferenceNavigator.BuildUri(
            new GitHubReferenceMatch("owner/repo", 9, "pull", "owner/repo#9"),
            "github.example.com");

        Assert.Equal("https://github.example.com/owner/repo/pull/9", uri.ToString());
    }
}
