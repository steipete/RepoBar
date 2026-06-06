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
        Assert.Equal(WindowsRepositoryMenuItem.Visibility, customization.RepositoryMenuOrder[0]);
        Assert.Equal(WindowsRepositoryMenuItem.OpenRepository, customization.RepositoryMenuOrder[1]);
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
                WindowsMainMenuItem.Quit,
            ],
        };

        customization.Normalize();

        Assert.DoesNotContain(WindowsMainMenuItem.RefreshNow, customization.VisibleMainMenuItems());
        Assert.Contains(WindowsMainMenuItem.Preferences, customization.VisibleMainMenuItems());
        Assert.Contains(WindowsMainMenuItem.Quit, customization.VisibleMainMenuItems());
        Assert.DoesNotContain(WindowsMainMenuItem.Preferences, customization.HiddenMainMenuItems);
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
                WindowsRepositoryMenuItem.Visibility,
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
        Assert.Contains(WindowsRepositoryMenuItem.Visibility, visible);
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
