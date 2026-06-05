param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",

    [string]$Configuration = "Release",

    [int]$LaunchSeconds = 8
)

$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
    throw "Windows tray smoke must run on Windows."
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$project = Join-Path $root "Windows/RepoBar.Windows/RepoBar.Windows.csproj"
$appData = Join-Path $env:APPDATA "RepoBar"
$settingsPath = Join-Path $appData "windows-settings.json"

dotnet publish $project -c $Configuration -r $Runtime --self-contained true `
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
    if (-not $settings.repositories -or $settings.repositories.Count -lt 1) {
        throw "RepoBar.Windows settings did not include the sample repository."
    }

    Write-Host "RepoBar.Windows smoke passed: pid=$($process.Id), settings=$settingsPath"
}
finally {
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
}
