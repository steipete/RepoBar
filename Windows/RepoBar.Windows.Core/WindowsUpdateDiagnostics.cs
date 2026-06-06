using System.Runtime.InteropServices;

namespace RepoBar.Windows;

internal sealed record WindowsUpdateDiagnostics(
    string ExecutablePath,
    string InstallDirectory,
    string CurrentVersion,
    bool CanCheckForUpdates,
    string OsDescription,
    string ProcessArchitecture)
{
    public static WindowsUpdateDiagnostics Capture(
        string? executablePath = null,
        string? currentVersion = null,
        bool canCheckForUpdates = true)
    {
        var path = string.IsNullOrWhiteSpace(executablePath)
            ? Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "RepoBar.Windows.exe")
            : executablePath;

        return new WindowsUpdateDiagnostics(
            Path.GetFullPath(path),
            Path.GetDirectoryName(Path.GetFullPath(path)) ?? "",
            string.IsNullOrWhiteSpace(currentVersion) ? WindowsUpdateChecker.CurrentVersion() : currentVersion,
            canCheckForUpdates,
            RuntimeInformation.OSDescription,
            RuntimeInformation.ProcessArchitecture.ToString());
    }

    public string ClipboardText()
    {
        return string.Join(Environment.NewLine, [
            "RepoBar Windows update diagnostics",
            $"executable_path: {ExecutablePath}",
            $"install_directory: {InstallDirectory}",
            $"current_version: {CurrentVersion}",
            $"can_check_for_updates: {CanCheckForUpdates}",
            $"os_description: {OsDescription}",
            $"process_architecture: {ProcessArchitecture}",
            "latest_release_api: https://api.github.com/repos/steipete/RepoBar/releases/latest",
            "windows_installer_asset_preference: msi, exe, zip",
        ]);
    }
}
