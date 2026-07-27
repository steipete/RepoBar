#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CACHE_PATH="${HOME}/Library/Caches/RepoBar/swiftpm"
mkdir -p "${CACHE_PATH}"

./Scripts/swiftpm_sanitize.sh

echo "==> swift build --build-tests"
swift build -q --build-tests --cache-path "${CACHE_PATH}"

BIN_PATH="$(swift build --show-bin-path --cache-path "${CACHE_PATH}")"
if [ -d "${BIN_PATH}/Sparkle.framework" ]; then
  mkdir -p "${BIN_PATH}/PackageFrameworks"
  ln -sfn "../Sparkle.framework" "${BIN_PATH}/PackageFrameworks/Sparkle.framework"
fi

echo "==> swift test --skip-build"
swift test -q --skip-build --cache-path "${CACHE_PATH}" "$@"
