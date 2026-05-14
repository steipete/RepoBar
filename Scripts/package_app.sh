#!/usr/bin/env bash
set -euo pipefail
CONFIGURATION=${1:-debug}
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RepoBar"
BUNDLE_IDENTIFIER="${REPOBAR_BUNDLE_IDENTIFIER:-com.steipete.repobar}"
ARCH_ARGS=()

# Load version info
source "$ROOT_DIR/version.env"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [ "${SKIP_BUILD:-0}" -eq 1 ]; then
  log "==> Skipping build (${CONFIGURATION})"
else
  log "==> Building ${APP_NAME} (${CONFIGURATION})"
  if [ "${CONFIGURATION}" = "release" ]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
  fi
  swift build -c "${CONFIGURATION}" "${ARCH_ARGS[@]}"
  swift build -c "${CONFIGURATION}" "${ARCH_ARGS[@]}" --product repobarcli
fi

BUILD_DIR="${ROOT_DIR}/.build/${CONFIGURATION}"
if [ "${CONFIGURATION}" = "release" ]; then
  UNIVERSAL_DIR="${ROOT_DIR}/.build/apple/Products/Release"
  if [ -f "${UNIVERSAL_DIR}/${APP_NAME}" ]; then
    BUILD_DIR="${UNIVERSAL_DIR}"
  fi
fi
if [ ! -d "${BUILD_DIR}" ]; then
  fail "Build dir not found: ${BUILD_DIR}"
fi

APP_EXECUTABLE="${BUILD_DIR}/${APP_NAME}"
if [ ! -f "${APP_EXECUTABLE}" ]; then
  fail "Missing executable: ${APP_EXECUTABLE}"
fi

APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
if [ -d "${APP_BUNDLE}" ]; then
  if command -v trash >/dev/null 2>&1; then
    trash "${APP_BUNDLE}" || true
  else
    rm -rf "${APP_BUNDLE}"
  fi
fi

ICON_SOURCE="${ROOT_DIR}/Icon.icon"
ICON_TARGET="${ROOT_DIR}/Icon.icns"
if [[ -d "${ICON_SOURCE}" && ! -f "${ICON_TARGET}" ]]; then
  log "==> Generating Icon.icns"
  (cd "${ROOT_DIR}" && "${ROOT_DIR}/Scripts/build_icon.sh" "${ICON_SOURCE}")
fi

log "==> Creating app bundle: ${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Frameworks" "${APP_BUNDLE}/Contents/Resources"
cp "${APP_EXECUTABLE}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" || true

CLI_BINARY="${BUILD_DIR}/repobarcli"
if [ -f "${CLI_BINARY}" ]; then
  log "==> Installing repobarcli"
  cp "${CLI_BINARY}" "${APP_BUNDLE}/Contents/MacOS/repobarcli"
  chmod +x "${APP_BUNDLE}/Contents/MacOS/repobarcli" || true
fi

RESOURCE_BUNDLE="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "${RESOURCE_BUNDLE}" ] && [ -n "$(find "${RESOURCE_BUNDLE}" -type f -print -quit 2>/dev/null || true)" ]; then
  log "==> Installing resources: $(basename "${RESOURCE_BUNDLE}")"
  if command -v ditto >/dev/null 2>&1; then
    ditto "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/$(basename "${RESOURCE_BUNDLE}")"
  else
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/"
  fi
fi

if [ -f "${ICON_TARGET}" ]; then
  log "==> Installing app icon"
  cp "${ICON_TARGET}" "${APP_BUNDLE}/Contents/Resources/Icon.icns"
fi

SPARKLE_FRAMEWORK="${BUILD_DIR}/Sparkle.framework"
if [ -d "${SPARKLE_FRAMEWORK}" ]; then
  log "==> Installing Sparkle.framework"
  if command -v ditto >/dev/null 2>&1; then
    ditto "${SPARKLE_FRAMEWORK}" "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
  else
    cp -R "${SPARKLE_FRAMEWORK}" "${APP_BUNDLE}/Contents/Frameworks/"
  fi

  # SwiftPM builds use @rpath + @loader_path, so keep Sparkle reachable next to the executable.
  ln -sf "../Frameworks/Sparkle.framework" "${APP_BUNDLE}/Contents/MacOS/Sparkle.framework" || true

  # The release binary can carry an `@executable_path/../lib` rpath; provide a stable location there too.
  mkdir -p "${APP_BUNDLE}/Contents/lib"
  ln -sf "../Frameworks/Sparkle.framework" "${APP_BUNDLE}/Contents/lib/Sparkle.framework" || true
fi

# Override Info.plist with packaged settings (LSUIElement, URL scheme, versions).
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
log "==> Writing Info.plist"
cat > "${INFO_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>SUFeedURL</key><string>https://raw.githubusercontent.com/steipete/RepoBar/main/appcast.xml</string>
    <key>SUPublicEDKey</key><string>AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI=</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUEnableInstallerLauncherService</key><true/>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>NSHighResolutionCapable</key><true/>
$(if [ "${CONFIGURATION}" = "debug" ]; then cat <<'PLIST_DEBUG_AUTH'
    <key>RepoBarTokenStore</key><string>file</string>
PLIST_DEBUG_AUTH
fi)
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>${BUNDLE_IDENTIFIER}</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>repobar</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Codesign for distribution/debug
IDENTITY="${CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
if [ -n "${IDENTITY}" ] && [ -d "${APP_BUNDLE}" ]; then
  log "==> Codesigning with ${IDENTITY}"
  "${ROOT_DIR}/Scripts/codesign_app.sh" "${APP_BUNDLE}" "${IDENTITY}" || true
elif [ "${CONFIGURATION}" = "debug" ] && [ -d "${APP_BUNDLE}" ] && command -v codesign >/dev/null 2>&1; then
  log "==> Ad-hoc codesigning debug app"
  codesign --force --deep --sign - "${APP_BUNDLE}" || true
fi

# Package dSYM (release builds only)
if [ "${CONFIGURATION}" = "release" ]; then
  DSYM_DIR="${BUILD_DIR}/${APP_NAME}.dSYM"
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
