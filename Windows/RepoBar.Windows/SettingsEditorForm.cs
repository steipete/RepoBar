using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class SettingsEditorForm : Form
{
    private readonly WindowsSettingsStore _settingsStore;
    private readonly Label _credentialState = new();
    private readonly Label _oauthState = new();
    private readonly Label _tokenValidationState = new();
    private readonly BindingList<AccountRow> _accounts = [];
    private readonly ComboBox _accountSelector = new();
    private readonly TextBox _accountLabelTextBox = new();
    private readonly TextBox _hostTextBox = new();
    private readonly TextBox _tokenEnvironmentTextBox = new();
    private readonly TextBox _oauthClientIdTextBox = new();
    private readonly TextBox _oauthSecretEnvironmentTextBox = new();
    private readonly TextBox _personalAccessTokenTextBox = new();
    private readonly NumericUpDown _refreshMinutes = new();
    private readonly CheckBox _openMenuOnLeftClick = new();
    private readonly CheckBox _launchAtLogin = new();
    private readonly CheckBox _discoverLocalProjects = new();
    private readonly TextBox _localProjectsRoot = new();
    private readonly NumericUpDown _localProjectsDepth = new();
    private readonly TextBox _localWorktreeFolderName = new();
    private readonly ComboBox _terminalPreference = new();
    private readonly CheckBox _fetchLocalProjectsBeforeStatus = new();
    private readonly NumericUpDown _localProjectsFetchIntervalMinutes = new();
    private readonly CheckBox _autoSyncLocalProjects = new();
    private readonly CheckBox _showDirtyFilesInMenu = new();
    private readonly CheckBox _enableResponseCache = new();
    private readonly TextBox _gitHubArchiveDatabasePath = new();
    private readonly NumericUpDown _repositoryDisplayLimit = new();
    private readonly ComboBox _repositoryMenuScope = new();
    private readonly ComboBox _repositorySortKey = new();
    private readonly CheckBox _includeForkedRepositories = new();
    private readonly CheckBox _includeArchivedRepositories = new();
    private readonly CheckBox _showOnlyMyRepositories = new();
    private readonly TextBox _repositoryOwnerFilter = new();
    private readonly CheckBox _showOnlyRepositoriesWithIssues = new();
    private readonly CheckBox _showOnlyRepositoriesWithPullRequests = new();
    private readonly ComboBox _heatmapDisplay = new();
    private readonly ComboBox _heatmapSpan = new();
    private readonly ComboBox _activityScope = new();
    private readonly CheckBox _showRateLimits = new();
    private readonly CheckBox _showContributionSummary = new();
    private readonly CheckBox _showActionsUsage = new();
    private readonly TextBox _actionsMonitoredOwners = new();
    private readonly CheckBox _diagnosticsEnabled = new();
    private readonly ComboBox _loggingVerbosity = new();
    private readonly CheckBox _fileLoggingEnabled = new();
    private readonly CheckBox _enableGitHubReferenceMonitor = new();
    private readonly CheckBox _enablePullRequestNotifications = new();
    private readonly CheckBox _enablePullRequestNewNotifications = new();
    private readonly CheckBox _enablePullRequestUpdateNotifications = new();
    private readonly CheckBox _enablePullRequestReviewRequestNotifications = new();
    private readonly CheckBox _enablePullRequestCommentNotifications = new();
    private readonly ComboBox _pullRequestNotificationClickAction = new();
    private readonly BindingList<RepositoryRow> _repositories = [];
    private readonly DataGridView _repositoriesGrid = new();
    private readonly TextBox _repositoryFilterTextBox = new();
    private WindowsMenuCustomization _menuCustomization = new();
    private AccountRow? _selectedAccount;
    private readonly string? _viewerLogin;
    private bool _loadingAccount;
    private bool _updatingOwnerFilterControls;

    public SettingsEditorForm(WindowsSettingsStore settingsStore, string? viewerLogin = null)
    {
        _settingsStore = settingsStore;
        _viewerLogin = string.IsNullOrWhiteSpace(viewerLogin) ? null : viewerLogin.Trim();
        Text = "RepoBar Preferences";
        StartPosition = FormStartPosition.CenterScreen;
        MinimizeBox = false;
        MaximizeBox = false;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        ClientSize = new Size(820, 740);

        LoadSettings();
        BuildControls();
    }

    private void LoadSettings()
    {
        var settings = _settingsStore.Settings;
        foreach (var account in settings.Accounts)
        {
            _accounts.Add(AccountRow.FromProfile(account));
        }

        if (_accounts.Count == 0)
        {
            _accounts.Add(AccountRow.FromProfile(WindowsAccountProfile.FromLegacy(settings)));
        }

        _hostTextBox.Text = settings.GitHubHost;
        _tokenEnvironmentTextBox.Text = settings.TokenEnvironmentVariable;
        _oauthClientIdTextBox.Text = settings.GitHubOAuthClientId;
        _oauthSecretEnvironmentTextBox.Text = settings.GitHubOAuthClientSecretEnvironmentVariable;
        _personalAccessTokenTextBox.UseSystemPasswordChar = true;
        _refreshMinutes.Minimum = 1;
        _refreshMinutes.Maximum = 60;
        _refreshMinutes.Value = Math.Clamp(settings.RefreshIntervalMinutes, 1, 60);
        _openMenuOnLeftClick.Checked = settings.OpenMenuOnLeftClick;
        _launchAtLogin.Checked = settings.LaunchAtLogin;
        _discoverLocalProjects.Checked = settings.DiscoverLocalProjects;
        _localProjectsRoot.Text = settings.LocalProjectsRoot ?? "";
        _localProjectsDepth.Minimum = 0;
        _localProjectsDepth.Maximum = 8;
        _localProjectsDepth.Value = Math.Clamp(settings.LocalProjectsMaxDepth, 0, 8);
        _localWorktreeFolderName.Text = settings.LocalWorktreeFolderName;
        _terminalPreference.DropDownStyle = ComboBoxStyle.DropDownList;
        _terminalPreference.DataSource = Enum.GetValues<WindowsTerminalPreference>()
            .Select(TerminalPreferenceRow.FromPreference)
            .ToArray();
        _terminalPreference.DisplayMember = nameof(TerminalPreferenceRow.DisplayName);
        _terminalPreference.ValueMember = nameof(TerminalPreferenceRow.Preference);
        _terminalPreference.SelectedValue = settings.TerminalPreference;
        _fetchLocalProjectsBeforeStatus.Checked = settings.FetchLocalProjectsBeforeStatus;
        _localProjectsFetchIntervalMinutes.Minimum = 1;
        _localProjectsFetchIntervalMinutes.Maximum = 60;
        _localProjectsFetchIntervalMinutes.Value = Math.Clamp(settings.LocalProjectsFetchIntervalMinutes, 1, 60);
        _autoSyncLocalProjects.Checked = settings.AutoSyncLocalProjects;
        _showDirtyFilesInMenu.Checked = settings.ShowDirtyFilesInMenu;
        _enableResponseCache.Checked = settings.EnableResponseCache;
        _gitHubArchiveDatabasePath.Text = settings.GitHubArchiveDatabasePath ?? "";
        _repositoryDisplayLimit.Minimum = 1;
        _repositoryDisplayLimit.Maximum = 100;
        _repositoryDisplayLimit.Value = Math.Clamp(settings.RepositoryDisplayLimit, 1, 100);
        _repositoryMenuScope.DropDownStyle = ComboBoxStyle.DropDownList;
        _repositoryMenuScope.DataSource = Enum.GetValues<RepositoryMenuScope>()
            .Select(RepositoryMenuScopeRow.FromScope)
            .ToArray();
        _repositoryMenuScope.DisplayMember = nameof(RepositoryMenuScopeRow.DisplayName);
        _repositoryMenuScope.ValueMember = nameof(RepositoryMenuScopeRow.Scope);
        _repositoryMenuScope.SelectedValue = settings.RepositoryMenuScope;
        _repositorySortKey.DropDownStyle = ComboBoxStyle.DropDownList;
        _repositorySortKey.DataSource = Enum.GetValues<RepositorySortKey>()
            .Select(RepositorySortKeyRow.FromSortKey)
            .ToArray();
        _repositorySortKey.DisplayMember = nameof(RepositorySortKeyRow.DisplayName);
        _repositorySortKey.ValueMember = nameof(RepositorySortKeyRow.SortKey);
        _repositorySortKey.SelectedValue = settings.RepositorySortKey;
        _includeForkedRepositories.Checked = settings.IncludeForkedRepositories;
        _includeArchivedRepositories.Checked = settings.IncludeArchivedRepositories;
        _repositoryOwnerFilter.Text = FormatRepositoryOwnerFilter(settings.RepositoryOwnerFilter);
        _showOnlyMyRepositories.Checked = WindowsRepositoryOwnerFilter.IsOnlyViewer(settings.RepositoryOwnerFilter, _viewerLogin);
        _showOnlyRepositoriesWithIssues.Checked = settings.ShowOnlyRepositoriesWithIssues;
        _showOnlyRepositoriesWithPullRequests.Checked = settings.ShowOnlyRepositoriesWithPullRequests;
        _heatmapDisplay.DropDownStyle = ComboBoxStyle.DropDownList;
        _heatmapDisplay.DataSource = Enum.GetValues<WindowsHeatmapDisplay>()
            .Select(HeatmapDisplayRow.FromDisplay)
            .ToArray();
        _heatmapDisplay.DisplayMember = nameof(HeatmapDisplayRow.DisplayName);
        _heatmapDisplay.ValueMember = nameof(HeatmapDisplayRow.Display);
        _heatmapDisplay.SelectedValue = settings.HeatmapDisplay;
        _heatmapSpan.DropDownStyle = ComboBoxStyle.DropDownList;
        _heatmapSpan.DataSource = Enum.GetValues<WindowsHeatmapSpan>()
            .Select(HeatmapSpanRow.FromSpan)
            .ToArray();
        _heatmapSpan.DisplayMember = nameof(HeatmapSpanRow.DisplayName);
        _heatmapSpan.ValueMember = nameof(HeatmapSpanRow.Span);
        _heatmapSpan.SelectedValue = settings.HeatmapSpan;
        _activityScope.DropDownStyle = ComboBoxStyle.DropDownList;
        _activityScope.DataSource = Enum.GetValues<WindowsActivityScope>()
            .Select(ActivityScopeRow.FromScope)
            .ToArray();
        _activityScope.DisplayMember = nameof(ActivityScopeRow.DisplayName);
        _activityScope.ValueMember = nameof(ActivityScopeRow.Scope);
        _activityScope.SelectedValue = settings.ActivityScope;
        _showRateLimits.Checked = settings.ShowRateLimits;
        _showContributionSummary.Checked = settings.ShowContributionSummary;
        _showActionsUsage.Checked = settings.ShowActionsUsage;
        _actionsMonitoredOwners.Text = FormatRepositoryOwnerFilter(settings.ActionsMonitoredOwners);
        _diagnosticsEnabled.Checked = settings.DiagnosticsEnabled;
        _loggingVerbosity.DropDownStyle = ComboBoxStyle.DropDownList;
        _loggingVerbosity.DataSource = Enum.GetValues<WindowsLogVerbosity>()
            .Select(LogVerbosityRow.FromVerbosity)
            .ToArray();
        _loggingVerbosity.DisplayMember = nameof(LogVerbosityRow.DisplayName);
        _loggingVerbosity.ValueMember = nameof(LogVerbosityRow.Verbosity);
        _loggingVerbosity.SelectedValue = settings.LoggingVerbosity;
        _fileLoggingEnabled.Checked = settings.FileLoggingEnabled;
        _enableGitHubReferenceMonitor.Checked = settings.EnableGitHubReferenceMonitor;
        _enablePullRequestNotifications.Checked = settings.EnablePullRequestNotifications;
        _enablePullRequestNewNotifications.Checked = settings.EnablePullRequestNewNotifications;
        _enablePullRequestUpdateNotifications.Checked = settings.EnablePullRequestUpdateNotifications;
        _enablePullRequestReviewRequestNotifications.Checked = settings.EnablePullRequestReviewRequestNotifications;
        _enablePullRequestCommentNotifications.Checked = settings.EnablePullRequestCommentNotifications;
        _pullRequestNotificationClickAction.DropDownStyle = ComboBoxStyle.DropDownList;
        _pullRequestNotificationClickAction.DataSource = Enum.GetValues<PullRequestNotificationClickAction>()
            .Select(NotificationClickActionRow.FromAction)
            .ToArray();
        _pullRequestNotificationClickAction.DisplayMember = nameof(NotificationClickActionRow.DisplayName);
        _pullRequestNotificationClickAction.ValueMember = nameof(NotificationClickActionRow.Action);
        _pullRequestNotificationClickAction.SelectedValue = settings.PullRequestNotificationClickAction;
        _menuCustomization = settings.MenuCustomization.Copy();

        foreach (var repository in settings.Repositories)
        {
            _repositories.Add(new RepositoryRow(repository.Owner, repository.Name, repository.Visibility));
        }
    }

    private void BuildControls()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6,
            Padding = new Padding(12),
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        Controls.Add(root);

        var settingsGrid = new TableLayoutPanel
        {
            AutoSize = true,
            ColumnCount = 4,
            Dock = DockStyle.Top,
        };
        settingsGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        settingsGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        settingsGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        settingsGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        root.Controls.Add(settingsGrid);

        _hostTextBox.TextChanged += (_, _) => UpdateCredentialState();
        _accountSelector.DropDownStyle = ComboBoxStyle.DropDownList;
        _accountSelector.DataSource = _accounts;
        _accountSelector.DisplayMember = nameof(AccountRow.DisplayName);
        _accountSelector.SelectedIndexChanged += (_, _) => SelectAccountFromCombo();
        AddLabeledControl(settingsGrid, "Active account", _accountSelector);
        AddLabeledControl(settingsGrid, "Account label", _accountLabelTextBox);
        AddLabeledControl(settingsGrid, "GitHub host", _hostTextBox);
        AddLabeledControl(settingsGrid, "Token env var", _tokenEnvironmentTextBox);
        AddLabeledControl(settingsGrid, "OAuth client ID", _oauthClientIdTextBox);
        AddLabeledControl(settingsGrid, "OAuth secret env", _oauthSecretEnvironmentTextBox);
        AddLabeledControl(settingsGrid, "Refresh minutes", _refreshMinutes);
        AddLabeledControl(settingsGrid, "Local scan depth", _localProjectsDepth);
        AddLabeledControl(settingsGrid, "Worktree folder", _localWorktreeFolderName);
        AddLabeledControl(settingsGrid, "Terminal", _terminalPreference);
        AddLabeledControl(settingsGrid, "Fetch interval minutes", _localProjectsFetchIntervalMinutes);
        AddLabeledControl(settingsGrid, "Archive DB path", _gitHubArchiveDatabasePath);
        AddLabeledControl(settingsGrid, "Repository limit", _repositoryDisplayLimit);
        AddLabeledControl(settingsGrid, "Repository scope", _repositoryMenuScope);
        AddLabeledControl(settingsGrid, "Repository sort", _repositorySortKey);
        AddLabeledControl(settingsGrid, "Owner filter", _repositoryOwnerFilter);
        AddLabeledControl(settingsGrid, "Repository heatmap", _heatmapDisplay);
        AddLabeledControl(settingsGrid, "Heatmap window", _heatmapSpan);
        AddLabeledControl(settingsGrid, "Activity feed", _activityScope);
        AddLabeledControl(settingsGrid, "Actions owners", _actionsMonitoredOwners);
        AddLabeledControl(settingsGrid, "Log verbosity", _loggingVerbosity);
        AddLabeledControl(settingsGrid, "PR notification click", _pullRequestNotificationClickAction);
        AddLabeledControl(settingsGrid, "Personal access token", _personalAccessTokenTextBox);
        _credentialState.AutoSize = true;
        UpdateCredentialState();
        settingsGrid.Controls.Add(new Label { Text = "Credential Manager", AutoSize = true, Anchor = AnchorStyles.Left });
        settingsGrid.Controls.Add(_credentialState);
        _oauthState.AutoSize = true;
        settingsGrid.Controls.Add(new Label { Text = "GitHub App OAuth", AutoSize = true, Anchor = AnchorStyles.Left });
        settingsGrid.Controls.Add(_oauthState);
        _tokenValidationState.AutoSize = true;
        _tokenValidationState.Text = "Not checked";
        settingsGrid.Controls.Add(new Label { Text = "Token status", AutoSize = true, Anchor = AnchorStyles.Left });
        settingsGrid.Controls.Add(_tokenValidationState);

        _openMenuOnLeftClick.Text = "Open menu on left click";
        _launchAtLogin.Text = "Launch at login";
        _discoverLocalProjects.Text = "Discover local projects";
        _fetchLocalProjectsBeforeStatus.Text = "Fetch before status";
        _autoSyncLocalProjects.Text = "Auto-sync clean behind repos";
        _showDirtyFilesInMenu.Text = "Show dirty files in menu";
        _enableResponseCache.Text = "Use response cache";
        _includeForkedRepositories.Text = "Include forked repos";
        _includeArchivedRepositories.Text = "Include archived repos";
        _showOnlyMyRepositories.Text = string.IsNullOrWhiteSpace(_viewerLogin)
            ? "Show only my repositories"
            : $"Show only my repositories ({_viewerLogin})";
        _showOnlyMyRepositories.Enabled = !string.IsNullOrWhiteSpace(_viewerLogin);
        _showOnlyMyRepositories.CheckedChanged += (_, _) => ToggleOnlyMyRepositoriesFromCheckbox();
        _repositoryOwnerFilter.TextChanged += (_, _) => SyncOnlyMyRepositoriesFromText();
        _showOnlyRepositoriesWithIssues.Text = "Only repos with issues";
        _showOnlyRepositoriesWithPullRequests.Text = "Only repos with PRs";
        _showRateLimits.Text = "Show rate limits";
        _showContributionSummary.Text = "Show contribution summary";
        _showActionsUsage.Text = "Show Actions usage";
        _actionsMonitoredOwners.PlaceholderText = "empty = auto";
        _diagnosticsEnabled.Text = "Enable diagnostics capture";
        _fileLoggingEnabled.Text = "Log to file";
        _enableGitHubReferenceMonitor.Text = "Watch clipboard references";
        _enablePullRequestNotifications.Text = "PR notifications";
        _enablePullRequestNewNotifications.Text = "Notify new PRs";
        _enablePullRequestUpdateNotifications.Text = "Notify PR updates";
        _enablePullRequestReviewRequestNotifications.Text = "Notify review requests";
        _enablePullRequestCommentNotifications.Text = "Notify PR comments";

        settingsGrid.Controls.Add(_openMenuOnLeftClick);
        settingsGrid.Controls.Add(_launchAtLogin);
        settingsGrid.Controls.Add(_discoverLocalProjects);
        settingsGrid.Controls.Add(_fetchLocalProjectsBeforeStatus);
        settingsGrid.Controls.Add(_autoSyncLocalProjects);
        settingsGrid.Controls.Add(_showDirtyFilesInMenu);
        settingsGrid.Controls.Add(_enableResponseCache);
        settingsGrid.Controls.Add(_includeForkedRepositories);
        settingsGrid.Controls.Add(_includeArchivedRepositories);
        settingsGrid.Controls.Add(_showOnlyMyRepositories);
        settingsGrid.Controls.Add(_showOnlyRepositoriesWithIssues);
        settingsGrid.Controls.Add(_showOnlyRepositoriesWithPullRequests);
        settingsGrid.Controls.Add(_showRateLimits);
        settingsGrid.Controls.Add(_showContributionSummary);
        settingsGrid.Controls.Add(_showActionsUsage);
        settingsGrid.Controls.Add(_diagnosticsEnabled);
        settingsGrid.Controls.Add(_fileLoggingEnabled);
        settingsGrid.Controls.Add(_enableGitHubReferenceMonitor);
        settingsGrid.Controls.Add(_enablePullRequestNotifications);
        settingsGrid.Controls.Add(_enablePullRequestNewNotifications);
        settingsGrid.Controls.Add(_enablePullRequestUpdateNotifications);
        settingsGrid.Controls.Add(_enablePullRequestReviewRequestNotifications);
        settingsGrid.Controls.Add(_enablePullRequestCommentNotifications);

        var localRootPanel = new Panel { Dock = DockStyle.Top, Height = 34 };
        _localProjectsRoot.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top;
        _localProjectsRoot.Width = 570;
        var browseButton = new Button { Text = "Browse", Left = 580, Width = 90 };
        browseButton.Click += (_, _) => BrowseLocalProjectsRoot();
        localRootPanel.Controls.Add(_localProjectsRoot);
        localRootPanel.Controls.Add(browseButton);
        root.Controls.Add(new Label { Text = "Local projects root", Dock = DockStyle.Top });
        root.Controls.Add(localRootPanel);

        var repositoryFilterPanel = new TableLayoutPanel
        {
            AutoSize = true,
            ColumnCount = 2,
            Dock = DockStyle.Top,
        };
        repositoryFilterPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        repositoryFilterPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        _repositoryFilterTextBox.PlaceholderText = "owner, repository, or description";
        _repositoryFilterTextBox.Anchor = AnchorStyles.Left | AnchorStyles.Right;
        repositoryFilterPanel.Controls.Add(new Label { Text = "Repository filter", AutoSize = true, Anchor = AnchorStyles.Left });
        repositoryFilterPanel.Controls.Add(_repositoryFilterTextBox);
        root.Controls.Add(repositoryFilterPanel);

        ConfigureRepositoryGrid();
        root.Controls.Add(_repositoriesGrid);

        var footer = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            Dock = DockStyle.Fill,
            AutoSize = true,
        };
        var saveButton = new Button { Text = "Save", DialogResult = DialogResult.OK };
        saveButton.Click += (_, _) => SaveSettings();
        var cancelButton = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel };
        var addButton = new Button { Text = "Add repo" };
        addButton.Click += (_, _) => _repositories.Add(new RepositoryRow("", "", RepositoryVisibility.Visible));
        var discoverButton = new Button { Text = "Discover repos" };
        discoverButton.Click += async (_, _) => await DiscoverRepositoriesAsync();
        var customizeMenuButton = new Button { Text = "Customize menu" };
        customizeMenuButton.Click += (_, _) => CustomizeMenu();
        var removeButton = new Button { Text = "Remove selected" };
        removeButton.Click += (_, _) => RemoveSelectedRepositories();
        var clearTokenButton = new Button { Text = "Clear token" };
        clearTokenButton.Click += (_, _) => ClearCredentialToken();
        var checkTokenButton = new Button { Text = "Check token" };
        checkTokenButton.Click += async (_, _) => await CheckTokenAsync();
        var createTokenButton = new Button { Text = "Create PAT" };
        createTokenButton.Click += (_, _) => OpenExternalUrl(CreateTokenUrl());
        var signInButton = new Button { Text = "Sign in with GitHub" };
        signInButton.Click += async (_, _) => await SignInWithGitHubAsync();
        var installAppButton = new Button { Text = "Install GitHub App" };
        installAppButton.Click += (_, _) => OpenExternalUrl("https://github.com/apps/repobar/installations/new");
        var refreshOAuthButton = new Button { Text = "Refresh OAuth" };
        refreshOAuthButton.Click += async (_, _) => await RefreshOAuthAsync();
        var clearOAuthButton = new Button { Text = "Clear OAuth" };
        clearOAuthButton.Click += (_, _) => ClearOAuthToken();
        var addAccountButton = new Button { Text = "Add account" };
        addAccountButton.Click += (_, _) => AddAccount();
        var removeAccountButton = new Button { Text = "Remove account" };
        removeAccountButton.Click += (_, _) => RemoveSelectedAccount();
        footer.Controls.Add(saveButton);
        footer.Controls.Add(cancelButton);
        footer.Controls.Add(removeAccountButton);
        footer.Controls.Add(addAccountButton);
        footer.Controls.Add(clearOAuthButton);
        footer.Controls.Add(refreshOAuthButton);
        footer.Controls.Add(installAppButton);
        footer.Controls.Add(signInButton);
        footer.Controls.Add(createTokenButton);
        footer.Controls.Add(checkTokenButton);
        footer.Controls.Add(clearTokenButton);
        footer.Controls.Add(removeButton);
        footer.Controls.Add(customizeMenuButton);
        footer.Controls.Add(discoverButton);
        footer.Controls.Add(addButton);
        root.Controls.Add(footer);

        AcceptButton = saveButton;
        CancelButton = cancelButton;

        var activeIndex = _accounts
            .Select((account, index) => (account, index))
            .FirstOrDefault(pair => string.Equals(pair.account.Id, _settingsStore.Settings.ActiveAccountId, StringComparison.OrdinalIgnoreCase))
            .index;
        _accountSelector.SelectedIndex = activeIndex < 0 ? 0 : activeIndex;
        SelectAccountFromCombo();
    }

    private static void AddLabeledControl(TableLayoutPanel table, string label, Control control)
    {
        table.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left });
        control.Anchor = AnchorStyles.Left | AnchorStyles.Right;
        table.Controls.Add(control);
    }

    private void SelectAccountFromCombo()
    {
        if (_loadingAccount)
        {
            return;
        }

        if (_selectedAccount != null)
        {
            SaveAccountFields(_selectedAccount);
        }

        if (_accountSelector.SelectedItem is AccountRow selected)
        {
            LoadAccountFields(selected);
        }
    }

    private void LoadAccountFields(AccountRow account)
    {
        _loadingAccount = true;
        _selectedAccount = account;
        _accountLabelTextBox.Text = account.Label;
        _hostTextBox.Text = account.GitHubHost;
        _tokenEnvironmentTextBox.Text = account.TokenEnvironmentVariable;
        _oauthClientIdTextBox.Text = account.GitHubOAuthClientId;
        _oauthSecretEnvironmentTextBox.Text = account.GitHubOAuthClientSecretEnvironmentVariable;
        _loadingAccount = false;
        UpdateCredentialState();
    }

    private void SaveAccountFields(AccountRow account)
    {
        account.Label = string.IsNullOrWhiteSpace(_accountLabelTextBox.Text) ? account.Id : _accountLabelTextBox.Text.Trim();
        account.GitHubHost = GitHubHost.Normalize(_hostTextBox.Text);
        account.TokenEnvironmentVariable = _tokenEnvironmentTextBox.Text.Trim();
        account.GitHubOAuthClientId = string.IsNullOrWhiteSpace(_oauthClientIdTextBox.Text)
            ? WindowsOAuthClient.DefaultClientId
            : _oauthClientIdTextBox.Text.Trim();
        account.GitHubOAuthClientSecretEnvironmentVariable = string.IsNullOrWhiteSpace(_oauthSecretEnvironmentTextBox.Text)
            ? WindowsOAuthClient.DefaultClientSecretEnvironmentVariable
            : _oauthSecretEnvironmentTextBox.Text.Trim();
        _accountSelector.Refresh();
    }

    private void AddAccount()
    {
        SaveSelectedAccountFields();
        var id = NextAccountId();
        var account = new AccountRow(
            id,
            $"Account {_accounts.Count + 1}",
            GitHubHost.Normalize(_hostTextBox.Text),
            _tokenEnvironmentTextBox.Text.Trim(),
            _oauthClientIdTextBox.Text.Trim(),
            _oauthSecretEnvironmentTextBox.Text.Trim());
        _accounts.Add(account);
        _accountSelector.SelectedItem = account;
    }

    private void RemoveSelectedAccount()
    {
        if (_accounts.Count <= 1 || _accountSelector.SelectedItem is not AccountRow account)
        {
            return;
        }

        var index = _accountSelector.SelectedIndex;
        _accounts.Remove(account);
        _selectedAccount = null;
        _accountSelector.SelectedIndex = Math.Clamp(index - 1, 0, _accounts.Count - 1);
        SelectAccountFromCombo();
    }

    private void SaveSelectedAccountFields()
    {
        if (_selectedAccount != null)
        {
            SaveAccountFields(_selectedAccount);
        }
    }

    private void ToggleOnlyMyRepositoriesFromCheckbox()
    {
        if (_updatingOwnerFilterControls || string.IsNullOrWhiteSpace(_viewerLogin))
        {
            return;
        }

        SetOwnerFilterText(_showOnlyMyRepositories.Checked ? [_viewerLogin] : []);
    }

    private void SyncOnlyMyRepositoriesFromText()
    {
        if (_updatingOwnerFilterControls)
        {
            return;
        }

        _updatingOwnerFilterControls = true;
        _showOnlyMyRepositories.Checked = WindowsRepositoryOwnerFilter.IsOnlyViewer(
            ParseRepositoryOwnerFilter(_repositoryOwnerFilter.Text),
            _viewerLogin);
        _updatingOwnerFilterControls = false;
    }

    private void SetOwnerFilterText(IEnumerable<string> owners)
    {
        _updatingOwnerFilterControls = true;
        _repositoryOwnerFilter.Text = FormatRepositoryOwnerFilter(owners);
        _showOnlyMyRepositories.Checked = WindowsRepositoryOwnerFilter.IsOnlyViewer(
            ParseRepositoryOwnerFilter(_repositoryOwnerFilter.Text),
            _viewerLogin);
        _updatingOwnerFilterControls = false;
    }

    private string NextAccountId()
    {
        var used = _accounts.Select(account => account.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
        for (var index = _accounts.Count + 1; ; index++)
        {
            var id = $"account-{index}";
            if (!used.Contains(id))
            {
                return id;
            }
        }
    }

    private void ConfigureRepositoryGrid()
    {
        _repositoriesGrid.Dock = DockStyle.Fill;
        _repositoriesGrid.AutoGenerateColumns = false;
        _repositoriesGrid.AllowUserToAddRows = false;
        _repositoriesGrid.AllowUserToDeleteRows = true;
        _repositoriesGrid.DataSource = _repositories;
        _repositoriesGrid.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(RepositoryRow.Owner),
            HeaderText = "Owner",
            AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill,
        });
        _repositoriesGrid.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(RepositoryRow.Name),
            HeaderText = "Repository",
            AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill,
        });
        _repositoriesGrid.Columns.Add(new DataGridViewComboBoxColumn
        {
            DataPropertyName = nameof(RepositoryRow.Visibility),
            HeaderText = "Visibility",
            DataSource = Enum.GetValues<RepositoryVisibility>(),
            Width = 120,
        });
    }

    private void BrowseLocalProjectsRoot()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Choose the folder RepoBar scans for local git repositories.",
            SelectedPath = Directory.Exists(_localProjectsRoot.Text) ? _localProjectsRoot.Text : "",
            UseDescriptionForTitle = true,
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            _localProjectsRoot.Text = dialog.SelectedPath;
        }
    }

    private void RemoveSelectedRepositories()
    {
        foreach (DataGridViewRow row in _repositoriesGrid.SelectedRows)
        {
            if (row.DataBoundItem is RepositoryRow repository)
            {
                _repositories.Remove(repository);
            }
        }
    }

    private void CustomizeMenu()
    {
        using var form = new MenuCustomizationForm(_menuCustomization);
        form.ShowDialog(this);
    }

    private async Task DiscoverRepositoriesAsync()
    {
        SaveCredentialTokenIfNeeded();
        try
        {
            using var client = new GitHubRepositoryDiscoveryClient(CurrentSettingsSnapshot(), ResolveTokenForSnapshot());
            var repositories = await client.LoadAccessibleRepositoriesAsync(
                CancellationToken.None,
                _repositoryFilterTextBox.Text).ConfigureAwait(true);
            var existing = _repositories
                .Where(repository => !string.IsNullOrWhiteSpace(repository.Owner) && !string.IsNullOrWhiteSpace(repository.Name))
                .ToDictionary(repository => $"{repository.Owner}/{repository.Name}", StringComparer.OrdinalIgnoreCase);
            var added = 0;
            foreach (var repository in repositories)
            {
                if (existing.ContainsKey(repository.FullName))
                {
                    continue;
                }

                var row = new RepositoryRow(repository.Owner, repository.Name, RepositoryVisibility.Visible);
                _repositories.Add(row);
                existing[repository.FullName] = row;
                added++;
            }

            MessageBox.Show(
                added == 0 ? "No new repositories found." : $"Added {added} repositories.",
                "RepoBar Repository Discovery",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "RepoBar Repository Discovery", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void SaveSettings()
    {
        _repositoriesGrid.EndEdit();
        SaveSelectedAccountFields();
        var settings = _settingsStore.Settings;
        var activeAccount = CurrentAccountRow();
        settings.Accounts = _accounts.Select(account => account.ToProfile()).ToList();
        settings.ActiveAccountId = activeAccount.Id;
        settings.GitHubHost = activeAccount.GitHubHost;
        settings.TokenEnvironmentVariable = activeAccount.TokenEnvironmentVariable;
        settings.GitHubOAuthClientId = activeAccount.GitHubOAuthClientId;
        settings.GitHubOAuthClientSecretEnvironmentVariable = activeAccount.GitHubOAuthClientSecretEnvironmentVariable;
        settings.RefreshIntervalMinutes = (int)_refreshMinutes.Value;
        settings.OpenMenuOnLeftClick = _openMenuOnLeftClick.Checked;
        settings.LaunchAtLogin = _launchAtLogin.Checked;
        new WindowsLaunchAtLogin().SetEnabled(settings.LaunchAtLogin, Application.ExecutablePath);
        settings.DiscoverLocalProjects = _discoverLocalProjects.Checked;
        settings.LocalProjectsRoot = string.IsNullOrWhiteSpace(_localProjectsRoot.Text) ? null : _localProjectsRoot.Text.Trim();
        settings.LocalProjectsMaxDepth = (int)_localProjectsDepth.Value;
        settings.LocalWorktreeFolderName = string.IsNullOrWhiteSpace(_localWorktreeFolderName.Text) ? ".work" : _localWorktreeFolderName.Text.Trim();
        settings.TerminalPreference = _terminalPreference.SelectedValue is WindowsTerminalPreference terminalPreference
            ? terminalPreference
            : WindowsTerminalPreference.Auto;
        settings.FetchLocalProjectsBeforeStatus = _fetchLocalProjectsBeforeStatus.Checked;
        settings.LocalProjectsFetchIntervalMinutes = (int)_localProjectsFetchIntervalMinutes.Value;
        settings.AutoSyncLocalProjects = _autoSyncLocalProjects.Checked;
        settings.ShowDirtyFilesInMenu = _showDirtyFilesInMenu.Checked;
        settings.EnableResponseCache = _enableResponseCache.Checked;
        settings.GitHubArchiveDatabasePath = string.IsNullOrWhiteSpace(_gitHubArchiveDatabasePath.Text)
            ? null
            : _gitHubArchiveDatabasePath.Text.Trim();
        settings.RepositoryDisplayLimit = (int)_repositoryDisplayLimit.Value;
        settings.RepositoryMenuScope = _repositoryMenuScope.SelectedValue is RepositoryMenuScope menuScope
            ? menuScope
            : RepositoryMenuScope.All;
        settings.RepositorySortKey = _repositorySortKey.SelectedValue is RepositorySortKey sortKey
            ? sortKey
            : RepositorySortKey.Activity;
        settings.IncludeForkedRepositories = _includeForkedRepositories.Checked;
        settings.IncludeArchivedRepositories = _includeArchivedRepositories.Checked;
        settings.RepositoryOwnerFilter = ParseRepositoryOwnerFilter(_repositoryOwnerFilter.Text);
        settings.ShowOnlyRepositoriesWithIssues = _showOnlyRepositoriesWithIssues.Checked;
        settings.ShowOnlyRepositoriesWithPullRequests = _showOnlyRepositoriesWithPullRequests.Checked;
        settings.HeatmapDisplay = _heatmapDisplay.SelectedValue is WindowsHeatmapDisplay heatmapDisplay
            ? heatmapDisplay
            : WindowsHeatmapDisplay.RowAndSubmenu;
        settings.HeatmapSpan = _heatmapSpan.SelectedValue is WindowsHeatmapSpan heatmapSpan
            ? heatmapSpan
            : WindowsHeatmapSpan.TwelveMonths;
        settings.ActivityScope = _activityScope.SelectedValue is WindowsActivityScope activityScope
            ? activityScope
            : WindowsActivityScope.MyActivity;
        settings.ShowRateLimits = _showRateLimits.Checked;
        settings.ShowContributionSummary = _showContributionSummary.Checked;
        settings.ShowActionsUsage = _showActionsUsage.Checked;
        settings.ActionsMonitoredOwners = ParseRepositoryOwnerFilter(_actionsMonitoredOwners.Text);
        settings.DiagnosticsEnabled = _diagnosticsEnabled.Checked;
        settings.LoggingVerbosity = _loggingVerbosity.SelectedValue is WindowsLogVerbosity verbosity
            ? verbosity
            : WindowsLogVerbosity.Info;
        settings.FileLoggingEnabled = _fileLoggingEnabled.Checked;
        WindowsDiagnosticsLogger.Configure(settings.LoggingVerbosity, settings.FileLoggingEnabled);
        settings.EnableGitHubReferenceMonitor = _enableGitHubReferenceMonitor.Checked;
        settings.EnablePullRequestNotifications = _enablePullRequestNotifications.Checked;
        settings.EnablePullRequestNewNotifications = _enablePullRequestNewNotifications.Checked;
        settings.EnablePullRequestUpdateNotifications = _enablePullRequestUpdateNotifications.Checked;
        settings.EnablePullRequestReviewRequestNotifications = _enablePullRequestReviewRequestNotifications.Checked;
        settings.EnablePullRequestCommentNotifications = _enablePullRequestCommentNotifications.Checked;
        settings.PullRequestNotificationClickAction = _pullRequestNotificationClickAction.SelectedValue is PullRequestNotificationClickAction action
            ? action
            : PullRequestNotificationClickAction.OpenInBrowser;
        settings.MenuCustomization = _menuCustomization.Copy();
        WindowsSettingsStore.NormalizeSettings(settings);

        _settingsStore.ReplaceRepositories(_repositories
            .Where(repository => !string.IsNullOrWhiteSpace(repository.Owner) && !string.IsNullOrWhiteSpace(repository.Name))
            .Select(repository => new RepositoryRef
            {
                Owner = repository.Owner,
                Name = repository.Name,
                Visibility = repository.Visibility,
            }));

        SaveCredentialTokenIfNeeded();
    }

    private WindowsSettings CurrentSettingsSnapshot()
    {
        SaveSelectedAccountFields();
        var activeAccount = CurrentAccountRow();
        return new WindowsSettings
        {
            ActiveAccountId = activeAccount.Id,
            GitHubHost = activeAccount.GitHubHost,
            TokenEnvironmentVariable = activeAccount.TokenEnvironmentVariable,
            GitHubOAuthClientId = activeAccount.GitHubOAuthClientId,
            GitHubOAuthClientSecretEnvironmentVariable = activeAccount.GitHubOAuthClientSecretEnvironmentVariable,
            GitHubArchiveDatabasePath = string.IsNullOrWhiteSpace(_gitHubArchiveDatabasePath.Text)
                ? null
                : _gitHubArchiveDatabasePath.Text.Trim(),
            IncludeForkedRepositories = _includeForkedRepositories.Checked,
            IncludeArchivedRepositories = _includeArchivedRepositories.Checked,
            RepositoryMenuScope = _repositoryMenuScope.SelectedValue is RepositoryMenuScope menuScope
                ? menuScope
                : RepositoryMenuScope.All,
            RepositoryOwnerFilter = ParseRepositoryOwnerFilter(_repositoryOwnerFilter.Text),
            ShowOnlyRepositoriesWithIssues = _showOnlyRepositoriesWithIssues.Checked,
            ShowOnlyRepositoriesWithPullRequests = _showOnlyRepositoriesWithPullRequests.Checked,
            ActivityScope = _activityScope.SelectedValue is WindowsActivityScope activityScope
                ? activityScope
                : WindowsActivityScope.MyActivity,
            ActionsMonitoredOwners = ParseRepositoryOwnerFilter(_actionsMonitoredOwners.Text),
            Accounts = _accounts.Select(account => account.ToProfile()).ToList(),
        };
    }

    private static string FormatRepositoryOwnerFilter(IEnumerable<string> owners)
    {
        return string.Join(", ", WindowsSettingsStore.NormalizeRepositoryOwnerFilter(owners));
    }

    private static List<string> ParseRepositoryOwnerFilter(string value)
    {
        return WindowsSettingsStore.NormalizeRepositoryOwnerFilter(
            value.Split([',', ';', ' ', '\r', '\n', '\t'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
    }

    private string? ResolveTokenForSnapshot()
    {
        var snapshot = CurrentSettingsSnapshot();
        var account = snapshot.GetActiveAccount();
        var oauthToken = new WindowsOAuthTokenStore(account.GitHubHost, account.Id).ReadTokens()?.AccessToken;
        if (!string.IsNullOrWhiteSpace(oauthToken))
        {
            return oauthToken;
        }

        if (!string.IsNullOrWhiteSpace(_personalAccessTokenTextBox.Text))
        {
            return _personalAccessTokenTextBox.Text;
        }

        var credentialToken = new WindowsCredentialStore(account.GitHubHost, account.Id).ReadToken();
        if (!string.IsNullOrWhiteSpace(credentialToken))
        {
            return credentialToken;
        }

        if (!string.IsNullOrWhiteSpace(account.TokenEnvironmentVariable))
        {
            var configuredToken = Environment.GetEnvironmentVariable(account.TokenEnvironmentVariable);
            if (!string.IsNullOrWhiteSpace(configuredToken))
            {
                return configuredToken;
            }
        }

        return Environment.GetEnvironmentVariable("REPOBAR_GITHUB_TOKEN") ??
            Environment.GetEnvironmentVariable("GITHUB_TOKEN") ??
            Environment.GetEnvironmentVariable("GH_TOKEN");
    }

    private string CreateTokenUrl()
    {
        var account = CurrentSettingsSnapshot().GetActiveAccount();
        return $"https://{GitHubHost.Normalize(account.GitHubHost)}/settings/tokens/new?scopes=repo,read:org&description=RepoBar";
    }

    private static void OpenExternalUrl(string url)
    {
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }

    private void SaveCredentialTokenIfNeeded()
    {
        if (string.IsNullOrWhiteSpace(_personalAccessTokenTextBox.Text))
        {
            return;
        }

        try
        {
            var snapshot = CurrentSettingsSnapshot();
            var account = snapshot.GetActiveAccount();
            new WindowsCredentialStore(account.GitHubHost, account.Id).SaveToken(_personalAccessTokenTextBox.Text);
            _personalAccessTokenTextBox.Clear();
            UpdateCredentialState();
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "RepoBar Credential Manager", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void ClearCredentialToken()
    {
        try
        {
            var snapshot = CurrentSettingsSnapshot();
            var account = snapshot.GetActiveAccount();
            new WindowsCredentialStore(account.GitHubHost, account.Id).ClearToken();
            _personalAccessTokenTextBox.Clear();
            UpdateCredentialState();
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "RepoBar Credential Manager", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private async Task SignInWithGitHubAsync()
    {
        try
        {
            var snapshot = CurrentSettingsSnapshot();
            var account = snapshot.GetActiveAccount();
            using var client = new WindowsOAuthClient();
            var tokens = await client.LoginAsync(snapshot, CancellationToken.None).ConfigureAwait(true);
            new WindowsOAuthTokenStore(account.GitHubHost, account.Id).SaveTokens(tokens);
            UpdateCredentialState();
            MessageBox.Show("GitHub sign-in complete.", "RepoBar GitHub Sign-In", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "RepoBar GitHub Sign-In", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private async Task CheckTokenAsync()
    {
        SaveCredentialTokenIfNeeded();
        try
        {
            var snapshot = CurrentSettingsSnapshot();
            using var validator = new WindowsTokenValidator(snapshot, ResolveTokenForSnapshot());
            var result = await validator.ValidateAsync(CancellationToken.None).ConfigureAwait(true);
            _tokenValidationState.Text = result.Message;
        }
        catch (Exception exception)
        {
            _tokenValidationState.Text = $"Token check failed: {exception.Message}";
        }
    }

    private async Task RefreshOAuthAsync()
    {
        try
        {
            var snapshot = CurrentSettingsSnapshot();
            var account = snapshot.GetActiveAccount();
            var store = new WindowsOAuthTokenStore(account.GitHubHost, account.Id);
            var tokens = store.ReadTokens();
            if (tokens == null)
            {
                _tokenValidationState.Text = "No OAuth token stored.";
                return;
            }
            if (string.IsNullOrWhiteSpace(tokens.RefreshToken))
            {
                _tokenValidationState.Text = "Stored OAuth token has no refresh token.";
                return;
            }

            using var client = new WindowsOAuthClient();
            var refreshed = await client.RefreshAsync(snapshot, tokens, CancellationToken.None).ConfigureAwait(true);
            store.SaveTokens(refreshed);
            UpdateCredentialState();
            _tokenValidationState.Text = "OAuth token refreshed.";
        }
        catch (Exception exception)
        {
            _tokenValidationState.Text = $"OAuth refresh failed: {exception.Message}";
        }
    }

    private void ClearOAuthToken()
    {
        try
        {
            var snapshot = CurrentSettingsSnapshot();
            var account = snapshot.GetActiveAccount();
            new WindowsOAuthTokenStore(account.GitHubHost, account.Id).ClearTokens();
            UpdateCredentialState();
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "RepoBar GitHub Sign-In", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void UpdateCredentialState()
    {
        var account = _selectedAccount ?? CurrentAccountRow();
        var store = new WindowsCredentialStore(account.GitHubHost, account.Id);
        _credentialState.Text = store.HasToken()
            ? $"PAT stored as {store.TargetName}"
            : $"No PAT stored ({store.TargetName})";
        var oauthStore = new WindowsOAuthTokenStore(account.GitHubHost, account.Id);
        _oauthState.Text = oauthStore.ReadTokens() == null
            ? $"No OAuth token ({oauthStore.TargetName})"
            : $"OAuth stored as {oauthStore.TargetName}";
    }

    private AccountRow CurrentAccountRow()
    {
        if (_accountSelector.SelectedItem is AccountRow row)
        {
            return row;
        }
        return _accounts.Count == 0
            ? AccountRow.FromProfile(WindowsAccountProfile.FromLegacy(_settingsStore.Settings))
            : _accounts[0];
    }

    private sealed class RepositoryRow
    {
        public RepositoryRow(string owner, string name, RepositoryVisibility visibility)
        {
            Owner = owner;
            Name = name;
            Visibility = visibility;
        }

        public string Owner { get; set; }
        public string Name { get; set; }
        public RepositoryVisibility Visibility { get; set; }
    }

    private sealed class AccountRow
    {
        public AccountRow(
            string id,
            string label,
            string gitHubHost,
            string tokenEnvironmentVariable,
            string gitHubOAuthClientId,
            string gitHubOAuthClientSecretEnvironmentVariable)
        {
            Id = WindowsSettingsStore.SanitizeAccountId(id);
            Label = label;
            GitHubHost = RepoBar.Windows.GitHubHost.Normalize(gitHubHost);
            TokenEnvironmentVariable = string.IsNullOrWhiteSpace(tokenEnvironmentVariable) ? "REPOBAR_GITHUB_TOKEN" : tokenEnvironmentVariable;
            GitHubOAuthClientId = string.IsNullOrWhiteSpace(gitHubOAuthClientId) ? WindowsOAuthClient.DefaultClientId : gitHubOAuthClientId;
            GitHubOAuthClientSecretEnvironmentVariable = string.IsNullOrWhiteSpace(gitHubOAuthClientSecretEnvironmentVariable)
                ? WindowsOAuthClient.DefaultClientSecretEnvironmentVariable
                : gitHubOAuthClientSecretEnvironmentVariable;
        }

        public string Id { get; }
        public string Label { get; set; }
        public string GitHubHost { get; set; }
        public string TokenEnvironmentVariable { get; set; }
        public string GitHubOAuthClientId { get; set; }
        public string GitHubOAuthClientSecretEnvironmentVariable { get; set; }
        public string DisplayName => $"{Label} ({GitHubHost})";

        public static AccountRow FromProfile(WindowsAccountProfile profile)
        {
            return new AccountRow(
                profile.Id,
                profile.DisplayName,
                profile.GitHubHost,
                profile.TokenEnvironmentVariable,
                profile.GitHubOAuthClientId,
                profile.GitHubOAuthClientSecretEnvironmentVariable);
        }

        public WindowsAccountProfile ToProfile()
        {
            return new WindowsAccountProfile
            {
                Id = Id,
                Label = Label,
                GitHubHost = GitHubHost,
                TokenEnvironmentVariable = TokenEnvironmentVariable,
                GitHubOAuthClientId = GitHubOAuthClientId,
                GitHubOAuthClientSecretEnvironmentVariable = GitHubOAuthClientSecretEnvironmentVariable,
            };
        }
    }

    private sealed record NotificationClickActionRow(PullRequestNotificationClickAction Action, string DisplayName)
    {
        public static NotificationClickActionRow FromAction(PullRequestNotificationClickAction action)
        {
            return new NotificationClickActionRow(action, action.DisplayName());
        }
    }

    private sealed record LogVerbosityRow(WindowsLogVerbosity Verbosity, string DisplayName)
    {
        public static LogVerbosityRow FromVerbosity(WindowsLogVerbosity verbosity)
        {
            return new LogVerbosityRow(verbosity, verbosity.DisplayName());
        }
    }

    private sealed record RepositorySortKeyRow(RepositorySortKey SortKey, string DisplayName)
    {
        public static RepositorySortKeyRow FromSortKey(RepositorySortKey sortKey)
        {
            return new RepositorySortKeyRow(sortKey, sortKey.DisplayName());
        }
    }

    private sealed record RepositoryMenuScopeRow(RepositoryMenuScope Scope, string DisplayName)
    {
        public static RepositoryMenuScopeRow FromScope(RepositoryMenuScope scope)
        {
            return new RepositoryMenuScopeRow(scope, scope.DisplayName());
        }
    }

    private sealed record HeatmapDisplayRow(WindowsHeatmapDisplay Display, string DisplayName)
    {
        public static HeatmapDisplayRow FromDisplay(WindowsHeatmapDisplay display)
        {
            return new HeatmapDisplayRow(display, display.DisplayName());
        }
    }

    private sealed record HeatmapSpanRow(WindowsHeatmapSpan Span, string DisplayName)
    {
        public static HeatmapSpanRow FromSpan(WindowsHeatmapSpan span)
        {
            return new HeatmapSpanRow(span, span.DisplayName());
        }
    }

    private sealed record ActivityScopeRow(WindowsActivityScope Scope, string DisplayName)
    {
        public static ActivityScopeRow FromScope(WindowsActivityScope scope)
        {
            return new ActivityScopeRow(scope, scope.DisplayName());
        }
    }

    private sealed record TerminalPreferenceRow(WindowsTerminalPreference Preference, string DisplayName)
    {
        public static TerminalPreferenceRow FromPreference(WindowsTerminalPreference preference)
        {
            return new TerminalPreferenceRow(preference, preference.DisplayName());
        }
    }
}
