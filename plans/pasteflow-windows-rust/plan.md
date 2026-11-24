---
title: "PasteFlow for Windows (Rust + Win32 TDD Implementation Plan)"
status: pending
mode: tdd
author: "Quốc Ngô (@lengo0951 / coolstar17)"
created: "2026-11-24"
source: "brainstorm_pasteflow_windows.md"
target: "Windows 10 & Windows 11"
stack: "Rust 2024, windows-rs, DWM Acrylic/Mica, Kiri MicroVM"
---

# 📋 Implementation Plan: PasteFlow for Windows (Rust Edition)

> **TDD Mode Enabled:** Mọi logic xử lý Clipboard, Hotkey, Giả lập phím dán, và Quản lý bộ nhớ đệm (Cache/LRU) đều được viết Unit Tests / Integration Tests trước khi hoàn thiện code thực tế (Red-Green-Refactor).

---

## 🎯 Mục tiêu & Ràng buộc Kỹ thuật

1. **Hiệu năng & Tài nguyên:**
   * **RAM chiếm dụng:** Không quá **25 MB** khi chạy nền.
   * **Dung lượng file `.exe`:** Dưới **8 MB** (sau khi strip symbols & nén LTO).
   * **CPU chạy nền:** **0.0%**.
   * **Thời gian khởi động lạnh (Cold launch):** Dưới **10 ms**.
2. **Khả năng tương thích:**
   * Chạy mượt mà trên cả **Windows 11** (giao diện Mica / Acrylic chuẩn) và **Windows 10** (Accent Policy blur).
   * Hỗ trợ cả 2 kiến trúc CPU: `x86_64` và `aarch64` (Windows on ARM).
3. **Môi trường giả lập & Test:**
   * Sử dụng **Kiri** (`/Applications/Kiri.app`) trên macOS để khởi chạy microVM / container Windows test trực tiếp.

---

## 🧪 Chiến lược Kiểm thử TDD (Test-Driven Strategy)

Mỗi pha core logic tuân thủ nghiêm ngặt chu trình TDD:
1. **Red:** Viết test cases trước (Mock Win32 message queue, mock `HWND`, clipboard payload serialization).
2. **Green:** Viết code tối giản để test pass.
3. **Refactor:** Tối ưu bộ nhớ, loại bỏ unsafe pointers, zero allocation.

```
┌─────────────────────────────────────────────────────────────┐
│                       TDD Test Matrix                       │
├──────────────────────┬──────────────────────────────────────┤
│ Clipboard Tests      │ Text, URL, Hex Color, Large string   │
│ Hotkey Tests         │ Dynamic rebinding, Conflict handling │
│ Simulation Tests     │ Keystroke ordering, Modifier safety  │
│ Privacy Guard Tests  │ Blacklist verification, Concealed    │
│ Persistence Tests    │ JSON encoding, LRU 500-item drop     │
└──────────────────────┴──────────────────────────────────────┘
```

---

## 🗺️ Lộ trình 9 Pha Nguyên tử (Atomic Phases)

| Pha | Tiêu đề | Mô tả chi tiết | Trạng thái TDD |
| :--- | :--- | :--- | :--- |
| **01** | `phase-01-kiri-environment.md` | Setup Rust toolchain, cross-compile Windows, dựng Windows test container trên Kiri | ✅ **Hoàn thành** (`cargo check` pass) |
| **02** | `phase-02-tdd-clipboard-listener.md` | Lắng nghe `WM_CLIPBOARDUPDATE`, trích xuất text/format, chống self-paste loop | ✅ **Hoàn thành** (`tests/clipboard_test.rs` 5/5 pass) |
| **03** | `phase-03-tdd-hotkey-manager.md` | Đăng ký `RegisterHotKey`, đọc/ghi cấu hình phím tắt linh hoạt từ `config.json` | ✅ **Hoàn thành** (`tests/hotkey_test.rs` 3/3 pass) |
| **04** | `phase-04-tdd-paste-simulator.md` | Giả lập `SendInput` (Ctrl+V) & Plain Text paste vào active window | ✅ **Hoàn thành** (`tests/paste_test.rs` 2/2 pass) |
| **05** | `phase-05-tdd-storage-and-privacy.md` | Lưu trữ `history.json`, `pinboards.json`, bảo mật lọc 1Password/Bitwarden | ✅ **Hoàn thành** (`tests/storage_test.rs` 3/3 pass) |
| **06** | `phase-06-acrylic-mica-window-hud.md` | Cửa sổ Win32 không viền, DWM Acrylic/Mica blur, trượt đáy màn hình | ✅ **Hoàn thành** (Win32 Acrylic/Mica DWM implemented) |
| **07** | `phase-07-quicklook-preview.md` | Cửa sổ xem trước Spacebar (Quick Look), phím số 1-9 dán nhanh | ✅ **Hoàn thành** (VK_SPACE modal & 1-9 quick paste) |
| **08** | `phase-08-settings-and-custom-hotkey.md` | Giao diện cài đặt cho phép người dùng đổi phím tắt trực tiếp | ✅ **Hoàn thành** (Dynamic hotkey parser & config loop) |
| **09** | `phase-09-e2e-testing-and-release.md` | Test toàn diện E2E trên Kiri Windows, build release `.exe`, đưa lên GitHub | ✅ **Hoàn thành** (13/13 tests pass, `build_windows.sh`) |

---

## 📂 Danh mục tài liệu chi tiết từng pha
* [Phase 1: Kiri Environment & Toolchain](phase-01-kiri-environment.md)
* [Phase 2: TDD Clipboard Listener](phase-02-tdd-clipboard-listener.md)
* [Phase 3: TDD Hotkey Manager & Config](phase-03-tdd-hotkey-manager.md)
* [Phase 4: TDD Paste Simulator](phase-04-tdd-paste-simulator.md)
* [Phase 5: TDD Storage & Privacy Guard](phase-05-tdd-storage-and-privacy.md)
* [Phase 6: Acrylic / Mica Window HUD](phase-06-acrylic-mica-window-hud.md)
* [Phase 7: Quick Look & Shortcuts](phase-07-quicklook-preview.md)
* [Phase 8: Settings & Custom Hotkey UI](phase-08-settings-and-custom-hotkey.md)
* [Phase 9: E2E Testing & Release](phase-09-e2e-testing-and-release.md)
