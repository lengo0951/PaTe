---
phase: 3
title: "TDD: Win32 Global Hotkey Manager & Config"
status: pending
type: tdd
---

# Phase 03: TDD Win32 Global Hotkey Manager & Config

## 🎯 Objective
Xây dựng module đăng ký phím tắt toàn hệ điều hành bằng Win32 `RegisterHotKey`, hỗ trợ đọc/ghi cấu hình phím tắt linh hoạt từ `config.json` để người dùng có thể tự đổi phím tắt bất kỳ lúc nào.

## 🧪 TDD Specification

### 1. Test Cases (`tests/hotkey_test.rs`)
* `test_default_hotkey_parsing()`: Phân tích cú pháp mặc định `"Ctrl+Shift+V"` thành Win32 modifiers `MOD_CONTROL | MOD_SHIFT` và VK code `0x56`.
* `test_custom_hotkey_parsing()`: Phân tích `"Alt+V"`, `"Ctrl+Alt+V"` thành VK tương ứng.
* `test_config_persistence()`: Khi thay đổi phím tắt, `config.json` cập nhật chính xác và hotkey cũ được `UnregisterHotKey` trước khi `RegisterHotKey` mới.
* `test_conflict_handling()`: Nếu phím tắt bị ứng dụng khác chiếm giữ, trả về `Result::Err(HotkeyError::AlreadyRegistered)` có thông báo rõ ràng thay vì crash.

### 2. Implementation (`src/core/hotkey.rs`)
* `struct HotkeyConfig`: Chứa `modifiers: u32`, `vk_code: u32`, `display_string: String`.
* Bắt thông điệp `WM_HOTKEY` trong Window message loop.
* Gửi tín hiệu đánh thức HUD mở lên đáy màn hình.

## 🧪 Acceptance Criteria
- [ ] Mọi test case phân tích và chuyển đổi chuỗi phím tắt đều PASS.
- [ ] Người dùng đổi phím tắt trong `config.json`, ứng dụng nhận diện và gán lại hotkey ngay lập tức mà không cần khởi động lại.
