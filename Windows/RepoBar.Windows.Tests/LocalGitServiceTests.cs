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
}
