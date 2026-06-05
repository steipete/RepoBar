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
}
