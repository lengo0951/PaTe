pub fn strip_rich_text(input: &str) -> String {
    input
        .chars()
        .filter(|&c| c == '\n' || c == '\r' || c == '\t' || !c.is_control())
        .collect::<String>()
        .replace("\r\n", "\n")
}

#[cfg(windows)]
pub mod win32 {
    use windows::Win32::Foundation::*;
    use windows::Win32::System::Threading::*;
    use windows::Win32::UI::Input::KeyboardAndMouse::*;
    use windows::Win32::UI::WindowsAndMessaging::*;

    /// Deterministically restores focus to `target_hwnd` bypassing Windows 11 Foreground Lock
    /// via `AttachThreadInput`, then synthesizes `Ctrl + V`.
    pub fn restore_focus(target_hwnd: Option<HWND>) {
        unsafe {
            if let Some(hwnd) = target_hwnd {
                if IsWindow(hwnd).as_bool() {
                    let fg = GetForegroundWindow();
                    if fg.0 != hwnd.0 {
                        let current_tid = GetCurrentThreadId();
                        let target_tid = GetWindowThreadProcessId(hwnd, None);
                        let attached = if current_tid != target_tid && target_tid != 0 {
                            AttachThreadInput(current_tid, target_tid, true).as_bool()
                        } else {
                            false
                        };

                        let _ = BringWindowToTop(hwnd);
                        let _ = SetForegroundWindow(hwnd);

                        if attached {
                            let _ = AttachThreadInput(current_tid, target_tid, false);
                        }
                        std::thread::sleep(std::time::Duration::from_millis(14));
                    }
                }
            }
        }
    }

    pub fn simulate_paste(target_hwnd: Option<HWND>) {
        restore_focus(target_hwnd);
        send_ctrl_v();
    }

    pub fn send_tab_key() {
        unsafe {
            let inputs = [
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VIRTUAL_KEY(0x09), // VK_TAB
                            wScan: 0,
                            dwFlags: KEYBD_EVENT_FLAGS(0),
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VIRTUAL_KEY(0x09),
                            wScan: 0,
                            dwFlags: KEYEVENTF_KEYUP,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
            ];
            let _ = SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
        }
    }

    pub fn send_ctrl_v() {
        unsafe {
            let inputs = [
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VIRTUAL_KEY(0x11), // VK_CONTROL
                            wScan: 0,
                            dwFlags: KEYBD_EVENT_FLAGS(0),
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VIRTUAL_KEY(0x56), // 'V'
                            wScan: 0,
                            dwFlags: KEYBD_EVENT_FLAGS(0),
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VIRTUAL_KEY(0x56),
                            wScan: 0,
                            dwFlags: KEYEVENTF_KEYUP,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VIRTUAL_KEY(0x11),
                            wScan: 0,
                            dwFlags: KEYEVENTF_KEYUP,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
            ];

            let _ = SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_strip_rich_text() {
        assert_eq!(strip_rich_text("Hello\r\nWorld\x07!"), "Hello\nWorld!");
    }
}
