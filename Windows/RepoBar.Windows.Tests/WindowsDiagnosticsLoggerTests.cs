using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsDiagnosticsLoggerTests
{
    [Fact]
    public void Logger_writes_when_file_logging_is_enabled_and_level_allows()
    {
        var path = WindowsDiagnosticsLogger.DefaultLogFilePath();
        if (File.Exists(path))
        {
            File.Delete(path);
        }

        WindowsDiagnosticsLogger.Configure(WindowsLogVerbosity.Debug, fileLoggingEnabled: true);
        WindowsDiagnosticsLogger.Log(WindowsLogVerbosity.Debug, "test", "debug message");
        WindowsDiagnosticsLogger.Log(WindowsLogVerbosity.Trace, "test", "trace message");
        WindowsDiagnosticsLogger.Configure(WindowsLogVerbosity.Info, fileLoggingEnabled: false);

        var text = File.ReadAllText(path);
        Assert.Contains("[debug] [test] debug message", text);
        Assert.DoesNotContain("trace message", text);
    }
}
