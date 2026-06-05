param(
    [ValidateSet("build", "test", "publish", "run")]
    [string]$Command = "build",

    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",

    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$project = Join-Path $root "Windows/RepoBar.Windows/RepoBar.Windows.csproj"
$testProject = Join-Path $root "Windows/RepoBar.Windows.Tests/RepoBar.Windows.Tests.csproj"

switch ($Command) {
    "build" {
        dotnet build $project -c $Configuration -r $Runtime
    }
    "test" {
        dotnet test $testProject -c $Configuration
    }
    "publish" {
        dotnet publish $project -c $Configuration -r $Runtime --self-contained true `
            -p:PublishSingleFile=true `
            -p:IncludeNativeLibrariesForSelfExtract=true `
            -p:PublishReadyToRun=true
    }
    "run" {
        dotnet run --project $project -c Debug
    }
}
