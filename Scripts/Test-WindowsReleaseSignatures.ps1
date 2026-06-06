<#
.SYNOPSIS
    Verifies RepoBar Windows release executable signing policy.

.DESCRIPTION
    Classifies every .exe in the Windows release payload. RepoBar.Windows.exe
    must carry a valid Authenticode signature when -RequireSignedRepoBar is
    passed. Unknown executables fail closed so new payloads must make an
    intentional signing decision.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadPath,

    [switch]$RequireSignedRepoBar,

    [string]$TrustedSignerPattern = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$payloadRoot = (Resolve-Path -LiteralPath $PayloadPath).Path

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    [System.IO.Path]::GetRelativePath($Root, $Path).Replace('/', '\')
}

function Get-ExecutableClassification {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    switch -Regex ($RelativePath) {
        '^RepoBar\.Windows\.exe$' { return "RepoBarOwned" }
        default { return "Unknown" }
    }
}

$executables = @(
    Get-ChildItem -LiteralPath $payloadRoot -Recurse -File -Filter *.exe |
        Sort-Object FullName |
        ForEach-Object {
            $relativePath = Get-RelativePath -Root $payloadRoot -Path $_.FullName
            $signature = Get-AuthenticodeSignature -LiteralPath $_.FullName
            $signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { "" }
            [pscustomobject]@{
                RelativePath = $relativePath
                Classification = Get-ExecutableClassification -RelativePath $relativePath
                SignatureStatus = $signature.Status.ToString()
                SignerSubject = $signerSubject
            }
        }
)

if ($executables.Count -eq 0) {
    throw "No executables found under $payloadRoot."
}

$executables | Format-Table -AutoSize

$errors = New-Object System.Collections.Generic.List[string]

foreach ($exe in $executables) {
    switch ($exe.Classification) {
        "RepoBarOwned" {
            if ($RequireSignedRepoBar -and $exe.SignatureStatus -ne "Valid") {
                $errors.Add("RepoBar executable is not validly signed: $($exe.RelativePath) [$($exe.SignatureStatus)]")
            }
            if ($TrustedSignerPattern -and $exe.SignatureStatus -eq "Valid" -and $exe.SignerSubject -notmatch $TrustedSignerPattern) {
                $errors.Add("RepoBar executable signer did not match trusted release signer: $($exe.RelativePath) [$($exe.SignerSubject)]")
            }
        }
        default {
            $errors.Add("Unknown executable in release payload: $($exe.RelativePath)")
        }
    }
}

if (-not ($executables | Where-Object RelativePath -eq "RepoBar.Windows.exe")) {
    $errors.Add("Missing RepoBar.Windows.exe.")
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "RepoBar Windows release signing policy passed." -ForegroundColor Green
