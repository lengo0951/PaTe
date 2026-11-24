#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== Building PasteFlow ==="

BUILD_DIR="$DIR/build"
APP_NAME="PasteFlow.app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Find all Swift source files
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
    -framework ServiceManagement \
    $SWIFT_FILES \
    -o "$MACOS_DIR/PasteFlow"

echo "Copying metadata and assets..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
if [ -d "Assets" ]; then
    cp -R Assets/* "$RESOURCES_DIR/"
fi

echo "Signing application bundle..."
codesign -s - --force --deep "$APP_BUNDLE"

echo "=== Build Successful: $APP_BUNDLE ==="
