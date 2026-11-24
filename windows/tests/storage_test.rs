use pasteflow_windows::core::storage::HistoryStore;
use pasteflow_windows::core::types::ClipboardItem;

#[test]
fn test_blacklist_filtering() {
    let temp_dir = std::env::temp_dir().join(format!("pasteflow_test_{}", uuid::Uuid::new_v4()));
    let mut store = HistoryStore::new(temp_dir);

    // 1Password should be blocked
    let pass_item = ClipboardItem::new_text(
        "SuperSecretPassword123".to_string(),
        Some("1Password.exe".to_string()),
        None,
    );
    assert!(!store.add_item(pass_item));
    assert_eq!(store.items.len(), 0);

    // Normal app should be allowed
    let normal_item = ClipboardItem::new_text(
        "Normal copied text".to_string(),
        Some("Code.exe".to_string()),
        None,
    );
    assert!(store.add_item(normal_item));
    assert_eq!(store.items.len(), 1);
}

#[test]
fn test_lru_eviction_and_pinned_protection() {
    let temp_dir = std::env::temp_dir().join(format!("pasteflow_test_{}", uuid::Uuid::new_v4()));
    let mut store = HistoryStore::new(temp_dir);
    store.config.max_items = 3;

    // Add 1st item (pinned to a board)
    let mut item1 = ClipboardItem::new_text("Item 1 (Pinned)".to_string(), None, None);
    item1.pinboard_ids.push("pinboard_api".to_string());
    store.add_item(item1);

    // Add 2nd, 3rd, 4th item (unpinned)
    store.add_item(ClipboardItem::new_text("Item 2".to_string(), None, None));
    store.add_item(ClipboardItem::new_text("Item 3".to_string(), None, None));
    store.add_item(ClipboardItem::new_text("Item 4".to_string(), None, None));

    // Store capped at max 3 items
    assert_eq!(store.items.len(), 3);

    // Pinned Item 1 MUST still be in store
    assert!(store.items.iter().any(|i| i.text_value.as_deref() == Some("Item 1 (Pinned)")));
    // Item 4 and Item 3 should be there
    assert!(store.items.iter().any(|i| i.text_value.as_deref() == Some("Item 4")));
    assert!(store.items.iter().any(|i| i.text_value.as_deref() == Some("Item 3")));
    // Item 2 (oldest unpinned) should have been evicted
    assert!(!store.items.iter().any(|i| i.text_value.as_deref() == Some("Item 2")));
}

#[test]
fn test_storage_roundtrip_persistence() {
    let temp_dir = std::env::temp_dir().join(format!("pasteflow_test_{}", uuid::Uuid::new_v4()));
    let mut store = HistoryStore::new(temp_dir.clone());
    store.add_item(ClipboardItem::new_text("Persistent Clip".to_string(), None, None));
    store.save().expect("Save should succeed");

    // Reopen store
    let store2 = HistoryStore::new(temp_dir);
    assert_eq!(store2.items.len(), 1);
    assert_eq!(store2.items[0].text_value.as_deref(), Some("Persistent Clip"));
}
