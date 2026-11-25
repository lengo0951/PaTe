#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

#[cfg(windows)]
fn main() -> Result<(), windows::core::Error> {
    pate_windows::ui::window::win32::run_app()
}

#[cfg(not(windows))]
fn main() {
    println!("PATE Windows Edition (Rust 2024)");
    println!("This binary is designed for Windows 10/11 using Win32 API.");
    println!("Run tests on macOS with: cargo test");
    println!("Cross-check for Windows with: cargo check --target x86_64-pc-windows-gnu");
}
