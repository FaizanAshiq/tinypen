//! The icon by the clock and its menu.

use windows::core::{HSTRING, Result};
use windows::Win32::Foundation::{HWND, LPARAM, POINT, WPARAM};
use windows::Win32::UI::Shell::*;
use windows::Win32::UI::WindowsAndMessaging::*;

/// What the icon sends the app's window when it is clicked.
pub const TRAY_MESSAGE: u32 = WM_APP + 1;

/// The menu's commands.
pub const DRAW: u32 = 1;
pub const LASER: u32 = 2;
pub const SPOTLIGHT: u32 = 3;
pub const ZOOM: u32 = 4;
pub const CLEAR: u32 = 10;
pub const OPEN_AT_LOGIN: u32 = 11;
pub const SETTINGS: u32 = 12;
pub const QUIT: u32 = 13;
pub const DOWNLOAD: u32 = 14;

/// One line of the menu: its command, its title, ticked, and available.
pub struct Entry {
    pub command: u32,
    pub title: String,
    pub checked: bool,
    pub enabled: bool,
}

pub struct Tray {
    window: HWND,
    icon: HICON,
    shown: bool,
}

impl Tray {
    pub fn new(window: HWND) -> Tray {
        // Windows reads a PNG as an icon resource as it is.
        let png = include_bytes!("../assets/tinypen-32.png");
        let icon = unsafe { CreateIconFromResourceEx(png, true, 0x0003_0000, 32, 32, LR_DEFAULTCOLOR) }.unwrap_or_default();
        Tray { window, icon, shown: false }
    }

    fn data(&self) -> NOTIFYICONDATAW {
        let mut data = NOTIFYICONDATAW {
            cbSize: size_of::<NOTIFYICONDATAW>() as u32,
            hWnd: self.window,
            uID: 1,
            uFlags: NIF_ICON | NIF_MESSAGE | NIF_TIP,
            uCallbackMessage: TRAY_MESSAGE,
            hIcon: self.icon,
            ..Default::default()
        };
        for (slot, unit) in data.szTip.iter_mut().zip("Tinypen".encode_utf16()) {
            *slot = unit;
        }
        data
    }

    /// Explorer restarted and forgot every icon by the clock: added again if it showed. Found reading:
    /// without this the icon was gone for good after Explorer restarted.
    pub fn explorer_restarted(&mut self, shown: bool) {
        self.shown = false;
        self.set_shown(shown);
    }

    pub fn set_shown(&mut self, shown: bool) {
        if shown == self.shown {
            return;
        }
        unsafe {
            let _ = Shell_NotifyIconW(if shown { NIM_ADD } else { NIM_DELETE }, &self.data());
        }
        self.shown = shown;
    }

    /// Shows the menu at the pointer and returns the command picked, if any.
    pub fn menu(&self, entries: &[Option<Entry>]) -> Result<Option<u32>> {
        unsafe {
            let menu = CreatePopupMenu()?;
            for entry in entries {
                match entry {
                    None => AppendMenuW(menu, MF_SEPARATOR, 0, None)?,
                    Some(entry) => {
                        let mut flags = MF_STRING;
                        if entry.checked {
                            flags |= MF_CHECKED;
                        }
                        if !entry.enabled {
                            flags |= MF_GRAYED;
                        }
                        AppendMenuW(menu, flags, entry.command as usize, &HSTRING::from(entry.title.as_str()))?;
                    }
                }
            }
            let mut at = POINT::default();
            GetCursorPos(&mut at)?;
            // Needed, or the menu stays open when the person clicks elsewhere.
            let _ = SetForegroundWindow(self.window);
            let picked = TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY, at.x, at.y, None, self.window, None);
            let _ = PostMessageW(Some(self.window), WM_NULL, WPARAM(0), LPARAM(0));
            let _ = DestroyMenu(menu);
            Ok((picked.0 != 0).then_some(picked.0 as u32))
        }
    }
}

impl Drop for Tray {
    fn drop(&mut self) {
        self.set_shown(false);
    }
}

