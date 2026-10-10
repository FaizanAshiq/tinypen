//! Drawing mode's floating toolbar, on the monitor being drawn on: at the top in the middle until
//! it is dragged by its background, then wherever it was dropped. It never takes the keys from the
//! drawing layer, so the tool keys keep working while it shows.

use crate::graphics::{Graphics, Surface};
use crate::icons::{self, Button};
use crate::system::Monitor;
use crate::tips::Tips;
use tinypen_core::{Rect, Tool, ToolbarSpot, WIDTHS};
use windows::core::{w, Result, PCWSTR};
use windows::Win32::Foundation::{COLORREF, HINSTANCE, HWND, POINT, RECT};
use windows::Win32::UI::Input::KeyboardAndMouse::{ReleaseCapture, SetCapture};
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
    pub can_clear: bool,
    pub can_undo: bool,
}

pub struct Toolbar {
    pub hwnd: HWND,
    surface: Option<Surface>,
    scale: f32,
    buttons: Vec<(Button, D2D_RECT_F)>,
    size: (f32, f32),
    hovered: Option<usize>,
    tips: Tips,
    /// Where the pointer and the window were when a drag by the background began.
    dragging: Option<(POINT, RECT)>,
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
            Ok(Toolbar { hwnd, surface: None, scale: 0.0, buttons, size, hovered: None, tips, dragging: None })
        }
    }

    /// At `spot` on `monitor`'s work area, wholly on it; without one, centred at the top, 12 pixels down.
    pub fn show(&mut self, graphics: &Graphics, monitor: &Monitor, spot: Option<ToolbarSpot>) -> Result<()> {
        let scale = monitor.scale;
        let (width, height) = ((self.size.0 * scale).ceil() as i32, (self.size.1 * scale).ceil() as i32);
        let frame = ToolbarSpot::frame(width as f32, height as f32, rect(monitor.work), spot, 12.0 * scale);
        let (x, y) = (frame.x.round() as i32, frame.y.round() as i32);
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

    /// A press on the background, not a button, the way Epic Pen's toolbar moves: the toolbar follows
    /// the pointer until let go.
    pub fn begin_drag(&mut self) {
        let mut pointer = POINT::default();
        let mut window = RECT::default();
        unsafe {
            if GetCursorPos(&mut pointer).is_err() || GetWindowRect(self.hwnd, &mut window).is_err() {
                return;
            }
            SetCapture(self.hwnd);
        }
        self.dragging = Some((pointer, window));
    }

    /// True while a drag is on, with the toolbar moved to follow the pointer.
    pub fn drag(&self) -> bool {
        let Some((start, window)) = self.dragging else { return false };
        let mut pointer = POINT::default();
        unsafe {
            if GetCursorPos(&mut pointer).is_ok() {
                let (x, y) = (window.left + pointer.x - start.x, window.top + pointer.y - start.y);
                let _ = SetWindowPos(self.hwnd, Some(HWND_TOPMOST), x, y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
            }
        }
        true
    }

    /// Let go: where the toolbar was dropped, in physical pixels; None when no drag was on.
    pub fn end_drag(&mut self) -> Option<Rect> {
        self.dragging.take()?;
        let mut window = RECT::default();
        unsafe {
            let _ = ReleaseCapture();
            GetWindowRect(self.hwnd, &mut window).ok()?;
        }
        Some(rect(window))
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
                let enabled = match button {
                    Button::Undo => look.can_undo,
                    Button::Clear => look.can_clear,
                    _ => true,
                };
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

/// A window rectangle as the core's.
pub fn rect(r: RECT) -> Rect {
    Rect { x: r.left as f32, y: r.top as f32, width: (r.right - r.left) as f32, height: (r.bottom - r.top) as f32 }
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
