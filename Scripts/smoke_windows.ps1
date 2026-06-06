param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",

    [string]$Configuration = "Release",

    [int]$LaunchSeconds = 8
)

$ErrorActionPreference = "Stop"

function Invoke-Native {
    $command = $args[0]
    $nativeArgs = @()
    if ($args.Count -gt 1) {
        $nativeArgs = $args[1..($args.Count - 1)]
    }
    & $command @nativeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "$command exited with code $LASTEXITCODE"
    }
}

function Save-SmokeScreenshot {
    param(
        [string]$Path
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        if ($null -eq $screen -or $screen.Bounds.Width -le 0 -or $screen.Bounds.Height -le 0) {
            return $null
        }

        $bounds = $screen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
            return [ordered]@{
                path = $Path
                error = $null
            }
        }
        finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
    catch {
        Write-Warning "RepoBar.Windows smoke screenshot unavailable: $($_.Exception.Message)"
        return [ordered]@{
            path = $null
            error = $_.Exception.Message
        }
    }
}

function Initialize-LocalGitSmokeFixture {
    param(
        [string]$ProjectsRoot
    )

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        throw "Git is required for the RepoBar.Windows local project smoke proof."
    }

    New-Item -ItemType Directory -Force -Path $ProjectsRoot | Out-Null
    $repoPath = Join-Path $ProjectsRoot "RepoBar"
    if (Test-Path $repoPath) {
        Remove-Item $repoPath -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $repoPath | Out-Null
    Invoke-Native git -C $repoPath init -b main | Out-Null
    Invoke-Native git -C $repoPath config user.email "repobar-smoke@example.invalid" | Out-Null
    Invoke-Native git -C $repoPath config user.name "RepoBar Smoke" | Out-Null
    Invoke-Native git -C $repoPath remote add origin "https://github.com/steipete/RepoBar.git" | Out-Null
    Set-Content -Encoding UTF8 -Path (Join-Path $repoPath "README.md") -Value "RepoBar smoke fixture"
    Invoke-Native git -C $repoPath add README.md | Out-Null
    Invoke-Native git -C $repoPath commit -m "smoke fixture" | Out-Null

    return $repoPath
}

function Wait-SmokeRuntimeSummary {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 30
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path $Path) {
            return Get-Content $Path -Raw | ConvertFrom-Json
        }

        Start-Sleep -Milliseconds 500
    }

    throw "RepoBar.Windows did not write the runtime smoke summary at $Path."
}

