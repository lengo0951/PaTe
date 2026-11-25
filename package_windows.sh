#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="1.2.0"
APP_NAME="PATE"
BUILD_DIR="$DIR/build"
WINDOWS_BUILD_DIR="$DIR/windows/target/x86_64-pc-windows-gnu/release"
STAGING_DIR="$DIR/dist/windows_staging"
OUTPUT_ZIP="$BUILD_DIR/PATE-v${VERSION}-windows.zip"

echo "=== Packaging $APP_NAME Windows Edition v$VERSION ==="

echo "Building release binary with embedded PE Manifest, VersionInfo & Icon..."
cd "$DIR/windows"
cargo build --release --target x86_64-pc-windows-gnu
cd "$DIR"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$BUILD_DIR"

cp "$WINDOWS_BUILD_DIR/pate.exe" "$STAGING_DIR/pate.exe"

cat << 'EOF' > "$STAGING_DIR/README.txt"
===================================================================
PATE v1.2.0 - Windows Edition (Native Rust & Win32 APIs)
Crafted by Quốc Ngô (@lengo0951)
===================================================================

PATE is a native, ultra-lightweight, privacy-first clipboard &
encrypted account manager for Windows 10 & 11 with DWM Acrylic/Mica
blur and Win32 DPAPI Account Vault.

ZERO-INSTALL PORTABLE SETUP (No Admin Rights Required):
1. Extract `pate.exe` to any folder (e.g. %LOCALAPPDATA%\PATE).
2. Double-click `pate.exe` to start (runs quietly in the System Tray).
3. Right-click the PATE System Tray icon and check:
     [x] Launch at Windows Startup
   to start automatically when you sign into Windows!

KEYBOARD & MOUSE SHORTCUTS:
- `Ctrl + Shift + V`       : Summon / Hide PATE HUD
- `Enter` or `Double-Click`: Paste clip (or Smart Auto-Fill User -> Tab -> Pass)
- `Shift + Enter`          : Smart Auto-Fill User -> Tab -> Pass -> Submit
- `Ctrl + U`               : Type Username & Pre-load Password (2-step logins)
- `Alt + Enter`            : Paste Password Only
- `Ctrl + N`               : Save New Account & Password (DPAPI Encrypted)
- `Tab`                    : Switch between Clipboard History & Accounts
- `1` .. `9`               : Instant Quick Paste
- `Space`                  : Quick Look Preview
- `Delete` / `Backspace`   : Delete selected item
- `Esc`                    : Close HUD
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
