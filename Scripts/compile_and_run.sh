#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RepoBar"
APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
# Load signing defaults from Config/Local.xcconfig if present
if [ -f "${ROOT_DIR}/Config/Local.xcconfig" ]; then
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/Config/Local.xcconfig"
fi

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

kill_existing() {
  for _ in {1..10}; do
    pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -x "${APP_NAME}" 2>/dev/null || true
    pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null || pgrep -x "${APP_NAME}" >/dev/null || return 0
    sleep 0.2
  done
}

log "==> Killing existing ${APP_NAME} instances"
kill_existing

log "==> swift build"
swift build -q

log "==> swift test"
swift test -q

log "==> Codesigning debug build"
DEFAULT_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development: Peter Steinberger}"
IDENTITY="${CODESIGN_IDENTITY:-$DEFAULT_IDENTITY}"
if [ -d "${ROOT_DIR}/.build/debug/${APP_NAME}.app" ]; then
  "${ROOT_DIR}/Scripts/codesign_app.sh" "${ROOT_DIR}/.build/debug/${APP_NAME}.app" "$IDENTITY" || true
else
  codesign --force --sign "$IDENTITY" "${ROOT_DIR}/.build/debug/${APP_NAME}" 2>/dev/null || true
fi

log "==> Launching debug build"
"${ROOT_DIR}/.build/debug/${APP_NAME}" &

sleep 1
if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1 || pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  log "OK: ${APP_NAME} is running."
else
  fail "App exited immediately."
fi
