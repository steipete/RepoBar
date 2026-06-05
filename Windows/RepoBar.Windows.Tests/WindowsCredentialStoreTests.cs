using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsCredentialStoreTests
{
    [Theory]
    [InlineData("github.com", "RepoBar.Windows:github.com")]
    [InlineData("GitHub.EXAMPLE.com", "RepoBar.Windows:github.example.com")]
    [InlineData("https://github.example.com", "RepoBar.Windows:github.example.com")]
    public void BuildTargetName_normalizes_host(string host, string expected)
    {
        Assert.Equal(expected, WindowsCredentialStore.BuildTargetName(host));
    }

    [Fact]
    public void ReadToken_returns_null_off_windows()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        Assert.Null(new WindowsCredentialStore("github.com").ReadToken());
    }

    [Theory]
    [InlineData(null, "github.com")]
    [InlineData("", "github.com")]
    [InlineData("GitHub.EXAMPLE.com/", "github.example.com")]
    [InlineData("https://github.example.com/org/repo", "github.example.com")]
    public void Normalize_host_accepts_urls_and_plain_hosts(string? host, string expected)
    {
        Assert.Equal(expected, GitHubHost.Normalize(host));
    }
}
