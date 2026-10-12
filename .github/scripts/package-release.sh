#!/bin/bash
set -euo pipefail
source version.env
export APP_STORE_CONNECT_KEY_ID="$ASC_KEY_ID"
export APP_STORE_CONNECT_ISSUER_ID="$ASC_ISSUER_ID"
export APP_STORE_CONNECT_API_KEY_P8="$ASC_PRIVATE_KEY_P8"
./Scripts/sign-and-notarize.sh
mv "RepoBar-${MARKETING_VERSION}.zip" "RepoBar-${MARKETING_VERSION}.dSYM.zip" release/
feed_dir="$RUNNER_TEMP/sparkle-feed"
mkdir "$feed_dir"
cp appcast.xml "$feed_dir/"
cp "release/RepoBar-${MARKETING_VERSION}.zip" "$feed_dir/"
python3 - "$feed_dir/RepoBar-${MARKETING_VERSION}.html" <<'PY'
import html, pathlib, sys
notes = pathlib.Path('release/RELEASE-NOTES.md').read_text()
pathlib.Path(sys.argv[1]).write_text('<html><body><pre>' + html.escape(notes) + '</pre></body></html>')
PY
sparkle_bin="$PWD/.build/artifacts/sparkle/Sparkle/bin"
"$sparkle_bin/generate_appcast" --ed-key-file "$RUNNER_TEMP/sparkle-key" \
  --download-url-prefix "https://github.com/steipete/RepoBar/releases/download/v${MARKETING_VERSION}/" \
  --embed-release-notes --maximum-deltas 0 \
  --link 'https://raw.githubusercontent.com/steipete/RepoBar/main/appcast.xml' "$feed_dir"
cp "$feed_dir/appcast.xml" release/
(cd release && shasum -a 256 -- * > SHA256SUMS)
