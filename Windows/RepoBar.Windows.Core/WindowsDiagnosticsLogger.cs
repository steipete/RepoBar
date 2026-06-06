using System.Globalization;

namespace RepoBar.Windows;

internal static class WindowsDiagnosticsLogger
{
    private static readonly object Lock = new();
    private static WindowsLogVerbosity _verbosity = WindowsLogVerbosity.Info;
    private static bool _fileLoggingEnabled;
    private static string? _logFilePath;

    public static string DefaultLogFilePath()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "RepoBar",
            "Logs",
            "repobar.log");
    }

    public static string? LogFilePath
    {
        get
        {
            lock (Lock)
            {
                return _logFilePath;
            }
        }
    }

    public static void Configure(WindowsLogVerbosity verbosity, bool fileLoggingEnabled)
    {
        lock (Lock)
        {
            _verbosity = Enum.IsDefined(verbosity) ? verbosity : WindowsLogVerbosity.Info;
            _fileLoggingEnabled = fileLoggingEnabled;
            _logFilePath = fileLoggingEnabled ? DefaultLogFilePath() : null;

            if (_logFilePath != null)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_logFilePath)!);
            }
        }
    }

    public static void Log(WindowsLogVerbosity level, string category, string message)
    {
        string? path;
        lock (Lock)
        {
            if (!_fileLoggingEnabled || level > _verbosity)
            {
                return;
            }

            path = _logFilePath;
        }

        if (path == null)
        {
            return;
        }

        var timestamp = DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture);
        var line = $"[{timestamp}] [{level.ToString().ToLowerInvariant()}] [{category}] {message}{Environment.NewLine}";
        File.AppendAllText(path, line);
    }
}
