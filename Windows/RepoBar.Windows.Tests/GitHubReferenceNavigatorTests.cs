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
        Assert.Contains(references, reference => reference.RepositoryFullName == "steipete/RepoBar" && reference.Number == 12L);
        Assert.Contains(references, reference => reference.RepositoryFullName == "openclaw/openclaw" && reference.Number == 34L);
        Assert.Contains(references, reference => reference.RepositoryFullName == "openclaw/openclaw" && reference.Number == 35L && reference.Kind == "pull");
        Assert.Contains(references, reference => reference.RepositoryFullName == "steipete/RepoBar" && reference.Number == 56L);
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
    public void BuildUri_preserves_commit_references()
    {
        var uri = GitHubReferenceNavigator.BuildUri(
            new GitHubReferenceMatch("owner/repo", 0, "commit", "owner/repo@ffd212ca43", Identifier: "ffd212ca43"),
            "github.example.com");

        Assert.Equal("https://github.example.com/owner/repo/commit/ffd212ca43", uri.ToString());
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
    public void Workflow_run_url_references_preserve_source_host_and_kind()
    {
        var reference = Assert.Single(GitHubReferenceNavigator.FindReferences(
            "https://GitHub.Enterprise.test/owner/repo/actions/runs/25620622163",
            "github.com",
            null));

        Assert.Equal("github.enterprise.test", reference.Host);
        Assert.Equal("owner/repo", reference.RepositoryFullName);
        Assert.Equal(25620622163L, reference.Number);
        Assert.Equal("actions", reference.Kind);

        var uri = GitHubReferenceNavigator.BuildUri(reference, "github.com");

        Assert.Equal("https://github.enterprise.test/owner/repo/actions/runs/25620622163", uri.ToString());
    }

    [Fact]
    public void Commit_url_references_preserve_source_host_hash_and_kind()
    {
        var reference = Assert.Single(GitHubReferenceNavigator.FindReferences(
            "https://GitHub.Enterprise.test/owner/repo/commit/FfD212Ca43abcdef",
            "github.com",
            null));

        Assert.Equal("github.enterprise.test", reference.Host);
        Assert.Equal("owner/repo", reference.RepositoryFullName);
        Assert.Equal("ffd212ca43abcdef", reference.ReferenceValue);
        Assert.Equal("commit", reference.Kind);
        Assert.Equal("owner/repo @ffd212ca43", reference.DisplayText);

        var uri = GitHubReferenceNavigator.BuildUri(reference, "github.com");

        Assert.Equal("https://github.enterprise.test/owner/repo/commit/ffd212ca43abcdef", uri.ToString());
    }

    [Fact]
    public void Pull_request_changes_urls_resolve_to_commit_references()
    {
        var reference = Assert.Single(GitHubReferenceNavigator.FindReferences(
            "https://github.com/openclaw/openclaw/pull/57843/changes/d04517cefff3af339f560a8e388cacc3898e6562",
            "github.com",
            null));

        Assert.Equal("openclaw/openclaw", reference.RepositoryFullName);
        Assert.Equal("d04517cefff3af339f560a8e388cacc3898e6562", reference.ReferenceValue);
        Assert.Equal("commit", reference.Kind);
    }

    [Fact]
    public void Workflow_run_references_do_not_dedupe_issue_references_with_same_number()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            https://github.com/owner/repo/actions/runs/42
            https://github.com/owner/repo/issues/42
            """,
            "github.com",
            null);

        Assert.Collection(
            references,
            reference => Assert.Equal(("owner/repo", 42L, "actions"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("owner/repo", 42L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
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
    public void FindReferences_resolves_direct_issue_number_against_default_repository()
    {
        var reference = Assert.Single(GitHubReferenceNavigator.FindReferences(
            "73655",
            "github.com",
            "steipete/RepoBar"));

        Assert.Equal("steipete/RepoBar", reference.RepositoryFullName);
        Assert.Equal(73655L, reference.Number);
        Assert.Equal("issues", reference.Kind);
    }

    [Theory]
    [InlineData("gh-42")]
    [InlineData("GH-42")]
    [InlineData("#42")]
    public void FindReferences_resolves_gh_prefixed_issue_number_against_default_repository(string input)
    {
        var reference = Assert.Single(GitHubReferenceNavigator.FindReferences(
            input,
            "github.com",
            "steipete/RepoBar"));

        Assert.Equal("steipete/RepoBar", reference.RepositoryFullName);
        Assert.Equal(42L, reference.Number);
        Assert.Equal("issues", reference.Kind);
    }

    [Theory]
    [InlineData("ffd212ca43")]
    [InlineData("4992546")]
    [InlineData("commit d04517cefff3af339f560a8e388cacc3898e6562")]
    [InlineData(" - bare short SHA: 4992546")]
    public void FindReferences_resolves_commit_hashes_against_default_repository(string input)
    {
        var reference = Assert.Single(GitHubReferenceNavigator.FindReferences(
            input,
            "github.com",
            "steipete/RepoBar"));

        Assert.Equal("steipete/RepoBar", reference.RepositoryFullName);
        Assert.Equal("commit", reference.Kind);
        Assert.Matches("^[0-9a-f]{7,40}$", reference.ReferenceValue);
        Assert.Equal($"https://github.com/steipete/RepoBar/commit/{reference.ReferenceValue}", GitHubReferenceNavigator.BuildUri(reference, "github.com").ToString());
    }

    [Fact]
    public void FindReferences_keeps_hashes_with_shared_display_prefix_distinct()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "commits abcdef1234000000000000000000000000000000 abcdef1234ffffffffffffffffffffffffffffff",
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal("abcdef1234000000000000000000000000000000", reference.ReferenceValue),
            reference => Assert.Equal("abcdef1234ffffffffffffffffffffffffffffff", reference.ReferenceValue));
    }

    [Fact]
    public void FindReferences_does_not_resolve_commit_hashes_without_default_repository()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "commit ffd212ca43",
            "github.com",
            null);

        Assert.Empty(references);
    }

    [Fact]
    public void FindReferences_ignores_short_hex_words_as_commit_hashes()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "commit abcdef",
            "github.com",
            "steipete/RepoBar");

        Assert.Empty(references);
    }

    [Fact]
    public void FindReferences_does_not_resolve_direct_issue_number_without_default_repository()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "73655",
            "github.com",
            null);

        Assert.Empty(references);
    }

    [Fact]
    public void FindReferences_does_not_resolve_incidental_sentence_numbers()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "released in 2026 with 2 commits",
            "github.com",
            "steipete/RepoBar");

        Assert.Empty(references);
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
            reference => Assert.Equal(("zed/project", 30L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("steipete/RepoBar", 4L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("acme/tools", 2L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("alpha/repo", 99L), (reference.RepositoryFullName, reference.Number)));
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
                Assert.Equal(9L, reference.Number);
                Assert.Equal("issues", reference.Kind);
                Assert.Equal("owner/repo issue #9", reference.RawText);
            },
            reference =>
            {
                Assert.Equal("owner/repo", reference.RepositoryFullName);
                Assert.Equal(10L, reference.Number);
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
            reference => Assert.Equal(("steipete/RepoBar", 123L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 456L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 789L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_resolves_plural_pr_prose_lists_against_default_repository()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "please review PRs 123 and 456 before release",
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("steipete/RepoBar", 123L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 456L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_resolves_plural_pull_request_prose_lists_against_default_repository()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "please review pull requests 123 and 456",
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("steipete/RepoBar", 123L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 456L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_resolves_chained_owner_repository_references()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "make - openclaw/crabbox#70/#71: work",
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/crabbox", 70L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("openclaw/crabbox", 71L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_resolves_ranged_owner_repository_references()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "also make openclaw/crabbox#66-#69 work",
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/crabbox", 66L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("openclaw/crabbox", 67L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("openclaw/crabbox", 68L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("openclaw/crabbox", 69L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_resolves_ranged_owner_repository_references_without_second_hash()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "openclaw/crabbox#66-69",
            "github.com",
            null);

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/crabbox", 66L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/crabbox", 67L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/crabbox", 68L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/crabbox", 69L), (reference.RepositoryFullName, reference.Number)));
    }

    [Fact]
    public void FindReferences_preserves_pull_kind_for_owner_repository_series()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "openclaw/crabbox PR #7-#8",
            "github.com",
            null);

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/crabbox", 7L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("openclaw/crabbox", 8L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_resolves_grouped_repository_issue_lists()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "openclaw/discrawl: #61, #62 and #63",
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/discrawl", 61L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/discrawl", 62L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/discrawl", 63L), (reference.RepositoryFullName, reference.Number)));
    }

    [Fact]
    public void FindReferences_resolves_repository_heading_child_references()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 1 issue / 1 PR
              #18 closes #17, 24 additions / 1 deletion.
            - openclaw/clawdex: 0 issues / 1 PR
              #1 removes the default personal backup remote.
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/Tachikoma", 18L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/Tachikoma", 17L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/clawdex", 1L), (reference.RepositoryFullName, reference.Number)));
    }

    [Fact]
    public void FindReferences_resolves_numbered_repository_heading_after_nested_count_summary()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
              1. steipete/birdclaw
                  - 0 issues / 1 PR
                  - PR #44: clean, one green GitGuardian check
              2. openclaw/wacli
                  - 1 issue / 1 PR
                  - PR #267: CI green
                  - issue #268 needs product decision
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("steipete/birdclaw", 44L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("openclaw/wacli", 267L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("openclaw/wacli", 268L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_keeps_numbered_repository_heading_sibling_contexts_separate()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
              1. steipete/birdclaw
                  - 0 issues / 1 PR
                  - PR #44
              2. openclaw/clawsweeper-state
                  - 0 issues / 1 PR
                  - PR #3
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("steipete/birdclaw", 44L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/clawsweeper-state", 3L), (reference.RepositoryFullName, reference.Number)));
    }

    [Fact]
    public void FindReferences_clears_pending_repository_only_heading_for_normal_headings()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            1. old/repo
            2. new/repo: 0 issues / 1 PR
               - 0 issues / 1 PR
               - PR #3
            """,
            "github.com",
            "steipete/RepoBar");

        var reference = Assert.Single(references);
        Assert.Equal("new/repo", reference.RepositoryFullName);
        Assert.Equal(3L, reference.Number);
    }

    [Fact]
    public void FindReferences_resolves_repository_heading_child_commit_hashes()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 0 issues / 1 PR
              commit 4992546
            """,
            "github.com",
            "steipete/RepoBar");

        var reference = Assert.Single(references);
        Assert.Equal("openclaw/Tachikoma", reference.RepositoryFullName);
        Assert.Equal("commit", reference.Kind);
        Assert.Equal("4992546", reference.ReferenceValue);
    }

    [Fact]
    public void FindReferences_carries_repository_heading_commit_context_across_child_lines()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 0 issues / 1 PR
              commit:
              4992546
            """,
            "github.com",
            "steipete/RepoBar");

        var reference = Assert.Single(references);
        Assert.Equal("openclaw/Tachikoma", reference.RepositoryFullName);
        Assert.Equal("commit", reference.Kind);
        Assert.Equal("4992546", reference.ReferenceValue);
    }

    [Fact]
    public void FindReferences_does_not_parse_heading_child_hex_words_without_commit_context()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 1 issue / 1 PR
              #18 defaced parser.
            """,
            "github.com",
            "steipete/RepoBar");

        var reference = Assert.Single(references);
        Assert.Equal("openclaw/Tachikoma", reference.RepositoryFullName);
        Assert.Equal(18L, reference.Number);
        Assert.Equal("issues", reference.Kind);
    }

    [Fact]
    public void FindReferences_resolves_repository_heading_child_compound_bare_shorthand()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 2 issues / 1 PR
              - #61/#62 fixes both.
              - #64-#65 fixes series.
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/Tachikoma", 61L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/Tachikoma", 62L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/Tachikoma", 64L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/Tachikoma", 65L), (reference.RepositoryFullName, reference.Number)));
    }

    [Fact]
    public void FindReferences_resolves_repository_heading_child_kinded_prose_references()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 2 issues / 1 PR
              #18 also fixes PR 19 and 20.
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/Tachikoma", 18L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("openclaw/Tachikoma", 19L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("openclaw/Tachikoma", 20L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_carries_repository_heading_issue_context_across_child_lines()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 2 issues / 1 PR
              PR #18.
              This is 19.
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("openclaw/Tachikoma", 18L), (reference.RepositoryFullName, reference.Number)),
            reference => Assert.Equal(("openclaw/Tachikoma", 19L), (reference.RepositoryFullName, reference.Number)));
    }

    [Fact]
    public void FindReferences_carries_repository_heading_issue_context_from_final_sentence_only()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 2 issues / 1 PR
              PR #18. Done.
              This is 19.
            """,
            "github.com",
            "steipete/RepoBar");

        var reference = Assert.Single(references);
        Assert.Equal("openclaw/Tachikoma", reference.RepositoryFullName);
        Assert.Equal(18L, reference.Number);
    }

    [Fact]
    public void FindReferences_does_not_carry_repository_heading_issue_count_summaries()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 1 issue / 1 PR
              Open issues: 1
              This is 2.
            """,
            "github.com",
            "steipete/RepoBar");

        Assert.Empty(references);
    }

    [Fact]
    public void FindReferences_stops_repository_heading_context_at_unindented_lines()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            """
            - openclaw/Tachikoma: 1 issue / 1 PR
            #18 should use the selected repository outside the indented block.
            """,
            "github.com",
            "steipete/RepoBar");

        var reference = Assert.Single(references);
        Assert.Equal("steipete/RepoBar", reference.RepositoryFullName);
        Assert.Equal(18L, reference.Number);
    }

    [Fact]
    public void FindReferences_resolves_unique_repository_name_shorthand()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "discrawl#64 should open the matching known repository.",
            "github.com",
            "steipete/RepoBar",
            ["openclaw/discrawl", "steipete/RepoBar"]);

        var reference = Assert.Single(references);
        Assert.Equal("openclaw/discrawl", reference.RepositoryFullName);
        Assert.Equal(64L, reference.Number);
        Assert.Equal("issues", reference.Kind);
    }

    [Fact]
    public void FindReferences_resolves_default_repository_name_shorthand()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "RepoBar#66",
            "github.com",
            "steipete/RepoBar");

        var reference = Assert.Single(references);
        Assert.Equal("steipete/RepoBar", reference.RepositoryFullName);
        Assert.Equal(66L, reference.Number);
    }

    [Fact]
    public void FindReferences_ignores_ambiguous_repository_name_shorthand()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "tools#64 should not fall back to the default repository.",
            "github.com",
            "steipete/RepoBar",
            ["openclaw/tools", "steipete/tools", "steipete/RepoBar"]);

        Assert.Empty(references);
    }

    [Fact]
    public void FindReferences_ignores_unknown_repository_name_shorthand()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "missing#64 should not fall back to the default repository.",
            "github.com",
            "steipete/RepoBar",
            ["steipete/RepoBar"]);

        Assert.Empty(references);
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
            reference => Assert.Equal(("steipete/RepoBar", 12L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 13L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 14L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
    }

    [Fact]
    public void FindReferences_resolves_plural_issue_prose_lists_against_default_repository()
    {
        var references = GitHubReferenceNavigator.FindReferences(
            "closed issues 12 and 13 delete stale state",
            "github.com",
            "steipete/RepoBar");

        Assert.Collection(
            references,
            reference => Assert.Equal(("steipete/RepoBar", 12L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 13L, "issues"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
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
            reference => Assert.Equal(("openclaw/openclaw", 42L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)),
            reference => Assert.Equal(("steipete/RepoBar", 99L, "pull"), (reference.RepositoryFullName, reference.Number, reference.Kind)));
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
