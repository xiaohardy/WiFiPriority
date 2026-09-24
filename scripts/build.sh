#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="${BUILD_DIR:-${TMPDIR:-/tmp}/wifipriority-build}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
# Native SwiftPM also supports Xcode versions before the Swift Build backend.
swift build --build-system native -c release --scratch-path "$BUILD_DIR"
BIN_DIR="$(swift build --build-system native -c release --scratch-path "$BUILD_DIR" --show-bin-path)"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wifipriority-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP="$STAGING_DIR/WiFi Priority.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_DIR/WiFiPriority" "$APP/Contents/MacOS/WiFiPriority"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto --norsrc --noextattr "$BIN_DIR/WiFiPriority_WiFiPriorityCore.bundle" "$APP/Contents/Resources/WiFiPriority_WiFiPriorityCore.bundle"
python3 scripts/package_resources.py "$APP"
chmod +x "$APP/Contents/MacOS/WiFiPriority"
xattr -cr "$APP"
# A persistent local identity keeps the Keychain's designated requirement
# stable across test builds. Public releases still need Developer ID signing.
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [ -n "${SIGNING_KEYCHAIN:-}" ]; then
    SIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"
if [ "${REQUIRE_STABLE_SIGNATURE:-0}" = 1 ]; then
    REQUIREMENT="$(codesign -d -r- "$APP" 2>&1)"
    case "$REQUIREMENT" in
        *"certificate root"*|*"certificate leaf"*) ;;
        *) echo "A stable certificate signature is required for this installer." >&2; exit 1 ;;
    esac
fi
mkdir -p "$OUTPUT_DIR"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ARCHIVE="$OUTPUT_DIR/WiFiPriority-$VERSION-dev.zip"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ARCHIVE"
ditto -x -k "$ARCHIVE" "$STAGING_DIR/verify"
codesign --verify --strict "$STAGING_DIR/verify/WiFi Priority.app"
"$STAGING_DIR/verify/WiFi Priority.app/Contents/MacOS/WiFiPriority" --check-localizations
# Keep a convenient loose preview copy; synchronized folders may add Finder
# metadata to it later. The verified ZIP is the portable development artifact.
ditto --norsrc --noextattr "$APP" "$OUTPUT_DIR/WiFi Priority.app"
printf 'Built and verified development archive: %s\n' "$ARCHIVE"
