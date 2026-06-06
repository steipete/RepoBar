using System.Drawing;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class AboutForm : Form
{
    private readonly WindowsAboutInfo _info;
    private readonly Action<string> _openUrl;
    private readonly Action _copyUpdateDiagnostics;
    private readonly Func<Task> _checkForUpdates;

    public AboutForm(
        WindowsAboutInfo info,
        Action<string> openUrl,
        Action copyUpdateDiagnostics,
        Func<Task> checkForUpdates)
    {
        _info = info;
        _openUrl = openUrl;
        _copyUpdateDiagnostics = copyUpdateDiagnostics;
        _checkForUpdates = checkForUpdates;
        Text = "About RepoBar";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(420, 300);
        MinimumSize = new Size(380, 280);
        MaximizeBox = false;
        MinimizeBox = false;

        BuildControls();
    }

    private void BuildControls()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 5,
            Padding = new Padding(16),
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        Controls.Add(root);

        root.Controls.Add(new Label
        {
            Text = _info.AppName,
            AutoSize = true,
            Font = new Font(Font, FontStyle.Bold),
            Dock = DockStyle.Top,
        });
        root.Controls.Add(new Label
        {
            Text = $"Version {_info.Version}{Environment.NewLine}{_info.Description}",
            AutoSize = true,
            Dock = DockStyle.Top,
            Padding = new Padding(0, 4, 0, 8),
        });

        var links = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoScroll = true,
        };
        foreach (var link in _info.Links)
        {
            var item = new LinkLabel
            {
                Text = link.Label,
                AutoSize = true,
                Tag = link.Url,
                Padding = new Padding(0, 3, 0, 3),
            };
            item.LinkClicked += (_, _) =>
            {
                if (item.Tag is string url)
                {
                    _openUrl(url);
                }
            };
            links.Controls.Add(item);
        }
        root.Controls.Add(links);

        root.Controls.Add(new Label
        {
            Text = "(c) 2025 Peter Steinberger. MIT License.",
            AutoSize = true,
            Dock = DockStyle.Top,
            Padding = new Padding(0, 8, 0, 4),
        });

        var footer = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
        };
        var closeButton = new Button { Text = "Close", DialogResult = DialogResult.OK };
        var diagnosticsButton = new Button { Text = "Copy update diagnostics", AutoSize = true };
        diagnosticsButton.Click += (_, _) => _copyUpdateDiagnostics();
        var updateButton = new Button { Text = "Check for updates", AutoSize = true };
        updateButton.Click += async (_, _) => await _checkForUpdates().ConfigureAwait(true);

        footer.Controls.Add(closeButton);
        footer.Controls.Add(diagnosticsButton);
        footer.Controls.Add(updateButton);
        root.Controls.Add(footer);
        AcceptButton = closeButton;
        CancelButton = closeButton;
    }
}
