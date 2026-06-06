using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class LocalGitServiceTests
{
    [Theory]
    [InlineData("https://github.com/steipete/RepoBar.git", "steipete/RepoBar")]
    [InlineData("https://github.com/steipete/RepoBar", "steipete/RepoBar")]
    [InlineData("git@github.com:steipete/RepoBar.git", "steipete/RepoBar")]
    [InlineData("ssh://git@github.com/steipete/RepoBar.git", "steipete/RepoBar")]
    [InlineData("https://github.example.com/org/repo.git", "org/repo")]
    public void TryParseGitHubFullName_normalizes_common_remote_shapes(string remote, string expected)
    {
        Assert.Equal(expected, LocalGitService.TryParseGitHubFullName(remote));
    }

    [Theory]
    [InlineData("https://github.com/steipete/RepoBar.git", "github.com", "steipete/RepoBar")]
    [InlineData("git@github.enterprise.test:owner/repo.git", "github.enterprise.test", "owner/repo")]
    [InlineData("ssh://git@GitHub.Example.com/owner/repo.git", "github.example.com", "owner/repo")]
    public void TryParseGitHubRemote_preserves_remote_host(string remote, string expectedHost, string expectedFullName)
    {
        var parsed = LocalGitService.TryParseGitHubRemote(remote) ??
            throw new InvalidOperationException("Expected remote to parse.");

        Assert.Equal(expectedHost, parsed.Host);
        Assert.Equal(expectedFullName, parsed.FullName);
    }

    [Fact]
    public void DiscoverRepositoryRoots_detects_git_directories_and_worktree_files()
    {
        var root = Path.Combine(Path.GetTempPath(), $"repobar-localgit-{Guid.NewGuid():N}");
        try
        {
            var normalRepo = Path.Combine(root, "normal");
            var worktreeRepo = Path.Combine(root, "nested", "worktree");
            var ignoredRepo = Path.Combine(root, "node_modules", "package");
            Directory.CreateDirectory(Path.Combine(normalRepo, ".git"));
            Directory.CreateDirectory(worktreeRepo);
            Directory.CreateDirectory(Path.Combine(ignoredRepo, ".git"));
            File.WriteAllText(Path.Combine(worktreeRepo, ".git"), "gitdir: ../.git/worktrees/worktree");

            var roots = LocalGitService.DiscoverRepositoryRoots(root, maxDepth: 3);

            Assert.Contains(normalRepo, roots);
            Assert.Contains(worktreeRepo, roots);
            Assert.DoesNotContain(ignoredRepo, roots);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void ScanSummary_reports_missing_empty_and_found_roots()
    {
        var root = Path.Combine(Path.GetTempPath(), $"repobar-localgit-{Guid.NewGuid():N}");
        var missing = Path.Combine(root, "missing");
        try
        {
            Assert.Equal("Choose a local projects folder.", LocalGitService.ScanSummary("", 2).DisplayText);
            Assert.Equal("Folder not found.", LocalGitService.ScanSummary(missing, 2).DisplayText);

            Directory.CreateDirectory(root);
            Assert.Equal("No repositories found.", LocalGitService.ScanSummary(root, 2).DisplayText);

            Directory.CreateDirectory(Path.Combine(root, "one", ".git"));
            Directory.CreateDirectory(Path.Combine(root, "two", ".git"));
            Assert.Equal("Found 2 local repositories.", LocalGitService.ScanSummary(root, 2).DisplayText);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void ParseWorktrees_reads_porcelain_output()
    {
        var worktrees = LocalGitService.ParseWorktrees("""
            worktree C:/Projects/repo
            HEAD abc123
            branch refs/heads/main

            worktree C:/Projects/repo/.work/feature
            HEAD def456
            branch refs/heads/feature

            """);

        Assert.Equal(2, worktrees.Count);
        Assert.Equal("C:/Projects/repo", worktrees[0].Path);
        Assert.Equal("main", worktrees[0].Branch);
        Assert.Equal("feature", worktrees[1].Branch);
    }

    [Fact]
    public void ParseBranches_marks_current_branch_and_sorts_it_first()
    {
        var branches = LocalGitService.ParseBranches("""
            feature/login
            main
            feature/login
            release

            """, "main");

        Assert.Equal(3, branches.Count);
        Assert.Equal("main", branches[0].Name);
        Assert.True(branches[0].IsCurrent);
        Assert.Equal("feature/login", branches[1].Name);
        Assert.False(branches[1].IsCurrent);
        Assert.Equal("release", branches[2].Name);
    }

    [Fact]
    public void CheckoutDestination_expands_root_and_sanitizes_repository_name()
    {
        var root = Path.Combine(Path.GetTempPath(), "RepoBar Projects");
        var destination = LocalGitService.CheckoutDestination(root, "Repo/Bar");

        Assert.Equal(Path.Combine(root, "Repo_Bar"), destination);
    }

    [Fact]
    public void WorktreeDestination_uses_configured_folder_and_sanitizes_branch_name()
    {
        var repoRoot = Path.Combine(Path.GetTempPath(), "repo");
        var destination = LocalGitService.WorktreeDestination(repoRoot, ".worktrees", "feature/menu cards");

        Assert.Equal(Path.Combine(repoRoot, ".worktrees", "feature_menu cards"), destination);
    }

    [Fact]
    public void ShouldFetchBeforeStatus_respects_enabled_state_and_interval()
    {
        var service = new LocalGitService();
        var repoRoot = Path.Combine(Path.GetTempPath(), "repo");
        var now = DateTimeOffset.Parse("2026-06-06T12:00:00Z");
        var settings = new WindowsSettings
        {
            FetchLocalProjectsBeforeStatus = true,
            LocalProjectsFetchIntervalMinutes = 5,
        };

        Assert.True(service.ShouldFetchBeforeStatus(repoRoot, settings, now));

        service.RecordFetch(repoRoot, now);

        Assert.False(service.ShouldFetchBeforeStatus(repoRoot, settings, now.AddMinutes(4)));
        Assert.True(service.ShouldFetchBeforeStatus(repoRoot, settings, now.AddMinutes(5)));
        Assert.False(service.ShouldFetchBeforeStatus(
            repoRoot,
            SettingsWithFetchBeforeStatus(enabled: false),
            now.AddMinutes(30)));
    }

    [Fact]
    public void Local_status_can_fast_forward_only_when_clean_and_behind()
    {
        var cleanBehind = new LocalGitRepositoryStatus(
            Path: "repo",
            Name: "repo",
            FullName: "owner/repo",
            Branch: "main",
            IsClean: true,
            AheadCount: 0,
            BehindCount: 2,
            SyncState: LocalSyncState.Behind,
            DirtyCounts: LocalDirtyCounts.Empty,
            DirtyFiles: [],
            WorktreeName: null,
            UpstreamBranch: "origin/main");
        var dirtyBehind = cleanBehind with
        {
            IsClean = false,
            SyncState = LocalSyncState.Dirty,
            DirtyCounts = new LocalDirtyCounts(0, 1, 0),
        };

        Assert.True(cleanBehind.CanFastForward);
        Assert.False(dirtyBehind.CanFastForward);
    }

    [Fact]
    public void Local_status_exposes_safe_sync_rebase_and_reset_capabilities()
    {
        var cleanBehind = new LocalGitRepositoryStatus(
            Path: "repo",
            Name: "repo",
            FullName: "owner/repo",
            Branch: "main",
            IsClean: true,
            AheadCount: 0,
            BehindCount: 2,
            SyncState: LocalSyncState.Behind,
            DirtyCounts: LocalDirtyCounts.Empty,
            DirtyFiles: [],
            WorktreeName: null,
            UpstreamBranch: "origin/main");
        var cleanAhead = cleanBehind with
        {
            AheadCount = 1,
            BehindCount = 0,
            SyncState = LocalSyncState.Ahead,
        };
        var dirtyBehind = cleanBehind with
        {
            IsClean = false,
            SyncState = LocalSyncState.Dirty,
            DirtyCounts = new LocalDirtyCounts(0, 1, 0),
        };
        var noUpstream = cleanBehind with { UpstreamBranch = null };

        Assert.True(cleanBehind.CanSync);
        Assert.True(cleanBehind.CanRebase);
        Assert.True(cleanBehind.CanResetToUpstream);
        Assert.True(cleanAhead.CanSync);
        Assert.False(cleanAhead.CanRebase);
        Assert.True(cleanAhead.CanResetToUpstream);
        Assert.False(dirtyBehind.CanSync);
        Assert.False(dirtyBehind.CanRebase);
        Assert.True(dirtyBehind.CanResetToUpstream);
        Assert.False(noUpstream.CanSync);
        Assert.False(noUpstream.CanRebase);
        Assert.False(noUpstream.CanResetToUpstream);
    }

    [Fact]
    public void Local_status_dirty_files_menu_respects_visibility_setting_and_caps_list()
    {
        var status = new LocalGitRepositoryStatus(
            Path: "repo",
            Name: "repo",
            FullName: "owner/repo",
            Branch: "main",
            IsClean: false,
            AheadCount: 0,
            BehindCount: 0,
            SyncState: LocalSyncState.Dirty,
            DirtyCounts: new LocalDirtyCounts(0, 4, 0),
            DirtyFiles: ["one.cs", "two.cs", "three.cs", "four.cs"],
            WorktreeName: null,
            UpstreamBranch: "origin/main");

        Assert.Equal(["one.cs", "two.cs", "three.cs"], status.DirtyFilesForMenu(new WindowsSettings()));
        Assert.Empty(status.DirtyFilesForMenu(new WindowsSettings { ShowDirtyFilesInMenu = false }));
    }

    [Fact]
    public void Local_index_exposes_auto_synced_repositories_for_notifications()
    {
        var synced = LocalStatus("owner/synced", LocalSyncState.Synced);
        var other = LocalStatus("owner/other", LocalSyncState.Synced);
        var index = new LocalGitIndex([synced, other], [synced]);

        Assert.Equal([synced], index.AutoSyncedRepositories);
        Assert.Equal(synced, index.Find(new RepositoryRef { Owner = "owner", Name = "synced" }));
    }

    [Fact]
    public void Local_index_matches_repositories_by_active_host_when_remote_host_is_known()
    {
        var github = LocalStatus("owner/repo", LocalSyncState.Synced, "github.com");
        var enterprise = LocalStatus("owner/repo", LocalSyncState.Synced, "github.enterprise.test");

        var index = new LocalGitIndex([github, enterprise], [], "github.enterprise.test");

        Assert.Equal(enterprise, index.Find(new RepositoryRef { Owner = "owner", Name = "repo" }));
    }

    [Fact]
    public void Local_index_does_not_cross_match_known_remote_hosts()
    {
        var github = LocalStatus("owner/repo", LocalSyncState.Synced, "github.com");
        var index = new LocalGitIndex([github], [], "github.enterprise.test");

        Assert.Null(index.Find(new RepositoryRef { Owner = "owner", Name = "repo" }));
    }

    [Fact]
    public void Local_sync_notification_formats_single_and_multiple_repositories()
    {
        var one = LocalStatus("owner/one", LocalSyncState.Synced);
        var two = LocalStatus("owner/two", LocalSyncState.Synced);

        Assert.Equal("Synced owner/one (main)", LocalGitSyncNotification.Body([one]));
        Assert.Equal("Synced 2 local repositories.", LocalGitSyncNotification.Body([one, two]));
        Assert.Equal("", LocalGitSyncNotification.Body([]));
    }

    private static WindowsSettings SettingsWithFetchBeforeStatus(bool enabled)
    {
        return new WindowsSettings
        {
            FetchLocalProjectsBeforeStatus = enabled,
            LocalProjectsFetchIntervalMinutes = 5,
        };
    }

    private static LocalGitRepositoryStatus LocalStatus(string fullName, LocalSyncState syncState, string? gitHubHost = null)
    {
        var name = fullName.Split('/')[1];
        return new LocalGitRepositoryStatus(
            Path: Path.Combine(Path.GetTempPath(), name),
            Name: name,
            FullName: fullName,
            Branch: "main",
            IsClean: syncState != LocalSyncState.Dirty,
            AheadCount: syncState == LocalSyncState.Ahead ? 1 : 0,
            BehindCount: syncState == LocalSyncState.Behind ? 1 : 0,
            SyncState: syncState,
            DirtyCounts: LocalDirtyCounts.Empty,
            DirtyFiles: [],
            WorktreeName: null,
            UpstreamBranch: "origin/main",
            GitHubHost: gitHubHost);
    }
}
