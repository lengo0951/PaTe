#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="1.1.0"
APP_NAME="PasteFlow"
BUILD_DIR="$DIR/build"
WINDOWS_BUILD_DIR="$DIR/windows/target/x86_64-pc-windows-gnu/release"
STAGING_DIR="$DIR/dist/windows_staging"
OUTPUT_ZIP="$BUILD_DIR/PasteFlow-v${VERSION}-windows.zip"

echo "=== Packaging $APP_NAME Windows Edition v$VERSION ==="

# 1. Compile Windows release binary if needed
echo "Building release binary with Cargo (x86_64-pc-windows-gnu)..."
cd "$DIR/windows"
cargo build --release --target x86_64-pc-windows-gnu
cd "$DIR"

# 2. Prepare staging directory
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$BUILD_DIR"

# 3. Copy pasteflow.exe
echo "Copying pasteflow.exe to staging..."
cp "$WINDOWS_BUILD_DIR/pasteflow.exe" "$STAGING_DIR/pasteflow.exe"

# 4. Create install.bat
cat << 'EOF' > "$STAGING_DIR/install.bat"
@echo off
setlocal
echo ========================================================
echo Installing PasteFlow for Windows (v1.1.0)
echo ========================================================

set INSTALL_DIR=%LOCALAPPDATA%\PasteFlow
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo Copying pasteflow.exe to %INSTALL_DIR%...
copy /Y "%~dp0pasteflow.exe" "%INSTALL_DIR%\pasteflow.exe" >nul

echo Creating Start Menu shortcut...
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut(\"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\PasteFlow.lnk\"); $s.TargetPath = \"$env:LOCALAPPDATA\PasteFlow\pasteflow.exe\"; $s.WorkingDirectory = \"$env:LOCALAPPDATA\PasteFlow\"; $s.Description = \"PasteFlow Clipboard Manager\"; $s.Save()"

echo Adding PasteFlow to Windows Startup (Run at login)...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "PasteFlow" /t REG_SZ /d "\"%INSTALL_DIR%\pasteflow.exe\"" /f >nul

echo.
echo ========================================================
echo Installation completed successfully!
echo Starting PasteFlow now...
echo Press Ctrl + Shift + V to toggle the PasteFlow HUD!
echo ========================================================
start "" "%INSTALL_DIR%\pasteflow.exe"
pause
EOF

# 5. Create uninstall.bat
cat << 'EOF' > "$STAGING_DIR/uninstall.bat"
@echo off
setlocal
echo ========================================================
echo Uninstalling PasteFlow...
echo ========================================================

taskkill /F /IM pasteflow.exe 2>nul

echo Removing Start Menu shortcut...
del /F /Q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\PasteFlow.lnk" 2>nul

echo Removing from Windows Startup...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "PasteFlow" /f 2>nul

echo Removing application files...
rd /S /Q "%LOCALAPPDATA%\PasteFlow" 2>nul

echo.
echo PasteFlow has been completely removed.
pause
EOF

# 6. Create README.txt
cat << 'EOF' > "$STAGING_DIR/README.txt"
===================================================================
PasteFlow v1.1.0 - Windows Edition (Rust 2024 & Win32 APIs)
Crafted by Quốc Ngô (@lengo0951)
===================================================================

PasteFlow is a native, ultra-lightweight, privacy-first clipboard manager
for Windows 10 & 11 with DWM Acrylic/Mica frosted glass blur.

QUICK START:
1. Double-click `pasteflow.exe` to run immediately (portable mode).
2. Press `Ctrl + Shift + V` to toggle the bottom clipboard bar.
3. Use Left/Right Arrow keys or mouse to navigate clips.
4. Press `Space` to Quick Look preview any clip (Space again to close).
5. Press `Return` to paste to active window, or `1` through `9` for quick paste.

INSTALLATION (Optional):
- Double-click `install.bat` to install PasteFlow to your system,
  create a Start Menu shortcut, and launch at startup.
- Run `uninstall.bat` anytime to completely remove PasteFlow.

GitHub: https://github.com/lengo0951/PasteFlow
===================================================================
EOF

# 7. Create Zip archive
echo "Creating zip package..."
rm -f "$OUTPUT_ZIP"
cd "$STAGING_DIR"
zip -r "$OUTPUT_ZIP" .
cd "$DIR"

# 8. Clean up
rm -rf "$DIR/dist/windows_staging"

echo ""
echo "=== Windows Package Created Successfully! ==="
echo "File path: $OUTPUT_ZIP"
ls -lh "$OUTPUT_ZIP"
echo ""
echo "SHA-256 Checksum:"
shasum -a 256 "$OUTPUT_ZIP"
