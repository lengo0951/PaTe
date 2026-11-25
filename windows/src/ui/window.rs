#[cfg(windows)]
pub mod win32 {
    use parking_lot::Mutex;
    use std::sync::Arc;
    use windows::core::*;
    use windows::Win32::Foundation::*;
    use windows::Win32::Graphics::Dwm::*;
    use windows::Win32::Graphics::Gdi::*;
    use windows::Win32::System::DataExchange::*;
    use windows::Win32::System::LibraryLoader::*;
    use windows::Win32::System::Memory::*;
    use windows::Win32::System::Registry::*;
    use windows::Win32::System::Threading::*;
    use windows::Win32::UI::Input::KeyboardAndMouse::*;
    use windows::Win32::UI::Shell::*;
    use windows::Win32::UI::WindowsAndMessaging::*;

    use crate::core::clipboard::win32::*;
    use crate::core::clipboard::CF_UNICODETEXT;
    use crate::core::hotkey::parse_hotkey;
    use crate::core::hotkey::win32::*;
    use crate::core::simulator::win32::*;
    use crate::core::storage::HistoryStore;
    use crate::core::types::{ClipboardItem, ContentType};

    pub const DWMWA_SYSTEMBACKDROP_TYPE: u32 = 38;
    pub const DWMWA_WINDOW_CORNER_PREFERENCE: u32 = 33;
    pub const DWMSBT_TRANSIENTWINDOW: u32 = 3;
    pub const DWMWCP_ROUND: u32 = 2;

    pub const WM_TRAYICON: u32 = WM_USER + 101;
    pub const IDT_CLEAR_SECRET: usize = 9001;

    pub const IDM_TOGGLE: usize = 1001;
    pub const IDM_ADD_ACCOUNT: usize = 1002;
    pub const IDM_STARTUP: usize = 1003;
    pub const IDM_CLEAR: usize = 1004;
    pub const IDM_ABOUT: usize = 1005;
    pub const IDM_EXIT: usize = 1006;

    // Credential Dialog Control IDs
    const IDC_TITLE_EDIT: i32 = 2001;
    const IDC_USER_EDIT: i32 = 2002;
    const IDC_PASS_EDIT: i32 = 2003;
    const IDC_SAVE_BTN: usize = 2004;
    const IDC_CANCEL_BTN: usize = 2005;
    const IDC_PASTE_USER_BTN: usize = 2006;
    const IDC_PASTE_PASS_BTN: usize = 2007;

    pub struct WindowState {
        pub store: HistoryStore,
        pub is_visible: bool,
        pub vault_only_tab: bool,
        pub selected_index: usize,
        pub target_hwnd: Option<HWND>,
        pub quicklook_active: bool,
        pub font_title: HFONT,
        pub font_body: HFONT,
        pub cred_dialog_hwnd: Option<HWND>,
    }

    pub static mut GLOBAL_STATE: Option<Arc<Mutex<WindowState>>> = None;

    /// Native Win32 Registry startup check & toggle (eliminates external .bat/PowerShell scripts)
    pub unsafe fn is_startup_enabled() -> bool {
        let subkey: Vec<u16> = "Software\\Microsoft\\Windows\\CurrentVersion\\Run\0"
            .encode_utf16()
            .collect();
        let val_name: Vec<u16> = "PATE\0".encode_utf16().collect();
        let mut hkey = HKEY::default();
        if RegOpenKeyExW(
            HKEY_CURRENT_USER,
            PCWSTR(subkey.as_ptr()),
            0,
            KEY_READ,
            &mut hkey,
        )
        .is_ok()
        {
            let exists = RegQueryValueExW(
                hkey,
                PCWSTR(val_name.as_ptr()),
                None,
                None,
                None,
                None,
            )
            .is_ok();
            let _ = RegCloseKey(hkey);
            return exists;
        }
        false
    }

    pub unsafe fn set_startup_enabled(enable: bool) {
        let subkey: Vec<u16> = "Software\\Microsoft\\Windows\\CurrentVersion\\Run\0"
            .encode_utf16()
            .collect();
        let val_name: Vec<u16> = "PATE\0".encode_utf16().collect();
        let mut hkey = HKEY::default();
        if RegOpenKeyExW(
            HKEY_CURRENT_USER,
            PCWSTR(subkey.as_ptr()),
            0,
            KEY_SET_VALUE,
            &mut hkey,
        )
        .is_ok()
        {
            if enable {
                let mut exe_buf = [0u16; 512];
                let len = GetModuleFileNameW(None, &mut exe_buf) as usize;
                if len > 0 {
                    let path_str = String::from_utf16_lossy(&exe_buf[..len]);
                    let quoted: Vec<u16> = format!("\"{}\"\0", path_str).encode_utf16().collect();
                    let bytes = std::slice::from_raw_parts(
                        quoted.as_ptr() as *const u8,
                        quoted.len() * 2,
                    );
                    let _ = RegSetValueExW(
                        hkey,
                        PCWSTR(val_name.as_ptr()),
                        0,
                        REG_SZ,
                        Some(bytes),
                    );
                }
            } else {
                let _ = RegDeleteValueW(hkey, PCWSTR(val_name.as_ptr()));
            }
            let _ = RegCloseKey(hkey);
        }
    }

    fn visible_item_indices(state: &WindowState) -> Vec<usize> {
        if state.vault_only_tab {
            state
                .store
                .items
                .iter()
                .enumerate()
                .filter(|(_, it)| it.content_type == ContentType::Credential)
                .map(|(i, _)| i)
                .collect()
        } else {
            (0..state.store.items.len()).collect()
        }
    }

    #[derive(Clone, Copy, PartialEq, Eq)]
    pub enum WinCredPasteMode {
        SmartAutoFill,
        SmartAutoFillAndSubmit,
        UsernameAndPreloadPass,
        PasswordOnly,
    }

