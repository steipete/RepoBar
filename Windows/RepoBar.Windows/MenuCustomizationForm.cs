using System.Drawing;
using System.Windows.Forms;

namespace RepoBar.Windows;

internal sealed class MenuCustomizationForm : Form
{
    private readonly WindowsMenuCustomization _target;
    private readonly WindowsMenuCustomization _customization;
    private readonly CheckedListBox _mainMenu = new();
    private readonly CheckedListBox _repositoryMenu = new();

    public MenuCustomizationForm(WindowsMenuCustomization customization)
    {
        _target = customization;
        _customization = customization.Copy();
        _customization.Normalize();

        Text = "RepoBar Menu Customization";
        StartPosition = FormStartPosition.CenterParent;
        MinimizeBox = false;
        MaximizeBox = false;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        ClientSize = new Size(720, 520);

        BuildControls();
        LoadRows();
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

        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(BuildPage("Main menu", _mainMenu));
        tabs.TabPages.Add(BuildPage("Repository menu", _repositoryMenu));
        root.Controls.Add(tabs);

        var footer = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            Dock = DockStyle.Fill,
            AutoSize = true,
        };
        var saveButton = new Button { Text = "Save", DialogResult = DialogResult.OK };
        saveButton.Click += (_, _) => SaveRows();
        var cancelButton = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel };
        var resetButton = new Button { Text = "Reset defaults" };
        resetButton.Click += (_, _) => ResetRows();
        footer.Controls.Add(saveButton);
        footer.Controls.Add(cancelButton);
        footer.Controls.Add(resetButton);
        root.Controls.Add(footer);

        AcceptButton = saveButton;
        CancelButton = cancelButton;
    }

    private static TabPage BuildPage(string title, CheckedListBox listBox)
    {
        var page = new TabPage(title);
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            Padding = new Padding(8),
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        page.Controls.Add(layout);

        listBox.Dock = DockStyle.Fill;
        listBox.CheckOnClick = true;
        listBox.DisplayMember = nameof(MenuCustomizationRow<WindowsMainMenuItem>.Label);
        listBox.ItemCheck += (_, args) =>
        {
            if (args.NewValue == CheckState.Unchecked &&
                listBox.Items[args.Index] is IMenuCustomizationRow { Required: true })
            {
                args.NewValue = CheckState.Checked;
            }
        };
        layout.Controls.Add(listBox);

        var buttons = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            Dock = DockStyle.Top,
            AutoSize = true,
        };
        var up = new Button { Text = "Up", Width = 90 };
        up.Click += (_, _) => MoveSelected(listBox, -1);
        var down = new Button { Text = "Down", Width = 90 };
        down.Click += (_, _) => MoveSelected(listBox, 1);
        buttons.Controls.Add(up);
        buttons.Controls.Add(down);
        layout.Controls.Add(buttons);

        return page;
    }

    private void LoadRows()
    {
        LoadRows(
            _mainMenu,
            _customization.MainMenuOrder,
            _customization.HiddenMainMenuItems,
            item => new MenuCustomizationRow<WindowsMainMenuItem>(item, item.DisplayName(), item.IsRequired()));
        LoadRows(
            _repositoryMenu,
            _customization.RepositoryMenuOrder,
            _customization.HiddenRepositoryMenuItems,
            item => new MenuCustomizationRow<WindowsRepositoryMenuItem>(item, item.DisplayName(), Required: false));
    }

    private static void LoadRows<T>(
        CheckedListBox listBox,
        IReadOnlyList<T> order,
        IReadOnlyCollection<T> hidden,
        Func<T, MenuCustomizationRow<T>> makeRow)
        where T : struct, Enum
    {
        listBox.Items.Clear();
        var hiddenSet = hidden.ToHashSet();
        foreach (var item in order)
        {
            var row = makeRow(item);
            listBox.Items.Add(row, row.Required || !hiddenSet.Contains(item));
        }
    }

    private void SaveRows()
    {
        SaveRows(_mainMenu, _customization.MainMenuOrder, _customization.HiddenMainMenuItems);
        SaveRows(_repositoryMenu, _customization.RepositoryMenuOrder, _customization.HiddenRepositoryMenuItems);
        _customization.Normalize();
        _target.HiddenMainMenuItems = _customization.HiddenMainMenuItems.ToList();
        _target.MainMenuOrder = _customization.MainMenuOrder.ToList();
        _target.HiddenRepositoryMenuItems = _customization.HiddenRepositoryMenuItems.ToList();
        _target.RepositoryMenuOrder = _customization.RepositoryMenuOrder.ToList();
        _target.Normalize();
    }

    private static void SaveRows<T>(CheckedListBox listBox, List<T> order, List<T> hidden)
        where T : struct, Enum
    {
        order.Clear();
        hidden.Clear();
        for (var index = 0; index < listBox.Items.Count; index++)
        {
            if (listBox.Items[index] is not MenuCustomizationRow<T> row)
            {
                continue;
            }

            order.Add(row.Item);
            if (!row.Required && !listBox.GetItemChecked(index))
            {
                hidden.Add(row.Item);
            }
        }
    }

    private void ResetRows()
    {
        _customization.HiddenMainMenuItems = [];
        _customization.MainMenuOrder = WindowsMenuCustomization.DefaultMainMenuOrder.ToList();
        _customization.HiddenRepositoryMenuItems = [];
        _customization.RepositoryMenuOrder = WindowsMenuCustomization.DefaultRepositoryMenuOrder.ToList();
        LoadRows();
    }

    private static void MoveSelected(CheckedListBox listBox, int delta)
    {
        var index = listBox.SelectedIndex;
        if (index < 0)
        {
            return;
        }

        var nextIndex = index + delta;
        if (nextIndex < 0 || nextIndex >= listBox.Items.Count)
        {
            return;
        }

        var item = listBox.Items[index];
        var isChecked = listBox.GetItemChecked(index);
        listBox.Items.RemoveAt(index);
        listBox.Items.Insert(nextIndex, item);
        listBox.SetItemChecked(nextIndex, isChecked);
        listBox.SelectedIndex = nextIndex;
    }

    private interface IMenuCustomizationRow
    {
        bool Required { get; }
    }

    private sealed record MenuCustomizationRow<T>(T Item, string Label, bool Required) : IMenuCustomizationRow
        where T : struct, Enum;
}
