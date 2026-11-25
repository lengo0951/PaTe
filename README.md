<div align="center">

<img src="Assets/AppIcon.png" width="128" height="128" alt="PATE Icon" />

# PATE ⚡

**Ultra-Lightweight, Native Clipboard & Encrypted Account Manager for macOS & Windows**

[![Release](https://img.shields.io/github/v/release/lengo0951/PaTe?color=FF375F&style=flat-square)](https://github.com/lengo0951/PaTe/releases)
[![macOS](https://img.shields.io/badge/macOS-13.0%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=flat-square&logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![Swift](https://img.shields.io/badge/macOS-Swift%206-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Rust](https://img.shields.io/badge/Windows-Rust%202024-DEA584?style=flat-square&logo=rust&logoColor=white)](https://www.rust-lang.org)
[![Memory](https://img.shields.io/badge/RAM-~20MB%20--%2035MB%20RSS-brightgreen?style=flat-square)](https://github.com/lengo0951/PaTe)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

*Crafted by [**Quốc Ngô**](https://github.com/lengo0951) (`@lengo0951` / `coolstar17`)*

[Download for macOS (DMG)](https://github.com/lengo0951/PaTe/releases/latest) • [Download for Windows (Zip)](https://github.com/lengo0951/PaTe/releases/latest) • [Key Features](#-key-features) • [Build from Source](#-build-from-source)

---

</div>

## 📖 Overview

**PATE** is a native, ultra-lightweight clipboard & encrypted credential manager engineered for developers, engineers, and power users across **macOS and Windows**.

Unlike heavy Electron-based or WebView-wrapped tools that easily consume 300 MB – 1 GB+ of RAM, **PATE** is built **100% natively**:
* **macOS:** Pure **Swift 6, SwiftUI, AppKit, and CryptoKit** with native `NSVisualEffectView` frosted glassmorphism.
* **Windows:** Pure **Rust 2024 and Win32 APIs (`windows-rs`)** with native Windows 11 **DWM Acrylic / Mica** blur and Win32 DPAPI encryption.

PATE runs silently in your menu bar / system tray with **0.0% idle CPU** and a tiny **~20 MB – 35 MB RSS** memory footprint while delivering instant clipboard search, 1-shot login auto-fill, and Quick Look previews.

---

## 🌟 Key Features

* 🔐 **Encrypted Account & Password Vault (`0ms` Unlock)**:
  * **macOS:** Hardware-accelerated **AES-256-GCM (`CryptoKit`) + macOS Keychain** — passwords are masked (`••••••••••`) on cards and never stored in plaintext JSON.
  * **Windows:** Native **Win32 DPAPI (`CryptProtectData`)** tied directly to your Windows user logon credentials.
  * **1-Shot Smart Hybrid Auto-Fill (`Username ⇥ Tab ⇥ Password`)**: Double-click or press `Enter` on an Account card to inject `Username` via Unicode HID stream -> press `Tab` -> paste `Password` with zero browser clipboard race conditions!
  * **2-Step Login Ready (`⌘U` / `Ctrl+U`)**: Types `Username` on Page 1 while pre-loading `Password` onto the clipboard so on Page 2 you simply press `⌘V` (`Ctrl+V`).
  * **1-Click Clip Encryption**: Right-click any existing text clip to convert and encrypt it directly into your Accounts Vault.
* 🎨 **Frosted Glassmorphism Floating HUD**:
  * Slides smoothly from the bottom of your active screen using native `NSVisualEffectView` (macOS) and DWM Acrylic/Mica (Windows), seamlessly matching Light & Dark modes.
* ⚡ **Ultra-Low Memory Footprint (~20 – 35 MB RAM)**:
  * Direct PNG fast-path & `400px` `ImageIO` thumbnails (~85% lower RAM when scrolling image clips).
  * `O(1)` checksum deduplication, memoized filter caching, zero-allocation RunLoop timers (`0.0%` idle CPU), and zero-allocation UTF-16 GDI `WM_PAINT` on Windows.
* 🔍 **Instant Quick Look (`Spacebar`) & Custom Naming (`R`)**:
  * Press `Space` to preview full-resolution images, code snippets, color swatches, links, files, or reveal Vault accounts.
  * Press `R` to give any clip a memorable custom name displayed cleanly on the card header.
* 🛡️ **Privacy-First & Self-Paste Protection**:
  * Automatically ignores clips from password managers (**1Password**, **Bitwarden**, **KeePassXC**, **Keychain Access**).
  * 100% local storage with zero telemetry, zero analytics, and zero network calls.
* 🗂️ **Custom Pinboards & Native Launch at Startup**:
  * Organize snippets, accounts, commands, and links into color-coded tabs.
  * Native `SMAppService` (macOS) and native System Tray Registry toggle (Windows — zero `.bat` scripts).

---

## 📊 Performance & Efficiency Benchmarks

Measured on Apple Silicon (macOS) and Windows 11 x64 using native profiling tools (`footprint`, `ps`, Task Manager):

| Metric | PATE (Native Swift 6 / Rust) | Typical Electron / WebView App | Difference |
| :--- | :--- | :--- | :--- |
| **Idle Memory (RSS)** | **~20 MB (Win) / ~35 MB (Mac)** | 250 MB – 550 MB | **~90% less RAM** |
| **Background CPU** | **0.0%** | 0.8% – 2.5% | **Zero idle wakeups** |
| **Cold Launch Time** | **< 35 ms** | 1,200 ms – 3,500 ms | **Instantaneous** |
| **HUD Popup Latency** | **< 10 ms** | 120 ms – 280 ms | **Frame-perfect render** |
| **Distribution Size** | **2.4 MB (DMG) / 261 KB (Win Zip)** | 110 MB – 220 MB | **98% smaller payload** |

> [!TIP]
> **Verify on your own Mac:** Run `ps -o pid,rss,%cpu,command -ax | grep PATE` at any time to verify live memory and `0.0%` idle CPU usage.

---

## ⌨️ Keyboard & Mouse Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`⌘ + ⇧ + V`** / **`Ctrl + Shift + V`** | Toggle PATE HUD from anywhere |
| **`Return` / `Double-Click`** | Paste clip — or **Smart Auto-Fill (`User ⇥ Tab ⇥ Pass`)** on Account cards |
| **`⇧ + Return`** / **`Shift + Enter`** | **Auto-Fill & Submit Login (`User ⇥ Tab ⇥ Pass ⇥ Enter`)** on Account cards |
| **`⌘ + U`** / **`Ctrl + U`** | Type **Username** & pre-load **Password** to clipboard (for 2-step web logins) |
| **`⌥ + Return`** / **`Alt + Enter`** | **Paste as Plain Text** (or **Password Only** on Account cards) |
| **`⌘ + N`** / **`Ctrl + N`** | Save new Account & Password into encrypted Vault |
| **`Space`** | Open / Close Quick Look preview modal |
| **`R`** | Rename clip or Edit Vault Account |
| **`1` – `9`** | Instant Quick Paste for card #1 through #9 |
| **`←` / `→`** | Navigate between items |
| **`Delete` / `Backspace`** | Delete selected card |
| **`Esc`** | Clear search or dismiss PATE HUD |

---

## 📦 Installation

### 🍎 macOS Option 1: Homebrew Tap (Recommended)
```bash
brew tap lengo0951/tap https://github.com/lengo0951/PaTe
brew install --cask pate
```

### 🍎 macOS Option 2: Download Pre-built DMG
1. Download **[PATE-1.2.0.dmg](https://github.com/lengo0951/PaTe/releases/latest)** (~2.4 MB).
2. Open the disk image and drag **PATE.app** into your **Applications** folder.
3. On first launch for open-source builds, Control-click **PATE.app** -> **Open** (or allow in *System Settings → Privacy & Security*), and grant **Accessibility** permission for `Cmd + V` synthesis.
4. Press **`⌘ + ⇧ + V`** to activate!

### 🪟 Windows (10 / 11 x64)
1. Download **[PATE-v1.2.0-windows.zip](https://github.com/lengo0951/PaTe/releases/latest)** (~261 KB).
2. Extract and run `pate.exe` (single portable native executable with embedded PE Manifest & icon, zero installer scripts).
3. Right-click the PATE System Tray icon to toggle **Launch at Windows Startup** or **Add Account / Password**.
4. Press **`Ctrl + Shift + V`** to activate!

---

## 🛠️ Build from Source

### Prerequisites
* **macOS:** macOS 13.0+ & Xcode Command Line Tools (`swiftc` with Swift 6).
* **Windows:** Rust toolchain (`cargo`), `x86_64-pc-windows-msvc` (or `x86_64-pc-windows-gnu` cross-compile).

### 1. Clone & Build macOS (`PATE.app` + DMG)
```bash
git clone https://github.com/lengo0951/PaTe.git
cd PaTe

# Compile & strictly sign PATE.app
./build.sh

# Package PATE-1.2.0.dmg
./package_dmg.sh
```

### 2. Test & Build Windows (`pate.exe` + Zip)
```bash
cd windows

# Run all 16 unit & integration tests
cargo test

# Build release binary (Windows native MSVC or macOS cross-compile)
cargo build --release --target x86_64-pc-windows-gnu
cd .. && ./package_windows.sh
```

---

## 🏛️ Architecture

```
PaTe/
├── Sources/                          # macOS Edition (Swift 6 + SwiftUI + AppKit)
│   ├── AppDelegate.swift             # App lifecycle, Edit MainMenu & status item
│   ├── Main.swift                    # @main PATEApp entry point
│   ├── Models/
│   │   ├── AppConfig.swift           # Theme, hotkey & behavior configuration
│   │   ├── ClipboardItem.swift       # Unified clip & credential model
│   │   ├── ContentType.swift         # Text, Code, Link, Color, Image, File, Account
│   │   ├── HistoryStore.swift        # O(1) dedup, ImageIO thumbnails & async save
│   │   └── Pinboard.swift            # System History, Accounts Vault & custom tabs
│   ├── Services/
│   │   ├── AppIconCache.swift        # Downscaled 32x32 LRU app icon cache
│   │   ├── ClipboardMonitor.swift    # Zero-alloc RunLoop timer & PNG fast-path
│   │   ├── CredentialVault.swift     # Hardware AES-256-GCM + macOS Keychain
│   │   ├── HotKeyManager.swift       # Carbon global hotkey handler
│   │   ├── PasteSimulator.swift      # Hybrid Unicode HID + Cmd+V & AXSecureTextField
│   │   └── SoundManager.swift        # Subtle audio feedback
│   └── UI/
│       ├── Views/                    # HUD, Card, Vault Modal, QuickLook, Settings
│       └── Window/                   # FirstMouseHostingView, FloatingPanel, Controller
├── windows/                          # Windows Edition (Rust 2024 + Win32)
│   ├── assets/                       # pate.ico, pate.manifest (asInvoker), pate.rc
│   ├── src/core/                     # types, storage, vault (DPAPI), simulator, hotkey
│   └── src/ui/                       # Acrylic HUD, Zero-alloc WM_PAINT, Tray & Dialog
├── Casks/pate.rb                     # Official Homebrew Cask formula
├── Entitlements.plist                # Apple Silicon signing entitlements
├── build.sh / package_dmg.sh / package_windows.sh
└── .github/workflows/release.yml     # Dual macOS arm64 + Windows MSVC CI/CD
```

---

## 👤 Author & Acknowledgments

* **Creator:** **Quốc Ngô** ([@lengo0951](https://github.com/lengo0951) • `coolstar17`)
* **Development Toolkit:** Powered by [QuocNgoKit](https://github.com/lengo0951/quocngokit) ⚡

---

## 📄 License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.
