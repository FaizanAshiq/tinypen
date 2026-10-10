//! The name and key shown as the pointer rests on a button of the toolbar or the colour picker.

use windows::core::{Result, PWSTR};
use windows::Win32::Foundation::{HINSTANCE, HWND, LPARAM, RECT};
use windows::Win32::Graphics::Direct2D::Common::D2D_RECT_F;
use windows::Win32::UI::Controls::*;
use windows::Win32::UI::WindowsAndMessaging::*;

pub struct Tips {
    hwnd: HWND,
    owner: HWND,
    /// Kept while the tips show, as the control reads them from here.
    texts: Vec<Vec<u16>>,
}

impl Tips {
    pub fn new(owner: HWND, instance: HINSTANCE) -> Result<Tips> {
        unsafe {
            let _ = InitCommonControlsEx(&INITCOMMONCONTROLSEX {
                dwSize: size_of::<INITCOMMONCONTROLSEX>() as u32,
                dwICC: ICC_WIN95_CLASSES,
            });
            let hwnd = CreateWindowExW(
                WS_EX_TOPMOST,
                TOOLTIPS_CLASSW,
                None,
                WS_POPUP | WINDOW_STYLE(TTS_ALWAYSTIP | TTS_NOPREFIX),
                0,
                0,
                0,
                0,
                Some(owner),
                None,
                Some(instance),
                None,
            )?;
            Ok(Tips { hwnd, owner, texts: Vec::new() })
        }
    }

    /// One tip per button, over its device-independent rect at `scale`, replacing the last set.
    pub fn place(&mut self, buttons: &[(String, D2D_RECT_F)], scale: f32) {
        for index in 0..self.texts.len() {
            let mut info = TTTOOLINFOW { cbSize: size_of::<TTTOOLINFOW>() as u32, hwnd: self.owner, uId: index, ..Default::default() };
            unsafe {
                SendMessageW(self.hwnd, TTM_DELTOOLW, None, Some(LPARAM(&mut info as *mut TTTOOLINFOW as isize)));
            }
        }
        self.texts = buttons.iter().map(|(name, _)| name.encode_utf16().chain([0]).collect()).collect();
        for (index, (_, rect)) in buttons.iter().enumerate() {
            let mut info = TTTOOLINFOW {
                cbSize: size_of::<TTTOOLINFOW>() as u32,
                uFlags: TTF_SUBCLASS,
                hwnd: self.owner,
                uId: index,
                rect: RECT {
                    left: (rect.left * scale) as i32,
                    top: (rect.top * scale) as i32,
                    right: (rect.right * scale) as i32,
                    bottom: (rect.bottom * scale) as i32,
                },
                lpszText: PWSTR(self.texts[index].as_mut_ptr()),
                ..Default::default()
            };
            unsafe {
                SendMessageW(self.hwnd, TTM_ADDTOOLW, None, Some(LPARAM(&mut info as *mut TTTOOLINFOW as isize)));
            }
        }
    }
}
