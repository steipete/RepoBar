param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64"
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

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    $installRoot = Join-Path $env:TEMP "repobar-dotnet"
    $installScript = Join-Path $env:TEMP "dotnet-install.ps1"

    New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing "https://dot.net/v1/dotnet-install.ps1" -OutFile $installScript
    & $installScript -Channel 8.0 -InstallDir $installRoot -NoPath

    $env:PATH = "$installRoot;$env:PATH"
}

Invoke-Native dotnet --info
./Scripts/build_windows.ps1 build -Runtime $Runtime
./Scripts/build_windows.ps1 test
./Scripts/smoke_windows.ps1 -Runtime $Runtime
