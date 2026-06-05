using System.ComponentModel;
using System.Drawing;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class SettingsEditorForm : Form
{
    private readonly WindowsSettingsStore _settingsStore;
    private readonly TextBox _hostTextBox = new();
    private readonly TextBox _tokenEnvironmentTextBox = new();
    private readonly NumericUpDown _refreshMinutes = new();
    private readonly CheckBox _openMenuOnLeftClick = new();
    private readonly CheckBox _discoverLocalProjects = new();
    private readonly TextBox _localProjectsRoot = new();
    private readonly NumericUpDown _localProjectsDepth = new();
    private readonly CheckBox _fetchLocalProjectsBeforeStatus = new();
    private readonly CheckBox _autoSyncLocalProjects = new();
    private readonly CheckBox _enableResponseCache = new();
    private readonly CheckBox _showRateLimits = new();
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
        ClientSize = new Size(760, 560);

        LoadSettings();
        BuildControls();
    }

    private void LoadSettings()
    {
        var settings = _settingsStore.Settings;
        _hostTextBox.Text = settings.GitHubHost;
        _tokenEnvironmentTextBox.Text = settings.TokenEnvironmentVariable;
        _refreshMinutes.Minimum = 1;
        _refreshMinutes.Maximum = 60;
        _refreshMinutes.Value = Math.Clamp(settings.RefreshIntervalMinutes, 1, 60);
        _openMenuOnLeftClick.Checked = settings.OpenMenuOnLeftClick;
        _discoverLocalProjects.Checked = settings.DiscoverLocalProjects;
        _localProjectsRoot.Text = settings.LocalProjectsRoot ?? "";
        _localProjectsDepth.Minimum = 0;
        _localProjectsDepth.Maximum = 8;
        _localProjectsDepth.Value = Math.Clamp(settings.LocalProjectsMaxDepth, 0, 8);
        _fetchLocalProjectsBeforeStatus.Checked = settings.FetchLocalProjectsBeforeStatus;
        _autoSyncLocalProjects.Checked = settings.AutoSyncLocalProjects;
        _enableResponseCache.Checked = settings.EnableResponseCache;
        _showRateLimits.Checked = settings.ShowRateLimits;
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

        AddLabeledControl(settingsGrid, "GitHub host", _hostTextBox);
        AddLabeledControl(settingsGrid, "Token env var", _tokenEnvironmentTextBox);
        AddLabeledControl(settingsGrid, "Refresh minutes", _refreshMinutes);
        AddLabeledControl(settingsGrid, "Local scan depth", _localProjectsDepth);

        _openMenuOnLeftClick.Text = "Open menu on left click";
        _discoverLocalProjects.Text = "Discover local projects";
        _fetchLocalProjectsBeforeStatus.Text = "Fetch before status";
        _autoSyncLocalProjects.Text = "Auto-sync clean behind repos";
        _enableResponseCache.Text = "Use response cache";
        _showRateLimits.Text = "Show rate limits";
        _showActionsUsage.Text = "Show Actions usage";
        _enablePullRequestNotifications.Text = "PR notifications";

        settingsGrid.Controls.Add(_openMenuOnLeftClick);
        settingsGrid.Controls.Add(_discoverLocalProjects);
        settingsGrid.Controls.Add(_fetchLocalProjectsBeforeStatus);
        settingsGrid.Controls.Add(_autoSyncLocalProjects);
        settingsGrid.Controls.Add(_enableResponseCache);
        settingsGrid.Controls.Add(_showRateLimits);
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
        var removeButton = new Button { Text = "Remove selected" };
        removeButton.Click += (_, _) => RemoveSelectedRepositories();
        footer.Controls.Add(saveButton);
        footer.Controls.Add(cancelButton);
        footer.Controls.Add(removeButton);
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

    private void SaveSettings()
    {
        _repositoriesGrid.EndEdit();
        var settings = _settingsStore.Settings;
        settings.GitHubHost = string.IsNullOrWhiteSpace(_hostTextBox.Text) ? "github.com" : _hostTextBox.Text.Trim();
        settings.TokenEnvironmentVariable = _tokenEnvironmentTextBox.Text.Trim();
        settings.RefreshIntervalMinutes = (int)_refreshMinutes.Value;
        settings.OpenMenuOnLeftClick = _openMenuOnLeftClick.Checked;
        settings.DiscoverLocalProjects = _discoverLocalProjects.Checked;
        settings.LocalProjectsRoot = string.IsNullOrWhiteSpace(_localProjectsRoot.Text) ? null : _localProjectsRoot.Text.Trim();
        settings.LocalProjectsMaxDepth = (int)_localProjectsDepth.Value;
        settings.FetchLocalProjectsBeforeStatus = _fetchLocalProjectsBeforeStatus.Checked;
        settings.AutoSyncLocalProjects = _autoSyncLocalProjects.Checked;
        settings.EnableResponseCache = _enableResponseCache.Checked;
        settings.ShowRateLimits = _showRateLimits.Checked;
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
