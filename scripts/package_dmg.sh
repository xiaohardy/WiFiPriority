#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCHIVE="$OUTPUT_DIR/WiFiPriority-$VERSION-dev.zip"
DMG="$OUTPUT_DIR/WiFiPriority-$VERSION-build$BUILD-preview-arm64.dmg"
test -f "$ARCHIVE"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/wifipriority-dmg.XXXXXX")"
MOUNT="$WORK/mounted"
MOUNT_DEVICE=""
cleanup() {
    if [ -n "$MOUNT_DEVICE" ]; then
        diskutil eject "$MOUNT_DEVICE" >/dev/null 2>&1 || hdiutil detach "$MOUNT_DEVICE" >/dev/null 2>&1 || true
    fi
    if mount | grep -Fq " on $MOUNT "; then
        echo "Could not unmount temporary installer image: $MOUNT" >&2
        return 1
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/stage" "$MOUNT"
MOUNT="$(cd "$MOUNT" && pwd -P)"
ditto -x -k "$ARCHIVE" "$WORK/stage"
APP="$WORK/stage/WiFi Priority.app"
codesign --verify --strict "$APP"
if LC_ALL=C strings "$APP/Contents/MacOS/WiFiPriority" | grep -E '/Users/[^/]+/|/home/[^/]+/' >/dev/null; then
    echo "Installer executable contains a personal build path." >&2
    exit 1
fi
if [ "${REQUIRE_STABLE_SIGNATURE:-0}" = 1 ]; then
    REQUIREMENT="$(codesign -d -r- "$APP" 2>&1)"
    case "$REQUIREMENT" in
        *"certificate root"*|*"certificate leaf"*) ;;
        *) echo "Installer app is missing a stable certificate signature." >&2; exit 1 ;;
    esac
fi
ln -s /Applications "$WORK/stage/Applications"
hdiutil create -quiet -ov -format UDZO -fs HFS+ -volname "WiFi Priority $VERSION" -srcfolder "$WORK/stage" "$DMG"
hdiutil verify "$DMG" >/dev/null
ATTACH_OUTPUT="$(hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG")"
MOUNT_DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '$1 ~ /^\/dev\/disk/ { print $1; exit }')"
test -n "$MOUNT_DEVICE"
INSTALLED="$MOUNT/WiFi Priority.app"
test -L "$MOUNT/Applications"
test "$(readlink "$MOUNT/Applications")" = /Applications
test "$(find "$MOUNT" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 2
codesign --verify --strict "$INSTALLED"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED/Contents/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALLED/Contents/Info.plist")" = "$BUILD"
file "$INSTALLED/Contents/MacOS/WiFiPriority" | grep -q arm64
"$INSTALLED/Contents/MacOS/WiFiPriority" --check-localizations >/dev/null
test -f "$INSTALLED/Contents/Resources/AppIcon.icns"
echo "Verified installer: $DMG"
shasum -a 256 "$DMG"
