pub const MOD_ALT: u32 = 0x0001;
pub const MOD_CONTROL: u32 = 0x0002;
pub const MOD_SHIFT: u32 = 0x0004;
pub const MOD_WIN: u32 = 0x0008;
pub const MOD_NOREPEAT: u32 = 0x4000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedHotkey {
    pub modifiers: u32,
    pub vk_code: u32,
    pub display: String,
}

pub fn parse_hotkey(input: &str) -> Result<ParsedHotkey, String> {
    let parts: Vec<&str> = input.split('+').map(|s| s.trim()).collect();
    if parts.is_empty() {
        return Err("Hotkey string cannot be empty".to_string());
    }

    let mut modifiers = MOD_NOREPEAT;
    let mut key_part = None;

    for part in parts {
        match part.to_lowercase().as_str() {
            "ctrl" | "control" => modifiers |= MOD_CONTROL,
            "shift" => modifiers |= MOD_SHIFT,
            "alt" => modifiers |= MOD_ALT,
            "win" | "super" | "cmd" => modifiers |= MOD_WIN,
            other => {
                if key_part.is_some() {
                    return Err(format!("Multiple main keys specified: {} and {}", key_part.unwrap(), other));
                }
                key_part = Some(other.to_string());
            }
        }
    }

    let key = key_part.ok_or_else(|| "No main key specified (e.g. 'V', 'Space', '1')".to_string())?;

    let vk_code = match key.to_uppercase().as_str() {
        "SPACE" => 0x20,
        "RETURN" | "ENTER" => 0x0D,
        "TAB" => 0x09,
        "ESC" | "ESCAPE" => 0x1B,
        single if single.len() == 1 => {
            let c = single.chars().next().unwrap();
            if c.is_ascii_alphanumeric() {
                c.to_ascii_uppercase() as u32
            } else {
                return Err(format!("Unsupported key character: {}", c));
            }
        }
        f_key if f_key.starts_with('F') => {
            if let Ok(num) = f_key[1..].parse::<u32>() {
                if (1..=12).contains(&num) {
                    0x6F + num // VK_F1 is 0x70
                } else {
                    return Err(format!("Unsupported F-key: {}", f_key));
                }
            } else {
                return Err(format!("Invalid F-key format: {}", f_key));
            }
        }
        unsupported => return Err(format!("Unsupported key: {}", unsupported)),
    };

    Ok(ParsedHotkey {
        modifiers,
        vk_code,
        display: input.to_string(),
    })
}

#[cfg(windows)]
pub mod win32 {
    use super::*;
    use windows::Win32::Foundation::*;
    use windows::Win32::UI::Input::KeyboardAndMouse::*;

    pub fn register(hwnd: HWND, id: i32, hotkey: &ParsedHotkey) -> Result<(), windows::core::Error> {
        unsafe {
            RegisterHotKey(
                hwnd,
                id,
                HOT_KEY_MODIFIERS(hotkey.modifiers),
                hotkey.vk_code,
            )
        }
    }

    pub fn unregister(hwnd: HWND, id: i32) -> Result<(), windows::core::Error> {
        unsafe {
            UnregisterHotKey(hwnd, id)
        }
    }
}