    unsafe fn execute_item_paste(
        hwnd: HWND,
        target: Option<HWND>,
        item: &ClipboardItem,
        vault_secret: Option<String>,
        mode: WinCredPasteMode,
    ) {
        if item.content_type == ContentType::Credential {
            let user = item.credential_username.clone().unwrap_or_default();
            let secret = vault_secret.unwrap_or_default();

            // Always pre-load Password onto Clipboard upfront so there is ZERO clipboard swap race!
            let clipboard_val = if !secret.is_empty() { &secret } else { &user };
            if !clipboard_val.is_empty() {
                set_clipboard_text_with_tag(hwnd, clipboard_val, true);
                let _ = SetTimer(hwnd, IDT_CLEAR_SECRET, 60_000, None);
            }

            restore_focus(target);

            match mode {
                WinCredPasteMode::PasswordOnly => {
                    send_ctrl_v();
                }
                WinCredPasteMode::UsernameAndPreloadPass => {
                    // Type Username directly via Unicode HID stream while Password stays ready on Clipboard for Page 2!
                    if !user.is_empty() {
                        send_unicode_text(&user);
                    } else {
                        send_ctrl_v();
                    }
                }
                WinCredPasteMode::SmartAutoFill | WinCredPasteMode::SmartAutoFillAndSubmit => {
                    if !user.is_empty() && !secret.is_empty() {
                        send_unicode_text(&user);
                        std::thread::sleep(std::time::Duration::from_millis(35));
                        send_tab_key();
                        std::thread::sleep(std::time::Duration::from_millis(45));
                        send_ctrl_v();
                    } else if !user.is_empty() {
                        send_unicode_text(&user);
                    } else {
                        send_ctrl_v();
                    }

                    if mode == WinCredPasteMode::SmartAutoFillAndSubmit {
                        std::thread::sleep(std::time::Duration::from_millis(45));
                        send_return_key();
                    }
                }
            }
        } else if let Some(ref text) = item.text_value {
            set_clipboard_text_with_tag(hwnd, text, false);
            simulate_paste(target);
        }
    }

    pub unsafe fn toggle_hud(hwnd: HWND) {
        if let Some(ref state_arc) = GLOBAL_STATE {
            let mut state = state_arc.lock();
            state.is_visible = !state.is_visible;
            if state.is_visible {
                let fg = GetForegroundWindow();
                if fg.0 != hwnd.0 && !fg.0.is_null() {
                    state.target_hwnd = Some(fg);
                }
                state.selected_index = 0;
                state.quicklook_active = false;
                let _ = ShowWindow(hwnd, SW_SHOW);
                let _ = SetForegroundWindow(hwnd);
                let _ = InvalidateRect(hwnd, None, true);
            } else {
                let _ = ShowWindow(hwnd, SW_HIDE);
            }
        }
    }

    pub unsafe fn open_credential_dialog(parent_hwnd: HWND) {
        if let Some(ref state_arc) = GLOBAL_STATE {
            let state = state_arc.lock();
            if let Some(existing) = state.cred_dialog_hwnd {
                if IsWindow(existing).as_bool() {
                    let _ = SetForegroundWindow(existing);
                    return;
                }
            }
        }

        let instance = GetModuleHandleW(None).unwrap_or_default();
        let cls: Vec<u16> = "PATECredDlg\0".encode_utf16().collect();
        let title: Vec<u16> = "Save Account & Password (DPAPI Encrypted)\0".encode_utf16().collect();

        let dlg = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_DLGMODALFRAME,
            PCWSTR(cls.as_ptr()),
            PCWSTR(title.as_ptr()),
            WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_VISIBLE,
            420,
            280,
            380,
            265,
            parent_hwnd,
            None,
            instance,
            None,
        );

