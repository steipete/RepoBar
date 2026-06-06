using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsUpdateCheckerTests
{
    [Theory]
    [InlineData("0.7.0", "0.7.0")]
    [InlineData("v0.7.1", "0.7.1")]
    [InlineData("RepoBar 1.2.3.4", "1.2.3.4")]
    [InlineData("not-a-version", null)]
    public void NormalizeVersion_extracts_version_token(string value, string? expected)
    {
        Assert.Equal(expected, WindowsUpdateChecker.NormalizeVersion(value)?.ToString());
    }

    [Fact]
    public async Task CheckLatestAsync_detects_newer_release()
    {
        using var checker = new WindowsUpdateChecker(new StubHandler(_ => JsonResponse("""
            {
              "tag_name": "v0.8.0",
              "html_url": "https://github.com/steipete/RepoBar/releases/tag/v0.8.0",
              "assets": [
                {"name":"RepoBar-macOS.zip","browser_download_url":"https://example.com/repobar-macos.zip"},
                {"name":"RepoBar-Windows-0.8.0.zip","browser_download_url":"https://example.com/repobar-windows.zip"},
                {"name":"RepoBar-Windows-0.8.0.msi","browser_download_url":"https://example.com/repobar-windows.msi"}
              ]
            }
            """)));

        var status = await checker.CheckLatestAsync("0.7.0", CancellationToken.None);

        Assert.True(status.IsNewer);
        Assert.Equal("v0.8.0", status.LatestTag);
        Assert.Equal("https://github.com/steipete/RepoBar/releases/tag/v0.8.0", status.ReleaseUrl);
        Assert.Equal("https://example.com/repobar-windows.msi", status.InstallerUrl);
        Assert.Equal(status.InstallerUrl, status.PreferredUpdateUrl);
    }

    [Fact]
    public async Task CheckLatestAsync_keeps_current_version_when_latest_is_not_newer()
    {
        using var checker = new WindowsUpdateChecker(new StubHandler(_ => JsonResponse("""
            {
              "tag_name": "v0.7.0",
              "html_url": "https://github.com/steipete/RepoBar/releases/tag/v0.7.0"
            }
            """)));

        var status = await checker.CheckLatestAsync("0.7.0", CancellationToken.None);

        Assert.False(status.IsNewer);
        Assert.Contains("up to date", status.DisplayText, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task CheckLatestAsync_falls_back_to_release_page_when_windows_asset_is_missing()
    {
        using var checker = new WindowsUpdateChecker(new StubHandler(_ => JsonResponse("""
            {
              "tag_name": "v0.8.0",
              "html_url": "https://github.com/steipete/RepoBar/releases/tag/v0.8.0",
              "assets": [
                {"name":"RepoBar-macOS.zip","browser_download_url":"https://example.com/repobar-macos.zip"}
              ]
            }
            """)));

        var status = await checker.CheckLatestAsync("0.7.0", CancellationToken.None);

        Assert.True(status.IsNewer);
        Assert.Null(status.InstallerUrl);
        Assert.Equal(status.ReleaseUrl, status.PreferredUpdateUrl);
    }

    [Fact]
    public void FindWindowsInstallerUrl_prefers_current_x64_architecture()
    {
        using var document = JsonDocument.Parse("""
            {
              "assets": [
                {"name":"RepoBar-Windows-arm64.msi","browser_download_url":"https://example.com/repobar-arm64.msi"},
                {"name":"RepoBar-Windows-x64.exe","browser_download_url":"https://example.com/repobar-x64.exe"},
                {"name":"RepoBar-Windows.zip","browser_download_url":"https://example.com/repobar-generic.zip"}
              ]
            }
            """);

        Assert.Equal(
            "https://example.com/repobar-x64.exe",
            WindowsUpdateChecker.FindWindowsInstallerUrl(document.RootElement, Architecture.X64));
    }

    [Fact]
    public void FindWindowsInstallerUrl_prefers_current_arm64_architecture()
    {
        using var document = JsonDocument.Parse("""
            {
              "assets": [
                {"name":"RepoBar-Windows-x64.msi","browser_download_url":"https://example.com/repobar-x64.msi"},
                {"name":"RepoBar-Windows-arm64.exe","browser_download_url":"https://example.com/repobar-arm64.exe"},
                {"name":"RepoBar-Windows.zip","browser_download_url":"https://example.com/repobar-generic.zip"}
              ]
            }
            """);

        Assert.Equal(
            "https://example.com/repobar-arm64.exe",
            WindowsUpdateChecker.FindWindowsInstallerUrl(document.RootElement, Architecture.Arm64));
    }

    [Fact]
    public void FindWindowsInstallerUrl_uses_extension_preference_with_generic_assets()
    {
        using var document = JsonDocument.Parse("""
            {
              "assets": [
                {"name":"RepoBar-Windows.zip","browser_download_url":"https://example.com/repobar.zip"},
                {"name":"RepoBar-Windows.exe","browser_download_url":"https://example.com/repobar.exe"}
              ]
            }
            """);

        Assert.Equal(
            "https://example.com/repobar.exe",
            WindowsUpdateChecker.FindWindowsInstallerUrl(document.RootElement, Architecture.X64));
    }

    [Fact]
    public void FindWindowsInstallerUrl_prefers_architecture_match_before_extension()
    {
        using var document = JsonDocument.Parse("""
            {
              "assets": [
                {"name":"RepoBar-Windows.msi","browser_download_url":"https://example.com/repobar-generic.msi"},
                {"name":"RepoBar-Windows-x64.zip","browser_download_url":"https://example.com/repobar-x64.zip"}
              ]
            }
            """);

        Assert.Equal(
            "https://example.com/repobar-x64.zip",
            WindowsUpdateChecker.FindWindowsInstallerUrl(document.RootElement, Architecture.X64));
    }

    [Fact]
    public void FindWindowsInstallerUrl_prefers_generic_asset_before_wrong_architecture()
    {
        using var document = JsonDocument.Parse("""
            {
              "assets": [
                {"name":"RepoBar-Windows-arm64.msi","browser_download_url":"https://example.com/repobar-arm64.msi"},
                {"name":"RepoBar-Windows.exe","browser_download_url":"https://example.com/repobar-generic.exe"}
              ]
            }
            """);

        Assert.Equal(
            "https://example.com/repobar-generic.exe",
            WindowsUpdateChecker.FindWindowsInstallerUrl(document.RootElement, Architecture.X64));
    }

    private static HttpResponseMessage JsonResponse(string json)
    {
        return new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
    }

    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _handler;

        public StubHandler(Func<HttpRequestMessage, HttpResponseMessage> handler)
        {
            _handler = handler;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Assert.Equal("/repos/steipete/RepoBar/releases/latest", request.RequestUri?.AbsolutePath);
            return Task.FromResult(_handler(request));
        }
    }
}
