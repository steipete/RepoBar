#!/usr/bin/env bash
set -euo pipefail
CONFIGURATION=${1:-debug}
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RepoBar"

# Load version info
source "$ROOT_DIR/version.env"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

log "==> Building ${APP_NAME} (${CONFIGURATION})"
swift build -c "${CONFIGURATION}"

APP_BUNDLE="${ROOT_DIR}/.build/${CONFIGURATION}/${APP_NAME}.app"
if [ -d "${APP_BUNDLE}" ]; then
  log "Built app at ${APP_BUNDLE}"
else
  fail "App bundle not found (SwiftPM may not have produced a bundle)."
fi

# Override Info.plist with packaged settings (LSUIElement, URL scheme, versions).
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
if [ -d "${APP_BUNDLE}" ]; then
  log "==> Writing Info.plist"
  cat > "${INFO_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>com.steipete.repobar</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>SUFeedURL</key><string>https://raw.githubusercontent.com/steipete/RepoBar/main/appcast.xml</string>
    <key>SUPublicEDKey</key><string>AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI=</string>
    <key>SUEnableInstallerLauncherService</key><true/>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.steipete.repobar</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>repobar</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST
fi

# Codesign for distribution/debug
IDENTITY="${CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-Apple Development: Peter Steinberger}}"
if [ -n "${IDENTITY}" ] && [ -d "${APP_BUNDLE}" ]; then
  log "==> Codesigning with ${IDENTITY}"
  "${ROOT_DIR}/Scripts/codesign_app.sh" "${APP_BUNDLE}" "${IDENTITY}" || true
fi

# Package dSYM (release builds only)
if [ "${CONFIGURATION}" = "release" ]; then
  DSYM_DIR="${ROOT_DIR}/.build/${CONFIGURATION}/${APP_NAME}.dSYM"
  if [ -d "${DSYM_DIR}" ]; then
    DSYM_ZIP="${ROOT_DIR}/${APP_NAME}-${MARKETING_VERSION}.dSYM.zip"
    log "==> Zipping dSYM to ${DSYM_ZIP}"
    /usr/bin/ditto -c -k --keepParent "${DSYM_DIR}" "${DSYM_ZIP}"
  else
    log "WARN: dSYM not found at ${DSYM_DIR}"
  fi
fi

# Optional notarization (set NOTARIZE=1 and NOTARY_PROFILE if needed)
if [ "${NOTARIZE:-0}" -eq 1 ] && [ -d "${APP_BUNDLE}" ]; then
  log "==> Notarizing app (profile: ${NOTARY_PROFILE:-Xcode Notary})"
  "${ROOT_DIR}/Scripts/notarize_app.sh" "${APP_BUNDLE}" "${NOTARY_PROFILE:-}" || log "Notarization failed"
fi
