using System.Threading;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(initiallyOwned: true, "RepoBar.Windows.Tray", out var ownsMutex);
        if (!ownsMutex)
        {
            return;
        }

        ApplicationConfiguration.Initialize();

        var settingsStore = WindowsSettingsStore.LoadOrCreate();
        WindowsDiagnosticsLogger.Configure(
            settingsStore.Settings.LoggingVerbosity,
            settingsStore.Settings.FileLoggingEnabled);
        WindowsDiagnosticsLogger.Log(WindowsLogVerbosity.Info, "startup", "RepoBar.Windows starting");
        WindowsGitHubArchiveReader.CreateSmokeFixtureIfRequested(settingsStore.Settings);
        using var context = new RepoBarTrayContext(settingsStore);
        Application.Run(context);
    }
}
