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

    [Fact]
    public void BuildUri_normalizes_enterprise_hosts()
    {
        var uri = GitHubReferenceNavigator.BuildUri(
            new GitHubReferenceMatch("owner/repo", 42, "issues", "owner/repo#42"),
            "https://GitHub.Enterprise.test/org");

        Assert.Equal("https://github.enterprise.test/owner/repo/issues/42", uri.ToString());
    }

    [Fact]
    public void Full_url_references_preserve_their_source_host()
    {
        var reference = Assert.Single(GitHubReferenceNavigator.FindReferences(
            "https://GitHub.Enterprise.test/owner/repo/pull/42",
            "github.com",
            null));

        Assert.Equal("github.enterprise.test", reference.Host);

        var uri = GitHubReferenceNavigator.BuildUri(reference, "github.com");

        Assert.Equal("https://github.enterprise.test/owner/repo/pull/42", uri.ToString());
    }

    [Fact]
    public void Bare_references_use_the_active_host()
    {
        var reference = Assert.Single(GitHubReferenceNavigator.FindReferences(
            "see #42",
            "github.enterprise.test",
            "owner/repo"));

        Assert.Null(reference.Host);

        var uri = GitHubReferenceNavigator.BuildUri(reference, "github.enterprise.test");

        Assert.Equal("https://github.enterprise.test/owner/repo/issues/42", uri.ToString());
    }

    [Fact]
    public void FindReferences_keeps_same_reference_number_on_different_hosts()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            https://github.com/owner/repo/issues/9
            https://github.enterprise.test/owner/repo/issues/9
            """,
            "github.com",
            null);

        Assert.Equal(2, references.Count);
        Assert.Contains(references, reference => reference.Host == "github.com");
        Assert.Contains(references, reference => reference.Host == "github.enterprise.test");
    }
}
