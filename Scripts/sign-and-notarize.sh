#!/usr/bin/env bash
set -euo pipefail

APP_NAME="RepoBar"
APP_IDENTITY="Developer ID Application: Peter Steinberger (Y5PE65HELJ)"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
ZIP_NAME="RepoBar-${MARKETING_VERSION}.zip"
DSYM_ZIP="RepoBar-${MARKETING_VERSION}.dSYM.zip"

if [[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing APP_STORE_CONNECT_* env vars (API key, key id, issuer id)." >&2
  exit 1
fi
api_key_p8=${APP_STORE_CONNECT_API_KEY_P8//\\n/$'\n'}
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/repobar-notarize.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
API_KEY_FILE="$WORK_DIR/api-key.p8"
NOTARY_ZIP="$WORK_DIR/RepoBarNotarize.zip"
(umask 077; printf "%s\n" "$api_key_p8" > "$API_KEY_FILE")

echo "Checking notarization access"
xcrun notarytool history --key "$API_KEY_FILE" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" > /dev/null

swift build -c release --arch arm64 --arch x86_64
SKIP_BUILD=1 ./Scripts/package_app.sh release

# SwiftPM output locations vary (Xcode toolchain + SwiftPM version).
# Resolve the produced app bundle explicitly instead of assuming `./RepoBar.app`.
APP_BUNDLE=""
for candidate in \
  ".build/apple/Products/Release/${APP_NAME}.app" \
  ".build/release/${APP_NAME}.app" \
  ".build/arm64-apple-macosx/release/${APP_NAME}.app" \
  ".build/x86_64-apple-macosx/release/${APP_NAME}.app"; do
  if [[ -d "$candidate" ]]; then
    APP_BUNDLE="$candidate"
    break
  fi
done
if [[ -z "$APP_BUNDLE" ]]; then
  echo "ERROR: app bundle not found (looked in common SwiftPM release locations)" >&2
  exit 1
fi

echo "Signing with $APP_IDENTITY"
export REPOBAR_SKIP_KEYCHAIN_GROUPS="${REPOBAR_SKIP_KEYCHAIN_GROUPS:-1}"
./Scripts/codesign_app.sh "$APP_BUNDLE" "$APP_IDENTITY"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$NOTARY_ZIP"

echo "Submitting for notarization"
xcrun notarytool submit "$NOTARY_ZIP" \
  --key "$API_KEY_FILE" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --no-s3-acceleration \
  --wait

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

"$DITTO_BIN" -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$ZIP_NAME"

/usr/sbin/spctl -a -t exec -vv "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "Packaging dSYM"
DSYM_PATH=".build/apple/Products/Release/RepoBar.dSYM"
if [[ ! -d "$DSYM_PATH" ]]; then
  DSYM_PATH=".build/release/RepoBar.dSYM"
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  DSYM_PATH=".build/arm64-apple-macosx/release/RepoBar.dSYM"
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  DSYM_PATH=".build/x86_64-apple-macosx/release/RepoBar.dSYM"
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  echo "Missing dSYM at $DSYM_PATH" >&2
  exit 1
fi
"$DITTO_BIN" -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"

echo "Done: $ZIP_NAME"
