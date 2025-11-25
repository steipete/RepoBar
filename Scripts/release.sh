#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"
source "$HOME/Projects/agent-scripts/release/sparkle_lib.sh"

APPCAST="$ROOT/appcast.xml"
APP_NAME="RepoBar"
ARTIFACT_PREFIX="RepoBar-"
BUNDLE_ID="com.steipete.repobar"
TAG="v${MARKETING_VERSION}"

err() { echo "ERROR: $*" >&2; exit 1; }

git status --porcelain | grep . && err "Working tree not clean"

swiftformat Sources Tests >/dev/null
swiftlint --strict
swift test

"$ROOT/Scripts/sign-and-notarize.sh"

clear_sparkle_caches "$BUNDLE_ID"

KEY_FILE=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE")
trap 'rm -f "$KEY_FILE"' EXIT

echo "Generating Sparkle signature for appcast entry"
SIGNATURE=$(sign_update --ed-key-file "$KEY_FILE" -p "${APP_NAME}-${MARKETING_VERSION}.zip")
SIZE=$(stat -f%z "${APP_NAME}-${MARKETING_VERSION}.zip")
PUBDATE=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')

python3 - "$APPCAST" "$MARKETING_VERSION" "$BUILD_NUMBER" "$SIGNATURE" "$SIZE" "$PUBDATE" <<'PY'
import sys, xml.etree.ElementTree as ET
appcast, ver, build, sig, size, pub = sys.argv[1:]
tree = ET.parse(appcast)
root = tree.getroot()
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
channel = root.find("./channel")
item = ET.Element("item")
ET.SubElement(item, "title").text = ver
ET.SubElement(item, "pubDate").text = pub
ET.SubElement(item, "link").text = "https://raw.githubusercontent.com/steipete/RepoBar/main/appcast.xml"
ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}version").text = build
ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString").text = ver
ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}minimumSystemVersion").text = "15.0"
enc = ET.SubElement(item, "enclosure")
enc.set("url", f"https://github.com/steipete/RepoBar/releases/download/v{ver}/RepoBar-{ver}.zip")
enc.set("length", size)
enc.set("type", "application/octet-stream")
enc.set("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature", sig)
channel.insert(1, item)
tree.write(appcast, encoding="utf-8", xml_declaration=True)
PY

verify_appcast_entry "$APPCAST" "$MARKETING_VERSION" "$KEY_FILE"

if [[ "${RUN_SPARKLE_UPDATE_TEST:-0}" == "1" ]]; then
  PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')
  [[ -z "$PREV_TAG" ]] && err "RUN_SPARKLE_UPDATE_TEST=1 set but no previous tag found"
  "$ROOT/Scripts/test_live_update.sh" "$PREV_TAG" "v${MARKETING_VERSION}"
fi

gh release create "$TAG" ${APP_NAME}-${MARKETING_VERSION}.zip ${APP_NAME}-${MARKETING_VERSION}.dSYM.zip \
  --title "${APP_NAME} ${MARKETING_VERSION}" \
  --notes "See CHANGELOG.md for this release."

check_assets "$TAG" "$ARTIFACT_PREFIX"

git tag -f "$TAG"
git push origin main --tags

echo "Release ${MARKETING_VERSION} complete."
