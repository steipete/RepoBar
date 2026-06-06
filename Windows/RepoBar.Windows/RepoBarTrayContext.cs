using System.Diagnostics;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class RepoBarTrayContext : ApplicationContext
{
    private readonly WindowsSettingsStore _settingsStore;
    private readonly LocalGitService _localGitService = new();
    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _menu = new();
    private readonly System.Windows.Forms.Timer _refreshTimer = new();
    private readonly CancellationTokenSource _shutdown = new();
    private readonly PullRequestNotificationTracker _pullRequestNotificationTracker = PullRequestNotificationTracker.CreateDefault();
    private GitHubRepositoryClient _githubClient;
    private IReadOnlyList<RepositoryStatus> _statuses = [];
    private ActionsInsights _actionsInsights = ActionsInsights.Empty;
    private GitHubAccountInsight? _accountInsight;
    private IReadOnlyList<GitHubRateLimitSnapshot> _rateLimits = [];
    private LocalGitIndex _localGitIndex = LocalGitIndex.Empty;
    private string? _resolvedToken;
    private string? _lastPullRequestNotificationUrl;
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
        _notifyIcon.BalloonTipClicked += (_, _) => OpenLastPullRequestNotification();

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
        _actionsInsights = ActionsInsights.Empty;
        _accountInsight = null;
        _rateLimits = [];
        BuildMenu();

        try
        {
            _resolvedToken = await WindowsTokenResolver.ResolveAsync(
                _settingsStore.Settings,
                _settingsStore.ResolveToken(),
                _shutdown.Token).ConfigureAwait(false);
            _githubClient.Dispose();
            _githubClient = new GitHubRepositoryClient(_settingsStore.Settings, _resolvedToken);
            _localGitIndex = await _localGitService.LoadIndexAsync(
                _settingsStore.Settings,
                _shutdown.Token);
            _statuses = await _githubClient.LoadRepositoriesAsync(
                _settingsStore.VisibleRepositories,
                _localGitIndex,
                _shutdown.Token);
            _actionsInsights = _settingsStore.Settings.ShowActionsUsage
                ? await LoadActionsInsightsAsync(_settingsStore.VisibleRepositories, _resolvedToken, _shutdown.Token).ConfigureAwait(false)
                : ActionsInsights.Empty;
            _accountInsight = _settingsStore.Settings.ShowContributionSummary
                ? await LoadAccountInsightAsync(_resolvedToken, _shutdown.Token).ConfigureAwait(false)
                : null;
            UpdateRateLimits();
            ShowPullRequestNotifications(_statuses);
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

        var visibleRepositories = _settingsStore.VisibleRepositories;
        if (visibleRepositories.Count == 0)
        {
            AddLocalOnlyRepositories();
            if (_localGitIndex.Repositories.Count == 0)
            {
                _menu.Items.Add(new ToolStripMenuItem("No repositories configured") { Enabled = false });
            }
            _menu.Items.Add(new ToolStripMenuItem("Open settings file", null, (_, _) => OpenFile(_settingsStore.SettingsPath)));
            _menu.Items.Add(new ToolStripMenuItem("Open Windows setup doc", null, (_, _) => OpenUrl("https://github.com/steipete/RepoBar/blob/main/docs/windows.md")));
        }
        else if (_statuses.Count == 0)
        {
            foreach (var repository in visibleRepositories)
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
            AddLocalOnlyRepositories();
        }

        if (!string.IsNullOrWhiteSpace(_lastError))
        {
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(new ToolStripMenuItem($"Error: {_lastError}") { Enabled = false });
        }

        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(new ToolStripMenuItem(_isRefreshing ? "Refreshing..." : "Refresh now", null, (_, _) => BeginRefresh()) { Enabled = !_isRefreshing });
        if (_accountInsight != null)
        {
            AddAccountInsightItems(_menu.Items, _accountInsight);
        }
        if (_settingsStore.Settings.ShowActionsUsage)
        {
            AddActionsUsageItems(_menu.Items);
        }
        if (_settingsStore.Settings.ShowRateLimits && _rateLimits.Count > 0)
        {
            AddRateLimitItems(_menu.Items, _rateLimits);
        }
        _menu.Items.Add(new ToolStripMenuItem("Issue Navigator", null, (_, _) => ShowIssueNavigator()));
        _menu.Items.Add(new ToolStripMenuItem("Preferences", null, (_, _) => ShowPreferences()));
        _menu.Items.Add(new ToolStripMenuItem("Check for updates", null, async (_, _) => await CheckForUpdatesAsync()));
        _menu.Items.Add(new ToolStripMenuItem("Open settings file", null, (_, _) => OpenFile(_settingsStore.SettingsPath)));
        _menu.Items.Add(new ToolStripMenuItem("Quit RepoBar", null, (_, _) => ExitThread()));
    }

    private static void AddRateLimitItems(ToolStripItemCollection items, IReadOnlyList<GitHubRateLimitSnapshot> snapshots)
    {
        var now = DateTimeOffset.UtcNow;
        var blocked = snapshots.Count(snapshot => snapshot.IsBlocked(now));
        var title = snapshots.Count == 1
            ? $"GitHub API: {snapshots[0].CompactText(now)}"
            : blocked > 0
                ? $"GitHub API: {blocked:n0} blocked  {snapshots.Count:n0} buckets"
                : $"GitHub API: {snapshots.Count:n0} buckets";
        var rateItem = new ToolStripMenuItem(title);

        foreach (var snapshot in snapshots)
        {
            var bucket = new ToolStripMenuItem(snapshot.CompactText(now));
            bucket.DropDownItems.Add(new ToolStripMenuItem($"Resource: {snapshot.Resource ?? "core"}") { Enabled = false });
            bucket.DropDownItems.Add(new ToolStripMenuItem($"Remaining: {snapshot.Remaining?.ToString("n0") ?? "unknown"}") { Enabled = false });
            bucket.DropDownItems.Add(new ToolStripMenuItem($"Limit: {snapshot.Limit?.ToString("n0") ?? "unknown"}") { Enabled = false });
            if (snapshot.PercentRemaining != null)
            {
                bucket.DropDownItems.Add(new ToolStripMenuItem($"Percent remaining: {snapshot.PercentRemaining}%") { Enabled = false });
            }
            if (snapshot.ResetAt != null)
            {
                bucket.DropDownItems.Add(new ToolStripMenuItem($"Reset: {snapshot.ResetAt.Value.LocalDateTime:g}") { Enabled = false });
            }
            if (snapshot.IsBlocked(now))
            {
                bucket.DropDownItems.Add(new ToolStripSeparator());
                bucket.DropDownItems.Add(new ToolStripMenuItem("Current blocker: GitHub API quota exhausted") { Enabled = false });
            }
            rateItem.DropDownItems.Add(bucket);
        }
        if (blocked > 0)
        {
            rateItem.DropDownItems.Add(new ToolStripSeparator());
            rateItem.DropDownItems.Add(new ToolStripMenuItem($"{blocked:n0} active quota blocker{(blocked == 1 ? "" : "s")}") { Enabled = false });
        }
        rateItem.DropDownItems.Add(new ToolStripSeparator());
        rateItem.DropDownItems.Add(new ToolStripMenuItem("Budget is shared by the GitHub user or token actor, not by each token string.") { Enabled = false });
        items.Add(rateItem);
    }

    private void AddAccountInsightItems(ToolStripItemCollection items, GitHubAccountInsight account)
    {
        var accountItem = new ToolStripMenuItem($"GitHub: {account.DisplayText}");
        if (!string.IsNullOrWhiteSpace(account.Url))
        {
            accountItem.Click += (_, _) => OpenUrl(account.Url);
        }
        accountItem.DropDownItems.Add(new ToolStripMenuItem($"{account.CommitContributions:n0} commits") { Enabled = false });
        accountItem.DropDownItems.Add(new ToolStripMenuItem($"{account.PullRequestContributions:n0} pull requests") { Enabled = false });
        accountItem.DropDownItems.Add(new ToolStripMenuItem($"{account.PullRequestReviewContributions:n0} reviews") { Enabled = false });
        accountItem.DropDownItems.Add(new ToolStripMenuItem($"{account.IssueContributions:n0} issues") { Enabled = false });
        if (account.ContributionWeeks.Count > 0)
        {
            accountItem.DropDownItems.Add(new ToolStripSeparator());
            accountItem.DropDownItems.Add(new ToolStripMenuItem($"Heatmap: {account.ContributionHeatmapDisplayText}") { Enabled = false });
            foreach (var week in account.ContributionWeeks.TakeLast(4))
            {
                accountItem.DropDownItems.Add(new ToolStripMenuItem(week.DisplayText) { Enabled = false });
            }
        }
        items.Add(accountItem);
    }

    private void AddActionsUsageItems(ToolStripItemCollection items)
    {
        if (_statuses.Count == 0)
        {
            return;
        }

        var running = _statuses.Count(status => status.LatestRun is { Status: var latestStatus } &&
            !string.Equals(latestStatus, "completed", StringComparison.OrdinalIgnoreCase));
        var failing = _statuses.Count(status => status.LatestRun is { Status: "completed", Conclusion: var conclusion } &&
            !string.Equals(conclusion, "success", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(conclusion, "skipped", StringComparison.OrdinalIgnoreCase));
        var healthy = _statuses.Count(status => status.LatestRun is { Status: "completed", Conclusion: var conclusion } &&
            (string.Equals(conclusion, "success", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(conclusion, "skipped", StringComparison.OrdinalIgnoreCase)));

        var actions = new ToolStripMenuItem(_actionsInsights.HasData
            ? $"{_actionsInsights.DisplayText}  {failing} failing  {healthy} healthy"
            : $"Actions: {running} running  {failing} failing  {healthy} healthy");
        if (_actionsInsights.HasData)
        {
            if (_actionsInsights.Billing != null)
            {
                actions.DropDownItems.Add(new ToolStripMenuItem($"Billing: {_actionsInsights.Billing.DisplayText}") { Enabled = false });
                foreach (var entry in _actionsInsights.Billing.MinutesByOs.OrderBy(entry => entry.Key, StringComparer.OrdinalIgnoreCase))
                {
                    actions.DropDownItems.Add(new ToolStripMenuItem($"{entry.Key}: {entry.Value:n0} minutes") { Enabled = false });
                }
                actions.DropDownItems.Add(new ToolStripSeparator());
            }
            if (_actionsInsights.CacheUsage.Count > 0)
            {
                actions.DropDownItems.Add(new ToolStripMenuItem($"Cache: {_actionsInsights.CacheUsage.Sum(usage => usage.CacheSizeMb):n0} MB") { Enabled = false });
                foreach (var usage in _actionsInsights.CacheUsage.OrderBy(usage => usage.Owner, StringComparer.OrdinalIgnoreCase))
                {
                    actions.DropDownItems.Add(new ToolStripMenuItem(usage.DisplayText) { Enabled = false });
                }
                actions.DropDownItems.Add(new ToolStripSeparator());
            }

            foreach (var insight in _actionsInsights.Repositories)
            {
                var repositoryItem = new ToolStripMenuItem($"{insight.Repository.FullName}: {insight.DisplayText}");
                if (insight.ErrorMessage != null)
                {
                    repositoryItem.DropDownItems.Add(new ToolStripMenuItem(insight.ErrorMessage) { Enabled = false });
                }
                else
                {
                    repositoryItem.DropDownItems.Add(new ToolStripMenuItem($"{insight.Queue.InProgressCount:n0} running  {insight.Queue.QueuedCount:n0} queued") { Enabled = false });
                    repositoryItem.DropDownItems.Add(new ToolStripMenuItem($"{insight.Runners.OnlineCount:n0} online  {insight.Runners.BusyCount:n0} busy  {insight.Runners.OfflineCount:n0} offline") { Enabled = false });
                    foreach (var runner in insight.Runners.Runners.Take(10))
                    {
                        repositoryItem.DropDownItems.Add(new ToolStripMenuItem(runner.DisplayText) { Enabled = false });
                    }
                    if (insight.Runners.TotalCount > 10)
                    {
                        repositoryItem.DropDownItems.Add(new ToolStripMenuItem($"... and {insight.Runners.TotalCount - 10:n0} more runners") { Enabled = false });
                    }
                }
                actions.DropDownItems.Add(repositoryItem);
            }

            actions.DropDownItems.Add(new ToolStripSeparator());
        }
        foreach (var status in _statuses.Where(status => status.LatestRun != null))
        {
            var item = new ToolStripMenuItem($"{status.Repository.FullName}: {status.LatestRun!.DisplayText}")
            {
                Enabled = !string.IsNullOrWhiteSpace(status.LatestRun.Url),
            };
            if (!string.IsNullOrWhiteSpace(status.LatestRun.Url))
            {
                item.Click += (_, _) => OpenUrl(status.LatestRun.Url);
            }
            actions.DropDownItems.Add(item);
        }

        items.Add(actions);
    }

    private async Task<ActionsInsights> LoadActionsInsightsAsync(
        IReadOnlyList<RepositoryRef> repositories,
        string? token,
        CancellationToken cancellationToken)
    {
        using var client = new GitHubActionsInsightClient(_settingsStore.Settings, token);
        return await client.LoadAsync(repositories, cancellationToken).ConfigureAwait(false);
    }

    private async Task<GitHubAccountInsight?> LoadAccountInsightAsync(string? token, CancellationToken cancellationToken)
    {
        using var client = new GitHubAccountInsightClient(_settingsStore.Settings, token);
        return await client.LoadAsync(cancellationToken).ConfigureAwait(false);
    }

    private void UpdateRateLimits()
    {
        var snapshots = new List<GitHubRateLimitSnapshot?>();
        snapshots.Add(_githubClient.LastRateLimit);
        snapshots.AddRange(_actionsInsights.RateLimits);
        if (_accountInsight != null)
        {
            snapshots.AddRange(_accountInsight.RateLimits);
        }

        _rateLimits = GitHubRateLimitSnapshot.LatestByResource(snapshots);
    }

    private ToolStripMenuItem BuildRepositoryMenu(RepositoryStatus status)
    {
        var item = new ToolStripMenuItem(RepositoryRowFormatter.BuildLabel(status));

        if (status.ErrorMessage != null)
        {
            item.DropDownItems.Add(new ToolStripMenuItem(status.ErrorMessage) { Enabled = false });
            item.DropDownItems.Add(new ToolStripMenuItem("Open repository", null, (_, _) => OpenRepository(status.Repository)));
            if (status.LocalStatus != null)
            {
                item.DropDownItems.Add(new ToolStripSeparator());
                AddLocalStatusItems(item.DropDownItems, status.LocalStatus);
            }
            else
            {
                AddCheckoutItem(item.DropDownItems, status.Repository);
            }
            AddVisibilityItems(item.DropDownItems, status.Repository.FullName);
            return item;
        }

        item.DropDownItems.Add(new ToolStripMenuItem("Open repository", null, (_, _) => OpenRepository(status.Repository)));
        item.DropDownItems.Add(new ToolStripMenuItem("Open issues", null, (_, _) => OpenRepository(status.Repository, "issues")));
        item.DropDownItems.Add(new ToolStripMenuItem("Open pull requests", null, (_, _) => OpenRepository(status.Repository, "pulls")));
        item.DropDownItems.Add(new ToolStripMenuItem("Open Actions", null, (_, _) => OpenRepository(status.Repository, "actions")));
        if (status.LocalStatus == null)
        {
            AddCheckoutItem(item.DropDownItems, status.Repository);
        }
        AddRecentItemsSubmenu(item.DropDownItems, "Issues", status.RecentLists.Issues);
        AddRecentItemsSubmenu(item.DropDownItems, "Pull Requests", status.RecentLists.Pulls);
        AddRecentItemsSubmenu(item.DropDownItems, "Releases", status.RecentLists.Releases);
        AddRecentItemsSubmenu(item.DropDownItems, "CI Runs", status.RecentLists.WorkflowRuns);
        AddRecentItemsSubmenu(item.DropDownItems, "Branches", status.RecentLists.Branches);
        AddRecentItemsSubmenu(item.DropDownItems, "Tags", status.RecentLists.Tags);
        AddRecentItemsSubmenu(item.DropDownItems, "Commits", status.RecentLists.Commits);
        AddRecentItemsSubmenu(item.DropDownItems, "Contributors", status.RecentLists.Contributors);
        AddRecentItemsSubmenu(item.DropDownItems, "Activity", status.RecentLists.Activity);
        AddRecentItemsSubmenu(item.DropDownItems, "Discussions", status.RecentLists.Discussions);

        if (status.LatestRelease is { Url: { Length: > 0 } releaseUrl })
        {
            item.DropDownItems.Add(new ToolStripMenuItem($"Latest release: {status.LatestRelease.TagName}", null, (_, _) => OpenUrl(releaseUrl)));
        }

        item.DropDownItems.Add(new ToolStripSeparator());
        item.DropDownItems.Add(new ToolStripMenuItem($"CI: {status.LatestRun?.DisplayText ?? "not available"}") { Enabled = false });
        item.DropDownItems.Add(new ToolStripMenuItem($"Stars: {status.Stars}  Forks: {status.Forks}") { Enabled = false });
        item.DropDownItems.Add(new ToolStripMenuItem($"Default branch: {status.DefaultBranch}") { Enabled = false });
        if (status.Traffic is { DisplayText.Length: > 0 })
        {
            item.DropDownItems.Add(new ToolStripMenuItem($"Traffic: {status.Traffic.DisplayText}") { Enabled = false });
        }
        if (status.Heatmap != null)
        {
            item.DropDownItems.Add(new ToolStripMenuItem($"Heatmap: {status.Heatmap.DisplayText}") { Enabled = false });
        }
        if (status.Changelog != null)
        {
            item.DropDownItems.Add(new ToolStripMenuItem($"Changelog: {status.Changelog.Headline}", null, (_, _) => OpenUrl(status.Changelog.Url)));
        }
        if (status.LocalStatus != null)
        {
            item.DropDownItems.Add(new ToolStripSeparator());
            AddLocalStatusItems(item.DropDownItems, status.LocalStatus);
        }
        if (status.PushedAt != null)
        {
            item.DropDownItems.Add(new ToolStripMenuItem($"Pushed: {status.PushedAt.Value.LocalDateTime:g}") { Enabled = false });
        }
        AddVisibilityItems(item.DropDownItems, status.Repository.FullName);

        return item;
    }

    private void AddCheckoutItem(ToolStripItemCollection items, RepositoryRef repository)
    {
        if (string.IsNullOrWhiteSpace(_settingsStore.Settings.LocalProjectsRoot))
        {
            items.Add(new ToolStripMenuItem("Set local projects folder...", null, (_, _) => ShowPreferences()));
            return;
        }

        items.Add(new ToolStripMenuItem("Checkout locally", null, async (_, _) => await CheckoutRepositoryAsync(repository)));
    }

    private void AddLocalOnlyRepositories()
    {
        var configured = _settingsStore.Settings.Repositories
            .Select(repository => repository.FullName)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var localOnly = _localGitIndex.Repositories
            .Where(repository => repository.FullName == null || !configured.Contains(repository.FullName))
            .Take(10)
            .ToArray();
        if (localOnly.Length == 0)
        {
            return;
        }

        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(new ToolStripMenuItem("Local repositories") { Enabled = false });
        foreach (var local in localOnly)
        {
            var item = new ToolStripMenuItem($"[git] {local.DisplayName}  {local.SyncDetail}");
            AddLocalStatusItems(item.DropDownItems, local);
            if (!string.IsNullOrWhiteSpace(local.FullName))
            {
                item.DropDownItems.Add(new ToolStripSeparator());
                item.DropDownItems.Add(new ToolStripMenuItem("Pin in RepoBar", null, (_, _) => SetVisibility(local.FullName, RepositoryVisibility.Pinned)));
            }
            _menu.Items.Add(item);
        }
    }

    private void AddLocalStatusItems(ToolStripItemCollection items, LocalGitRepositoryStatus local)
    {
        items.Add(new ToolStripMenuItem($"Branch: {local.Branch}") { Enabled = false });
        if (!string.IsNullOrWhiteSpace(local.UpstreamBranch))
        {
            items.Add(new ToolStripMenuItem($"Upstream: {local.UpstreamBranch}") { Enabled = false });
        }
        items.Add(new ToolStripMenuItem(local.SyncDetail) { Enabled = false });
        if (local.DirtyFiles.Count > 0)
        {
            items.Add(new ToolStripMenuItem("Dirty files") { Enabled = false });
            foreach (var file in local.DirtyFiles)
            {
                items.Add(new ToolStripMenuItem(file) { Enabled = false });
            }
        }
        items.Add(new ToolStripSeparator());
        items.Add(new ToolStripMenuItem("Fetch", null, async (_, _) => await RunLocalGitActionAsync(
            "Fetch",
            token => _localGitService.FetchAsync(local.Path, token))));
        items.Add(new ToolStripMenuItem("Sync fast-forward", null, async (_, _) => await RunLocalGitActionAsync(
            "Sync",
            token => _localGitService.FastForwardAsync(local.Path, token)))
        {
            Enabled = local.CanFastForward,
        });
        AddBranchesSubmenu(items, local);
        AddWorktreesSubmenu(items, local);
        items.Add(new ToolStripSeparator());
        items.Add(new ToolStripMenuItem("Open folder", null, (_, _) => OpenFile(local.Path)));
        items.Add(new ToolStripMenuItem("Open in terminal", null, (_, _) => OpenTerminal(local.Path)));
    }

    private void AddBranchesSubmenu(ToolStripItemCollection items, LocalGitRepositoryStatus local)
    {
        var submenu = new ToolStripMenuItem("Branches");
        submenu.DropDownOpening += async (_, _) =>
        {
            submenu.DropDownItems.Clear();
            submenu.DropDownItems.Add(new ToolStripMenuItem("Loading...") { Enabled = false });
            var branches = await _localGitService.ListBranchesAsync(local.Path, _shutdown.Token).ConfigureAwait(true);
            submenu.DropDownItems.Clear();
            if (branches.Count == 0)
            {
                submenu.DropDownItems.Add(new ToolStripMenuItem("No branches") { Enabled = false });
                return;
            }

            foreach (var branch in branches)
            {
                var label = branch.IsCurrent ? $"[current] {branch.Name}" : branch.Name;
                submenu.DropDownItems.Add(new ToolStripMenuItem(label, null, async (_, _) => await RunLocalGitActionAsync(
                    $"Switch branch to {branch.Name}",
                    token => _localGitService.SwitchBranchAsync(local.Path, branch.Name, token)))
                {
                    Enabled = !branch.IsCurrent,
                });
            }
        };
        items.Add(submenu);
    }

    private void AddWorktreesSubmenu(ToolStripItemCollection items, LocalGitRepositoryStatus local)
    {
        var submenu = new ToolStripMenuItem("Worktrees");
        submenu.DropDownOpening += async (_, _) =>
        {
            submenu.DropDownItems.Clear();
            submenu.DropDownItems.Add(new ToolStripMenuItem("Loading...") { Enabled = false });
            var worktrees = await _localGitService.ListWorktreesAsync(local.Path, _shutdown.Token).ConfigureAwait(true);
            submenu.DropDownItems.Clear();
            if (worktrees.Count == 0)
            {
                submenu.DropDownItems.Add(new ToolStripMenuItem("No worktrees") { Enabled = false });
                return;
            }

            foreach (var worktree in worktrees)
            {
                var branch = string.IsNullOrWhiteSpace(worktree.Branch) ? "detached" : worktree.Branch;
                var label = $"{Path.GetFileName(worktree.Path)}  {branch}";
                var item = new ToolStripMenuItem(label);
                item.DropDownItems.Add(new ToolStripMenuItem(worktree.Path) { Enabled = false });
                item.DropDownItems.Add(new ToolStripMenuItem("Open folder", null, (_, _) => OpenFile(worktree.Path)));
                item.DropDownItems.Add(new ToolStripMenuItem("Open in terminal", null, (_, _) => OpenTerminal(worktree.Path)));
                submenu.DropDownItems.Add(item);
            }
        };
        items.Add(submenu);
    }

    private async Task RunLocalGitActionAsync(
        string actionName,
        Func<CancellationToken, Task<LocalGitActionResult>> action)
    {
        var result = await action(_shutdown.Token).ConfigureAwait(true);
        if (!result.Success)
        {
            MessageBox.Show(result.DisplayText, $"RepoBar {actionName}", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        _lastPullRequestNotificationUrl = null;
        _notifyIcon.ShowBalloonTip(5000, $"RepoBar {actionName}", result.DisplayText, ToolTipIcon.Info);
        BeginRefresh();
    }

    private static void AddRecentItemsSubmenu(ToolStripItemCollection items, string title, IReadOnlyList<GitHubListItem> recentItems)
    {
        if (recentItems.Count == 0)
        {
            return;
        }

        var submenu = new ToolStripMenuItem(title);
        foreach (var recent in recentItems)
        {
            var item = new ToolStripMenuItem(recent.Title, null, (_, _) =>
            {
                if (!string.IsNullOrWhiteSpace(recent.Url))
                {
                    OpenUrl(recent.Url);
                }
            })
            {
                Enabled = !string.IsNullOrWhiteSpace(recent.Url),
                ToolTipText = recent.Subtitle ?? recent.Title,
            };
            submenu.DropDownItems.Add(item);
        }

        items.Add(submenu);
    }

    private void AddVisibilityItems(ToolStripItemCollection items, string fullName)
    {
        items.Add(new ToolStripSeparator());
        items.Add(new ToolStripMenuItem("Pin", null, (_, _) => SetVisibility(fullName, RepositoryVisibility.Pinned)));
        items.Add(new ToolStripMenuItem("Set Visible", null, (_, _) => SetVisibility(fullName, RepositoryVisibility.Visible)));
        items.Add(new ToolStripMenuItem("Hide", null, (_, _) => SetVisibility(fullName, RepositoryVisibility.Hidden)));
    }

    private string BuildHeaderText()
    {
        var repoCount = _settingsStore.VisibleRepositories.Count;
        var tokenState = (_resolvedToken ?? _settingsStore.ResolveToken()) == null ? "no token" : "token";
        var cacheState = _settingsStore.Settings.EnableResponseCache ? "cache" : "no cache";
        var refreshState = _isRefreshing ? "refreshing" : "ready";
        return $"RepoBar Windows - {repoCount} repos - {_localGitIndex.Repositories.Count} local - {tokenState} - {cacheState} - {refreshState}";
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
        return $"RepoBar - {_settingsStore.VisibleRepositories.Count} repos / {_localGitIndex.Repositories.Count} local - {summary}";
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

    private async Task CheckoutRepositoryAsync(RepositoryRef repository)
    {
        var root = _settingsStore.Settings.LocalProjectsRoot;
        if (string.IsNullOrWhiteSpace(root))
        {
            ShowPreferences();
            return;
        }

        var destination = LocalGitService.CheckoutDestination(root, repository.Name);
        if (Directory.Exists(destination) || File.Exists(destination))
        {
            MessageBox.Show($"{destination} already exists.", "RepoBar Checkout", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var result = await _localGitService.CloneRepositoryAsync(
            BuildCloneUrl(repository),
            destination,
            _shutdown.Token).ConfigureAwait(true);
        if (!result.Success)
        {
            MessageBox.Show(result.DisplayText, "RepoBar Checkout", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        _notifyIcon.ShowBalloonTip(5000, "RepoBar Checkout", $"Checked out {repository.FullName}", ToolTipIcon.Info);
        OpenFile(destination);
        BeginRefresh();
    }

    private string BuildCloneUrl(RepositoryRef repository)
    {
        var host = GitHubHost.Normalize(_settingsStore.Settings.GitHubHost);
        return $"https://{host}/{Uri.EscapeDataString(repository.Owner)}/{Uri.EscapeDataString(repository.Name)}.git";
    }

    private void SetVisibility(string fullName, RepositoryVisibility visibility)
    {
        _settingsStore.SetVisibility(fullName, visibility);
        BeginRefresh();
    }

    private void ShowPullRequestNotifications(IReadOnlyList<RepositoryStatus> statuses)
    {
        if (!_settingsStore.Settings.EnablePullRequestNotifications)
        {
            return;
        }

        foreach (var status in statuses.Where(status => status.ErrorMessage == null))
        {
            var newPulls = _pullRequestNotificationTracker.DetectNewPullRequests(
                status.Repository.FullName,
                status.RecentLists.Pulls);
            foreach (var pull in newPulls.Take(3))
            {
                if (!string.IsNullOrWhiteSpace(pull.Url))
                {
                    _lastPullRequestNotificationUrl = pull.Url;
                }
                _notifyIcon.ShowBalloonTip(
                    timeout: 8000,
                    tipTitle: $"{status.Repository.FullName} pull request",
                    tipText: pull.Title,
                    tipIcon: ToolTipIcon.Info);
            }
        }
    }

    private void OpenLastPullRequestNotification()
    {
        if (!string.IsNullOrWhiteSpace(_lastPullRequestNotificationUrl))
        {
            OpenUrl(_lastPullRequestNotificationUrl);
        }
    }

    private void ShowPreferences()
    {
        using var form = new SettingsEditorForm(_settingsStore);
        if (form.ShowDialog() == DialogResult.OK)
        {
            _refreshTimer.Interval = Math.Clamp(_settingsStore.Settings.RefreshIntervalMinutes, 1, 60) * 60 * 1000;
            _githubClient.Dispose();
            _resolvedToken = null;
            _githubClient = new GitHubRepositoryClient(_settingsStore.Settings, _settingsStore.ResolveToken());
            BeginRefresh();
        }
    }

    private void ShowIssueNavigator()
    {
        using var form = new ReferenceNavigatorForm(_settingsStore.Settings);
        form.ShowDialog();
    }

    private static async Task CheckForUpdatesAsync()
    {
        try
        {
            using var checker = new WindowsUpdateChecker();
            var status = await checker.CheckLatestAsync(WindowsUpdateChecker.CurrentVersion(), CancellationToken.None).ConfigureAwait(true);
            if (status.IsNewer && !string.IsNullOrWhiteSpace(status.PreferredUpdateUrl))
            {
                var target = status.InstallerUrl == null ? "latest release" : "Windows installer";
                var result = MessageBox.Show(
                    $"{status.DisplayText}.\n\nOpen the {target}?",
                    "RepoBar Updates",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Information);
                if (result == DialogResult.Yes)
                {
                    OpenUrl(status.PreferredUpdateUrl);
                }
                return;
            }

            MessageBox.Show(status.DisplayText, "RepoBar Updates", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "RepoBar Updates", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static void OpenFile(string path)
    {
        StartShell(path);
    }

    private static void OpenTerminal(string path)
    {
        try
        {
            Process.Start(new ProcessStartInfo("wt.exe")
            {
                UseShellExecute = true,
                Arguments = $"-d \"{path}\"",
            });
        }
        catch
        {
            Process.Start(new ProcessStartInfo("cmd.exe")
            {
                UseShellExecute = true,
                Arguments = $"/K cd /d \"{path}\"",
            });
        }
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

}
