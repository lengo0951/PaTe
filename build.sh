#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== Building PATE v1.2.0 (macOS Native) ==="

BUILD_DIR="$DIR/build"
APP_NAME="PATE.app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

rm -rf "$APP_BUNDLE" "$BUILD_DIR/PasteFlow.app"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

SWIFT_FILES=$(find Sources -name "*.swift" | sort)

echo "Compiling Swift sources..."
swiftc -O \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -framework ApplicationServices \
    -framework Carbon \
    -framework CryptoKit \
    -framework Security \
    -framework ImageIO \
    -framework ServiceManagement \
    $SWIFT_FILES \
    -o "$MACOS_DIR/PATE"

echo "Copying metadata and assets..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
if [ -d "Assets" ]; then
    cp -R Assets/* "$RESOURCES_DIR/"
fi

xattr -cr "$APP_BUNDLE" 2>/dev/null || true

SIGN_ID="${CODESIGN_IDENTITY:--}"
echo "Signing application bundle (Identity: $SIGN_ID, strict non-deep)..."
if [ "$SIGN_ID" != "-" ]; then
    codesign --force --options runtime --entitlements Entitlements.plist --sign "$SIGN_ID" "$MACOS_DIR/PATE"
    codesign --force --options runtime --entitlements Entitlements.plist --sign "$SIGN_ID" "$APP_BUNDLE"
else
    codesign --force --entitlements Entitlements.plist --sign - "$MACOS_DIR/PATE"
    codesign --force --entitlements Entitlements.plist --sign - "$APP_BUNDLE"
fi

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
echo "=== Build Successful: $APP_BUNDLE ==="
