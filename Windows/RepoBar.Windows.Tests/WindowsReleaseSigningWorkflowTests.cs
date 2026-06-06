using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class WindowsReleaseSigningWorkflowTests
{
    [Fact]
    public void CiWorkflow_uses_openclaw_azure_artifact_signing_for_trusted_pushes()
    {
        var workflow = File.ReadAllText(Path.Combine(GetRepositoryRoot(), ".github", "workflows", "ci.yml"));

        Assert.Contains("tags: ['v*']", workflow);
        Assert.Contains("windows-signing:", workflow);
        Assert.Contains("if: github.event_name == 'push' && (github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v'))", workflow);
        Assert.Contains("environment: release-signing", workflow);
        Assert.Contains("id-token: write", workflow);
        Assert.Contains("uses: azure/login@v3", workflow);
        Assert.Contains("client-id: ${{ secrets.AZURE_CLIENT_ID }}", workflow);
        Assert.Contains("tenant-id: ${{ secrets.AZURE_TENANT_ID }}", workflow);
        Assert.Contains("subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}", workflow);
        Assert.Contains("uses: azure/artifact-signing-action@v2", workflow);
        Assert.Contains("endpoint: https://eus.codesigning.azure.net/", workflow);
        Assert.Contains("signing-account-name: openclaw", workflow);
        Assert.Contains("certificate-profile-name: openclaw", workflow);
        Assert.Contains("files-folder: signing-input-win-x64", workflow);
        Assert.Contains("files-folder-filter: exe", workflow);
        Assert.Contains("timestamp-rfc3161: http://timestamp.acs.microsoft.com", workflow);
        Assert.Contains("Build Windows installer from signed layout", workflow);
        Assert.Contains("Sign RepoBar Windows Installer", workflow);
        Assert.Contains("files-folder: dist/windows", workflow);
        Assert.Contains("Verify RepoBar Windows Installer Signature", workflow);
        Assert.DoesNotContain("AZURE_CLIENT_SECRET", workflow);
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
        Assert.Contains("OpenClaw Foundation", verifier);
        Assert.Contains("Unknown executable in release payload", verifier);
        Assert.Contains("Missing RepoBar.Windows.exe.", verifier);
        Assert.Contains("repobar-windows-installer-win-x64-signed", workflow);
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
