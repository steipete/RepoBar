using System.Drawing;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class DiagnosticsForm : Form
{
    private readonly Func<WindowsDiagnosticsReport> _capture;
    private readonly Func<int> _clearCache;
    private readonly Action _forceRefresh;
    private readonly TextBox _summary = new();
    private WindowsDiagnosticsReport _report;

    public DiagnosticsForm(
        Func<WindowsDiagnosticsReport> capture,
        Func<int> clearCache,
        Action forceRefresh)
    {
        _capture = capture;
        _clearCache = clearCache;
        _forceRefresh = forceRefresh;
        _report = _capture();
        Text = "RepoBar Diagnostics";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(760, 520);
        MinimumSize = new Size(640, 420);

        BuildControls();
        RefreshSummary();
    }

    private void BuildControls()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            Padding = new Padding(12),
        };
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        Controls.Add(root);

        _summary.Dock = DockStyle.Fill;
        _summary.Multiline = true;
        _summary.ReadOnly = true;
        _summary.ScrollBars = ScrollBars.Both;
        _summary.WordWrap = false;
        root.Controls.Add(_summary);

        var footer = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
        };
        var closeButton = new Button { Text = "Close", DialogResult = DialogResult.OK };
        var copyButton = new Button { Text = "Copy" };
        copyButton.Click += (_, _) => Clipboard.SetText(_report.ClipboardText());
        var reloadButton = new Button { Text = "Reload" };
        reloadButton.Click += (_, _) =>
        {
            _report = _capture();
            RefreshSummary();
        };
        var forceRefreshButton = new Button { Text = "Force refresh" };
        forceRefreshButton.Click += (_, _) =>
        {
            _forceRefresh();
            MessageBox.Show("Refresh requested.", "RepoBar Diagnostics", MessageBoxButtons.OK, MessageBoxIcon.Information);
        };
        var clearCacheButton = new Button { Text = "Clear cache" };
        clearCacheButton.Click += (_, _) =>
        {
            var deleted = _clearCache();
            _report = _capture();
            RefreshSummary();
            MessageBox.Show($"Deleted {deleted} cache entr{(deleted == 1 ? "y" : "ies")}.", "RepoBar Diagnostics", MessageBoxButtons.OK, MessageBoxIcon.Information);
        };

        footer.Controls.Add(closeButton);
        footer.Controls.Add(copyButton);
        footer.Controls.Add(reloadButton);
        footer.Controls.Add(forceRefreshButton);
        footer.Controls.Add(clearCacheButton);
        root.Controls.Add(footer);
        AcceptButton = closeButton;
    }

    private void RefreshSummary()
    {
        _summary.Text = _report.SummaryText() + Environment.NewLine + _report.ClipboardText();
    }
}
