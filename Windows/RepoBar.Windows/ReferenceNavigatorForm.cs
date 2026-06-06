using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class ReferenceNavigatorForm : Form
{
    private readonly WindowsSettings _settings;
    private readonly TextBox _input = new();
    private readonly ComboBox _defaultRepository = new();
    private readonly BindingList<ReferenceRow> _references = [];
    private readonly DataGridView _referenceGrid = new();
    private readonly WebBrowser _preview = new();

    public ReferenceNavigatorForm(WindowsSettings settings)
    {
        _settings = settings;
        Text = "RepoBar Issue Navigator";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(980, 620);
        MinimumSize = new Size(760, 480);

        BuildControls();
        TrySeedClipboard();
        RefreshReferences();
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
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 40));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 60));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        Controls.Add(root);

        _defaultRepository.DropDownStyle = ComboBoxStyle.DropDownList;
        _defaultRepository.Items.AddRange(_settings.Repositories
            .Where(repository => repository.IsVisible)
            .Select(repository => repository.FullName)
            .Cast<object>()
            .ToArray());
        if (_defaultRepository.Items.Count > 0)
        {
            _defaultRepository.SelectedIndex = 0;
        }
        _defaultRepository.SelectedIndexChanged += (_, _) => RefreshReferences();
        root.Controls.Add(_defaultRepository);

        _input.Multiline = true;
        _input.ScrollBars = ScrollBars.Vertical;
        _input.Dock = DockStyle.Fill;
        _input.TextChanged += (_, _) => RefreshReferences();
        root.Controls.Add(_input);

        root.Controls.Add(new Label { Text = "References", AutoSize = true });
        ConfigureGrid();
        ConfigurePreview();
        var split = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Vertical,
            SplitterDistance = 420,
        };
        split.Panel1.Controls.Add(_referenceGrid);
        split.Panel2.Controls.Add(_preview);
        root.Controls.Add(split);

        var footer = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            Dock = DockStyle.Fill,
        };
        var openSelected = new Button { Text = "Open selected" };
        openSelected.Click += (_, _) => OpenSelected();
        var copySelected = new Button { Text = "Copy URL" };
        copySelected.Click += (_, _) => CopySelectedUrl();
        var paste = new Button { Text = "Paste" };
        paste.Click += (_, _) =>
        {
            if (Clipboard.ContainsText())
            {
                _input.Text = Clipboard.GetText();
            }
        };
        footer.Controls.Add(openSelected);
        footer.Controls.Add(copySelected);
        footer.Controls.Add(paste);
        root.Controls.Add(footer);
    }

    private void ConfigureGrid()
    {
        _referenceGrid.Dock = DockStyle.Fill;
        _referenceGrid.AutoGenerateColumns = false;
        _referenceGrid.AllowUserToAddRows = false;
        _referenceGrid.AllowUserToDeleteRows = false;
        _referenceGrid.ReadOnly = true;
        _referenceGrid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        _referenceGrid.MultiSelect = true;
        _referenceGrid.DataSource = _references;
        _referenceGrid.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ReferenceRow.Repository),
            HeaderText = "Repository",
            AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill,
        });
        _referenceGrid.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ReferenceRow.Number),
            HeaderText = "#",
            Width = 80,
        });
        _referenceGrid.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ReferenceRow.Url),
            HeaderText = "URL",
            AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill,
        });
        _referenceGrid.CellDoubleClick += (_, _) => OpenSelected();
        _referenceGrid.SelectionChanged += (_, _) => PreviewSelected();
    }

    private void ConfigurePreview()
    {
        _preview.Dock = DockStyle.Fill;
        _preview.AllowWebBrowserDrop = false;
        _preview.ScriptErrorsSuppressed = true;
    }

    private void TrySeedClipboard()
    {
        try
        {
            if (Clipboard.ContainsText())
            {
                _input.Text = Clipboard.GetText();
            }
        }
        catch
        {
            // Clipboard can be temporarily locked by another process.
        }
    }

    private void RefreshReferences()
    {
        var defaultRepository = _defaultRepository.SelectedItem as string;
        var references = GitHubReferenceNavigator.FindReferences(
            _input.Text,
            _settings.GitHubHost,
            defaultRepository);

        _references.Clear();
        foreach (var reference in references)
        {
            _references.Add(new ReferenceRow(
                reference.RepositoryFullName,
                reference.Number,
                GitHubReferenceNavigator.BuildUri(reference, _settings.GitHubHost).ToString()));
        }

        SelectFirstReference();
    }

    private void OpenSelected()
    {
        foreach (var row in SelectedReferenceRows())
        {
            OpenUrl(row.Url);
        }
    }

    private void CopySelectedUrl()
    {
        var row = SelectedReferenceRows().FirstOrDefault();
        if (row != null)
        {
            Clipboard.SetText(row.Url);
        }
    }

    private void PreviewSelected()
    {
        var row = SelectedReferenceRows().FirstOrDefault();
        try
        {
            _preview.Navigate(row?.Url ?? "about:blank");
        }
        catch
        {
            _preview.Navigate("about:blank");
        }
    }

    private void SelectFirstReference()
    {
        if (_referenceGrid.Rows.Count == 0)
        {
            PreviewSelected();
            return;
        }

        _referenceGrid.ClearSelection();
        _referenceGrid.Rows[0].Selected = true;
        _referenceGrid.CurrentCell = _referenceGrid.Rows[0].Cells[0];
        PreviewSelected();
    }

    private IReadOnlyList<ReferenceRow> SelectedReferenceRows()
    {
        var selected = _referenceGrid.SelectedRows
            .Cast<DataGridViewRow>()
            .Select(row => row.DataBoundItem)
            .OfType<ReferenceRow>()
            .ToArray();
        if (selected.Length > 0)
        {
            return selected;
        }

        return _referenceGrid.CurrentRow?.DataBoundItem is ReferenceRow current ? [current] : [];
    }

    private static void OpenUrl(string url)
    {
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }

    private sealed record ReferenceRow(string Repository, int Number, string Url);
}
