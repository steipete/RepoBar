using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsMenuCustomizationTests
{
    [Fact]
    public void Normalize_deduplicates_orders_and_appends_missing_items()
    {
        var customization = new WindowsMenuCustomization
        {
            MainMenuOrder =
            [
                WindowsMainMenuItem.Quit,
                WindowsMainMenuItem.Quit,
                WindowsMainMenuItem.RefreshNow,
            ],
            RepositoryMenuOrder =
            [
                WindowsRepositoryMenuItem.Visibility,
                WindowsRepositoryMenuItem.Visibility,
                WindowsRepositoryMenuItem.OpenRepository,
            ],
        };

        customization.Normalize();

        Assert.Equal(WindowsMainMenuItem.Quit, customization.MainMenuOrder[0]);
        Assert.Equal(WindowsMainMenuItem.RefreshNow, customization.MainMenuOrder[1]);
        Assert.Contains(WindowsMainMenuItem.GlobalCommits, customization.MainMenuOrder);
        Assert.Contains(WindowsMainMenuItem.GlobalActivity, customization.MainMenuOrder);
        Assert.Contains(WindowsMainMenuItem.About, customization.MainMenuOrder);
        Assert.Contains(WindowsMainMenuItem.AccountSwitcher, customization.MainMenuOrder);
        Assert.Contains(WindowsMainMenuItem.RepositoryScope, customization.MainMenuOrder);
        Assert.Contains(WindowsMainMenuItem.RepositorySort, customization.MainMenuOrder);
        Assert.Contains(WindowsMainMenuItem.MyRepositories, customization.MainMenuOrder);
        Assert.Contains(WindowsMainMenuItem.ClearResponseCache, customization.MainMenuOrder);
        Assert.Contains(WindowsMainMenuItem.Diagnostics, customization.MainMenuOrder);
        Assert.Contains(WindowsMainMenuItem.CopyUpdateDiagnostics, customization.MainMenuOrder);
        Assert.Equal(WindowsMenuCustomization.DefaultMainMenuOrder.Count, customization.MainMenuOrder.Count);
        Assert.Equal(
            [
                WindowsRepositoryMenuItem.PinToggle,
                WindowsRepositoryMenuItem.SetVisible,
                WindowsRepositoryMenuItem.HideRepository,
                WindowsRepositoryMenuItem.MoveUp,
                WindowsRepositoryMenuItem.MoveDown,
                WindowsRepositoryMenuItem.OpenRepository,
            ],
            customization.RepositoryMenuOrder.Take(6));
        Assert.DoesNotContain(WindowsRepositoryMenuItem.Visibility, customization.RepositoryMenuOrder);
        Assert.Equal(WindowsMenuCustomization.DefaultRepositoryMenuOrder.Count, customization.RepositoryMenuOrder.Count);
    }

    [Fact]
    public void VisibleMainMenuItems_keeps_required_items_even_when_hidden()
    {
        var customization = new WindowsMenuCustomization
        {
            HiddenMainMenuItems =
            [
                WindowsMainMenuItem.RefreshNow,
                WindowsMainMenuItem.Preferences,
                WindowsMainMenuItem.About,
                WindowsMainMenuItem.Quit,
            ],
        };

        customization.Normalize();

        Assert.DoesNotContain(WindowsMainMenuItem.RefreshNow, customization.VisibleMainMenuItems());
        Assert.Contains(WindowsMainMenuItem.Preferences, customization.VisibleMainMenuItems());
        Assert.Contains(WindowsMainMenuItem.About, customization.VisibleMainMenuItems());
        Assert.Contains(WindowsMainMenuItem.Quit, customization.VisibleMainMenuItems());
        Assert.DoesNotContain(WindowsMainMenuItem.Preferences, customization.HiddenMainMenuItems);
        Assert.DoesNotContain(WindowsMainMenuItem.About, customization.HiddenMainMenuItems);
        Assert.DoesNotContain(WindowsMainMenuItem.Quit, customization.HiddenMainMenuItems);
    }

    [Fact]
    public void VisibleRepositoryMenuItems_respects_hidden_items_and_order()
    {
        var customization = new WindowsMenuCustomization
        {
            RepositoryMenuOrder =
            [
                WindowsRepositoryMenuItem.Heatmap,
                WindowsRepositoryMenuItem.OpenRepository,
                WindowsRepositoryMenuItem.HideRepository,
            ],
            HiddenRepositoryMenuItems =
            [
                WindowsRepositoryMenuItem.OpenRepository,
            ],
        };

        customization.Normalize();

        var visible = customization.VisibleRepositoryMenuItems();

        Assert.Equal(WindowsRepositoryMenuItem.Heatmap, visible[0]);
        Assert.DoesNotContain(WindowsRepositoryMenuItem.OpenRepository, visible);
        Assert.Contains(WindowsRepositoryMenuItem.HideRepository, visible);
    }

    [Fact]
    public void Normalize_expands_legacy_visibility_hidden_item_to_manage_actions()
    {
        var customization = new WindowsMenuCustomization
        {
            HiddenRepositoryMenuItems =
            [
                WindowsRepositoryMenuItem.Visibility,
            ],
        };

        customization.Normalize();

        Assert.DoesNotContain(WindowsRepositoryMenuItem.Visibility, customization.HiddenRepositoryMenuItems);
        Assert.Contains(WindowsRepositoryMenuItem.PinToggle, customization.HiddenRepositoryMenuItems);
        Assert.Contains(WindowsRepositoryMenuItem.SetVisible, customization.HiddenRepositoryMenuItems);
        Assert.Contains(WindowsRepositoryMenuItem.HideRepository, customization.HiddenRepositoryMenuItems);
        Assert.Contains(WindowsRepositoryMenuItem.MoveUp, customization.HiddenRepositoryMenuItems);
        Assert.Contains(WindowsRepositoryMenuItem.MoveDown, customization.HiddenRepositoryMenuItems);
    }

    [Fact]
    public void VisibleRepositoryMenuBlocks_groups_adjacent_visible_items()
    {
        var customization = new WindowsMenuCustomization
        {
            RepositoryMenuOrder =
            [
                WindowsRepositoryMenuItem.OpenRepository,
                WindowsRepositoryMenuItem.OpenIssues,
                WindowsRepositoryMenuItem.LocalStatus,
                WindowsRepositoryMenuItem.RecentIssues,
                WindowsRepositoryMenuItem.RecentPullRequests,
                WindowsRepositoryMenuItem.Heatmap,
                WindowsRepositoryMenuItem.PinToggle,
                WindowsRepositoryMenuItem.HideRepository,
            ],
            HiddenRepositoryMenuItems =
            [
                WindowsRepositoryMenuItem.OpenIssues,
            ],
        };

        var blocks = customization.VisibleRepositoryMenuBlocks();

        Assert.Collection(
            blocks,
            block =>
            {
                Assert.Equal(WindowsRepositoryMenuGroup.Open, block.Group);
                Assert.Equal([WindowsRepositoryMenuItem.OpenRepository], block.Items);
            },
            block =>
            {
                Assert.Equal(WindowsRepositoryMenuGroup.Local, block.Group);
                Assert.Equal([WindowsRepositoryMenuItem.LocalStatus], block.Items);
            },
            block =>
            {
                Assert.Equal(WindowsRepositoryMenuGroup.Lists, block.Group);
                Assert.Equal(
                    [
                        WindowsRepositoryMenuItem.RecentIssues,
                        WindowsRepositoryMenuItem.RecentPullRequests,
                    ],
                    block.Items);
            },
            block =>
            {
                Assert.Equal(WindowsRepositoryMenuGroup.Status, block.Group);
                Assert.Equal([WindowsRepositoryMenuItem.Heatmap], block.Items);
            },
            block =>
            {
                Assert.Equal(WindowsRepositoryMenuGroup.Manage, block.Group);
                Assert.Equal(
                    [
                        WindowsRepositoryMenuItem.PinToggle,
                        WindowsRepositoryMenuItem.HideRepository,
                    ],
                    block.Items);
            });
    }

    [Fact]
    public void Default_repository_order_keeps_mac_style_groups_contiguous()
    {
        var blocks = new WindowsMenuCustomization().VisibleRepositoryMenuBlocks();

        Assert.Equal(
            [
                WindowsRepositoryMenuGroup.Open,
                WindowsRepositoryMenuGroup.Local,
                WindowsRepositoryMenuGroup.Lists,
                WindowsRepositoryMenuGroup.Status,
                WindowsRepositoryMenuGroup.Commits,
                WindowsRepositoryMenuGroup.Activity,
                WindowsRepositoryMenuGroup.Manage,
            ],
            blocks.Select(block => block.Group));

        var localBlock = Assert.Single(blocks, block => block.Group == WindowsRepositoryMenuGroup.Local);
        Assert.Equal(
            [
                WindowsRepositoryMenuItem.OpenFolder,
                WindowsRepositoryMenuItem.OpenTerminal,
                WindowsRepositoryMenuItem.Checkout,
                WindowsRepositoryMenuItem.LocalStatus,
            ],
            localBlock.Items);

        var manageBlock = Assert.Single(blocks, block => block.Group == WindowsRepositoryMenuGroup.Manage);
        Assert.Equal(
            [
                WindowsRepositoryMenuItem.PinToggle,
                WindowsRepositoryMenuItem.SetVisible,
                WindowsRepositoryMenuItem.HideRepository,
                WindowsRepositoryMenuItem.MoveUp,
                WindowsRepositoryMenuItem.MoveDown,
            ],
            manageBlock.Items);
    }

    [Fact]
    public void Display_names_cover_customizable_items()
    {
        foreach (var item in WindowsMenuCustomization.DefaultMainMenuOrder)
        {
            Assert.False(string.IsNullOrWhiteSpace(item.DisplayName()));
        }

        foreach (var item in WindowsMenuCustomization.DefaultRepositoryMenuOrder)
        {
            Assert.False(string.IsNullOrWhiteSpace(item.DisplayName()));
        }
    }

    [Fact]
    public void Copy_keeps_dialog_edits_isolated_until_saved()
    {
        var original = new WindowsMenuCustomization();
        var pending = original.Copy();

        pending.HiddenMainMenuItems.Add(WindowsMainMenuItem.RefreshNow);

        Assert.Empty(original.HiddenMainMenuItems);
        Assert.Contains(WindowsMainMenuItem.RefreshNow, pending.HiddenMainMenuItems);
    }
}
