//! Drawing mode's floating toolbar, at the top of the monitor being drawn on. It never takes the
//! keys from the drawing layer, so the tool keys keep working while it shows.

use crate::graphics::{Graphics, Surface};
use crate::icons::{self, Button};
use crate::system::Monitor;
use tinypen_core::{Palette, Tool};
use windows::core::{w, Result, PCWSTR, PWSTR};
use windows::Win32::Foundation::{COLORREF, HINSTANCE, HWND, LPARAM, RECT};
use windows::Win32::UI::Controls::*;
use windows::Win32::Graphics::Direct2D::Common::*;
use windows::Win32::Graphics::Direct2D::*;
use windows::Win32::UI::WindowsAndMessaging::*;

pub const TOOLBAR_CLASS: PCWSTR = w!("TinypenToolbar");

const BUTTON: (f32, f32) = (32.0, 28.0);
const DOT: f32 = 24.0;
const INSIDE: f32 = 2.0;
const BETWEEN: f32 = 14.0;
const PADDING: (f32, f32) = (12.0, 6.0);

/// What the toolbar shows as chosen and available.
pub struct Look {
    pub chosen: Tool,
    pub color: String,
    pub thinner: bool,
    pub thicker: bool,
    pub has_marks: bool,
}

pub struct Toolbar {
    pub hwnd: HWND,
    surface: Option<Surface>,
    scale: f32,
    buttons: Vec<(Button, D2D_RECT_F)>,
    size: (f32, f32),
    hovered: Option<usize>,
    /// Each button's name and key, shown as the pointer rests on it.
    tips: HWND,
    tip_texts: Vec<Vec<u16>>,
}

