#!/bin/bash
set -e

echo "==> Building Release Binary (Milestone 2 Production Candidate)..."
swift build -c release

APP_NAME="NexWave Network Workbench"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="NexWave_Network_Workbench_v1.0_Candidate.dmg"
STAGING_DIR="dmg_staging"

echo "==> Packaging macOS Application Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp .build/release/NexWaveApp "$APP_BUNDLE/Contents/MacOS/NexWaveApp"
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [ -f "Info.plist" ]; then
    cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
fi

echo "==> Ad-hoc signing application bundle..."
codesign --force --deep -s - "$APP_BUNDLE"

echo "==> Preparing DMG staging directory..."
rm -rf "$STAGING_DIR" "$DMG_NAME"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating compressed UDZO Disk Image via hdiutil..."
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$STAGING_DIR" \
               -ov \
               -format UDZO \
               "$DMG_NAME"

rm -rf "$STAGING_DIR"

echo "==> DMG Build Successful!"
ls -lh "$DMG_NAME"
echo -n "==> SHA256: "
shasum -a 256 "$DMG_NAME"
