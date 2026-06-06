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

    [Fact]
    public void FindReferences_preserves_pasted_reference_order()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            1. zed/project PR #30
            2. see #4
            3. https://github.enterprise.test/acme/tools/issues/2
            4. alpha/repo issue #99
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("zed/project", 30), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("steipete/RepoBar", 4), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("acme/tools", 2), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("alpha/repo", 99), (reference.RepositoryFullName, reference.Number)));
    }

    [Fact]
    public void FindReferences_keeps_first_duplicate_in_pasted_order()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            owner/repo issue #9
            later duplicate https://github.com/owner/repo/issues/9
            owner/repo PR #10
            """,
            "github.com",
            null);

        Assert.Collection(
            references,
            reference =>
            {
                Assert.Equal("owner/repo", reference.RepositoryFullName);
                Assert.Equal(9, reference.Number);
                Assert.Equal("issues", reference.Kind);
                Assert.Equal("owner/repo issue #9", reference.RawText);
            },
            reference =>
            {
                Assert.Equal("owner/repo", reference.RepositoryFullName);
                Assert.Equal(10, reference.Number);
                Assert.Equal("pull", reference.Kind);
            });
    }

    [Fact]
    public void FindReferences_resolves_bare_pr_prose_lists_against_default_repository()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "Please check PR 123, 456 and 789 before release.",
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("steipete/RepoBar", 123, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 456, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 789, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_resolves_bare_issue_prose_lists_against_default_repository()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "Fix issue #12 and #13, then compare with #14.",
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("steipete/RepoBar", 12, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 13, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 14, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_does_not_duplicate_owner_repository_references_as_bare_prose()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            openclaw/openclaw PR #42
            PR #99
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/openclaw", 42, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 99, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_ignores_bare_prose_without_default_repository()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "PR 123 and issue #456",
            "github.com",
            null);

        Assert.Empty(references);
    }

    [Fact]
    public void FindReferences_ignores_plural_status_counts()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "State: main, clean. Open PRs: none. Open issues: 12.",
            "github.com",
            "steipete/RepoBar");

        Assert.Empty(references);
    }
}
