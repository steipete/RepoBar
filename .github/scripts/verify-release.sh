#!/bin/bash
set -euo pipefail
source version.env
(cd release && shasum -a 256 -c SHA256SUMS)
verify_dir="$RUNNER_TEMP/verify-release"
mkdir "$verify_dir"
ditto -x -k "release/RepoBar-${MARKETING_VERSION}.zip" "$verify_dir"
ditto -x -k "release/RepoBar-${MARKETING_VERSION}.dSYM.zip" "$verify_dir"
app="$verify_dir/RepoBar.app"
codesign --verify --deep --strict "$app"
codesign --verify --strict --check-notarization "$app"
spctl --assess --type execute --verbose=2 "$app"
xcrun stapler validate "$app"
for binary in "$app/Contents/MacOS/RepoBar" "$app/Contents/MacOS/repobarcli"; do
  architectures="$(lipo -archs "$binary")"
  [[ " $architectures " == *" arm64 "* ]]
  [[ " $architectures " == *" x86_64 "* ]]
  for architecture in arm64 x86_64; do
    otool -arch "$architecture" -l "$binary" | grep -A3 LC_BUILD_VERSION
    minimum="$(otool -arch "$architecture" -l "$binary" | awk '/LC_BUILD_VERSION/ { found=1 } found && $1 == "minos" { print $2; found=0 }')"
    python3 - "$minimum" <<'PY'
import sys
minimum = tuple(map(int, sys.argv[1].split('.')))
assert minimum <= (15, 0, 0), f"Binary requires macOS {sys.argv[1]}, newer than macOS 15.0"
PY
  done
  codesign --verify --strict --check-notarization "$binary"
  details="$(codesign -d --verbose=4 "$binary" 2>&1)"
  grep -F 'TeamIdentifier=Y5PE65HELJ' <<< "$details"
  grep -F 'Authority=Developer ID Application: Peter Steinberger (Y5PE65HELJ)' <<< "$details"
  grep -E 'flags=.*runtime' <<< "$details"
  grep -E '^Timestamp=' <<< "$details"
done
for architecture in arm64 x86_64; do
  arch "-$architecture" "$app/Contents/MacOS/repobarcli" --help > "$RUNNER_TEMP/cli-help-$architecture.txt"
  grep -i 'repobar' "$RUNNER_TEMP/cli-help-$architecture.txt"
done
python3 - "$app/Contents/Info.plist" "$MARKETING_VERSION" "$BUILD_NUMBER" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as stream:
    info=plistlib.load(stream)
assert info['CFBundleShortVersionString']==sys.argv[2]
assert info['CFBundleVersion']==sys.argv[3]
assert info['LSMinimumSystemVersion']=='15.0'
assert 'RepoBarTokenStore' not in info
assert info['SUPublicEDKey']=='AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI='
PY
codesign -d --entitlements :- "$app" > "$RUNNER_TEMP/entitlements.plist" 2>/dev/null
python3 - "$RUNNER_TEMP/entitlements.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as stream:
    entitlements=plistlib.load(stream)
assert not entitlements.get('com.apple.security.get-task-allow', False)
assert 'keychain-access-groups' not in entitlements
PY
dwarfdump --uuid "$app/Contents/MacOS/RepoBar" | awk '{print $2,$3}' | sort > "$RUNNER_TEMP/app-uuids"
dwarfdump --uuid "$verify_dir/RepoBar.dSYM" | awk '{print $2,$3}' | sort > "$RUNNER_TEMP/dsym-uuids"
test -s "$RUNNER_TEMP/app-uuids"
cmp "$RUNNER_TEMP/app-uuids" "$RUNNER_TEMP/dsym-uuids"
python3 - "$MARKETING_VERSION" "$BUILD_NUMBER" "$RUNNER_TEMP/signature" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
version, build, output=sys.argv[1:]
ns='{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items=[i for i in ET.parse('release/appcast.xml').findall('./channel/item') if i.findtext(ns+'shortVersionString')==version]
assert len(items)==1
item=items[0]
assert item.findtext(ns+'version')==build
assert item.findtext(ns+'minimumSystemVersion')=='15.0'
e=item.find('enclosure')
assert e.attrib['url']==f'https://github.com/steipete/RepoBar/releases/download/v{version}/RepoBar-{version}.zip'
assert int(e.attrib['length'])==pathlib.Path(f'release/RepoBar-{version}.zip').stat().st_size
pathlib.Path(output).write_text(e.attrib[ns+'edSignature'])
PY
swift .github/scripts/verify-sparkle.swift "release/RepoBar-${MARKETING_VERSION}.zip" "$RUNNER_TEMP/signature"
