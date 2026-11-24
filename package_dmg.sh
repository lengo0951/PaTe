#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="1.1.0"
APP_NAME="PasteFlow"
DMG_NAME="PasteFlow-${VERSION}.dmg"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
DIST_DIR="$DIR/dist"
STAGING_DIR="$DIST_DIR/dmg_staging"
OUTPUT_DMG="$BUILD_DIR/$DMG_NAME"

echo "=== Packaging $APP_NAME v$VERSION into DMG ==="

# 1. Build the app if not built
if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle not found. Running build.sh first..."
    ./build.sh
fi

# 2. Prepare staging directory
rm -rf "$DIST_DIR"
mkdir -p "$STAGING_DIR"

echo "Copying $APP_NAME.app to staging..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

echo "Creating /Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

# 3. Create DMG image
echo "Building compressed DMG with hdiutil..."
rm -f "$OUTPUT_DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG"

# Also create a generic PasteFlow.dmg symlink or copy for convenience
cp "$OUTPUT_DMG" "$BUILD_DIR/${APP_NAME}.dmg"

# 4. Clean up temporary staging files
rm -rf "$DIST_DIR"

echo ""
echo "=== DMG Package Created Successfully! ==="
echo "File path: $OUTPUT_DMG"
ls -lh "$OUTPUT_DMG"
echo ""
echo "SHA-256 Checksum:"
shasum -a 256 "$OUTPUT_DMG"
