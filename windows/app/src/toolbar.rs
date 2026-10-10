//! Drawing mode's floating toolbar, at the top of the monitor being drawn on. It never takes the
//! keys from the drawing layer, so the tool keys keep working while it shows.

use crate::graphics::{Graphics, Surface};
use crate::icons::{self, Button};
use crate::system::Monitor;
use crate::tips::Tips;
use tinypen_core::{Tool, WIDTHS};
use windows::core::{w, Result, PCWSTR};
use windows::Win32::Foundation::{COLORREF, HINSTANCE, HWND, RECT};
use windows::Win32::Graphics::Direct2D::Common::*;
use windows::Win32::Graphics::Direct2D::*;
use windows::Win32::UI::WindowsAndMessaging::*;

pub const TOOLBAR_CLASS: PCWSTR = w!("TinypenToolbar");

const BUTTON: (f32, f32) = (32.0, 28.0);
const INSIDE: f32 = 2.0;
const BETWEEN: f32 = 14.0;
const PADDING: (f32, f32) = (12.0, 6.0);

/// What the toolbar shows as chosen and available.
pub struct Look {
    pub chosen: Tool,
    pub color: String,
    /// Index into `WIDTHS`.
    pub size: usize,
    pub has_marks: bool,
}

pub struct Toolbar {
    pub hwnd: HWND,
    surface: Option<Surface>,
    scale: f32,
    buttons: Vec<(Button, D2D_RECT_F)>,
    size: (f32, f32),
    hovered: Option<usize>,
    tips: Tips,
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
            let tips = Tips::new(hwnd, instance)?;
            Ok(Toolbar { hwnd, surface: None, scale: 0.0, buttons, size, hovered: None, tips })
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
            let names: Vec<(String, D2D_RECT_F)> = self.buttons.iter().map(|(button, rect)| (button.name(), *rect)).collect();
            self.tips.place(&names, scale);
        }
        Ok(())
    }

    /// The colour button on screen, in physical pixels, for the colour picker to hang from.
    pub fn color_button(&self) -> Option<(RECT, f32)> {
        let (_, rect) = self.buttons.iter().find(|(button, _)| *button == Button::Color)?;
        let mut window = RECT::default();
        unsafe { GetWindowRect(self.hwnd, &mut window).ok()? };
        let at = |value: f32| (value * self.scale) as i32;
        let on_screen = RECT {
            left: window.left + at(rect.left),
            top: window.top + at(rect.top),
            right: window.left + at(rect.right),
            bottom: window.top + at(rect.bottom),
        };
        Some((on_screen, self.scale))
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
                let chosen = match button {
                    Button::Tool(tool) => tool == look.chosen,
                    Button::Size(size) => size == look.size,
                    _ => false,
                };
                let enabled = !matches!(button, Button::Undo | Button::Clear) || look.has_marks;
                let cell = D2D1_ROUNDED_RECT { rect, radiusX: 13.0, radiusY: 13.0 };
                if chosen {
                    context.FillRoundedRectangle(&cell, &graphics.brush("#0078D4", 1.0)?);
                } else if enabled && self.hovered == Some(index) {
                    context.FillRoundedRectangle(&cell, &graphics.brush("#FFFFFF", 0.12)?);
                }
                let ink = graphics.brush("#FFFFFF", if enabled { 1.0 } else { 0.35 })?;
                icons::draw(graphics, button, rect, &ink, &look.color)?;
            }
            Ok(())
        })
    }
}

/// Every button's place, in device-independent pixels, and the toolbar's size: the marking tools,
/// the pointer tools and the board, the colour, the five sizes, undo and clear, and done.
fn layout() -> (Vec<(Button, D2D_RECT_F)>, (f32, f32)) {
    let groups: Vec<Vec<Button>> = vec![
        vec![Button::Tool(Tool::Pen), Button::Tool(Tool::Highlighter), Button::Tool(Tool::Arrow), Button::Tool(Tool::Box)],
        vec![Button::Tool(Tool::Laser), Button::Tool(Tool::Spotlight), Button::Tool(Tool::Zoom), Button::Board],
        vec![Button::Color],
        (0..WIDTHS.len()).map(Button::Size).collect(),
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
            buttons.push((button, D2D_RECT_F { left: x, top: PADDING.1, right: x + BUTTON.0, bottom: PADDING.1 + BUTTON.1 }));
            x += BUTTON.0;
        }
    }
    (buttons, (x + PADDING.0, BUTTON.1 + PADDING.1 * 2.0))
}
