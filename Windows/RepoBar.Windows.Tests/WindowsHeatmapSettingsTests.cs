using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsHeatmapSettingsTests
{
    [Fact]
    public void Span_weeks_match_settings_labels()
    {
        Assert.Equal(4, WindowsHeatmapSpan.OneMonth.Weeks());
        Assert.Equal(13, WindowsHeatmapSpan.ThreeMonths.Weeks());
        Assert.Equal(26, WindowsHeatmapSpan.SixMonths.Weeks());
        Assert.Equal(52, WindowsHeatmapSpan.TwelveMonths.Weeks());

        foreach (var display in Enum.GetValues<WindowsHeatmapDisplay>())
        {
            Assert.False(string.IsNullOrWhiteSpace(display.DisplayName()));
        }

        foreach (var span in Enum.GetValues<WindowsHeatmapSpan>())
        {
            Assert.False(string.IsNullOrWhiteSpace(span.DisplayName()));
        }
    }

    [Fact]
    public void Display_modes_map_to_row_and_submenu_surfaces()
    {
        Assert.False(WindowsHeatmapDisplay.Hidden.ShowsRow());
        Assert.False(WindowsHeatmapDisplay.Hidden.ShowsSubmenu());
        Assert.True(WindowsHeatmapDisplay.Row.ShowsRow());
        Assert.False(WindowsHeatmapDisplay.Row.ShowsSubmenu());
        Assert.False(WindowsHeatmapDisplay.Submenu.ShowsRow());
        Assert.True(WindowsHeatmapDisplay.Submenu.ShowsSubmenu());
        Assert.True(WindowsHeatmapDisplay.RowAndSubmenu.ShowsRow());
        Assert.True(WindowsHeatmapDisplay.RowAndSubmenu.ShowsSubmenu());
    }
}
