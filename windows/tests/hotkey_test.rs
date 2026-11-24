use pasteflow_windows::core::hotkey::{parse_hotkey, MOD_ALT, MOD_CONTROL, MOD_NOREPEAT, MOD_SHIFT, MOD_WIN};

#[test]
fn test_default_hotkey_parsing() {
    let parsed = parse_hotkey("Ctrl+Shift+V").expect("Should parse default hotkey");
    assert_eq!(parsed.modifiers & MOD_CONTROL, MOD_CONTROL);
    assert_eq!(parsed.modifiers & MOD_SHIFT, MOD_SHIFT);
    assert_eq!(parsed.modifiers & MOD_NOREPEAT, MOD_NOREPEAT);
    assert_eq!(parsed.vk_code, 0x56); // 'V'
}

#[test]
fn test_custom_hotkey_combinations() {
    // Alt + V
    let alt_v = parse_hotkey("Alt+V").expect("Should parse Alt+V");
    assert_eq!(alt_v.modifiers & MOD_ALT, MOD_ALT);
    assert_eq!(alt_v.vk_code, 0x56);

    // Ctrl + Space
    let ctrl_space = parse_hotkey("Ctrl+Space").expect("Should parse Ctrl+Space");
    assert_eq!(ctrl_space.modifiers & MOD_CONTROL, MOD_CONTROL);
    assert_eq!(ctrl_space.vk_code, 0x20);

    // Win + Shift + V
    let win_shift_v = parse_hotkey("Win+Shift+V").expect("Should parse Win+Shift+V");
    assert_eq!(win_shift_v.modifiers & MOD_WIN, MOD_WIN);
    assert_eq!(win_shift_v.modifiers & MOD_SHIFT, MOD_SHIFT);

    // F12
    let f12 = parse_hotkey("Ctrl+F12").expect("Should parse Ctrl+F12");
    assert_eq!(f12.vk_code, 0x7B); // VK_F12
}

#[test]
fn test_invalid_hotkey_strings() {
    assert!(parse_hotkey("").is_err());
    assert!(parse_hotkey("Ctrl+Shift").is_err()); // No main key
    assert!(parse_hotkey("Ctrl+Alt+InvalidKeyName").is_err());
}
