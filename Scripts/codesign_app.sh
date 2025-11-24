#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/debug/RepoBar.app}"
# Default to Peter's Apple Development cert; allow override via second arg or CODESIGN_IDENTITY/Local.xcconfig.
DEFAULT_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development: Peter Steinberger}"
IDENTITY="${2:-${CODESIGN_IDENTITY:-$DEFAULT_IDENTITY}}"
ENTITLEMENTS="$ROOT_DIR/RepoBar.entitlements"
TMP_ENTITLEMENTS="/tmp/RepoBar_entitlements.plist"

log() { printf '%s\n' "[$(date '+%H:%M:%S')] $*"; }

if [ ! -d "$APP_PATH" ]; then
  log "App bundle not found: $APP_PATH"
  exit 1
fi

# Prepare entitlements (enable hardened runtime, Sparkle XPC exceptions)
if [ -f "$ENTITLEMENTS" ]; then
  sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo 'com.steipete.repobar')/" \
    "$ENTITLEMENTS" > "$TMP_ENTITLEMENTS"
else
  cat > "$TMP_ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.hardened-runtime</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>com.steipete.repobar-spks</string>
        <string>com.steipete.repobar-spkd</string>
    </array>
</dict>
</plist>
PLIST
fi

log "Signing frameworks (if any)"
find "$APP_PATH/Contents/Frameworks" \( -type d -name '*.framework' -o -type f -name '*.dylib' \) 2>/dev/null | while read -r fw; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$fw"
done

log "Signing main binary"
codesign --force --options runtime --timestamp --entitlements "$TMP_ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH/Contents/MacOS/RepoBar"

log "Signing app bundle"
codesign --force --options runtime --timestamp --entitlements "$TMP_ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH"

log "Verifying"
codesign --verify --verbose=2 "$APP_PATH"

rm -f "$TMP_ENTITLEMENTS"
log "Done codesigning $APP_PATH"
