#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="1.2.0"
APP_NAME="PasteFlow"
DMG_NAME="PasteFlow-${VERSION}.dmg"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
DIST_DIR="$DIR/dist"
STAGING_DIR="$DIST_DIR/dmg_staging"
OUTPUT_DMG="$BUILD_DIR/$DMG_NAME"

echo "=== Packaging $APP_NAME v$VERSION into DMG ==="

if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle not found. Running build.sh first..."
    ./build.sh
fi

rm -rf "$DIST_DIR"
mkdir -p "$STAGING_DIR"

echo "Copying $APP_NAME.app to staging..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

echo "Creating /Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

cat << 'EOF' > "$STAGING_DIR/README - First Launch Guide.txt"
PasteFlow v1.2.0 for macOS (Apple Silicon)
Crafted by Quốc Ngô (@lengo0951)
============================================================

INSTALLATION:
1. Drag PasteFlow.app into the Applications folder.
2. Recommended via Homebrew (clean open-source install):
     brew tap lengo0951/tap https://github.com/lengo0951/PasteFlow
     brew install --cask pasteflow

FIRST LAUNCH (Apple Gatekeeper for Open-Source Builds):
If downloaded directly via a web browser without Apple Notarization:
1. Control-click (or Right-click) PasteFlow.app in /Applications and choose "Open", OR
2. Open System Settings -> Privacy & Security -> scroll down and click "Open Anyway".
3. Grant Accessibility access when prompted so PasteFlow can synthesize Cmd+V paste events.
4. Press Cmd + Shift + V from anywhere to summon PasteFlow!
EOF

echo "Building compressed DMG with hdiutil..."
rm -f "$OUTPUT_DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG"

cp "$OUTPUT_DMG" "$BUILD_DIR/${APP_NAME}.dmg"
rm -rf "$DIST_DIR"

# Optional Apple Notarization if credentials are provided in CI/environment
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ]; then
    echo "Submitting DMG to Apple Notary Service..."
    xcrun notarytool submit "$OUTPUT_DMG" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
    xcrun stapler staple "$OUTPUT_DMG"
fi

echo ""
echo "=== DMG Package Created Successfully! ==="
echo "File path: $OUTPUT_DMG"
ls -lh "$OUTPUT_DMG"
echo ""
echo "SHA-256 Checksum:"
shasum -a 256 "$OUTPUT_DMG"
