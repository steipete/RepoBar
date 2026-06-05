using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsLaunchAtLoginTests
{
    [Theory]
    [InlineData(@"C:\Tools\RepoBar\RepoBar.Windows.exe", @"""C:\Tools\RepoBar\RepoBar.Windows.exe""")]
    [InlineData(@"""C:\Tools\RepoBar\RepoBar.Windows.exe""", @"""C:\Tools\RepoBar\RepoBar.Windows.exe""")]
    public void Quote_wraps_executable_path_once(string path, string expected)
    {
        Assert.Equal(expected, WindowsLaunchAtLogin.Quote(path));
    }

    [Theory]
    [InlineData(null, null)]
    [InlineData("", null)]
    [InlineData(@"""C:\Tools\RepoBar\RepoBar.Windows.exe""", @"C:\Tools\RepoBar\RepoBar.Windows.exe")]
    public void Unquote_normalizes_registry_value(string? value, string? expected)
    {
        Assert.Equal(expected, WindowsLaunchAtLogin.Unquote(value));
    }

    [Fact]
    public void Registry_access_is_noop_off_windows()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var launcher = new WindowsLaunchAtLogin();

        launcher.SetEnabled(enabled: true, "/tmp/RepoBar.Windows.exe");

        Assert.False(launcher.IsEnabled("/tmp/RepoBar.Windows.exe"));
    }
}
