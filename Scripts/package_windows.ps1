param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",

    [string]$Configuration = "Release",

    [string]$Version = "",

    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$project = Join-Path $root "Windows/RepoBar.Windows/RepoBar.Windows.csproj"
$installerScript = Join-Path $root "Windows/installer.iss"
$publishRoot = Join-Path $root "dist/windows/publish/$Runtime"

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionEnv = Join-Path $root "version.env"
    if (Test-Path $versionEnv) {
        $line = Get-Content $versionEnv | Where-Object { $_ -match '^(MARKETING_VERSION|VERSION)=' } | Select-Object -First 1
        if ($line) {
            $Version = $line -replace '^(MARKETING_VERSION|VERSION)=', ''
        }
    }
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = "0.1.0"
}

if (Test-Path $publishRoot) {
    Remove-Item $publishRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $publishRoot | Out-Null

dotnet publish $project -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:PublishReadyToRun=true `
    -o $publishRoot

if ($SkipInstaller) {
    Write-Host "Published RepoBar.Windows to $publishRoot"
    return
}

$isccCommand = Get-Command iscc.exe -ErrorAction SilentlyContinue
$iscc = if ($isccCommand) { $isccCommand.Source } else { $null }
if (-not $iscc) {
    $defaultIscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (Test-Path $defaultIscc) {
        $iscc = $defaultIscc
    }
}
if (-not $iscc) {
    throw "Inno Setup compiler not found. Install Inno Setup 6 or rerun with -SkipInstaller."
}

$env:REPOBAR_WINDOWS_VERSION = $Version
$env:REPOBAR_WINDOWS_PUBLISH_DIR = $publishRoot
& $iscc $installerScript
