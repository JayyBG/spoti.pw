#!/usr/bin/env bash
# Builds the Listening stats home screen widget extension without an Xcode project.
#
#   scripts/build-widget.sh <host Info.plist> <out dir>
#
# Writes <out dir>/SpotifyGlassWidget.appex, which pipeline.sh injects into PlugIns and puts on the
# App Group shim. Needs Xcode (xcode-select or DEVELOPER_DIR).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_PLIST="${1:?usage: $0 <host Info.plist> <out dir>}"
OUT="${2:?usage: $0 <host Info.plist> <out dir>}"
NAME=SpotifyGlassWidget
APPEX="$OUT/$NAME.appex"
SOURCE="$ROOT/extension/Widget/StatsWidget.swift"

rm -rf "$APPEX"
mkdir -p "$APPEX"
# A build that fails leaves no half-made appex for pipeline.sh to inject.
trap 'rm -rf "$APPEX"' ERR

echo "==> building $NAME.appex"
xcrun --sdk iphoneos swiftc -O -wmo -parse-as-library -target arm64-apple-ios16.0 -module-name "$NAME" \
  -Xlinker -e -Xlinker _NSExtensionMain -o "$APPEX/$NAME" "$SOURCE"

sed -e "s/HOST_BUNDLE_ID/$(plutil -extract CFBundleIdentifier raw -o - "$HOST_PLIST")/" \
    -e "s/HOST_SHORT_VERSION/$(plutil -extract CFBundleShortVersionString raw -o - "$HOST_PLIST")/" \
    -e "s/HOST_VERSION/$(plutil -extract CFBundleVersion raw -o - "$HOST_PLIST")/" \
    "$ROOT/extension/Widget/Info.plist" > "$APPEX/Info.plist"
plutil -convert binary1 "$APPEX/Info.plist"

codesign -f -s - "$APPEX" >/dev/null 2>&1
echo "    $APPEX"
