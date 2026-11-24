---
phase: 9
title: "Kiri Windows E2E Testing, Optimization & GitHub Release"
status: pending
type: release
---

# Phase 09: Kiri Windows E2E Testing, Optimization & GitHub Release

## 🎯 Objective
Thực hiện kiểm thử đầu-cuối (End-to-End) bên trong môi trường giả lập Windows trên Kiri, tối ưu hóa kích thước file binary bằng Link-Time Optimization (LTO) & Strip symbols, đóng gói file `.exe` cài đặt và bản Portable Zip để phát hành lên GitHub.

## 📋 Implementation Details

1. **Kiểm thử E2E trên Kiri Windows:**
   * Khởi chạy file `.exe` bên trong container/microVM Windows trên Kiri.
   * Kiểm tra khả năng đồng bộ clipboard, phím tắt toàn hệ thống, dán tự động vào các ứng dụng Windows.
   * Đo đạc bộ nhớ RAM bằng Task Manager (mục tiêu: < 25 MB).
2. **Tối ưu hóa Binary (Cargo Profile Release):**
   ```toml
   [profile.release]
   opt-level = 3
   lto = true
   codegen-units = 1
   panic = "abort"
   strip = true
   ```
   * Dung lượng `.exe` đầu ra đạt ngưỡng **~5 MB – 7 MB**.
3. **Phát hành lên GitHub Releases:**
   * Sử dụng lệnh `gh release upload` để phát hành bản `PasteFlow-v1.1.0-windows-x64.zip`.

## 🧪 Acceptance Criteria
- [ ] Chạy mượt mà trên môi trường Kiri Windows, RAM thực tế đo được < 25 MB.
- [ ] File `.exe` độc lập không cần cài đặt thêm .NET hay bất kỳ runtime phụ nào.
- [ ] Bản phát hành hoàn chỉnh được upload lên GitHub repo `lengo0951/PasteFlow`.
