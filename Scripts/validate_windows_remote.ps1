param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    $installRoot = Join-Path $env:TEMP "repobar-dotnet"
    $installScript = Join-Path $env:TEMP "dotnet-install.ps1"

    New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing "https://dot.net/v1/dotnet-install.ps1" -OutFile $installScript
    & $installScript -Channel 8.0 -InstallDir $installRoot -NoPath

    $env:PATH = "$installRoot;$env:PATH"
}

dotnet --info
./Scripts/build_windows.ps1 build -Runtime $Runtime
./Scripts/build_windows.ps1 test
./Scripts/smoke_windows.ps1 -Runtime $Runtime
