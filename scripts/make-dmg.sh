#!/bin/sh
# Build dist/Speakhold.dmg from dist/Speakhold.app: the app, an Applications shortcut and a "drag it here"
# background, laid out through Finder. Free and certificate-free; it does not change what Gatekeeper says.
set -e
cd "$(dirname "$0")/.."
APP=dist/Speakhold.app; OUT=dist/Speakhold.dmg; VOL=Speakhold
[ -d "$APP" ] || { echo "run ./build.sh first"; exit 1; }
STAGE=$(mktemp -d); RW="$STAGE/rw.dmg"
mkdir -p "$STAGE/root/.background"
cp -R "$APP" "$STAGE/root/"
cp Resources/dmg/background.png "$STAGE/root/.background/background.png"
ln -s /Applications "$STAGE/root/Applications"
hdiutil create -quiet -srcfolder "$STAGE/root" -volname "$VOL" -fs HFS+ -format UDRW -size 80m "$RW"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/Apple_HFS/ {print $NF}')
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 160, 860, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "Speakhold.app" of container window to {170, 210}
    set position of item "Applications" of container window to {490, 210}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "$MOUNT"
rm -f "$OUT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -rf "$STAGE"
echo "$OUT $(du -h "$OUT" | cut -f1)"
