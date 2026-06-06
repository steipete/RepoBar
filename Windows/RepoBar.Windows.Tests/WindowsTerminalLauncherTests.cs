using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsTerminalLauncherTests
{
    [Fact]
    public void Candidates_auto_prefers_windows_terminal_then_powershell_then_command_prompt()
    {
        var candidates = WindowsTerminalLauncher.Candidates(@"C:\Projects\RepoBar", WindowsTerminalPreference.Auto);

        Assert.Equal(["wt.exe", "powershell.exe", "cmd.exe"], candidates.Select(candidate => candidate.FileName));
        Assert.Equal(@"-d ""C:\Projects\RepoBar""", candidates[0].Arguments);
        Assert.Equal(@"/K cd /d ""C:\Projects\RepoBar""", candidates[2].Arguments);
    }

    [Fact]
    public void Candidates_windows_terminal_falls_back_to_command_prompt()
    {
        var candidates = WindowsTerminalLauncher.Candidates(@"C:\Projects\RepoBar", WindowsTerminalPreference.WindowsTerminal);

        Assert.Equal(["wt.exe", "cmd.exe"], candidates.Select(candidate => candidate.FileName));
    }

    [Fact]
    public void Candidates_powershell_escapes_literal_path()
    {
        var candidates = WindowsTerminalLauncher.Candidates(@"C:\Projects\Owner's Repo", WindowsTerminalPreference.PowerShell);

        Assert.Single(candidates);
        Assert.Equal("powershell.exe", candidates[0].FileName);
        Assert.Equal(@"-NoExit -Command Set-Location -LiteralPath 'C:\Projects\Owner''s Repo'", candidates[0].Arguments);
    }
}
