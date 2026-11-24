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

    pub struct WindowState {
        pub store: HistoryStore,
        pub is_visible: bool,
        pub selected_index: usize,
        pub target_hwnd: Option<HWND>,
        pub quicklook_active: bool,
    }

    pub static mut GLOBAL_STATE: Option<Arc<Mutex<WindowState>>> = None;

    pub unsafe extern "system" fn window_proc(
        hwnd: HWND,
        msg: u32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        match msg {
            WM_CLIPBOARDUPDATE => {
                if let Some(ref state_arc) = GLOBAL_STATE {
                    if !is_self_paste(hwnd) {
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
                }
                LRESULT(0)
            }
            WM_HOTKEY => {
                if let Some(ref state_arc) = GLOBAL_STATE {
                    let mut state = state_arc.lock();
                    state.is_visible = !state.is_visible;
                    if state.is_visible {
                        let fg = GetForegroundWindow();
                        state.target_hwnd = if fg.0 != hwnd.0 { Some(fg) } else { None };
                        state.selected_index = 0;
                        state.quicklook_active = false;
                        let _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE);
                        let _ = InvalidateRect(hwnd, None, true);
                    } else {
                        let _ = ShowWindow(hwnd, SW_HIDE);
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
                        0x20 => { // VK_SPACE
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
                        let card_gap = 12;

                        for (idx, item) in state.store.items.iter().take(12).enumerate() {
                            let card_x = start_x + (idx as i32) * (card_width + card_gap);
                            let card_y = 20;
                            let card_rc = RECT {
                                left: card_x,
                                top: card_y,
                                right: card_x + card_width,
                                bottom: card_y + card_height,
                            };

                            let is_selected = idx == state.selected_index;
                            let card_color = if is_selected {
                                COLORREF(0x003A3A3A) // Highlight
                            } else {
                                COLORREF(0x002A2A2A) // Card
                            };
                            let card_brush = CreateSolidBrush(card_color);
                            FillRect(mem_dc, &card_rc, card_brush);
                            let _ = DeleteObject(HGDIOBJ(card_brush.0));

                            // Number badge (1..9)
                            if idx < 9 {
                                SetTextColor(mem_dc, COLORREF(0x00888888));
                                SetBkMode(mem_dc, TRANSPARENT);
                                let badge = format!("{}", idx + 1);
                                let wide_badge: Vec<u16> = badge.encode_utf16().collect();
                                let _ = TextOutW(mem_dc, card_x + 8, card_y + 8, &wide_badge);
                            }

                            // App name
                            if let Some(ref app) = item.app_name {
                                SetTextColor(mem_dc, COLORREF(0x000A84FF));
                                SetBkMode(mem_dc, TRANSPARENT);
                                let wide_app: Vec<u16> = app.encode_utf16().collect();
                                let _ = TextOutW(mem_dc, card_x + 30, card_y + 8, &wide_app);
                            }

                            // Text snippet preview
                            if let Some(ref text) = item.text_value {
                                SetTextColor(mem_dc, COLORREF(0x00E0E0E0));
                                SetBkMode(mem_dc, TRANSPARENT);
                                let clean_text: String = text.chars().take(80).collect();
                                let mut text_rc = RECT {
                                    left: card_x + 10,
                                    top: card_y + 36,
                                    right: card_x + card_width - 10,
                                    bottom: card_y + card_height - 10,
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
                style: CS_HREDRAW | CS_VREDRAW,
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
