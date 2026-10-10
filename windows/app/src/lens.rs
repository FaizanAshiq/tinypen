//! The zoom lens: Windows' own magnifier in a round window on the pointer, with Tinypen's windows
//! left out of what it shows.

use tinypen_core::Lens;
use windows::core::{w, Result, PCWSTR};
use windows::Win32::Foundation::{COLORREF, HINSTANCE, HWND, RECT};
use windows::Win32::Graphics::Gdi::{CreateEllipticRgn, InvalidateRect, SetWindowRgn};
use windows::Win32::UI::Magnification::*;
use windows::Win32::UI::WindowsAndMessaging::*;

pub const LENS_CLASS: PCWSTR = w!("TinypenLens");

pub struct LensWindow {
    pub host: HWND,
    view: HWND,
    side: i32,
}

impl LensWindow {
    pub fn new(instance: HINSTANCE) -> Result<LensWindow> {
        unsafe {
            MagInitialize().ok()?;
            let host = CreateWindowExW(
                WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                LENS_CLASS,
                w!("Tinypen zoom"),
                WS_POPUP,
                0,
                0,
                1,
                1,
                None,
                None,
                Some(instance),
                None,
            )?;
            SetLayeredWindowAttributes(host, COLORREF(0), 255, LWA_ALPHA)?;
            let view = CreateWindowExW(
                WINDOW_EX_STYLE(0),
                WC_MAGNIFIER,
                w!("Tinypen zoom view"),
                WS_CHILD | WS_VISIBLE,
                0,
                0,
                1,
                1,
                Some(host),
                None,
                Some(instance),
                None,
            )?;
            Ok(LensWindow { host, view, side: 0 })
        }
    }

    /// Tinypen's own windows, which the lens never shows magnified.
    pub fn exclude(&self, windows: &[HWND]) {
        let mut list = windows.to_vec();
        list.push(self.host);
        unsafe {
            let _ = MagSetWindowFilterList(self.view, MW_FILTERMODE_EXCLUDE, list.len() as i32, list.as_mut_ptr());
        }
    }

    /// Centred on `center`, in physical pixels, on a monitor at `scale`.
    pub fn place(&mut self, center: (i32, i32), scale: f32, magnification: f32) {
        let radius = (Lens::RADIUS * scale).round() as i32;
        let side = radius * 2;
        unsafe {
            if side != self.side {
                let _ = SetWindowPos(self.view, None, 0, 0, side, side, SWP_NOZORDER | SWP_NOACTIVATE);
                let _ = SetWindowRgn(self.host, Some(CreateEllipticRgn(0, 0, side + 1, side + 1)), true);
                self.side = side;
            }
            let _ = SetWindowPos(
                self.host,
                Some(HWND_TOPMOST),
                center.0 - radius,
                center.1 - radius,
                side,
                side,
                SWP_NOACTIVATE | SWP_SHOWWINDOW,
            );
            let mut transform = MAGTRANSFORM { v: [magnification, 0.0, 0.0, 0.0, magnification, 0.0, 0.0, 0.0, 1.0] };
            let _ = MagSetWindowTransform(self.view, &mut transform);
            let half = (radius as f32 / magnification).round() as i32;
            let source = RECT { left: center.0 - half, top: center.1 - half, right: center.0 + half, bottom: center.1 + half };
            let _ = MagSetWindowSource(self.view, source);
            let _ = InvalidateRect(Some(self.view), None, true);
        }
    }

    pub fn hide(&self) {
        unsafe {
            let _ = ShowWindow(self.host, SW_HIDE);
        }
    }
}
