using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsUpdateDiagnosticsTests
{
    [Fact]
    public void ClipboardText_includes_update_location_and_runtime_signals()
    {
        var executablePath = Path.Combine(Path.GetTempPath(), "RepoBar", "RepoBar.Windows.exe");
        var diagnostics = WindowsUpdateDiagnostics.Capture(
            executablePath: executablePath,
            currentVersion: "0.7.1",
            canCheckForUpdates: true);

        var text = diagnostics.ClipboardText();

        Assert.Contains($"executable_path: {Path.GetFullPath(executablePath)}", text);
        Assert.Contains($"install_directory: {Path.GetDirectoryName(Path.GetFullPath(executablePath))}", text);
        Assert.Contains("current_version: 0.7.1", text);
        Assert.Contains("can_check_for_updates: True", text);
        Assert.Contains("latest_release_api: https://api.github.com/repos/steipete/RepoBar/releases/latest", text);
        Assert.Contains("windows_installer_asset_preference: matching architecture, then msi, exe, zip", text);
        Assert.False(string.IsNullOrWhiteSpace(diagnostics.OsDescription));
        Assert.False(string.IsNullOrWhiteSpace(diagnostics.ProcessArchitecture));
    }
}
