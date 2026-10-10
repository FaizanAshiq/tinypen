//! Monitors, open at login, the settings file and keeping to one running copy.

use windows::core::{w, HSTRING, PCWSTR};
use windows::Win32::Foundation::{ERROR_ALREADY_EXISTS, GetLastError, LPARAM, RECT};
use windows::Win32::Graphics::Gdi::{EnumDisplayMonitors, GetMonitorInfoW, HDC, HMONITOR, MONITORINFO};
use windows::Win32::System::Registry::*;
use windows::Win32::System::Threading::CreateMutexW;
use windows::Win32::UI::HiDpi::{GetDpiForMonitor, MDT_EFFECTIVE_DPI};
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;

/// A monitor as it is now, in physical pixels on the virtual desktop.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Monitor {
    pub handle: isize,
    pub rect: RECT,
    pub work: RECT,
    /// Physical pixels per device-independent pixel: 1.5 at 150%.
    pub scale: f32,
}

pub fn monitors() -> Vec<Monitor> {
    unsafe extern "system" fn each(monitor: HMONITOR, _: HDC, _: *mut RECT, data: LPARAM) -> windows::core::BOOL {
        let list = unsafe { &mut *(data.0 as *mut Vec<Monitor>) };
        let mut info = MONITORINFO { cbSize: size_of::<MONITORINFO>() as u32, ..Default::default() };
        if unsafe { GetMonitorInfoW(monitor, &mut info) }.as_bool() {
            let (mut x, mut y) = (96, 96);
            let _ = unsafe { GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &mut x, &mut y) };
            list.push(Monitor { handle: monitor.0 as isize, rect: info.rcMonitor, work: info.rcWork, scale: x as f32 / 96.0 });
        }
        true.into()
    }
    let mut list: Vec<Monitor> = Vec::new();
    unsafe {
        let _ = EnumDisplayMonitors(None, None, Some(each), LPARAM(&mut list as *mut Vec<Monitor> as isize));
    }
    list
}

const RUN: PCWSTR = w!("Software\\Microsoft\\Windows\\CurrentVersion\\Run");

/// Asked of Windows each time, so it never disagrees with the Startup apps list.
pub fn opens_at_login() -> bool {
    unsafe { RegGetValueW(HKEY_CURRENT_USER, RUN, w!("Tinypen"), RRF_RT_REG_SZ, None, None, None).is_ok() }
}

/// False when Windows refused the change.
pub fn set_opens_at_login(enabled: bool) -> bool {
    unsafe {
        if !enabled {
            let gone = RegDeleteKeyValueW(HKEY_CURRENT_USER, RUN, w!("Tinypen"));
            return gone.is_ok() || !opens_at_login();
        }
        let Ok(exe) = std::env::current_exe() else { return false };
        let value: Vec<u16> = format!("\"{}\"", exe.display()).encode_utf16().chain([0]).collect();
        let bytes = std::slice::from_raw_parts(value.as_ptr() as *const u8, value.len() * 2);
        RegSetKeyValueW(HKEY_CURRENT_USER, RUN, w!("Tinypen"), REG_SZ.0, Some(bytes.as_ptr() as *const _), bytes.len() as u32).is_ok()
    }
}

/// The settings file in Notepad, where the hotkeys are changed for now.
pub fn open_in_notepad(path: &std::path::Path) {
    let file = HSTRING::from(format!("\"{}\"", path.display()));
    unsafe {
        ShellExecuteW(None, w!("open"), w!("notepad.exe"), &file, None, SW_SHOWNORMAL);
    }
}

/// False when another Tinypen already runs. The handle is left open for the life of the process.
pub fn first_copy() -> bool {
    unsafe {
        let _ = CreateMutexW(None, false, w!("Local\\Tinypen.OneCopy"));
        GetLastError() != ERROR_ALREADY_EXISTS
    }
}
