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
        using var context = new RepoBarTrayContext(settingsStore);
        Application.Run(context);
    }
}
