---
phase: 7
title: "Quick Look Spacebar Preview & Quick Paste 1-9"
status: pending
type: feature
---

# Phase 07: Quick Look Spacebar Preview & Quick Paste 1-9

## 🎯 Objective
Bổ sung tính năng xem trước tức thì bằng phím cách (`Spacebar`) tương tự Quick Look trên macOS và dán nhanh bằng các phím số `1` đến `9`.

## 📋 Implementation Details

1. **Xem nhanh bằng phím Space:**
   * Bắt sự kiện bàn phím `WM_KEYDOWN` với phím `VK_SPACE`.
   * Mở rộng modal trung tâm hiển thị:
     * Code Snippet: Hiển thị font Monospace (Consolas / Cascadia Code), số dòng và cú pháp.
     * Ảnh: Hiển thị ảnh kích thước đầy đủ.
     * Màu sắc: Hiển thị ô màu lớn kèm các mã HEX, RGB, HSL.
2. **Dán nhanh 1-9:**
   * Khi thanh HUD đang mở, người dùng bấm phím `1` đến `9` sẽ dán ngay lập tức thẻ tương ứng mà không cần dùng chuột click.

## 🧪 Acceptance Criteria
- [ ] Bấm Space mở modal xem trước mượt mà; bấm Esc hoặc Space lần nữa đóng lại.
- [ ] Bấm phím 1-9 dán chính xác thẻ tương ứng vào ứng dụng đích.
