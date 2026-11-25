#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="1.2.0"
APP_NAME="PasteFlow"
BUILD_DIR="$DIR/build"
WINDOWS_BUILD_DIR="$DIR/windows/target/x86_64-pc-windows-gnu/release"
STAGING_DIR="$DIR/dist/windows_staging"
OUTPUT_ZIP="$BUILD_DIR/PasteFlow-v${VERSION}-windows.zip"

echo "=== Packaging $APP_NAME Windows Edition v$VERSION ==="

echo "Building release binary with embedded PE Manifest, VersionInfo & Icon..."
cd "$DIR/windows"
cargo build --release --target x86_64-pc-windows-gnu
cd "$DIR"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$BUILD_DIR"

cp "$WINDOWS_BUILD_DIR/pasteflow.exe" "$STAGING_DIR/pasteflow.exe"

cat << 'EOF' > "$STAGING_DIR/README.txt"
===================================================================
PasteFlow v1.2.0 - Windows Edition (Native Rust & Win32 APIs)
Crafted by Quốc Ngô (@lengo0951)
===================================================================

PasteFlow is a native, ultra-lightweight, privacy-first clipboard &
credential manager for Windows 10 & 11 with DWM Acrylic/Mica blur
and Win32 DPAPI encrypted Account Vault.

ZERO-INSTALL PORTABLE SETUP (No Admin Rights Required):
1. Extract `pasteflow.exe` to any folder (e.g. %LOCALAPPDATA%\PasteFlow).
2. Double-click `pasteflow.exe` to start (runs quietly in the System Tray).
3. Right-click the PasteFlow System Tray icon and check:
     [x] Launch at Windows Startup
   to start automatically when you sign into Windows!

KEYBOARD & MOUSE SHORTCUTS:
- `Ctrl + Shift + V`       : Summon / Hide PasteFlow HUD
- `Enter` or `Double-Click`: Paste selected clip (or Vault Password)
- `Ctrl + U`               : Paste Username (for Vault Accounts)
- `Ctrl + Shift + Enter`   : Auto-Fill Username -> Tab -> Password
- `Ctrl + N`               : Save New Account & Password (DPAPI Encrypted)
- `Tab`                    : Switch between Clipboard History & Accounts
- `1` .. `9`               : Instant Quick Paste
- `Space`                  : Quick Look Preview
- `Delete` / `Backspace`   : Delete selected item
- `Esc`                    : Close HUD

FIRST LAUNCH NOTE (Windows SmartScreen for Open-Source Builds):
If SmartScreen displays "Windows protected your PC" on first launch,
click "More info" -> "Run anyway".
===================================================================
EOF

echo "Creating Zip archive: $OUTPUT_ZIP..."
rm -f "$OUTPUT_ZIP"
cd "$STAGING_DIR"
zip -9 -r "$OUTPUT_ZIP" .
cd "$DIR"

rm -rf "$DIR/dist"

echo ""
echo "=== Windows Package Created Successfully! ==="
echo "File path: $OUTPUT_ZIP"
ls -lh "$OUTPUT_ZIP"
echo ""
echo "SHA-256 Checksum:"
shasum -a 256 "$OUTPUT_ZIP"
