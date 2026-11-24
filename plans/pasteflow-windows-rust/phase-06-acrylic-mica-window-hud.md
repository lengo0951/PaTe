---
phase: 6
title: "Acrylic / Mica Window HUD & DirectComposition"
status: pending
type: ui
---

# Phase 06: Acrylic / Mica Window HUD & DirectComposition

## 🎯 Objective
Xây dựng cửa sổ không viền (borderless popup HUD) trượt từ cạnh đáy màn hình Windows lên, áp dụng hiệu ứng kính mờ chuẩn Windows 11 (**Mica / Acrylic**) và Windows 10 (**Accent Blur**).

## 📋 Implementation Details

1. **Khởi tạo Cửa sổ Win32:**
   * `CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, ...)`
   * Kích thước: Rộng 100% màn hình trừ lề 24px, cao 210px.
2. **Kích hoạt Hiệu ứng Kính mờ (DWM):**
   * Trên Windows 11:
     ```rust
     DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &DWMSBT_TRANSIENTWINDOW, sizeof(u32));
     DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &DWMWCP_ROUND, sizeof(u32));
     ```
   * Trên Windows 10: Gọi `SetWindowCompositionAttribute` bật `ACCENT_ENABLE_ACRYLICBLURBEHIND`.
3. **Animation trượt đáy:**
   * Điều chỉnh `SetWindowPos` bằng hàm nội suy mượt mà (Ease-out Cubic) trong 150ms khi người dùng nhấn phím tắt.

## 🧪 Acceptance Criteria
- [ ] Cửa sổ hiển thị mờ kính trong suốt và bo góc đẹp mắt trên cả Win 10 & Win 11.
- [ ] Nhấn phím tắt mở/đóng thanh HUD với độ trễ < 5ms.
- [ ] Không giật lag, không cướp focus của ứng dụng đang gõ phím.
