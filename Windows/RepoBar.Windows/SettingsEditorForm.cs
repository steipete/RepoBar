using System.ComponentModel;
using System.Drawing;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class SettingsEditorForm : Form
{
    private readonly WindowsSettingsStore _settingsStore;
    private readonly Label _credentialState = new();
    private readonly Label _oauthState = new();
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
    private readonly CheckBox _fetchLocalProjectsBeforeStatus = new();
    private readonly CheckBox _autoSyncLocalProjects = new();
    private readonly CheckBox _enableResponseCache = new();
    private readonly CheckBox _showRateLimits = new();
    private readonly CheckBox _showContributionSummary = new();
    private readonly CheckBox _showActionsUsage = new();
    private readonly CheckBox _enablePullRequestNotifications = new();
    private readonly BindingList<RepositoryRow> _repositories = [];
    private readonly DataGridView _repositoriesGrid = new();

    public SettingsEditorForm(WindowsSettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
        Text = "RepoBar Preferences";
        StartPosition = FormStartPosition.CenterScreen;
        MinimizeBox = false;
        MaximizeBox = false;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        ClientSize = new Size(820, 590);

        LoadSettings();
        BuildControls();
    }

    private void LoadSettings()
    {
        var settings = _settingsStore.Settings;
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
        _fetchLocalProjectsBeforeStatus.Checked = settings.FetchLocalProjectsBeforeStatus;
        _autoSyncLocalProjects.Checked = settings.AutoSyncLocalProjects;
        _enableResponseCache.Checked = settings.EnableResponseCache;
        _showRateLimits.Checked = settings.ShowRateLimits;
        _showContributionSummary.Checked = settings.ShowContributionSummary;
        _showActionsUsage.Checked = settings.ShowActionsUsage;
        _enablePullRequestNotifications.Checked = settings.EnablePullRequestNotifications;

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
            RowCount = 5,
            Padding = new Padding(12),
        };
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
        AddLabeledControl(settingsGrid, "GitHub host", _hostTextBox);
        AddLabeledControl(settingsGrid, "Token env var", _tokenEnvironmentTextBox);
        AddLabeledControl(settingsGrid, "OAuth client ID", _oauthClientIdTextBox);
        AddLabeledControl(settingsGrid, "OAuth secret env", _oauthSecretEnvironmentTextBox);
        AddLabeledControl(settingsGrid, "Refresh minutes", _refreshMinutes);
        AddLabeledControl(settingsGrid, "Local scan depth", _localProjectsDepth);
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
        _enablePullRequestNotifications.Text = "PR notifications";

        settingsGrid.Controls.Add(_openMenuOnLeftClick);
        settingsGrid.Controls.Add(_launchAtLogin);
        settingsGrid.Controls.Add(_discoverLocalProjects);
        settingsGrid.Controls.Add(_fetchLocalProjectsBeforeStatus);
        settingsGrid.Controls.Add(_autoSyncLocalProjects);
        settingsGrid.Controls.Add(_enableResponseCache);
        settingsGrid.Controls.Add(_showRateLimits);
        settingsGrid.Controls.Add(_showContributionSummary);
        settingsGrid.Controls.Add(_showActionsUsage);
        settingsGrid.Controls.Add(_enablePullRequestNotifications);

        var localRootPanel = new Panel { Dock = DockStyle.Top, Height = 34 };
        _localProjectsRoot.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top;
        _localProjectsRoot.Width = 570;
        var browseButton = new Button { Text = "Browse", Left = 580, Width = 90 };
        browseButton.Click += (_, _) => BrowseLocalProjectsRoot();
        localRootPanel.Controls.Add(_localProjectsRoot);
        localRootPanel.Controls.Add(browseButton);
        root.Controls.Add(new Label { Text = "Local projects root", Dock = DockStyle.Top });
        root.Controls.Add(localRootPanel);

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
        var removeButton = new Button { Text = "Remove selected" };
        removeButton.Click += (_, _) => RemoveSelectedRepositories();
        var clearTokenButton = new Button { Text = "Clear token" };
        clearTokenButton.Click += (_, _) => ClearCredentialToken();
        var signInButton = new Button { Text = "Sign in with GitHub" };
        signInButton.Click += async (_, _) => await SignInWithGitHubAsync();
        var clearOAuthButton = new Button { Text = "Clear OAuth" };
        clearOAuthButton.Click += (_, _) => ClearOAuthToken();
        footer.Controls.Add(saveButton);
        footer.Controls.Add(cancelButton);
        footer.Controls.Add(clearOAuthButton);
        footer.Controls.Add(signInButton);
        footer.Controls.Add(clearTokenButton);
        footer.Controls.Add(removeButton);
        footer.Controls.Add(discoverButton);
        footer.Controls.Add(addButton);
        root.Controls.Add(footer);

        AcceptButton = saveButton;
        CancelButton = cancelButton;
    }

    private static void AddLabeledControl(TableLayoutPanel table, string label, Control control)
    {
        table.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left });
        control.Anchor = AnchorStyles.Left | AnchorStyles.Right;
        table.Controls.Add(control);
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

    private async Task DiscoverRepositoriesAsync()
    {
        SaveCredentialTokenIfNeeded();
        try
        {
            using var client = new GitHubRepositoryDiscoveryClient(CurrentSettingsSnapshot(), ResolveTokenForSnapshot());
            var repositories = await client.LoadAccessibleRepositoriesAsync(CancellationToken.None).ConfigureAwait(true);
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
        var settings = _settingsStore.Settings;
        settings.GitHubHost = GitHubHost.Normalize(_hostTextBox.Text);
        _hostTextBox.Text = settings.GitHubHost;
        settings.TokenEnvironmentVariable = _tokenEnvironmentTextBox.Text.Trim();
        settings.GitHubOAuthClientId = string.IsNullOrWhiteSpace(_oauthClientIdTextBox.Text)
            ? WindowsOAuthClient.DefaultClientId
            : _oauthClientIdTextBox.Text.Trim();
        _oauthClientIdTextBox.Text = settings.GitHubOAuthClientId;
        settings.GitHubOAuthClientSecretEnvironmentVariable = string.IsNullOrWhiteSpace(_oauthSecretEnvironmentTextBox.Text)
            ? WindowsOAuthClient.DefaultClientSecretEnvironmentVariable
            : _oauthSecretEnvironmentTextBox.Text.Trim();
        _oauthSecretEnvironmentTextBox.Text = settings.GitHubOAuthClientSecretEnvironmentVariable;
        settings.RefreshIntervalMinutes = (int)_refreshMinutes.Value;
        settings.OpenMenuOnLeftClick = _openMenuOnLeftClick.Checked;
        settings.LaunchAtLogin = _launchAtLogin.Checked;
        new WindowsLaunchAtLogin().SetEnabled(settings.LaunchAtLogin, Application.ExecutablePath);
        settings.DiscoverLocalProjects = _discoverLocalProjects.Checked;
        settings.LocalProjectsRoot = string.IsNullOrWhiteSpace(_localProjectsRoot.Text) ? null : _localProjectsRoot.Text.Trim();
        settings.LocalProjectsMaxDepth = (int)_localProjectsDepth.Value;
        settings.FetchLocalProjectsBeforeStatus = _fetchLocalProjectsBeforeStatus.Checked;
        settings.AutoSyncLocalProjects = _autoSyncLocalProjects.Checked;
        settings.EnableResponseCache = _enableResponseCache.Checked;
        settings.ShowRateLimits = _showRateLimits.Checked;
        settings.ShowContributionSummary = _showContributionSummary.Checked;
        settings.ShowActionsUsage = _showActionsUsage.Checked;
        settings.EnablePullRequestNotifications = _enablePullRequestNotifications.Checked;

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
        return new WindowsSettings
        {
            GitHubHost = GitHubHost.Normalize(_hostTextBox.Text),
            TokenEnvironmentVariable = _tokenEnvironmentTextBox.Text.Trim(),
            GitHubOAuthClientId = string.IsNullOrWhiteSpace(_oauthClientIdTextBox.Text)
                ? WindowsOAuthClient.DefaultClientId
                : _oauthClientIdTextBox.Text.Trim(),
            GitHubOAuthClientSecretEnvironmentVariable = string.IsNullOrWhiteSpace(_oauthSecretEnvironmentTextBox.Text)
                ? WindowsOAuthClient.DefaultClientSecretEnvironmentVariable
                : _oauthSecretEnvironmentTextBox.Text.Trim(),
        };
    }

    private string? ResolveTokenForSnapshot()
    {
        var snapshot = CurrentSettingsSnapshot();
        var oauthToken = new WindowsOAuthTokenStore(snapshot.GitHubHost).ReadTokens()?.AccessToken;
        if (!string.IsNullOrWhiteSpace(oauthToken))
        {
            return oauthToken;
        }

        if (!string.IsNullOrWhiteSpace(_personalAccessTokenTextBox.Text))
        {
            return _personalAccessTokenTextBox.Text;
        }

        var credentialToken = new WindowsCredentialStore(snapshot.GitHubHost).ReadToken();
        if (!string.IsNullOrWhiteSpace(credentialToken))
        {
            return credentialToken;
        }

        if (!string.IsNullOrWhiteSpace(snapshot.TokenEnvironmentVariable))
        {
            var configuredToken = Environment.GetEnvironmentVariable(snapshot.TokenEnvironmentVariable);
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
            new WindowsCredentialStore(_hostTextBox.Text).SaveToken(_personalAccessTokenTextBox.Text);
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
            new WindowsCredentialStore(_hostTextBox.Text).ClearToken();
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
            using var client = new WindowsOAuthClient();
            var tokens = await client.LoginAsync(snapshot, CancellationToken.None).ConfigureAwait(true);
            new WindowsOAuthTokenStore(snapshot.GitHubHost).SaveTokens(tokens);
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
            new WindowsOAuthTokenStore(_hostTextBox.Text).ClearTokens();
            UpdateCredentialState();
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "RepoBar GitHub Sign-In", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void UpdateCredentialState()
    {
        var store = new WindowsCredentialStore(_hostTextBox.Text);
        _credentialState.Text = store.HasToken()
            ? $"PAT stored as {store.TargetName}"
            : $"No PAT stored ({store.TargetName})";
        var oauthStore = new WindowsOAuthTokenStore(_hostTextBox.Text);
        _oauthState.Text = oauthStore.ReadTokens() == null
            ? $"No OAuth token ({oauthStore.TargetName})"
            : $"OAuth stored as {oauthStore.TargetName}";
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
}
