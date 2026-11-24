---
phase: 5
title: "TDD: Storage Persistence & Privacy Blacklist Guard"
status: pending
type: tdd
---

# Phase 05: TDD Storage Persistence & Privacy Blacklist Guard

## 🎯 Objective
Quản lý lưu trữ trạng thái tại `%APPDATA%\PasteFlow\` bằng `serde_json`, triển khai thuật toán LRU giữ tối đa 500 clips để giới hạn dung lượng file < 1MB, và xây dựng bộ lọc bảo mật tự động bỏ qua dữ liệu từ các trình quản lý mật khẩu.

## 🧪 TDD Specification

### 1. Test Cases (`tests/storage_test.rs`)
* `test_history_serialization_roundtrip()`: Serialize và Deserialize danh sách `ClipboardItem` qua JSON không làm mất mát dữ liệu hoặc timestamp.
* `test_lru_capacity_limit()`: Khi thêm clip thứ 501, clip cũ nhất (không được ghim trong pinboard) tự động bị đào thải.
* `test_pinboard_persistence()`: Đảm bảo các thẻ được ghim vào Pinboard không bao giờ bị tự động xóa bởi cơ chế LRU.
* `test_privacy_blacklist_check()`: Kiểm tra danh sách ứng dụng bị cấm (`1Password.exe`, `Bitwarden.exe`, `KeePass.exe`, `KeePassXC.exe`). Khi tiến trình nguồn nằm trong danh sách đen, hàm trả về `false` và clip bị từ chối lưu.

### 2. Implementation (`src/core/storage.rs`)
* Cấu trúc thư mục:
  * `%APPDATA%\PasteFlow\history.json`
  * `%APPDATA%\PasteFlow\pinboards.json`
  * `%APPDATA%\PasteFlow\config.json`
* Sử dụng `atomic_write` để tránh hỏng file JSON khi máy tính tắt đột ngột.

## 🧪 Acceptance Criteria
- [ ] TDD tests cho LRU, serialization và privacy guard đều PASS.
- [ ] Dung lượng file lưu trữ luôn nằm trong ngưỡng tối ưu (< 500 KB cho 500 items).
