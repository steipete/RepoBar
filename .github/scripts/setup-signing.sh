#!/bin/bash
set -euo pipefail
set +x
umask 077
for name in MACOS_SIGNING_P12 MACOS_SIGNING_P12_PASSWORD ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_P8 SPARKLE_PRIVATE_KEY; do
  [[ -n "${!name:-}" ]] || { echo "Missing release secret: $name" >&2; exit 1; }
done
printf '%s' "$MACOS_SIGNING_P12" | base64 --decode > "$RUNNER_TEMP/signing.p12"
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$RUNNER_TEMP/sparkle-key"
security list-keychains -d user > "$RUNNER_TEMP/original-keychains"
keychain="$RUNNER_TEMP/release.keychain-db"
password="$(openssl rand -hex 24)"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$RUNNER_TEMP/signing.p12" -k "$keychain" -P "$MACOS_SIGNING_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$password" "$keychain" >/dev/null
python3 - "$keychain" "$RUNNER_TEMP/original-keychains" <<'PY'
import pathlib, shlex, subprocess, sys
subprocess.run(['security','list-keychains','-d','user','-s',sys.argv[1],*shlex.split(pathlib.Path(sys.argv[2]).read_text())], check=True)
PY
security find-identity -v -p codesigning "$keychain" | grep -F 'Developer ID Application: Peter Steinberger (Y5PE65HELJ)' >/dev/null
rm "$RUNNER_TEMP/signing.p12"