function Initialize-SmokeSettings {
    param(
        [string]$Path,
        [string]$ProjectsRoot,
        [string]$ArchiveDatabasePath
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $settings = [ordered]@{
        activeAccountId = "work"
        accounts = @(
            [ordered]@{
                id = "default"
                label = "Default"
                gitHubHost = "github.com"
                tokenEnvironmentVariable = "REPOBAR_GITHUB_TOKEN"
                gitHubOAuthClientId = "Iv23liGm2arUyotWSjwJ"
                gitHubOAuthClientSecretEnvironmentVariable = "REPOBAR_GITHUB_CLIENT_SECRET"
            },
            [ordered]@{
                id = "work"
                label = "Work"
                gitHubHost = "github.com"
                tokenEnvironmentVariable = "REPOBAR_WORK_GITHUB_TOKEN"
                gitHubOAuthClientId = "Iv23liGm2arUyotWSjwJ"
                gitHubOAuthClientSecretEnvironmentVariable = "REPOBAR_WORK_GITHUB_CLIENT_SECRET"
            }
        )
        refreshIntervalMinutes = 5
        openMenuOnLeftClick = $true
        discoverLocalProjects = $true
        localProjectsRoot = $ProjectsRoot
        localProjectsMaxDepth = 3
        localWorktreeFolderName = ".work"
        fetchLocalProjectsBeforeStatus = $false
        localProjectsFetchIntervalMinutes = 5
        showDirtyFilesInMenu = $true
        enableResponseCache = $true
        gitHubArchiveDatabasePath = $ArchiveDatabasePath
        repositoryDisplayLimit = 6
        repositoryMenuScope = "all"
        repositorySortKey = "activity"
        showRateLimits = $true
        showContributionSummary = $false
        actionsMonitoredOwners = @("steipete")
        diagnosticsEnabled = $true
        loggingVerbosity = "debug"
        fileLoggingEnabled = $true
        menuCustomization = [ordered]@{
            hiddenMainMenuItems = @()
            mainMenuOrder = @(
                "refreshNow",
                "contributionSummary",
                "globalCommits",
                "globalActivity",
                "actionsUsage",
                "rateLimits",
                "repositoryScope",
                "repositorySort",
                "myRepositories",
                "diagnostics",
                "issueNavigator",
                "accountSwitcher",
                "logOut",
                "preferences",
                "about",
                "checkForUpdates",
                "copyUpdateDiagnostics",
                "openSettingsFile",
                "clearResponseCache",
                "quit"
            )
            hiddenRepositoryMenuItems = @()
            repositoryMenuOrder = @(
                "openRepository",
                "openIssues",
                "openPullRequests",
                "openActions",
                "checkout",
                "recentIssues",
                "recentPullRequests",
                "releases",
                "ciRuns",
                "branches",
                "tags",
                "commits",
                "contributors",
                "activity",
                "discussions",
                "latestRelease",
                "statusDetails",
                "traffic",
                "heatmap",
                "changelog",
                "localStatus",
                "pushedAt",
                "visibility"
            )
        }
        repositories = @(
            [ordered]@{
                owner = "steipete"
                name = "RepoBar"
                visibility = "pinned"
            }
        )
    }

    $settings | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path $Path
}

$isWindowsHost = if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWindows } else { $env:OS -eq "Windows_NT" }
if (-not $isWindowsHost) {
    throw "Windows tray smoke must run on Windows."
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$project = Join-Path $root "Windows/RepoBar.Windows/RepoBar.Windows.csproj"
$appData = Join-Path $env:APPDATA "RepoBar"
$settingsPath = Join-Path $appData "windows-settings.json"
$smokeArtifacts = Join-Path $root "dist/windows/smoke"
$timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$screenshotPath = Join-Path $smokeArtifacts "repobar-windows-smoke-$timestamp.png"
$summaryPath = Join-Path $smokeArtifacts "repobar-windows-smoke-$timestamp.json"
$runtimeSummaryPath = Join-Path $smokeArtifacts "repobar-windows-runtime-$timestamp.json"
$archiveDatabasePath = Join-Path $smokeArtifacts "repobar-windows-archive-$timestamp.sqlite"

Invoke-Native dotnet publish $project -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:PublishReadyToRun=true

$exe = Get-ChildItem -Path (Join-Path $root "Windows/RepoBar.Windows/bin/$Configuration") `
    -Filter "RepoBar.Windows.exe" `
    -Recurse |
    Where-Object { $_.FullName -like "*$Runtime*publish*" } |
    Select-Object -First 1
if ($null -eq $exe) {
    throw "Published executable not found."
}

if (Test-Path $settingsPath) {
    Remove-Item $settingsPath -Force
}

$projectsRoot = Join-Path $env:USERPROFILE "Projects"
$localFixturePath = Initialize-LocalGitSmokeFixture -ProjectsRoot $projectsRoot
Initialize-SmokeSettings -Path $settingsPath -ProjectsRoot $projectsRoot -ArchiveDatabasePath $archiveDatabasePath
$previousRuntimeSummaryPath = $env:REPOBAR_WINDOWS_SMOKE_SUMMARY_PATH
$previousSmokeArchiveFixture = $env:REPOBAR_WINDOWS_SMOKE_ARCHIVE_FIXTURE
$previousSmokeForceArchiveFallback = $env:REPOBAR_WINDOWS_SMOKE_FORCE_ARCHIVE_FALLBACK
$env:REPOBAR_WINDOWS_SMOKE_SUMMARY_PATH = $runtimeSummaryPath
$env:REPOBAR_WINDOWS_SMOKE_ARCHIVE_FIXTURE = "1"
$env:REPOBAR_WINDOWS_SMOKE_FORCE_ARCHIVE_FALLBACK = "1"
$process = Start-Process -FilePath $exe.FullName -PassThru
try {
    Start-Sleep -Seconds $LaunchSeconds
    if ($process.HasExited) {
        throw "RepoBar.Windows exited during smoke with code $($process.ExitCode)."
    }
    if (-not (Test-Path $settingsPath)) {
        throw "RepoBar.Windows did not create $settingsPath."
    }

    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $repositories = @($settings.repositories)
    if ($repositories.Count -lt 1) {
        throw "RepoBar.Windows settings did not include the sample repository."
    }

    New-Item -ItemType Directory -Force -Path $smokeArtifacts | Out-Null
    $screenshot = Save-SmokeScreenshot -Path $screenshotPath
    $capturedScreenshot = $screenshot.path
    $runtimeSummary = Wait-SmokeRuntimeSummary -Path $runtimeSummaryPath
    $localRepositories = @($runtimeSummary.localRepositories)
    $runtimeRows = @($runtimeSummary.rows)
    $localRepo = $localRepositories | Where-Object { $_.fullName -eq "steipete/RepoBar" } | Select-Object -First 1
    $localRow = $runtimeRows | Where-Object { $_.repository -eq "steipete/RepoBar" -and $_.hasLocalStatus } | Select-Object -First 1
    if ($null -eq $localRepo -or $null -eq $localRow) {
        throw "RepoBar.Windows runtime smoke did not attach local Git status to steipete/RepoBar."
    }
    $archiveIssueTitles = @($localRow.recentIssueTitles)
    $archivePullTitles = @($localRow.recentPullRequestTitles)
    if ($archiveIssueTitles -notcontains "#987 Smoke archive issue") {
        throw "RepoBar.Windows runtime smoke did not render the archive-backed recent issue fallback."
    }
    if ($archivePullTitles -notcontains "#654 Smoke archive pull") {
        throw "RepoBar.Windows runtime smoke did not render the archive-backed recent pull request fallback."
    }
    if ($runtimeSummary.activeAccountId -ne "work") {
        throw "RepoBar.Windows runtime smoke did not use the work account profile."
    }
    if (-not $runtimeSummary.fileLoggingEnabled -or -not (Test-Path $runtimeSummary.logFilePath)) {
        throw "RepoBar.Windows runtime smoke did not write the configured diagnostics log file."
    }

    $activeAccount = @($settings.accounts) | Where-Object { $_.id -eq $settings.activeAccountId } | Select-Object -First 1
    $sampleRepository = $repositories | Select-Object -First 1
    $menuOrder = @($settings.menuCustomization.mainMenuOrder)
    $summary = [ordered]@{
        pid = $process.Id
        processName = $process.ProcessName
        executablePath = $exe.FullName
        runtime = $Runtime
        configuration = $Configuration
        settingsPath = $settingsPath
        activeAccountId = $settings.activeAccountId
        activeAccountLabel = if ($activeAccount) { $activeAccount.label } else { $null }
        gitHubHost = $settings.githubHost
        repositoryCount = $repositories.Count
        sampleRepository = if ($sampleRepository) { "$($sampleRepository.owner)/$($sampleRepository.name)" } else { $null }
        localGitFixturePath = $localFixturePath
        gitHubArchiveDatabasePath = $archiveDatabasePath
        localRepositoryCount = $runtimeSummary.localRepositoryCount
        runtimeSummaryPath = $runtimeSummaryPath
        runtimeFirstLocalRepository = $localRepo.fullName
        runtimeFirstLocalSync = $localRepo.syncDetail
        runtimeFirstRowLabel = $localRow.label
        runtimeFirstArchiveIssue = $archiveIssueTitles | Select-Object -First 1
        runtimeFirstArchivePullRequest = $archivePullTitles | Select-Object -First 1
        runtimeActiveAccountId = $runtimeSummary.activeAccountId
        runtimeActiveAccountLabel = $runtimeSummary.activeAccountLabel
        runtimeActiveAccountCredentialTargets = @($runtimeSummary.activeAccountCredentialTargets)
        runtimeDiagnosticsEnabled = $runtimeSummary.diagnosticsEnabled
        runtimeLoggingVerbosity = $runtimeSummary.loggingVerbosity
        runtimeFileLoggingEnabled = $runtimeSummary.fileLoggingEnabled
        runtimeLogFilePath = $runtimeSummary.logFilePath
        mainMenuOrder = $menuOrder
        proof = [ordered]@{
            processRunning = -not $process.HasExited
            settingsCreated = Test-Path $settingsPath
            sampleRepositoryConfigured = $null -ne $sampleRepository
            localGitFixtureCreated = Test-Path (Join-Path $localFixturePath ".git")
            localGitStatusAttached = $null -ne $localRow
            archiveFallbackIssueListed = $archiveIssueTitles -contains "#987 Smoke archive issue"
            archiveFallbackPullRequestListed = $archivePullTitles -contains "#654 Smoke archive pull"
            workAccountActive = $runtimeSummary.activeAccountId -eq "work"
            workCredentialTargetsScoped = @($runtimeSummary.activeAccountCredentialTargets) -contains "RepoBar.Windows:github.com:work"
            accountSwitcherConfigured = $menuOrder -contains "accountSwitcher"
            cacheResetConfigured = $menuOrder -contains "clearResponseCache"
            repositoryScopeConfigured = $menuOrder -contains "repositoryScope"
            repositorySortConfigured = $menuOrder -contains "repositorySort"
            myRepositoriesConfigured = $menuOrder -contains "myRepositories"
            diagnosticsConfigured = $menuOrder -contains "diagnostics"
            aboutConfigured = $menuOrder -contains "about"
            diagnosticsCaptureEnabled = $runtimeSummary.diagnosticsEnabled
            logVerbosityConfigured = $runtimeSummary.loggingVerbosity -eq "debug"
            fileLoggingWritten = $runtimeSummary.fileLoggingEnabled -and (Test-Path $runtimeSummary.logFilePath)
            localFetchIntervalConfigured = $settings.localProjectsFetchIntervalMinutes -eq 5
            actionsMonitoredOwnersConfigured = @($settings.actionsMonitoredOwners) -contains "steipete"
            updateDiagnosticsConfigured = $menuOrder -contains "copyUpdateDiagnostics"
        }
        screenshotAvailable = $null -ne $capturedScreenshot
        screenshotPath = $capturedScreenshot
        screenshotError = $screenshot.error
        capturedAt = [DateTime]::UtcNow.ToString("o")
    }
    $summary | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path $summaryPath

    $screenshotText = if ($capturedScreenshot) { $capturedScreenshot } else { "unavailable" }
    $proofText = "processRunning=$($summary.proof.processRunning), settingsCreated=$($summary.proof.settingsCreated), sampleRepository=$($summary.sampleRepository), localRepositoryCount=$($summary.localRepositoryCount), localGitStatusAttached=$($summary.proof.localGitStatusAttached), archiveFallbackIssue=$($summary.proof.archiveFallbackIssueListed), archiveFallbackPullRequest=$($summary.proof.archiveFallbackPullRequestListed), workAccountActive=$($summary.proof.workAccountActive), workCredentialTargetsScoped=$($summary.proof.workCredentialTargetsScoped), accountSwitcher=$($summary.proof.accountSwitcherConfigured), cacheReset=$($summary.proof.cacheResetConfigured), repositoryScope=$($summary.proof.repositoryScopeConfigured), repositorySort=$($summary.proof.repositorySortConfigured), myRepositories=$($summary.proof.myRepositoriesConfigured), diagnostics=$($summary.proof.diagnosticsConfigured), about=$($summary.proof.aboutConfigured), diagnosticsCapture=$($summary.proof.diagnosticsCaptureEnabled), logVerbosity=$($summary.proof.logVerbosityConfigured), fileLogging=$($summary.proof.fileLoggingWritten), localFetchInterval=$($summary.proof.localFetchIntervalConfigured), actionsMonitoredOwners=$($summary.proof.actionsMonitoredOwnersConfigured), updateDiagnostics=$($summary.proof.updateDiagnosticsConfigured)"
    Write-Host "RepoBar.Windows smoke passed: pid=$($process.Id), settings=$settingsPath, screenshot=$screenshotText, summary=$summaryPath"
    Write-Host "RepoBar.Windows smoke proof: $proofText"
}
finally {
    $env:REPOBAR_WINDOWS_SMOKE_SUMMARY_PATH = $previousRuntimeSummaryPath
    $env:REPOBAR_WINDOWS_SMOKE_ARCHIVE_FIXTURE = $previousSmokeArchiveFixture
    $env:REPOBAR_WINDOWS_SMOKE_FORCE_ARCHIVE_FALLBACK = $previousSmokeForceArchiveFallback
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
}
