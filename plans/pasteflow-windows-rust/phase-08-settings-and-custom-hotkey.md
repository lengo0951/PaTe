---
phase: 8
title: "Settings Window & Dynamic Hotkey Configuration UI"
status: pending
type: feature
---

# Phase 08: Settings Window & Dynamic Hotkey Configuration UI

## 🎯 Objective
Xây dựng giao diện Cài đặt (Settings) cho phép người dùng đổi phím tắt kích hoạt tùy ý (bắt tổ hợp phím trực tiếp), bật/tắt khởi động cùng Windows, và quản lý danh sách đen các ứng dụng nhạy cảm.

## 📋 Implementation Details

1. **Custom Hotkey Recorder:**
   * Hộp thoại bấm tổ hợp phím (Key Recorder Box) lắng nghe sự kiện phím và ghi lại (VD: `Ctrl + Shift + V`, `Alt + V`, `Win + Shift + V`).
   * Kiểm tra xung đột trước khi lưu vào `config.json`.
2. **Khởi động cùng Windows:**
   * Thêm/xóa Registry key tại `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
3. **Quản lý Danh sách đen (Blacklist):**
   * Cho phép người dùng thêm tên tiến trình (VD: `keepass.exe`, `telegram.exe`) để PasteFlow không lưu nội dung copy từ các app này.

## 🧪 Acceptance Criteria
- [ ] Người dùng đổi phím tắt thành công qua giao diện và phím tắt mới có hiệu lực ngay lập tức.
- [ ] Tùy chọn Launch on Startup hoạt động chuẩn xác qua Registry của Windows.
