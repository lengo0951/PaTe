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
    use windows::Win32::System::Threading::*;
    use windows::Win32::UI::Shell::*;
    use windows::Win32::UI::WindowsAndMessaging::*;

    use crate::core::clipboard::win32::*;
    use crate::core::clipboard::CF_UNICODETEXT;
    use crate::core::hotkey::win32::*;
    use crate::core::hotkey::parse_hotkey;
    use crate::core::simulator::win32::*;
    use crate::core::storage::HistoryStore;
    use crate::core::types::ClipboardItem;

    pub const DWMWA_SYSTEMBACKDROP_TYPE: u32 = 38;
    pub const DWMWA_WINDOW_CORNER_PREFERENCE: u32 = 33;
    pub const DWMSBT_TRANSIENTWINDOW: u32 = 3; // Acrylic blur
    pub const DWMWCP_ROUND: u32 = 2; // Rounded corners

    pub const WM_TRAYICON: u32 = WM_USER + 101;
    pub const IDM_TOGGLE: usize = 1001;
    pub const IDM_CLEAR: usize = 1002;
    pub const IDM_ABOUT: usize = 1003;
    pub const IDM_EXIT: usize = 1004;

    pub struct WindowState {
        pub store: HistoryStore,
        pub is_visible: bool,
        pub selected_index: usize,
        pub target_hwnd: Option<HWND>,
        pub quicklook_active: bool,
    }

    pub static mut GLOBAL_STATE: Option<Arc<Mutex<WindowState>>> = None;

    pub unsafe fn toggle_hud(hwnd: HWND) {
        if let Some(ref state_arc) = GLOBAL_STATE {
            let mut state = state_arc.lock();
            state.is_visible = !state.is_visible;
            if state.is_visible {
                let fg = GetForegroundWindow();
                state.target_hwnd = if fg.0 != hwnd.0 { Some(fg) } else { None };
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

    pub unsafe extern "system" fn window_proc(
        hwnd: HWND,
        msg: u32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        match msg {
            WM_CLIPBOARDUPDATE => {
                if let Some(ref state_arc) = GLOBAL_STATE {
                    if let Some(text) = read_clipboard_text(hwnd) {
                            let mut app_name = None;
                            let fg_hwnd = GetForegroundWindow();
                            if fg_hwnd.0 != std::ptr::null_mut() {
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
                                let _ = InvalidateRect(hwnd, None, true);
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
                    IDM_TOGGLE => {
                        toggle_hud(hwnd);
                    }
                    IDM_CLEAR => {
                        if let Some(ref state_arc) = GLOBAL_STATE {
                            let mut state = state_arc.lock();
                            state.store.items.retain(|i| !i.pinboard_ids.is_empty());
                            let _ = state.store.save();
                            let _ = InvalidateRect(hwnd, None, true);
                        }
                    }
                    IDM_ABOUT => {
                        toggle_hud(hwnd);
                    }
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
                        // Left-click on toolbar/system tray icon toggles PasteFlow HUD
                        toggle_hud(hwnd);
                    }
                    WM_RBUTTONUP => {
                        // Right-click shows context popup menu
                        if let Ok(hmenu) = CreatePopupMenu() {
                            let m_toggle: Vec<u16> = "Toggle PasteFlow (Ctrl+Shift+V)\0".encode_utf16().collect();
                            let m_clear: Vec<u16> = "Clear History (Keep Pinned)\0".encode_utf16().collect();
                            let m_about: Vec<u16> = "About PasteFlow (by Quốc Ngô)\0".encode_utf16().collect();
                            let m_exit: Vec<u16> = "Exit PasteFlow\0".encode_utf16().collect();

                            let _ = AppendMenuW(hmenu, MF_STRING, IDM_TOGGLE, PCWSTR(m_toggle.as_ptr()));
                            let _ = AppendMenuW(hmenu, MF_SEPARATOR, 0, PCWSTR(std::ptr::null()));
                            let _ = AppendMenuW(hmenu, MF_STRING, IDM_CLEAR, PCWSTR(m_clear.as_ptr()));
                            let _ = AppendMenuW(hmenu, MF_STRING, IDM_ABOUT, PCWSTR(m_about.as_ptr()));
                            let _ = AppendMenuW(hmenu, MF_SEPARATOR, 0, PCWSTR(std::ptr::null()));
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
                    let start_x = 20;
                    let card_width = 180;
                    let card_height = 160;
                    let card_y = 25;
                    let spacing = 14;

                    if mouse_y >= card_y && mouse_y <= card_y + card_height && mouse_x >= start_x {
                        let card_idx = ((mouse_x - start_x) / (card_width + spacing)) as usize;
                        let offset_in_card = (mouse_x - start_x) % (card_width + spacing);
                        if offset_in_card <= card_width && card_idx < state.store.items.len() {
                            if state.selected_index != card_idx {
                                state.selected_index = card_idx;
                                let _ = InvalidateRect(hwnd, None, true);
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
                    let card_width = 180;
                    let card_height = 160;
                    let card_y = 25;
                    let spacing = 14;

                    if mouse_y >= card_y && mouse_y <= card_y + card_height && mouse_x >= start_x {
                        let card_idx = ((mouse_x - start_x) / (card_width + spacing)) as usize;
                        let offset_in_card = (mouse_x - start_x) % (card_width + spacing);
                        if offset_in_card <= card_width && card_idx < state.store.items.len() {
                            state.selected_index = card_idx;
                            let target = state.target_hwnd;
                            let item_opt = state.store.items.get(card_idx).cloned();
                            state.is_visible = false;
                            state.quicklook_active = false;
                            let _ = ShowWindow(hwnd, SW_HIDE);
                            drop(state);

                            if let Some(item) = item_opt {
                                if let Some(ref text) = item.text_value {
                                    set_clipboard_text_with_tag(hwnd, text);
                                    simulate_paste(target);
                                }
                            }
                        }
                    }
                }
                LRESULT(0)
            }
            WM_KEYDOWN => {
                let vk = wparam.0 as i32;
                if let Some(ref state_arc) = GLOBAL_STATE {
                    let mut state = state_arc.lock();
                    match vk {
                        0x1B => { // VK_ESCAPE
                            state.is_visible = false;
                            state.quicklook_active = false;
                            let _ = ShowWindow(hwnd, SW_HIDE);
                        }
                        0x20 => { // VK_SPACE (Toggle preview)
                            state.quicklook_active = !state.quicklook_active;
                            let _ = InvalidateRect(hwnd, None, true);
                        }
                        0x0D => { // VK_RETURN
                            let target = state.target_hwnd;
                            let item_opt = state.store.items.get(state.selected_index).cloned();
                            state.is_visible = false;
                            state.quicklook_active = false;
                            let _ = ShowWindow(hwnd, SW_HIDE);
                            drop(state);

                            if let Some(item) = item_opt {
                                if let Some(ref text) = item.text_value {
                                    // Copy to clipboard with self-paste tag
                                    set_clipboard_text_with_tag(hwnd, text);
                                    simulate_paste(target);
                                }
                            }
                        }
                        0x31..=0x39 => { // VK_1 through VK_9
                            let index = (vk - 0x31) as usize;
                            if let Some(item) = state.store.items.get(index).cloned() {
                                let target = state.target_hwnd;
                                state.is_visible = false;
                                let _ = ShowWindow(hwnd, SW_HIDE);
                                drop(state);

                                if let Some(ref text) = item.text_value {
                                    set_clipboard_text_with_tag(hwnd, text);
                                    simulate_paste(target);
                                }
                            }
                        }
                        0x25 => { // VK_LEFT
                            if state.selected_index > 0 {
                                state.selected_index -= 1;
                                let _ = InvalidateRect(hwnd, None, true);
                            }
                        }
                        0x27 => { // VK_RIGHT
                            if state.selected_index + 1 < state.store.items.len() {
                                state.selected_index += 1;
                                let _ = InvalidateRect(hwnd, None, true);
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

                    // Create double buffer DC
                    let mem_dc = CreateCompatibleDC(hdc);
                    let mem_bmp = CreateCompatibleBitmap(hdc, rc.right - rc.left, rc.bottom - rc.top);
                    let old_bmp = SelectObject(mem_dc, HGDIOBJ(mem_bmp.0));

                    // Background brush
                    let bg_brush = CreateSolidBrush(COLORREF(0x001E1E1E));
                    FillRect(mem_dc, &rc, bg_brush);
                    let _ = DeleteObject(HGDIOBJ(bg_brush.0));

                    // Draw items
                    if let Some(ref state_arc) = GLOBAL_STATE {
                        let state = state_arc.lock();
                        let start_x = 20;
                        let card_width = 180;
                        let card_height = 160;
                        let card_y = 25;
                        let spacing = 14;

                        // Pre-allocate GDI brushes & pens once outside loop (Zero allocation churn per frame!)
                        let card_bg_sel = CreateSolidBrush(COLORREF(0x002D2D2D));
                        let card_bg_norm = CreateSolidBrush(COLORREF(0x00242424));
                        let border_pen_sel = CreatePen(PS_SOLID, 2, COLORREF(0x00FF840A)); // RGB(10, 132, 255)
                        let border_pen_norm = CreatePen(PS_SOLID, 1, COLORREF(0x003A3A3A));
                        let null_brush = GetStockObject(NULL_BRUSH);
                        let old_brush = SelectObject(mem_dc, null_brush);

                        for (idx, item) in state.store.items.iter().enumerate() {
                            let card_x = start_x + (idx as i32) * (card_width + spacing);
                            if card_x > rc.right {
                                break;
                            }

                            let card_rc = RECT {
                                left: card_x,
                                top: card_y,
                                right: card_x + card_width,
                                bottom: card_y + card_height,
                            };

                            let is_selected = idx == state.selected_index;

                            // Card background
                            FillRect(mem_dc, &card_rc, if is_selected { card_bg_sel } else { card_bg_norm });

                            // Card border (Electric Blue if selected)
                            let cur_pen = if is_selected { border_pen_sel } else { border_pen_norm };
                            let old_pen = SelectObject(mem_dc, HGDIOBJ(cur_pen.0));
                            let _ = Rectangle(mem_dc, card_rc.left, card_rc.top, card_rc.right, card_rc.bottom);
                            let _ = SelectObject(mem_dc, old_pen);

                            // Header Text (App Name or Custom Title)
                            SetTextColor(mem_dc, if item.custom_title.is_some() { COLORREF(0x00FF840A) } else { COLORREF(0x00AAAAAA) });
                            SetBkMode(mem_dc, TRANSPARENT);
                            let header_title = item.custom_title.as_deref().unwrap_or(item.app_name.as_deref().unwrap_or("Text"));
                            let wide_app: Vec<u16> = header_title.encode_utf16().collect();
                            let mut header_rc = RECT {
                                left: card_rc.left + 10,
                                top: card_rc.top + 8,
                                right: card_rc.right - 10,
                                bottom: card_rc.top + 26,
                            };
                            DrawTextW(
                                mem_dc,
                                &mut wide_app.clone(),
                                &mut header_rc,
                                DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS,
                            );

                            // Content Preview Text
                            if let Some(ref text) = item.text_value {
                                SetTextColor(mem_dc, COLORREF(0x00EEEEEE));
                                let mut text_rc = RECT {
                                    left: card_rc.left + 10,
                                    top: card_rc.top + 32,
                                    right: card_rc.right - 10,
                                    bottom: card_rc.bottom - 10,
                                };
                                let clean_text = if text.len() > 120 {
                                    format!("{}...", &text[..120])
                                } else {
                                    text.clone()
                                };
                                let wide_text: Vec<u16> = clean_text.encode_utf16().collect();
                                DrawTextW(
                                    mem_dc,
                                    &mut wide_text.clone(),
                                    &mut text_rc,
                                    DT_LEFT | DT_WORDBREAK | DT_END_ELLIPSIS,
                                );
                            }
                        }

                        // Cleanup reusable GDI objects
                        let _ = SelectObject(mem_dc, old_brush);
                        let _ = DeleteObject(HGDIOBJ(card_bg_sel.0));
                        let _ = DeleteObject(HGDIOBJ(card_bg_norm.0));
                        let _ = DeleteObject(HGDIOBJ(border_pen_sel.0));
                        let _ = DeleteObject(HGDIOBJ(border_pen_norm.0));

                        // Quick Look overlay if active
                        if state.quicklook_active {
                            if let Some(item) = state.store.items.get(state.selected_index) {
                                let ql_rc = RECT {
                                    left: rc.left + 50,
                                    top: rc.top + 10,
                                    right: rc.right - 50,
                                    bottom: rc.bottom - 10,
                                };
                                let ql_brush = CreateSolidBrush(COLORREF(0x00151515));
                                FillRect(mem_dc, &ql_rc, ql_brush);
                                let _ = DeleteObject(HGDIOBJ(ql_brush.0));

                                SetTextColor(mem_dc, COLORREF(0x00FFFFFF));
                                SetBkMode(mem_dc, TRANSPARENT);
                                if let Some(ref text) = item.text_value {
                                    let mut ql_text_rc = RECT {
                                        left: ql_rc.left + 20,
                                        top: ql_rc.top + 20,
                                        right: ql_rc.right - 20,
                                        bottom: ql_rc.bottom - 20,
                                    };
                                    let wide: Vec<u16> = text.encode_utf16().collect();
                                    DrawTextW(mem_dc, &mut wide.clone(), &mut ql_text_rc, DT_LEFT | DT_WORDBREAK);
                                }
                            }
                        }
                    }

                    // Copy to front buffer
                    let _ = BitBlt(hdc, 0, 0, rc.right - rc.left, rc.bottom - rc.top, mem_dc, 0, 0, SRCCOPY);
                    let _ = SelectObject(mem_dc, old_bmp);
                    let _ = DeleteObject(HGDIOBJ(mem_bmp.0));
                    let _ = DeleteDC(mem_dc);
                    let _ = EndPaint(hwnd, &ps);
                }
                LRESULT(0)
            }
            WM_DESTROY => {
                // Remove notification toolbar / tray icon
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

    pub fn set_clipboard_text_with_tag(hwnd: HWND, text: &str) {
        unsafe {
            if OpenClipboard(hwnd).is_ok() {
                let _ = EmptyClipboard();

                // 1. Tag format
                let tag_id = get_auto_generated_format_id();
                let _ = SetClipboardData(tag_id, HANDLE(1 as *mut _));

                // 2. Unicode text
                let wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
                let bytes = wide.len() * 2;
                if let Ok(hglobal) = GlobalAlloc(GLOBAL_ALLOC_FLAGS(0x0002), bytes) { // GMEM_MOVEABLE
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
            let class_name: Vec<u16> = "PasteFlowHUDClass\0".encode_utf16().collect();

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

            // Screen work area
            let mut work_area = RECT::default();
            SystemParametersInfoW(SPI_GETWORKAREA, 0, Some(&mut work_area as *mut _ as *mut _), SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0))?;

            let width = (work_area.right - work_area.left) - 48;
            let height = 210;
            let x = work_area.left + 24;
            let y = work_area.bottom - height - 12;

            // WS_EX_TOOLWINDOW: Guarantees the window does NOT show an icon/button on the Taskbar!
            // WS_POPUP: Borderless floating bar.
            let hwnd = CreateWindowExW(
                WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                PCWSTR(class_name.as_ptr()),
                PCWSTR("PasteFlow\0".encode_utf16().collect::<Vec<u16>>().as_ptr()),
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

            // Apply DWM Backdrop / Mica / Acrylic
            let backdrop = DWMSBT_TRANSIENTWINDOW;
            let _ = DwmSetWindowAttribute(hwnd, DWMWINDOWATTRIBUTE(DWMWA_SYSTEMBACKDROP_TYPE as i32), &backdrop as *const _ as *const _, std::mem::size_of::<u32>() as u32);
            let corner = DWMWCP_ROUND;
            let _ = DwmSetWindowAttribute(hwnd, DWMWINDOWATTRIBUTE(DWMWA_WINDOW_CORNER_PREFERENCE as i32), &corner as *const _ as *const _, std::mem::size_of::<u32>() as u32);

            // Register Notification Area / System Tray (Toolbar) Icon
            let hicon = LoadIconW(None, IDI_APPLICATION).unwrap_or_default();
            let mut nid = NOTIFYICONDATAW::default();
            nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
            nid.hWnd = hwnd;
            nid.uID = 1;
            nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
            nid.uCallbackMessage = WM_TRAYICON;
            nid.hIcon = hicon;

            let tip = "PasteFlow - Clipboard Manager\0".encode_utf16().collect::<Vec<u16>>();
            for (i, &c) in tip.iter().enumerate().take(nid.szTip.len() - 1) {
                nid.szTip[i] = c;
            }

            let _ = Shell_NotifyIconW(NIM_ADD, &nid);

            // Load storage
            let app_data = std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
            let storage_path = std::path::PathBuf::from(app_data).join("PasteFlow");
            let store = HistoryStore::new(storage_path);

            // Register HotKey
            let hotkey_str = store.config.hotkey.clone();
            if let Ok(parsed) = parse_hotkey(&hotkey_str) {
                let _ = register(hwnd, 1, &parsed);
            }

            // Register Clipboard Listener
            let _ = AddClipboardFormatListener(hwnd);

            GLOBAL_STATE = Some(Arc::new(Mutex::new(WindowState {
                store,
                is_visible: false,
                selected_index: 0,
                target_hwnd: None,
                quicklook_active: false,
            })));

            // Message Loop
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                let _ = TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }

            Ok(())
        }
    }
}
