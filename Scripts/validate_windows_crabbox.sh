#!/usr/bin/env bash
set -euo pipefail

CRABBOX_BIN="${CRABBOX_BIN:-crabbox}"
PROVIDER="${CRABBOX_PROVIDER:-aws}"
TARGET="${CRABBOX_TARGET:-windows}"
WINDOWS_SHELL="${CRABBOX_WINDOWS_SHELL:-powershell.exe}"
RUNTIME="${CRABBOX_WINDOWS_RUNTIME:-win-x64}"

"$CRABBOX_BIN" run --provider "$PROVIDER" --target "$TARGET" -- "$WINDOWS_SHELL" -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./Scripts/validate_windows_remote.ps1 -Runtime "$RUNTIME"