        if let Ok(dlg_hwnd) = dlg {
            let static_cls: Vec<u16> = "STATIC\0".encode_utf16().collect();
            let edit_cls: Vec<u16> = "EDIT\0".encode_utf16().collect();
            let btn_cls: Vec<u16> = "BUTTON\0".encode_utf16().collect();

            let l1: Vec<u16> = "Account Name (e.g. dgcb sso prod):\0".encode_utf16().collect();
            let l2: Vec<u16> = "Username / Email (Ctrl+V or click Paste):\0".encode_utf16().collect();
            let l3: Vec<u16> = "Password / Token (Ctrl+V or click Paste):\0".encode_utf16().collect();
            let b_paste: Vec<u16> = "Paste\0".encode_utf16().collect();
            let b_save: Vec<u16> = "Save to Vault\0".encode_utf16().collect();
            let b_cancel: Vec<u16> = "Cancel\0".encode_utf16().collect();

            let _ = CreateWindowExW(WINDOW_EX_STYLE(0), PCWSTR(static_cls.as_ptr()), PCWSTR(l1.as_ptr()), WS_CHILD | WS_VISIBLE, 18, 14, 330, 18, dlg_hwnd, None, instance, None);
            let h_title = CreateWindowExW(WS_EX_CLIENTEDGE, PCWSTR(edit_cls.as_ptr()), PCWSTR::null(), WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(ES_AUTOHSCROLL as u32), 18, 34, 330, 24, dlg_hwnd, HMENU(IDC_TITLE_EDIT as *mut _), instance, None);

            let _ = CreateWindowExW(WINDOW_EX_STYLE(0), PCWSTR(static_cls.as_ptr()), PCWSTR(l2.as_ptr()), WS_CHILD | WS_VISIBLE, 18, 68, 330, 18, dlg_hwnd, None, instance, None);
            let _ = CreateWindowExW(WS_EX_CLIENTEDGE, PCWSTR(edit_cls.as_ptr()), PCWSTR::null(), WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(ES_AUTOHSCROLL as u32), 18, 88, 265, 24, dlg_hwnd, HMENU(IDC_USER_EDIT as *mut _), instance, None);
            let _ = CreateWindowExW(WINDOW_EX_STYLE(0), PCWSTR(btn_cls.as_ptr()), PCWSTR(b_paste.as_ptr()), WS_CHILD | WS_VISIBLE | WS_TABSTOP, 288, 88, 60, 24, dlg_hwnd, HMENU(IDC_PASTE_USER_BTN as *mut _), instance, None);

            let _ = CreateWindowExW(WINDOW_EX_STYLE(0), PCWSTR(static_cls.as_ptr()), PCWSTR(l3.as_ptr()), WS_CHILD | WS_VISIBLE, 18, 122, 330, 18, dlg_hwnd, None, instance, None);
            let _ = CreateWindowExW(WS_EX_CLIENTEDGE, PCWSTR(edit_cls.as_ptr()), PCWSTR::null(), WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(ES_AUTOHSCROLL as u32), 18, 142, 265, 24, dlg_hwnd, HMENU(IDC_PASS_EDIT as *mut _), instance, None);
            let _ = CreateWindowExW(WINDOW_EX_STYLE(0), PCWSTR(btn_cls.as_ptr()), PCWSTR(b_paste.as_ptr()), WS_CHILD | WS_VISIBLE | WS_TABSTOP, 288, 142, 60, 24, dlg_hwnd, HMENU(IDC_PASTE_PASS_BTN as *mut _), instance, None);

            let _ = CreateWindowExW(WINDOW_EX_STYLE(0), PCWSTR(btn_cls.as_ptr()), PCWSTR(b_cancel.as_ptr()), WS_CHILD | WS_VISIBLE | WS_TABSTOP, 158, 182, 85, 28, dlg_hwnd, HMENU(IDC_CANCEL_BTN as *mut _), instance, None);
            let _ = CreateWindowExW(WINDOW_EX_STYLE(0), PCWSTR(btn_cls.as_ptr()), PCWSTR(b_save.as_ptr()), WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(BS_DEFPUSHBUTTON as u32), 253, 182, 95, 28, dlg_hwnd, HMENU(IDC_SAVE_BTN as *mut _), instance, None);

            if let Some(ref state_arc) = GLOBAL_STATE {
                state_arc.lock().cred_dialog_hwnd = Some(dlg_hwnd);
            }
            let _ = SetForegroundWindow(dlg_hwnd);
            if let Ok(ht) = h_title {
                let _ = SetFocus(ht);
            }
        }
    }

    unsafe fn read_control_text(dlg: HWND, id: i32) -> String {
        if let Ok(ctrl) = GetDlgItem(dlg, id) {
            let mut buf = [0u16; 512];
            let len = GetWindowTextW(ctrl, &mut buf) as usize;
            return String::from_utf16_lossy(&buf[..len]).trim().to_string();
        }
        String::new()
    }

    pub unsafe extern "system" fn cred_dlg_proc(
        hwnd: HWND,
        msg: u32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        match msg {
            WM_COMMAND => {
                let id = (wparam.0 & 0xFFFF) as usize;
                if id == IDC_PASTE_USER_BTN || id == IDC_PASTE_PASS_BTN {
                    let target_ctrl_id = if id == IDC_PASTE_USER_BTN { IDC_USER_EDIT } else { IDC_PASS_EDIT };
                    if let Ok(ctrl) = GetDlgItem(hwnd, target_ctrl_id) {
                        let _ = SendMessageW(ctrl, WM_PASTE, WPARAM(0), LPARAM(0));
                    }
                    return LRESULT(0);
                } else if id == IDC_SAVE_BTN {
                    let title = read_control_text(hwnd, IDC_TITLE_EDIT);
                    let user = read_control_text(hwnd, IDC_USER_EDIT);
                    let pass = read_control_text(hwnd, IDC_PASS_EDIT);
                    if !pass.is_empty() || !user.is_empty() {
                        let final_title = if title.is_empty() {
                            if user.is_empty() { "Account".to_string() } else { user.clone() }
                        } else {
                            title
                        };
                        if let Some(ref state_arc) = GLOBAL_STATE {
                            let mut state = state_arc.lock();
                            state.store.save_credential(None, final_title, user, &pass, None);
                            let _ = state.store.save();
                            state.cred_dialog_hwnd = None;
                        }
                    }
                    let _ = DestroyWindow(hwnd);
                    return LRESULT(0);
                } else if id == IDC_CANCEL_BTN {
                    if let Some(ref state_arc) = GLOBAL_STATE {
                        state_arc.lock().cred_dialog_hwnd = None;
                    }
                    let _ = DestroyWindow(hwnd);
                    return LRESULT(0);
                }
                LRESULT(0)
            }
            WM_CLOSE => {
                if let Some(ref state_arc) = GLOBAL_STATE {
                    state_arc.lock().cred_dialog_hwnd = None;
                }
                let _ = DestroyWindow(hwnd);
                LRESULT(0)
            }
            _ => DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }

    pub unsafe extern "system" fn window_proc(
        hwnd: HWND,
        msg: u32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        match msg {
            WM_TIMER => {
                if wparam.0 == IDT_CLEAR_SECRET {
                    let _ = KillTimer(hwnd, IDT_CLEAR_SECRET);
                    if OpenClipboard(hwnd).is_ok() {
                        let _ = EmptyClipboard();
                        let _ = CloseClipboard();
                    }
                }
                LRESULT(0)
            }
            WM_CLIPBOARDUPDATE => {
                if let Some(ref state_arc) = GLOBAL_STATE {
                    if let Some(text) = read_clipboard_text(hwnd) {
                        let mut app_name = None;
                        let fg_hwnd = GetForegroundWindow();
                        if !fg_hwnd.0.is_null() {
                            let mut pid = 0;
                            GetWindowThreadProcessId(fg_hwnd, Some(&mut pid));
                            if pid != 0 {
                                if let Ok(process) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) {
                                    let mut buffer = [0u16; 512];
                                    let mut size = buffer.len() as u32;
                                    if QueryFullProcessImageNameW(process, PROCESS_NAME_FORMAT(0), PWSTR(buffer.as_mut_ptr()), &mut size).is_ok() {
                                        let full_path = String::from_utf16_lossy(&buffer[..size as usize]);
                                        if let Some(file_name) = full_path.split('\\').last() {
                                            app_name = Some(file_name.to_string());
                                        }
                                    }
                                    let _ = CloseHandle(process);
                                }
                            }
                        }

                        let item = ClipboardItem::new_text(text, app_name.clone(), app_name);
                        let mut state = state_arc.lock();
                        if state.store.add_item(item) {
                            let _ = state.store.save();
                            let _ = InvalidateRect(hwnd, None, false);
                        }
                    }
                }
                LRESULT(0)
            }
            WM_HOTKEY => {
                toggle_hud(hwnd);
                LRESULT(0)
            }
            WM_COMMAND => {
                let id = wparam.0 as usize;
                match id {
                    IDM_TOGGLE => toggle_hud(hwnd),
                    IDM_ADD_ACCOUNT => open_credential_dialog(hwnd),
                    IDM_STARTUP => {
                        let currently_on = is_startup_enabled();
                        set_startup_enabled(!currently_on);
                        if let Some(ref state_arc) = GLOBAL_STATE {
                            let mut state = state_arc.lock();
                            state.store.config.launch_at_startup = !currently_on;
                            let _ = state.store.save();
                        }
                    }
                    IDM_CLEAR => {
                        if let Some(ref state_arc) = GLOBAL_STATE {
                            let mut state = state_arc.lock();
                            state.store.items.retain(|i| i.is_pinned());
                            let _ = state.store.save();
                            let _ = InvalidateRect(hwnd, None, false);
                        }
                    }
                    IDM_ABOUT => toggle_hud(hwnd),
                    IDM_EXIT => {
                        let _ = DestroyWindow(hwnd);
                    }
                    _ => {}
                }
                LRESULT(0)
            }
            WM_TRAYICON => {
                let event = lparam.0 as u32;
                match event {
                    WM_LBUTTONUP => {
                        toggle_hud(hwnd);
                    }
                    WM_RBUTTONUP => {
                        if let Ok(hmenu) = CreatePopupMenu() {
                            let startup_on = is_startup_enabled();
                            let m_toggle: Vec<u16> = "Toggle PATE (Ctrl+Shift+V)\0".encode_utf16().collect();
                            let m_add: Vec<u16> = "Add Account / Password... (Ctrl+N)\0".encode_utf16().collect();
                            let m_startup: Vec<u16> = "Launch at Windows Startup\0".encode_utf16().collect();
                            let m_clear: Vec<u16> = "Clear History (Keep Pinned & Accounts)\0".encode_utf16().collect();
                            let m_about: Vec<u16> = "PATE v1.2.0 (by Quốc Ngô)\0".encode_utf16().collect();
                            let m_exit: Vec<u16> = "Exit PATE\0".encode_utf16().collect();

                            let _ = AppendMenuW(hmenu, MF_STRING, IDM_TOGGLE, PCWSTR(m_toggle.as_ptr()));
                            let _ = AppendMenuW(hmenu, MF_STRING, IDM_ADD_ACCOUNT, PCWSTR(m_add.as_ptr()));
                            let _ = AppendMenuW(hmenu, MF_SEPARATOR, 0, PCWSTR::null());
                            let startup_flags = if startup_on { MF_STRING | MF_CHECKED } else { MF_STRING };
                            let _ = AppendMenuW(hmenu, startup_flags, IDM_STARTUP, PCWSTR(m_startup.as_ptr()));
                            let _ = AppendMenuW(hmenu, MF_STRING, IDM_CLEAR, PCWSTR(m_clear.as_ptr()));
                            let _ = AppendMenuW(hmenu, MF_SEPARATOR, 0, PCWSTR::null());
                            let _ = AppendMenuW(hmenu, MF_STRING, IDM_ABOUT, PCWSTR(m_about.as_ptr()));
                            let _ = AppendMenuW(hmenu, MF_STRING, IDM_EXIT, PCWSTR(m_exit.as_ptr()));

                            let mut pt = POINT::default();
                            let _ = GetCursorPos(&mut pt);
                            let _ = SetForegroundWindow(hwnd);
                            let _ = TrackPopupMenu(hmenu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, None);
                            let _ = DestroyMenu(hmenu);
                        }
                    }
                    _ => {}
                }
                LRESULT(0)
            }
            WM_LBUTTONDOWN => {
                let mouse_x = (lparam.0 as i32) as i16 as i32;
                let mouse_y = ((lparam.0 >> 16) as i32) as i16 as i32;
                if let Some(ref state_arc) = GLOBAL_STATE {
                    let mut state = state_arc.lock();
                    // Top header bar click: toggle All vs Accounts or "+ Account"
                    if mouse_y >= 4 && mouse_y <= 26 {
                        if mouse_x >= 20 && mouse_x <= 155 {
                            state.vault_only_tab = false;
                            state.selected_index = 0;
                            let _ = InvalidateRect(hwnd, None, false);
                        } else if mouse_x >= 160 && mouse_x <= 275 {
                            state.vault_only_tab = true;
                            state.selected_index = 0;
                            let _ = InvalidateRect(hwnd, None, false);
                        } else if mouse_x >= 285 && mouse_x <= 405 {
                            drop(state);
                            open_credential_dialog(hwnd);
                        }
                        return LRESULT(0);
                    }

                    let start_x = 20;
                    let card_width = 185;
                    let card_height = 165;
                    let card_y = 32;
                    let spacing = 14;

                    let visible = visible_item_indices(&state);
                    if mouse_y >= card_y && mouse_y <= card_y + card_height && mouse_x >= start_x {
                        let card_idx = ((mouse_x - start_x) / (card_width + spacing)) as usize;
                        let offset_in_card = (mouse_x - start_x) % (card_width + spacing);
                        if offset_in_card <= card_width && card_idx < visible.len() {
                            if state.selected_index != card_idx {
                                state.selected_index = card_idx;
                                let _ = InvalidateRect(hwnd, None, false);
                            }
                        }
                    }
                }
                LRESULT(0)
            }
            WM_LBUTTONDBLCLK => {
                let mouse_x = (lparam.0 as i32) as i16 as i32;
                let mouse_y = ((lparam.0 >> 16) as i32) as i16 as i32;
                if let Some(ref state_arc) = GLOBAL_STATE {
                    let mut state = state_arc.lock();
                    let start_x = 20;
                    let card_width = 185;
                    let card_height = 165;
                    let card_y = 32;
                    let spacing = 14;

                    let visible = visible_item_indices(&state);
                    if mouse_y >= card_y && mouse_y <= card_y + card_height && mouse_x >= start_x {
                        let card_idx = ((mouse_x - start_x) / (card_width + spacing)) as usize;
                        let offset_in_card = (mouse_x - start_x) % (card_width + spacing);
                        if offset_in_card <= card_width && card_idx < visible.len() {
                            let real_idx = visible[card_idx];
                            state.selected_index = card_idx;
                            let target = state.target_hwnd;
                            let item_opt = state.store.items.get(real_idx).cloned();
                            let secret = item_opt
                                .as_ref()
                                .and_then(|it| state.store.vault.get_secret(&it.id));
                            state.is_visible = false;
                            state.quicklook_active = false;
                            let _ = ShowWindow(hwnd, SW_HIDE);
                            drop(state);

                            if let Some(item) = item_opt {
                                execute_item_paste(
                                    hwnd,
                                    target,
                                    &item,
                                    secret,
                                    WinCredPasteMode::SmartAutoFill,
                                );
                            }
                        }
                    }
                }
                LRESULT(0)
            }
            WM_KEYDOWN => {
                let vk = wparam.0 as i32;
                let ctrl_down = (GetAsyncKeyState(0x11) as u16 & 0x8000) != 0;
                let shift_down = (GetAsyncKeyState(0x10) as u16 & 0x8000) != 0;
                let alt_down = (GetAsyncKeyState(0x12) as u16 & 0x8000) != 0;

                if let Some(ref state_arc) = GLOBAL_STATE {
                    let mut state = state_arc.lock();
                    let visible = visible_item_indices(&state);

                    match vk {
                        0x1B => {
                            // VK_ESCAPE
                            state.is_visible = false;
                            state.quicklook_active = false;
                            let _ = ShowWindow(hwnd, SW_HIDE);
                        }
                        0x09 => {
                            // VK_TAB switches All History <-> Accounts Vault
                            state.vault_only_tab = !state.vault_only_tab;
                            state.selected_index = 0;
                            let _ = InvalidateRect(hwnd, None, false);
                        }
                        0x4E if ctrl_down => {
                            // Ctrl + N -> Add Account
                            drop(state);
                            open_credential_dialog(hwnd);
                        }
                        0x55 if ctrl_down => {
                            // Ctrl + U -> Type Username & Pre-load Password to Clipboard
                            if let Some(&real_idx) = visible.get(state.selected_index) {
                                let target = state.target_hwnd;
                                let item_opt = state.store.items.get(real_idx).cloned();
                                let secret = item_opt
                                    .as_ref()
                                    .and_then(|it| state.store.vault.get_secret(&it.id));
                                state.is_visible = false;
                                let _ = ShowWindow(hwnd, SW_HIDE);
                                drop(state);
                                if let Some(item) = item_opt {
                                    execute_item_paste(
                                        hwnd,
                                        target,
                                        &item,
                                        secret,
                                        WinCredPasteMode::UsernameAndPreloadPass,
                                    );
                                }
                            }
                        }
                        0x20 => {
                            // VK_SPACE
                            state.quicklook_active = !state.quicklook_active;
                            let _ = InvalidateRect(hwnd, None, false);
                        }
                        0x0D => {
                            // VK_RETURN: Default Smart Auto-Fill (User -> Tab -> Pass)
                            if let Some(&real_idx) = visible.get(state.selected_index) {
                                let target = state.target_hwnd;
                                let item_opt = state.store.items.get(real_idx).cloned();
                                let secret = item_opt
                                    .as_ref()
                                    .and_then(|it| state.store.vault.get_secret(&it.id));
                                state.is_visible = false;
                                state.quicklook_active = false;
                                let _ = ShowWindow(hwnd, SW_HIDE);
                                drop(state);

                                if let Some(item) = item_opt {
                                    let mode = if shift_down {
                                        WinCredPasteMode::SmartAutoFillAndSubmit
                                    } else if alt_down {
                                        WinCredPasteMode::PasswordOnly
                                    } else {
                                        WinCredPasteMode::SmartAutoFill
                                    };
                                    execute_item_paste(hwnd, target, &item, secret, mode);
                                }
                            }
                        }
                        0x31..=0x39 => {
                            let idx = (vk - 0x31) as usize;
                            if let Some(&real_idx) = visible.get(idx) {
                                let target = state.target_hwnd;
                                let item_opt = state.store.items.get(real_idx).cloned();
                                let secret = item_opt
                                    .as_ref()
                                    .and_then(|it| state.store.vault.get_secret(&it.id));
                                state.is_visible = false;
                                let _ = ShowWindow(hwnd, SW_HIDE);
                                drop(state);

                                if let Some(item) = item_opt {
                                    execute_item_paste(
                                        hwnd,
                                        target,
                                        &item,
                                        secret,
                                        WinCredPasteMode::SmartAutoFill,
                                    );
                                }
                            }
                        }
                        0x2E | 0x08 => {
                            // VK_DELETE or VK_BACK
                            if let Some(&real_idx) = visible.get(state.selected_index) {
                                if let Some(id) = state.store.items.get(real_idx).map(|i| i.id.clone()) {
                                    state.store.remove_item(&id);
                                    let _ = state.store.save();
                                    if state.selected_index > 0 && state.selected_index >= visible.len().saturating_sub(1) {
                                        state.selected_index -= 1;
                                    }
                                    let _ = InvalidateRect(hwnd, None, false);
                                }
                            }
                        }
                        0x25 => {
                            if state.selected_index > 0 {
                                state.selected_index -= 1;
                                let _ = InvalidateRect(hwnd, None, false);
                            }
                        }
                        0x27 => {
                            if state.selected_index + 1 < visible.len() {
                                state.selected_index += 1;
                                let _ = InvalidateRect(hwnd, None, false);
                            }
                        }
                        _ => {}
                    }
                }
                LRESULT(0)
            }
            WM_PAINT => {
                let mut ps = PAINTSTRUCT::default();
                let hdc = BeginPaint(hwnd, &mut ps);
                if !hdc.0.is_null() {
                    let mut rc = RECT::default();
                    let _ = GetClientRect(hwnd, &mut rc);

                    let mem_dc = CreateCompatibleDC(hdc);
                    let mem_bmp = CreateCompatibleBitmap(hdc, rc.right - rc.left, rc.bottom - rc.top);
                    let old_bmp = SelectObject(mem_dc, HGDIOBJ(mem_bmp.0));

                    let bg_brush = CreateSolidBrush(COLORREF(0x001C1A1A));
                    FillRect(mem_dc, &rc, bg_brush);
                    let _ = DeleteObject(HGDIOBJ(bg_brush.0));

                    SetBkMode(mem_dc, TRANSPARENT);

                    if let Some(ref state_arc) = GLOBAL_STATE {
                        let state = state_arc.lock();
                        let old_font = SelectObject(mem_dc, HGDIOBJ(state.font_title.0));

                        // Draw Top Tab Bar
                        let tab_all_bg = CreateSolidBrush(COLORREF(if !state.vault_only_tab { 0x00663A10 } else { 0x002A2A2A }));
                        let tab_vault_bg = CreateSolidBrush(COLORREF(if state.vault_only_tab { 0x003A1E5A } else { 0x002A2A2A }));
                        let tab_add_bg = CreateSolidBrush(COLORREF(0x00332048));

                        let mut rc_all = RECT { left: 20, top: 6, right: 152, bottom: 26 };
                        let mut rc_vault = RECT { left: 160, top: 6, right: 274, bottom: 26 };
                        let mut rc_add = RECT { left: 284, top: 6, right: 404, bottom: 26 };

                        FillRect(mem_dc, &rc_all, tab_all_bg);
                        FillRect(mem_dc, &rc_vault, tab_vault_bg);
                        FillRect(mem_dc, &rc_add, tab_add_bg);

                        let _ = DeleteObject(HGDIOBJ(tab_all_bg.0));
                        let _ = DeleteObject(HGDIOBJ(tab_vault_bg.0));
                        let _ = DeleteObject(HGDIOBJ(tab_add_bg.0));

                        SetTextColor(mem_dc, COLORREF(0x00FFFFFF));
                        let mut t_all: [u16; 16] = [
                            b'C' as u16, b'l' as u16, b'i' as u16, b'p' as u16, b'b' as u16, b'o' as u16,
                            b'a' as u16, b'r' as u16, b'd' as u16, b' ' as u16, b'(' as u16, b'T' as u16,
                            b'a' as u16, b'b' as u16, b')' as u16, 0,
                        ];
                        let mut t_vault: [u16; 9] = [
                            b'A' as u16, b'c' as u16, b'c' as u16, b'o' as u16, b'u' as u16, b'n' as u16,
                            b't' as u16, b's' as u16, 0,
                        ];
                        let mut t_add: [u16; 12] = [
                            b'+' as u16, b' ' as u16, b'A' as u16, b'c' as u16, b'c' as u16, b'o' as u16,
                            b'u' as u16, b'n' as u16, b't' as u16, b' ' as u16, b'^' as u16, b'N' as u16,
                        ];
                        DrawTextW(mem_dc, &mut t_all[..15], &mut rc_all, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
                        DrawTextW(mem_dc, &mut t_vault[..8], &mut rc_vault, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
                        SetTextColor(mem_dc, COLORREF(0x007A5CFF));
                        DrawTextW(mem_dc, &mut t_add, &mut rc_add, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

                        // Reusable GDI card brushes & pens (Zero per-card GDI handle churn!)
                        let card_bg_sel = CreateSolidBrush(COLORREF(0x00463222));
                        let card_bg_norm = CreateSolidBrush(COLORREF(0x002B2B2B));
                        let border_pen_sel = CreatePen(PS_SOLID, 2, COLORREF(0x00FF840A));
                        let border_pen_cred = CreatePen(PS_SOLID, 1, COLORREF(0x005F37FF));
                        let border_pen_norm = CreatePen(PS_SOLID, 1, COLORREF(0x00444444));
                        let null_brush = GetStockObject(NULL_BRUSH);
                        let old_brush = SelectObject(mem_dc, null_brush);

                        let visible = visible_item_indices(&state);
                        let mut x_offset = 20;
                        let card_width = 185;
                        let card_height = 165;
                        let card_y = 32;
                        let spacing = 14;

                        for (vis_idx, &real_idx) in visible.iter().take(12).enumerate() {
                            if x_offset + card_width > rc.right {
                                break;
                            }
                            let item = &state.store.items[real_idx];
                            let is_selected = vis_idx == state.selected_index;
                            let card_rc = RECT {
                                left: x_offset,
                                top: card_y,
                                right: x_offset + card_width,
                                bottom: card_y + card_height,
                            };

                            FillRect(mem_dc, &card_rc, if is_selected { card_bg_sel } else { card_bg_norm });
                            let pen = if is_selected {
                                border_pen_sel
                            } else if item.content_type == ContentType::Credential {
                                border_pen_cred
                            } else {
                                border_pen_norm
                            };
                            let old_pen = SelectObject(mem_dc, HGDIOBJ(pen.0));
                            let _ = Rectangle(mem_dc, card_rc.left, card_rc.top, card_rc.right, card_rc.bottom);
                            let _ = SelectObject(mem_dc, old_pen);

                            // Header Title (Zero heap allocation: reads pre-cached UTF-16 slice)
                            let _ = SelectObject(mem_dc, HGDIOBJ(state.font_title.0));
                            SetTextColor(
                                mem_dc,
                                COLORREF(if item.content_type == ContentType::Credential {
                                    0x007557FF
                                } else if item.custom_title.is_some() {
                                    0x00FFAA44
                                } else {
                                    0x00BBBBBB
                                }),
                            );
                            let mut header_rc = RECT {
                                left: card_rc.left + 10,
                                top: card_rc.top + 7,
                                right: card_rc.right - 10,
                                bottom: card_rc.top + 25,
                            };
                            let mut hdr_buf = [0u16; 32];
                            let hlen = item.cached_header_utf16.len().min(32);
                            hdr_buf[..hlen].copy_from_slice(&item.cached_header_utf16[..hlen]);
                            DrawTextW(mem_dc, &mut hdr_buf[..hlen], &mut header_rc, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS);

                            // Body Text (Zero heap allocation: stack buffer copy of cached UTF-16 preview)
                            let _ = SelectObject(mem_dc, HGDIOBJ(state.font_body.0));
                            SetTextColor(mem_dc, COLORREF(0x00F0F0F0));
                            let mut body_rc = RECT {
                                left: card_rc.left + 10,
                                top: card_rc.top + 30,
                                right: card_rc.right - 10,
                                bottom: card_rc.bottom - 10,
                            };
                            let mut body_buf = [0u16; 180];
                            let blen = item.cached_preview_utf16.len().min(180);
                            body_buf[..blen].copy_from_slice(&item.cached_preview_utf16[..blen]);
                            DrawTextW(mem_dc, &mut body_buf[..blen], &mut body_rc, DT_LEFT | DT_WORDBREAK | DT_END_ELLIPSIS);

                            x_offset += card_width + spacing;
                        }

                        let _ = SelectObject(mem_dc, old_brush);
                        let _ = SelectObject(mem_dc, old_font);
                        let _ = DeleteObject(HGDIOBJ(card_bg_sel.0));
                        let _ = DeleteObject(HGDIOBJ(card_bg_norm.0));
                        let _ = DeleteObject(HGDIOBJ(border_pen_sel.0));
                        let _ = DeleteObject(HGDIOBJ(border_pen_cred.0));
                        let _ = DeleteObject(HGDIOBJ(border_pen_norm.0));
                    }

                    let _ = BitBlt(hdc, 0, 0, rc.right - rc.left, rc.bottom - rc.top, mem_dc, 0, 0, SRCCOPY);
                    let _ = SelectObject(mem_dc, old_bmp);
                    let _ = DeleteObject(HGDIOBJ(mem_bmp.0));
                    let _ = DeleteDC(mem_dc);
                    let _ = EndPaint(hwnd, &ps);
                }
                LRESULT(0)
            }
            WM_DESTROY => {
                let mut nid = NOTIFYICONDATAW::default();
                nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
                nid.hWnd = hwnd;
                nid.uID = 1;
                let _ = Shell_NotifyIconW(NIM_DELETE, &nid);

                let _ = RemoveClipboardFormatListener(hwnd);
                let _ = unregister(hwnd, 1);
                PostQuitMessage(0);
                LRESULT(0)
            }
            _ => DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }

    pub fn set_clipboard_text_with_tag(hwnd: HWND, text: &str, concealed: bool) {
        unsafe {
            if OpenClipboard(hwnd).is_ok() {
                let _ = EmptyClipboard();

                let tag_id = get_auto_generated_format_id();
                let _ = SetClipboardData(tag_id, HANDLE(1 as *mut _));

                if concealed {
                    let ignore_name: Vec<u16> = "ExcludeClipboardContentFromMonitorProcessing\0"
                        .encode_utf16()
                        .collect();
                    let fmt_ignore = RegisterClipboardFormatW(PCWSTR(ignore_name.as_ptr()));
                    if fmt_ignore != 0 {
                        let _ = SetClipboardData(fmt_ignore, HANDLE(1 as *mut _));
                    }
                }

                let wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
                let bytes = wide.len() * 2;
                if let Ok(hglobal) = GlobalAlloc(GLOBAL_ALLOC_FLAGS(0x0002), bytes) {
                    let ptr = GlobalLock(hglobal);
                    if !ptr.is_null() {
                        std::ptr::copy_nonoverlapping(wide.as_ptr() as *const u8, ptr as *mut u8, bytes);
                        let _ = GlobalUnlock(hglobal);
                        let _ = SetClipboardData(CF_UNICODETEXT, HANDLE(hglobal.0));
                    }
                }

                let _ = CloseClipboard();
            }
        }
    }

    pub fn run_app() -> windows::core::Result<()> {
        unsafe {
            let instance = GetModuleHandleW(None)?;
            let class_name: Vec<u16> = "PATEHUDClass\0".encode_utf16().collect();
            let dlg_class_name: Vec<u16> = "PATECredDlg\0".encode_utf16().collect();

            let wc = WNDCLASSW {
                style: CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS,
                lpfnWndProc: Some(window_proc),
                hInstance: instance.into(),
                lpszClassName: PCWSTR(class_name.as_ptr()),
                hbrBackground: HBRUSH(GetStockObject(BLACK_BRUSH).0),
                hCursor: LoadCursorW(None, IDC_ARROW)?,
                ..Default::default()
            };
            RegisterClassW(&wc);

            let dlg_wc = WNDCLASSW {
                style: CS_HREDRAW | CS_VREDRAW,
                lpfnWndProc: Some(cred_dlg_proc),
                hInstance: instance.into(),
                lpszClassName: PCWSTR(dlg_class_name.as_ptr()),
                hbrBackground: HBRUSH((COLOR_BTNFACE.0 + 1) as *mut _),
                hCursor: LoadCursorW(None, IDC_ARROW)?,
                ..Default::default()
            };
            RegisterClassW(&dlg_wc);

            let mut work_area = RECT::default();
            SystemParametersInfoW(
                SPI_GETWORKAREA,
                0,
                Some(&mut work_area as *mut _ as *mut _),
                SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
            )?;

            let width = (work_area.right - work_area.left) - 48;
            let height = 212;
            let x = work_area.left + 24;
            let y = work_area.bottom - height - 12;

            let hwnd = CreateWindowExW(
                WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                PCWSTR(class_name.as_ptr()),
                PCWSTR("PATE\0".encode_utf16().collect::<Vec<u16>>().as_ptr()),
                WS_POPUP,
                x,
                y,
                width,
                height,
                None,
                None,
                instance,
                None,
            )?;

            let backdrop = DWMSBT_TRANSIENTWINDOW;
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWINDOWATTRIBUTE(DWMWA_SYSTEMBACKDROP_TYPE as i32),
                &backdrop as *const _ as *const _,
                std::mem::size_of::<u32>() as u32,
            );
            let corner = DWMWCP_ROUND;
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWINDOWATTRIBUTE(DWMWA_WINDOW_CORNER_PREFERENCE as i32),
                &corner as *const _ as *const _,
                std::mem::size_of::<u32>() as u32,
            );

            // Cache ClearType Segoe UI fonts once at startup
            let face: Vec<u16> = "Segoe UI\0".encode_utf16().collect();
            let mut lf = LOGFONTW::default();
            for (i, &c) in face.iter().enumerate().take(lf.lfFaceName.len() - 1) {
                lf.lfFaceName[i] = c;
            }
            lf.lfQuality = CLEARTYPE_QUALITY;
            lf.lfHeight = -13;
            lf.lfWeight = 700;
            let font_title = CreateFontIndirectW(&lf);
            lf.lfHeight = -12;
            lf.lfWeight = 400;
            let font_body = CreateFontIndirectW(&lf);

            let hicon = LoadIconW(instance, PCWSTR(1 as *const u16))
                .unwrap_or_else(|_| LoadIconW(None, IDI_APPLICATION).unwrap_or_default());
            let mut nid = NOTIFYICONDATAW::default();
            nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
            nid.hWnd = hwnd;
            nid.uID = 1;
            nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
            nid.uCallbackMessage = WM_TRAYICON;
            nid.hIcon = hicon;

            let tip = "PATE v1.2.0 - Clipboard & Account Vault\0"
                .encode_utf16()
                .collect::<Vec<u16>>();
            for (i, &c) in tip.iter().enumerate().take(nid.szTip.len() - 1) {
                nid.szTip[i] = c;
            }
            let _ = Shell_NotifyIconW(NIM_ADD, &nid);

            let app_data = std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
            let storage_path = std::path::PathBuf::from(&app_data).join("PATE");
            let legacy_path = std::path::PathBuf::from(&app_data).join("PasteFlow");
            if !storage_path.exists() && legacy_path.exists() {
                let _ = std::fs::create_dir_all(&storage_path);
                if let Ok(entries) = std::fs::read_dir(&legacy_path) {
                    for entry in entries.flatten() {
                        let _ = std::fs::copy(entry.path(), storage_path.join(entry.file_name()));
                    }
                }
            }
            let store = HistoryStore::new(storage_path);

            let hotkey_str = store.config.hotkey.clone();
            if let Ok(parsed) = parse_hotkey(&hotkey_str) {
                let _ = register(hwnd, 1, &parsed);
            }

            let _ = AddClipboardFormatListener(hwnd);

            GLOBAL_STATE = Some(Arc::new(Mutex::new(WindowState {
                store,
                is_visible: false,
                vault_only_tab: false,
                selected_index: 0,
                target_hwnd: None,
                quicklook_active: false,
                font_title,
                font_body,
                cred_dialog_hwnd: None,
            })));

            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                let dlg_opt = (*std::ptr::addr_of!(GLOBAL_STATE))
                    .as_ref()
                    .and_then(|s| s.lock().cred_dialog_hwnd);
                if let Some(dlg) = dlg_opt {
                    if IsWindow(dlg).as_bool() && IsDialogMessageW(dlg, &msg).as_bool() {
                        continue;
                    }
                }
                let _ = TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }

            Ok(())
        }
    }
}