impl Toolbar {
    pub fn new(instance: HINSTANCE) -> Result<Toolbar> {
        let (buttons, size) = layout();
        unsafe {
            let hwnd = CreateWindowExW(
                WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOREDIRECTIONBITMAP | WS_EX_NOACTIVATE | WS_EX_LAYERED,
                TOOLBAR_CLASS,
                w!("Tinypen toolbar"),
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
            SetLayeredWindowAttributes(hwnd, COLORREF(0), 255, LWA_ALPHA)?;
            let _ = InitCommonControlsEx(&INITCOMMONCONTROLSEX {
                dwSize: size_of::<INITCOMMONCONTROLSEX>() as u32,
                dwICC: ICC_WIN95_CLASSES,
            });
            let tips = CreateWindowExW(
                WS_EX_TOPMOST,
                TOOLTIPS_CLASSW,
                None,
                WS_POPUP | WINDOW_STYLE(TTS_ALWAYSTIP | TTS_NOPREFIX),
                0,
                0,
                0,
                0,
                Some(hwnd),
                None,
                Some(instance),
                None,
            )?;
            let tip_texts = buttons.iter().map(|(button, _)| button.name().encode_utf16().chain([0]).collect()).collect();
            Ok(Toolbar { hwnd, surface: None, scale: 0.0, buttons, size, hovered: None, tips, tip_texts })
        }
    }

    /// Centred at the top of `monitor`'s work area, 12 pixels down.
    pub fn show(&mut self, graphics: &Graphics, monitor: &Monitor) -> Result<()> {
        let scale = monitor.scale;
        let (width, height) = ((self.size.0 * scale).ceil() as i32, (self.size.1 * scale).ceil() as i32);
        let work = monitor.work;
        let x = (work.left + work.right) / 2 - width / 2;
        let y = work.top + (12.0 * scale) as i32;
        unsafe {
            SetWindowPos(self.hwnd, Some(HWND_TOPMOST), x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW)?;
        }
        if self.surface.is_none() || self.scale != scale {
            self.surface = Some(graphics.surface(self.hwnd, width as u32, height as u32)?);
            self.scale = scale;
            self.place_tips();
        }
        Ok(())
    }

    /// One tip per button, over the button's pixels at the current scale.
    fn place_tips(&mut self) {
        for (index, (_, rect)) in self.buttons.iter().enumerate() {
            let mut info = TTTOOLINFOW {
                cbSize: size_of::<TTTOOLINFOW>() as u32,
                uFlags: TTF_SUBCLASS,
                hwnd: self.hwnd,
                uId: index,
                rect: RECT {
                    left: (rect.left * self.scale) as i32,
                    top: (rect.top * self.scale) as i32,
                    right: (rect.right * self.scale) as i32,
                    bottom: (rect.bottom * self.scale) as i32,
                },
                lpszText: PWSTR(self.tip_texts[index].as_mut_ptr()),
                ..Default::default()
            };
            let pointer = Some(LPARAM(&mut info as *mut TTTOOLINFOW as isize));
            unsafe {
                SendMessageW(self.tips, TTM_DELTOOLW, None, pointer);
                SendMessageW(self.tips, TTM_ADDTOOLW, None, pointer);
            }
        }
    }

    /// Back over the drawing layers, which a new layer can cover.
    pub fn raise(&self) {
        unsafe {
            let _ = SetWindowPos(self.hwnd, Some(HWND_TOPMOST), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
    }

    pub fn hide(&mut self) {
        self.hovered = None;
        unsafe {
            let _ = ShowWindow(self.hwnd, SW_HIDE);
        }
    }

    /// The button at a point in the window's client pixels.
    pub fn hit(&self, x: i32, y: i32) -> Option<Button> {
        self.index_at(x, y).map(|index| self.buttons[index].0)
    }

    fn index_at(&self, x: i32, y: i32) -> Option<usize> {
        let (x, y) = (x as f32 / self.scale.max(1.0), y as f32 / self.scale.max(1.0));
        self.buttons.iter().position(|(_, rect)| x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom)
    }

    /// True when the pointer moved onto another button, so the toolbar needs drawing again.
    pub fn hover(&mut self, x: i32, y: i32) -> bool {
        let hovered = self.index_at(x, y);
        let changed = hovered != self.hovered;
        self.hovered = hovered;
        changed
    }

    pub fn render(&self, graphics: &Graphics, look: &Look) -> Result<()> {
        let Some(surface) = &self.surface else { return Ok(()) };
        let whole = D2D_RECT_F { left: 0.5, top: 0.5, right: self.size.0 - 0.5, bottom: self.size.1 - 0.5 };
        surface.frame(graphics, self.scale, |graphics| unsafe {
            let context = &graphics.context;
            let ground = D2D1_ROUNDED_RECT { rect: whole, radiusX: 20.0, radiusY: 20.0 };
            context.FillRoundedRectangle(&ground, &graphics.brush("#202020", 0.94)?);
            context.DrawRoundedRectangle(&ground, &graphics.brush("#FFFFFF", 0.14)?, 1.0, None);
            for (index, &(button, rect)) in self.buttons.iter().enumerate() {
                let chosen = matches!(button, Button::Tool(tool) if tool == look.chosen);
                let enabled = match button {
                    Button::Thinner => look.thinner,
                    Button::Thicker => look.thicker,
                    Button::Undo | Button::Clear => look.has_marks,
                    _ => true,
                };
                let cell = D2D1_ROUNDED_RECT { rect, radiusX: 13.0, radiusY: 13.0 };
                if chosen {
                    context.FillRoundedRectangle(&cell, &graphics.brush("#0078D4", 1.0)?);
                } else if enabled && self.hovered == Some(index) && !matches!(button, Button::Color(_)) {
                    context.FillRoundedRectangle(&cell, &graphics.brush("#FFFFFF", 0.12)?);
                }
                let ink = graphics.brush("#FFFFFF", if enabled { 1.0 } else { 0.35 })?;
                let chosen_color = matches!(button, Button::Color(index) if Palette::COLORS[index] == look.color);
                icons::draw(graphics, button, rect, &ink, chosen_color)?;
            }
            Ok(())
        })
    }
}

/// Every button's place, in device-independent pixels, and the toolbar's size: the marking tools,
/// the pointer tools and the board, the colours, size, undo and clear, and done.
fn layout() -> (Vec<(Button, D2D_RECT_F)>, (f32, f32)) {
    let groups: Vec<Vec<Button>> = vec![
        vec![Button::Tool(Tool::Pen), Button::Tool(Tool::Highlighter), Button::Tool(Tool::Arrow), Button::Tool(Tool::Box)],
        vec![Button::Tool(Tool::Laser), Button::Tool(Tool::Spotlight), Button::Tool(Tool::Zoom), Button::Board],
        (0..Palette::COLORS.len()).map(Button::Color).collect(),
        vec![Button::Thinner, Button::Thicker],
        vec![Button::Undo, Button::Clear],
        vec![Button::Done],
    ];
    let mut buttons = Vec::new();
    let mut x = PADDING.0;
    for (number, group) in groups.iter().enumerate() {
        if number > 0 {
            x += BETWEEN;
        }
        for (index, &button) in group.iter().enumerate() {
            if index > 0 {
                x += INSIDE;
            }
            let width = if matches!(button, Button::Color(_)) { DOT } else { BUTTON.0 };
            buttons.push((button, D2D_RECT_F { left: x, top: PADDING.1, right: x + width, bottom: PADDING.1 + BUTTON.1 }));
            x += width;
        }
    }
    (buttons, (x + PADDING.0, BUTTON.1 + PADDING.1 * 2.0))
}
