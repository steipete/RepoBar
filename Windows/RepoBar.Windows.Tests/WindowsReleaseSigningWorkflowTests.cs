using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsReleaseSigningWorkflowTests
{
    [Fact]
    public void CiWorkflow_uses_windows_node_trusted_signing_profile_for_trusted_pushes()
    {
        var workflow = File.ReadAllText(Path.Combine(GetRepositoryRoot(), ".github", "workflows", "ci.yml"));

        Assert.Contains("tags: ['v*']", workflow);
        Assert.Contains("windows-signing:", workflow);
        Assert.Contains("if: github.event_name == 'push' && (github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v'))", workflow);
        Assert.Contains("environment: release-signing", workflow);
        Assert.Contains("uses: azure/login@v3", workflow);
        Assert.Contains("clientId\":\"${{ secrets.AZURE_CLIENT_ID }}", workflow);
        Assert.Contains("clientSecret\":\"${{ secrets.AZURE_CLIENT_SECRET }}", workflow);
        Assert.Contains("subscriptionId\":\"${{ secrets.AZURE_SUBSCRIPTION_ID }}", workflow);
        Assert.Contains("tenantId\":\"${{ secrets.AZURE_TENANT_ID }}", workflow);
        Assert.Contains("uses: azure/trusted-signing-action@v2", workflow);
        Assert.Contains("azure-tenant-id: ${{ secrets.AZURE_TENANT_ID }}", workflow);
        Assert.Contains("azure-client-id: ${{ secrets.AZURE_CLIENT_ID }}", workflow);
        Assert.Contains("azure-client-secret: ${{ secrets.AZURE_CLIENT_SECRET }}", workflow);
        Assert.Contains("endpoint: https://wus2.codesigning.azure.net/", workflow);
        Assert.Contains("signing-account-name: hanselman", workflow);
        Assert.Contains("certificate-profile-name: WindowsEdgeLight", workflow);
        Assert.Contains("files-folder: signing-input-win-x64", workflow);
        Assert.Contains("files-folder-filter: exe", workflow);
        Assert.Contains("timestamp-rfc3161: http://timestamp.acs.microsoft.com", workflow);
        Assert.Contains("Build Windows installer from signed layout", workflow);
        Assert.Contains("Sign RepoBar Windows Installer", workflow);
        Assert.Contains("files-folder: dist/windows", workflow);
        Assert.Contains("Verify RepoBar Windows Installer Signature", workflow);
        Assert.DoesNotContain("azure/artifact-signing-action", workflow);
        Assert.DoesNotContain("signing-account-name: openclaw", workflow);
        Assert.DoesNotContain("WINDOWS_CERTIFICATE", workflow);
        Assert.DoesNotContain(".pfx", workflow, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void CiWorkflow_signs_and_verifies_only_the_repobar_executable()
    {
        var workflow = File.ReadAllText(Path.Combine(GetRepositoryRoot(), ".github", "workflows", "ci.yml"));
        var verifier = File.ReadAllText(Path.Combine(GetRepositoryRoot(), "Scripts", "Test-WindowsReleaseSignatures.ps1"));

        Assert.Contains(@"New-Item -ItemType HardLink -Path signing-input-win-x64\RepoBar.Windows.exe -Target dist\windows\publish\win-x64\RepoBar.Windows.exe", workflow);
        Assert.Contains("Test-WindowsReleaseSignatures.ps1 -PayloadPath dist/windows/publish/win-x64 -RequireSignedRepoBar", workflow);
        Assert.Contains(@"^RepoBar\.Windows\.exe$", verifier);
        Assert.Contains("Unknown executable in release payload", verifier);
        Assert.Contains("Missing RepoBar.Windows.exe.", verifier);
        Assert.Contains("TrustedSignerPattern", verifier);
        Assert.Contains("repobar-windows-installer-win-x64-signed", workflow);
    }

    [Fact]
    public void CiWorkflow_runs_windows_smoke_and_uploads_proof_artifacts()
    {
        var workflow = File.ReadAllText(Path.Combine(GetRepositoryRoot(), ".github", "workflows", "ci.yml"));
        var validator = File.ReadAllText(Path.Combine(GetRepositoryRoot(), "Scripts", "Test-WindowsValidationArtifacts.ps1"));

        Assert.Contains("timeout-minutes: 30", workflow);
        Assert.Contains("name: Windows tray", workflow);
        Assert.Contains("run: ./Scripts/build_windows.ps1 test", workflow);
        Assert.Contains("name: Upload Windows test results", workflow);
        Assert.Contains("name: repobar-windows-test-results", workflow);
        Assert.Contains("path: dist/windows/test-results", workflow);
        Assert.Contains("if-no-files-found: warn", workflow);
        Assert.Contains("name: Smoke tray", workflow);
        Assert.Contains("run: ./Scripts/smoke_windows.ps1 -Runtime win-x64 -LaunchSeconds 5", workflow);
        Assert.Contains("name: Upload Windows smoke artifacts", workflow);
        Assert.Contains("name: repobar-windows-smoke", workflow);
        Assert.Contains("path: dist/windows/smoke", workflow);
        Assert.Contains("name: repobar-windows-win-x64-unsigned", workflow);
        Assert.Contains("path: dist/windows/publish/win-x64", workflow);
        Assert.Contains("name: Package ARM64 tray layout", workflow);
        Assert.Contains("run: ./Scripts/package_windows.ps1 -Runtime win-arm64 -SkipInstaller", workflow);
        Assert.Contains("name: Upload unsigned ARM64 tray layout", workflow);
        Assert.Contains("name: repobar-windows-win-arm64-unsigned", workflow);
        Assert.Contains("path: dist/windows/publish/win-arm64", workflow);
        Assert.Contains("name: Validate Windows proof artifacts", workflow);
        Assert.Contains("run: ./Scripts/Test-WindowsValidationArtifacts.ps1", workflow);
        Assert.Contains("name: Upload Windows validation manifest", workflow);
        Assert.Contains("name: repobar-windows-validation", workflow);
        Assert.Contains("path: dist/windows/smoke/repobar-windows-validation.json", workflow);

        Assert.True(
            workflow.IndexOf("name: Smoke tray", StringComparison.Ordinal) <
            workflow.IndexOf("name: Package tray layout", StringComparison.Ordinal));
        Assert.True(
            workflow.IndexOf("name: Upload Windows test results", StringComparison.Ordinal) <
            workflow.IndexOf("name: Smoke tray", StringComparison.Ordinal));
        Assert.True(
            workflow.IndexOf("name: Upload Windows smoke artifacts", StringComparison.Ordinal) <
            workflow.IndexOf("name: Package tray layout", StringComparison.Ordinal));
        Assert.True(
            workflow.IndexOf("name: Package tray layout", StringComparison.Ordinal) <
            workflow.IndexOf("name: Package ARM64 tray layout", StringComparison.Ordinal));
        Assert.True(
            workflow.IndexOf("name: Package ARM64 tray layout", StringComparison.Ordinal) <
            workflow.IndexOf("name: Validate Windows proof artifacts", StringComparison.Ordinal));
        Assert.True(
            workflow.IndexOf("name: Validate Windows proof artifacts", StringComparison.Ordinal) <
            workflow.IndexOf("name: Upload Windows validation manifest", StringComparison.Ordinal));
        Assert.True(
            workflow.IndexOf("name: Upload unsigned ARM64 tray layout", StringComparison.Ordinal) <
            workflow.IndexOf("windows-signing:", StringComparison.Ordinal));

        Assert.Contains("[string[]]$RequiredRuntimes = @(\"win-x64\", \"win-arm64\")", validator);
        Assert.Contains("RepoBar.Windows.exe", validator);
        Assert.Contains("publishLayouts = $layouts", validator);
    }

    private static string GetRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory != null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Package.swift")) &&
                Directory.Exists(Path.Combine(directory.FullName, "Windows")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new InvalidOperationException("Could not find repository root.");
    }
}
