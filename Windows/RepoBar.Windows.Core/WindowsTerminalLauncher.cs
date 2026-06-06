using System.Diagnostics;

namespace RepoBar.Windows;

internal static class WindowsTerminalLauncher
{
    public static IReadOnlyList<ProcessStartInfo> Candidates(string path, WindowsTerminalPreference preference)
    {
        return preference switch
        {
            WindowsTerminalPreference.WindowsTerminal => [WindowsTerminal(path), CommandPrompt(path)],
            WindowsTerminalPreference.PowerShell => [PowerShell(path)],
            WindowsTerminalPreference.CommandPrompt => [CommandPrompt(path)],
            _ => [WindowsTerminal(path), PowerShell(path), CommandPrompt(path)],
        };
    }

    private static ProcessStartInfo WindowsTerminal(string path)
    {
        return new ProcessStartInfo("wt.exe")
        {
            UseShellExecute = true,
            Arguments = $"-d \"{path}\"",
        };
    }

    private static ProcessStartInfo PowerShell(string path)
    {
        return new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = true,
            Arguments = $"-NoExit -Command Set-Location -LiteralPath '{EscapePowerShellLiteral(path)}'",
        };
    }

    private static ProcessStartInfo CommandPrompt(string path)
    {
        return new ProcessStartInfo("cmd.exe")
        {
            UseShellExecute = true,
            Arguments = $"/K cd /d \"{path}\"",
        };
    }

    private static string EscapePowerShellLiteral(string value)
    {
        return value.Replace("'", "''", StringComparison.Ordinal);
    }
}
