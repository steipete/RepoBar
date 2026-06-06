using System.ComponentModel;
using System.Drawing;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class SettingsEditorForm : Form
{
    private readonly WindowsSettingsStore _settingsStore;
    private readonly Label _credentialState = new();
    private readonly Label _oauthState = new();
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
    private readonly CheckBox _fetchLocalProjectsBeforeStatus = new();
    private readonly CheckBox _autoSyncLocalProjects = new();
    private readonly CheckBox _enableResponseCache = new();
    private readonly TextBox _gitHubArchiveDatabasePath = new();
    private readonly NumericUpDown _repositoryDisplayLimit = new();
    private readonly ComboBox _repositorySortKey = new();
    private readonly CheckBox _showRateLimits = new();
    private readonly CheckBox _showContributionSummary = new();
    private readonly CheckBox _showActionsUsage = new();
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
    private bool _loadingAccount;

    public SettingsEditorForm(WindowsSettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
        Text = "RepoBar Preferences";
        StartPosition = FormStartPosition.CenterScreen;
        MinimizeBox = false;
        MaximizeBox = false;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        ClientSize = new Size(820, 620);

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
        _fetchLocalProjectsBeforeStatus.Checked = settings.FetchLocalProjectsBeforeStatus;
        _autoSyncLocalProjects.Checked = settings.AutoSyncLocalProjects;
        _enableResponseCache.Checked = settings.EnableResponseCache;
        _gitHubArchiveDatabasePath.Text = settings.GitHubArchiveDatabasePath ?? "";
        _repositoryDisplayLimit.Minimum = 1;
        _repositoryDisplayLimit.Maximum = 100;
        _repositoryDisplayLimit.Value = Math.Clamp(settings.RepositoryDisplayLimit, 1, 100);
        _repositorySortKey.DropDownStyle = ComboBoxStyle.DropDownList;
        _repositorySortKey.DataSource = Enum.GetValues<RepositorySortKey>()
            .Select(RepositorySortKeyRow.FromSortKey)
            .ToArray();
        _repositorySortKey.DisplayMember = nameof(RepositorySortKeyRow.DisplayName);
        _repositorySortKey.ValueMember = nameof(RepositorySortKeyRow.SortKey);
        _repositorySortKey.SelectedValue = settings.RepositorySortKey;
        _showRateLimits.Checked = settings.ShowRateLimits;
        _showContributionSummary.Checked = settings.ShowContributionSummary;
        _showActionsUsage.Checked = settings.ShowActionsUsage;
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
        AddLabeledControl(settingsGrid, "Archive DB path", _gitHubArchiveDatabasePath);
        AddLabeledControl(settingsGrid, "Repository limit", _repositoryDisplayLimit);
        AddLabeledControl(settingsGrid, "Repository sort", _repositorySortKey);
        AddLabeledControl(settingsGrid, "PR notification click", _pullRequestNotificationClickAction);
        AddLabeledControl(settingsGrid, "Personal access token", _personalAccessTokenTextBox);
        _credentialState.AutoSize = true;
        UpdateCredentialState();
        settingsGrid.Controls.Add(new Label { Text = "Credential Manager", AutoSize = true, Anchor = AnchorStyles.Left });
        settingsGrid.Controls.Add(_credentialState);
        _oauthState.AutoSize = true;
        settingsGrid.Controls.Add(new Label { Text = "GitHub App OAuth", AutoSize = true, Anchor = AnchorStyles.Left });
        settingsGrid.Controls.Add(_oauthState);

        _openMenuOnLeftClick.Text = "Open menu on left click";
        _launchAtLogin.Text = "Launch at login";
        _discoverLocalProjects.Text = "Discover local projects";
        _fetchLocalProjectsBeforeStatus.Text = "Fetch before status";
        _autoSyncLocalProjects.Text = "Auto-sync clean behind repos";
        _enableResponseCache.Text = "Use response cache";
        _showRateLimits.Text = "Show rate limits";
        _showContributionSummary.Text = "Show contribution summary";
        _showActionsUsage.Text = "Show Actions usage";
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
        settingsGrid.Controls.Add(_enableResponseCache);
        settingsGrid.Controls.Add(_showRateLimits);
        settingsGrid.Controls.Add(_showContributionSummary);
        settingsGrid.Controls.Add(_showActionsUsage);
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
        var signInButton = new Button { Text = "Sign in with GitHub" };
        signInButton.Click += async (_, _) => await SignInWithGitHubAsync();
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
        footer.Controls.Add(signInButton);
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
        settings.FetchLocalProjectsBeforeStatus = _fetchLocalProjectsBeforeStatus.Checked;
        settings.AutoSyncLocalProjects = _autoSyncLocalProjects.Checked;
        settings.EnableResponseCache = _enableResponseCache.Checked;
        settings.GitHubArchiveDatabasePath = string.IsNullOrWhiteSpace(_gitHubArchiveDatabasePath.Text)
            ? null
            : _gitHubArchiveDatabasePath.Text.Trim();
        settings.RepositoryDisplayLimit = (int)_repositoryDisplayLimit.Value;
        settings.RepositorySortKey = _repositorySortKey.SelectedValue is RepositorySortKey sortKey
            ? sortKey
            : RepositorySortKey.Activity;
        settings.ShowRateLimits = _showRateLimits.Checked;
        settings.ShowContributionSummary = _showContributionSummary.Checked;
        settings.ShowActionsUsage = _showActionsUsage.Checked;
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
            Accounts = _accounts.Select(account => account.ToProfile()).ToList(),
        };
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

    private sealed record RepositorySortKeyRow(RepositorySortKey SortKey, string DisplayName)
    {
        public static RepositorySortKeyRow FromSortKey(RepositorySortKey sortKey)
        {
            return new RepositorySortKeyRow(sortKey, sortKey.DisplayName());
        }
    }
}
