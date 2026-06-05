using Microsoft.Win32;

namespace RepoBar.Windows;

internal sealed class WindowsLaunchAtLogin
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "RepoBar";

    public bool IsEnabled(string executablePath)
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        var value = key?.GetValue(ValueName) as string;
        return string.Equals(Unquote(value), executablePath, StringComparison.OrdinalIgnoreCase);
    }

    public void SetEnabled(bool enabled, string executablePath)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
        if (enabled)
        {
            key.SetValue(ValueName, Quote(executablePath), RegistryValueKind.String);
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }

    internal static string Quote(string path)
    {
        return $"\"{path.Trim('"')}\"";
    }

    internal static string? Unquote(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim().Trim('"');
    }
}
