#!/usr/bin/env bash
set -euo pipefail

CRABBOX_BIN="${CRABBOX_BIN:-crabbox}"
PROVIDER="${CRABBOX_PROVIDER:-aws}"
TARGET="${CRABBOX_TARGET:-windows}"

"$CRABBOX_BIN" run --provider "$PROVIDER" --target "$TARGET" -- pwsh -NoLogo -NoProfile -Command '
  $ErrorActionPreference = "Stop"
  dotnet --info
  ./Scripts/build_windows.ps1 build -Runtime win-x64
  ./Scripts/build_windows.ps1 test
  ./Scripts/smoke_windows.ps1 -Runtime win-x64
'
