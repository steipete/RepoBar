param(
    [string]$TestResultsPath = "dist/windows/test-results",
    [string]$SmokePath = "dist/windows/smoke",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    $root = Resolve-Path (Join-Path $PSScriptRoot "..")
    return Join-Path $root $Path
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$testResults = Resolve-RepoPath $TestResultsPath
$smokeArtifacts = Resolve-RepoPath $SmokePath
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $smokeArtifacts "repobar-windows-validation.json"
}
else {
    $OutputPath = Resolve-RepoPath $OutputPath
}

$trx = Get-ChildItem -LiteralPath $testResults -File -Filter "*.trx" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if ($null -eq $trx) {
    throw "RepoBar.Windows validation did not produce a TRX file under $testResults."
}

$trxXml = [xml](Get-Content -LiteralPath $trx.FullName -Raw)
$counters = $trxXml.TestRun.ResultSummary.Counters
if ($null -eq $counters) {
    throw "RepoBar.Windows TRX file does not contain result counters: $($trx.FullName)."
}
Assert-True ([int]$counters.total -gt 0) "RepoBar.Windows TRX file did not record any tests."
Assert-True ([int]$counters.failed -eq 0) "RepoBar.Windows TRX file recorded failed tests."
Assert-True ([int]$counters.error -eq 0) "RepoBar.Windows TRX file recorded errored tests."

$summary = Get-ChildItem -LiteralPath $smokeArtifacts -File -Filter "repobar-windows-smoke-*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if ($null -eq $summary) {
    throw "RepoBar.Windows validation did not produce a smoke summary under $smokeArtifacts."
}

$runtime = Get-ChildItem -LiteralPath $smokeArtifacts -File -Filter "repobar-windows-runtime-*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if ($null -eq $runtime) {
    throw "RepoBar.Windows validation did not produce a runtime smoke summary under $smokeArtifacts."
}

$smoke = Get-Content -LiteralPath $summary.FullName -Raw | ConvertFrom-Json
$runtimeSmoke = Get-Content -LiteralPath $runtime.FullName -Raw | ConvertFrom-Json

$requiredProofs = @(
    "processRunning",
    "settingsCreated",
    "activeAccountRepositoriesScoped",
    "localGitFixtureCreated",
    "localGitStatusAttached",
    "archiveFallbackIssueListed",
    "archiveFallbackPullRequestListed",
    "workAccountActive",
    "workCredentialTargetsScoped",
    "responseCacheAccountScoped",
    "pullRequestNotificationsAccountScoped",
    "refreshIntervalConfigured",
    "repositoryMenuSettingsConfigured",
    "localDiscoveryConfigured",
    "localFetchSyncConfigured",
    "actionsMonitoredOwnersConfigured",
    "actionsPlanTierConfigured",
    "clipboardReferenceMonitorConfigured",
    "pullRequestNotificationsConfigured",
    "autoUpdateCheckConfigured",
    "renderedMainMenuComplete",
    "renderedRepositoryMenuComplete"
)

foreach ($proofName in $requiredProofs) {
    $value = $smoke.proof.$proofName
    Assert-True ($value -eq $true) "RepoBar.Windows smoke proof '$proofName' was not true in $($summary.FullName)."
}

Assert-True ($smoke.runtimeSummaryPath -and (Test-Path -LiteralPath $smoke.runtimeSummaryPath)) "RepoBar.Windows smoke summary points to a missing runtime summary."
Assert-True ($smoke.runtimeFirstLocalRepository -eq "steipete/RepoBar") "RepoBar.Windows smoke did not prove local status for steipete/RepoBar."
Assert-True ($smoke.runtimeFirstArchiveIssue -eq "#987 Smoke archive issue") "RepoBar.Windows smoke did not prove archive-backed issue fallback."
Assert-True ($smoke.runtimeFirstArchivePullRequest -eq "#654 Smoke archive pull") "RepoBar.Windows smoke did not prove archive-backed pull request fallback."
Assert-True ($runtimeSmoke.renderedMenuProof.mainMenuComplete -eq $true) "RepoBar.Windows runtime summary did not prove the main menu."
Assert-True ($runtimeSmoke.renderedMenuProof.repositoryMenuComplete -eq $true) "RepoBar.Windows runtime summary did not prove the repository menu."

$result = [ordered]@{
    trx = $trx.FullName
    tests = [int]$counters.total
    smokeSummary = $summary.FullName
    runtimeSummary = $runtime.FullName
    screenshotAvailable = [bool]$smoke.screenshotAvailable
    screenshotPath = $smoke.screenshotPath
    validatedAt = [DateTime]::UtcNow.ToString("o")
}

$resultJson = $result | ConvertTo-Json -Depth 4
$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}
$resultJson | Set-Content -Encoding UTF8 -Path $OutputPath
$resultJson
