#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SimQuotaMenu"
VERSION="${1:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME-$VERSION.dmg"
TMP_DMG_PATH="$ROOT_DIR/dist/$APP_NAME-$VERSION.tmp.dmg"
BACKGROUND_PATH="$ROOT_DIR/Resources/DmgBackground.png"
VOLUME_NAME="SIM流量"
MOUNT_DIR=""

cleanup() {
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  fi
  rm -f "$TMP_DMG_PATH"
}
trap cleanup EXIT

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/package_app.sh" "$VERSION"

if [[ ! -f "$BACKGROUND_PATH" ]]; then
  python3 "$ROOT_DIR/scripts/generate_dmg_background.py" "$ROOT_DIR/Resources/AppIconSource.png" "$BACKGROUND_PATH"
fi

rm -f "$DMG_PATH" "$TMP_DMG_PATH"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -size 64m \
  -fs HFS+ \
  -ov \
  "$TMP_DMG_PATH"

MOUNT_OUTPUT="$(hdiutil attach "$TMP_DMG_PATH" -readwrite -noverify -noautoopen)"
MOUNT_DIR="$(printf '%s\n' "$MOUNT_OUTPUT" | awk '/\/Volumes\// { print substr($0, index($0, "/Volumes/")); exit }')"
if [[ -z "$MOUNT_DIR" ]]; then
  echo "Failed to mount $TMP_DMG_PATH" >&2
  exit 1
fi

cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND_PATH" "$MOUNT_DIR/.background/DmgBackground.png"
chflags hidden "$MOUNT_DIR/.background" || true

open "$MOUNT_DIR"
osascript <<APPLESCRIPT
tell application "Finder"
  activate
  delay 1
  set installerWindow to front Finder window
  set current view of installerWindow to icon view
  set toolbar visible of installerWindow to false
  set statusbar visible of installerWindow to false
  set bounds of installerWindow to {100, 100, 820, 580}
  set viewOptions to icon view options of installerWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set background picture of viewOptions to (POSIX file "$MOUNT_DIR/.background/DmgBackground.png" as alias)
  set position of item "$APP_NAME.app" of installerWindow to {205, 250}
  set position of item "Applications" of installerWindow to {515, 250}
  delay 2
  close installerWindow
end tell
APPLESCRIPT

bless --folder "$MOUNT_DIR" --openfolder "$MOUNT_DIR" >/dev/null 2>&1 || true
rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes"
sync
hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

hdiutil convert "$TMP_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" \
  -ov

echo "$DMG_PATH"
