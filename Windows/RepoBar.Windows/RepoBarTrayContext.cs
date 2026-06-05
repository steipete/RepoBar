using System.Diagnostics;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class RepoBarTrayContext : ApplicationContext
{
    private readonly WindowsSettingsStore _settingsStore;
    private readonly GitHubRepositoryClient _githubClient;
    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _menu = new();
    private readonly System.Windows.Forms.Timer _refreshTimer = new();
    private readonly CancellationTokenSource _shutdown = new();
    private IReadOnlyList<RepositoryStatus> _statuses = [];
    private bool _isRefreshing;
    private string? _lastError;

    public RepoBarTrayContext(WindowsSettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
        _githubClient = new GitHubRepositoryClient(settingsStore.Settings, settingsStore.ResolveToken());
        _notifyIcon = new NotifyIcon
        {
            Icon = TrayIconFactory.Create(TrayHealth.Unknown),
            Text = "RepoBar",
            ContextMenuStrip = _menu,
            Visible = true,
        };

        _notifyIcon.MouseUp += OnNotifyIconMouseUp;

        _refreshTimer.Interval = Math.Clamp(settingsStore.Settings.RefreshIntervalMinutes, 1, 60) * 60 * 1000;
        _refreshTimer.Tick += (_, _) => BeginRefresh();
        _refreshTimer.Start();

        BuildMenu();
        BeginRefresh();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _shutdown.Cancel();
            _refreshTimer.Stop();
            _refreshTimer.Dispose();
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _githubClient.Dispose();
            _shutdown.Dispose();
            _menu.Dispose();
        }

        base.Dispose(disposing);
    }

    private void BeginRefresh()
    {
        if (_isRefreshing)
        {
            return;
        }

        _ = RefreshAsync();
    }

    private async Task RefreshAsync()
    {
        _isRefreshing = true;
        _lastError = null;
        BuildMenu();

        try
        {
            _statuses = await _githubClient.LoadRepositoriesAsync(
                _settingsStore.Settings.Repositories,
                _shutdown.Token);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            _lastError = exception.Message;
        }
        finally
        {
            _isRefreshing = false;
            if (!_shutdown.IsCancellationRequested)
            {
                UpdateTrayIcon();
                BuildMenu();
            }
        }
    }

    private void BuildMenu()
    {
        _menu.Items.Clear();
        _menu.Items.Add(new ToolStripMenuItem(BuildHeaderText()) { Enabled = false });
        _menu.Items.Add(new ToolStripSeparator());

        if (_settingsStore.Settings.Repositories.Count == 0)
        {
            _menu.Items.Add(new ToolStripMenuItem("No repositories configured") { Enabled = false });
            _menu.Items.Add(new ToolStripMenuItem("Open settings file", null, (_, _) => OpenFile(_settingsStore.SettingsPath)));
            _menu.Items.Add(new ToolStripMenuItem("Open Windows setup doc", null, (_, _) => OpenUrl("https://github.com/steipete/RepoBar/blob/main/docs/windows.md")));
        }
        else if (_statuses.Count == 0)
        {
            foreach (var repository in _settingsStore.Settings.Repositories)
            {
                _menu.Items.Add(new ToolStripMenuItem($"[ ] {repository.FullName}") { Enabled = false });
            }
        }
        else
        {
            foreach (var status in _statuses)
            {
                _menu.Items.Add(BuildRepositoryMenu(status));
            }
        }

        if (!string.IsNullOrWhiteSpace(_lastError))
        {
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(new ToolStripMenuItem($"Error: {_lastError}") { Enabled = false });
        }

        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(new ToolStripMenuItem(_isRefreshing ? "Refreshing..." : "Refresh now", null, (_, _) => BeginRefresh()) { Enabled = !_isRefreshing });
        _menu.Items.Add(new ToolStripMenuItem("Open settings file", null, (_, _) => OpenFile(_settingsStore.SettingsPath)));
        _menu.Items.Add(new ToolStripMenuItem("Quit RepoBar", null, (_, _) => ExitThread()));
    }

    private ToolStripMenuItem BuildRepositoryMenu(RepositoryStatus status)
    {
        var label = $"{HealthPrefix(status.Health)} {status.Repository.FullName}  {status.IssueCount} issues  {status.PullRequestCount} PRs";
        var item = new ToolStripMenuItem(label);

        if (status.ErrorMessage != null)
        {
            item.DropDownItems.Add(new ToolStripMenuItem(status.ErrorMessage) { Enabled = false });
            item.DropDownItems.Add(new ToolStripMenuItem("Open repository", null, (_, _) => OpenRepository(status.Repository)));
            return item;
        }

        item.DropDownItems.Add(new ToolStripMenuItem("Open repository", null, (_, _) => OpenRepository(status.Repository)));
        item.DropDownItems.Add(new ToolStripMenuItem("Open issues", null, (_, _) => OpenRepository(status.Repository, "issues")));
        item.DropDownItems.Add(new ToolStripMenuItem("Open pull requests", null, (_, _) => OpenRepository(status.Repository, "pulls")));
        item.DropDownItems.Add(new ToolStripMenuItem("Open Actions", null, (_, _) => OpenRepository(status.Repository, "actions")));

        if (status.LatestRelease is { Url: { Length: > 0 } releaseUrl })
        {
            item.DropDownItems.Add(new ToolStripMenuItem($"Latest release: {status.LatestRelease.TagName}", null, (_, _) => OpenUrl(releaseUrl)));
        }

        item.DropDownItems.Add(new ToolStripSeparator());
        item.DropDownItems.Add(new ToolStripMenuItem($"CI: {status.LatestRun?.DisplayText ?? "not available"}") { Enabled = false });
        item.DropDownItems.Add(new ToolStripMenuItem($"Stars: {status.Stars}  Forks: {status.Forks}") { Enabled = false });
        item.DropDownItems.Add(new ToolStripMenuItem($"Default branch: {status.DefaultBranch}") { Enabled = false });
        if (status.PushedAt != null)
        {
            item.DropDownItems.Add(new ToolStripMenuItem($"Pushed: {status.PushedAt.Value.LocalDateTime:g}") { Enabled = false });
        }

        return item;
    }

    private string BuildHeaderText()
    {
        var repoCount = _settingsStore.Settings.Repositories.Count;
        var tokenState = _settingsStore.ResolveToken() == null ? "no token" : "token";
        var refreshState = _isRefreshing ? "refreshing" : "ready";
        return $"RepoBar Windows - {repoCount} repos - {tokenState} - {refreshState}";
    }

    private void UpdateTrayIcon()
    {
        var health = WorstHealth();
        var oldIcon = _notifyIcon.Icon;
        _notifyIcon.Icon = TrayIconFactory.Create(health);
        oldIcon?.Dispose();
        _notifyIcon.Text = BuildTooltip(health);
    }

    private TrayHealth WorstHealth()
    {
        if (_lastError != null || _statuses.Any(status => status.Health == TrayHealth.Failing))
        {
            return TrayHealth.Failing;
        }

        if (_statuses.Any(status => status.Health == TrayHealth.Busy))
        {
            return TrayHealth.Busy;
        }

        if (_statuses.Count > 0 && _statuses.All(status => status.Health == TrayHealth.Healthy))
        {
            return TrayHealth.Healthy;
        }

        return TrayHealth.Unknown;
    }

    private string BuildTooltip(TrayHealth health)
    {
        var summary = health switch
        {
            TrayHealth.Healthy => "healthy",
            TrayHealth.Busy => "running",
            TrayHealth.Failing => "needs attention",
            _ => "ready",
        };
        return $"RepoBar - {_settingsStore.Settings.Repositories.Count} repos - {summary}";
    }

    private void OnNotifyIconMouseUp(object? sender, MouseEventArgs eventArgs)
    {
        if (eventArgs.Button == MouseButtons.Left && _settingsStore.Settings.OpenMenuOnLeftClick)
        {
            _menu.Show(Cursor.Position);
        }
    }

    private void OpenRepository(RepositoryRef repository, string? path = null)
    {
        OpenUrl(_githubClient.BuildWebUri(repository, path).ToString());
    }

    private static void OpenFile(string path)
    {
        StartShell(path);
    }

    private static void OpenUrl(string url)
    {
        StartShell(url);
    }

    private static void StartShell(string target)
    {
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "RepoBar", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static string HealthPrefix(TrayHealth health)
    {
        return health switch
        {
            TrayHealth.Healthy => "[ok]",
            TrayHealth.Busy => "[..]",
            TrayHealth.Failing => "[!]",
            _ => "[ ]",
        };
    }
}
