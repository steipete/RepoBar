param(
    [ValidateSet("build", "test", "publish", "run")]
    [string]$Command = "build",

    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",

    [string]$Configuration = "Release"
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

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$project = Join-Path $root "Windows/RepoBar.Windows/RepoBar.Windows.csproj"
$testProject = Join-Path $root "Windows/RepoBar.Windows.Tests/RepoBar.Windows.Tests.csproj"
$testResults = Join-Path $root "dist/windows/test-results"

switch ($Command) {
    "build" {
        Invoke-Native dotnet build $project -c $Configuration -r $Runtime
    }
    "test" {
        $trxPath = Join-Path $testResults "repobar-windows-tests.trx"
        New-Item -ItemType Directory -Force -Path $testResults | Out-Null
        Invoke-Native dotnet test $testProject -c $Configuration --logger "trx;LogFileName=repobar-windows-tests.trx" --results-directory $testResults
        Write-Host "RepoBar.Windows test results: $trxPath"
    }
    "publish" {
        Invoke-Native dotnet publish $project -c $Configuration -r $Runtime --self-contained true `
            -p:PublishSingleFile=true `
            -p:IncludeNativeLibrariesForSelfExtract=true `
            -p:PublishReadyToRun=true
    }
    "run" {
        Invoke-Native dotnet run --project $project -c Debug
    }
}
