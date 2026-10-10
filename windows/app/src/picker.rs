//! The colour picker under the toolbar's colour button: the six on top, then the custom colours
//! picked lately, any colour from Windows' colour dialog, and a hex code. Like the toolbar it never
//! takes the keys from the drawing layer, which hands it what is typed into the hex field.

use crate::graphics::{Graphics, Surface};
use crate::icons;
use crate::tips::Tips;
use tinypen_core::Palette;
use windows::core::{w, Result, PCWSTR};
use windows::Win32::Foundation::{COLORREF, HINSTANCE, HWND, RECT};
use windows::Win32::Graphics::Direct2D::Common::*;
use windows::Win32::Graphics::Direct2D::*;
use windows::Win32::UI::WindowsAndMessaging::*;

pub const PICKER_CLASS: PCWSTR = w!("TinypenPicker");

const BUTTON: (f32, f32) = (32.0, 28.0);
const FIELD: f32 = 86.0;
const INSIDE: f32 = 2.0;
const ROWS: f32 = 6.0;
const PADDING: f32 = 10.0;

#[derive(Clone, Debug, PartialEq)]
pub enum Item {
    Swatch(String),
    Wheel,
    Hex,
}

pub struct Picker {
    pub hwnd: HWND,
    surface: Option<Surface>,
    scale: f32,
    items: Vec<(Item, D2D_RECT_F)>,
    size: (f32, f32),
    hovered: Option<usize>,
    tips: Tips,
    pub shown: bool,
    /// The hex field takes what is typed.
    pub editing: bool,
    /// The digits typed, without the #.
    typed: String,
    /// What is typed is selected, to type over, as after a code that was not a colour.
    selected: bool,
}

impl Picker {
    pub fn new(instance: HINSTANCE) -> Result<Picker> {
        unsafe {
            let hwnd = CreateWindowExW(
                WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOREDIRECTIONBITMAP | WS_EX_NOACTIVATE | WS_EX_LAYERED,
                PICKER_CLASS,
                w!("Tinypen colours"),
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
            Ok(Picker {
                hwnd,
                surface: None,
                scale: 0.0,
                items: Vec::new(),
                size: (0.0, 0.0),
                hovered: None,
                tips,
                shown: false,
                editing: false,
                typed: String::new(),
                selected: false,
            })
        }
    }

    /// Under `button`, the toolbar's colour button in physical pixels, with an empty hex field.
    pub fn show(&mut self, graphics: &Graphics, button: RECT, scale: f32, recent: &[String]) -> Result<()> {
        let (items, size) = layout(recent);
        let (width, height) = ((size.0 * scale).ceil() as i32, (size.1 * scale).ceil() as i32);
        // The first colour right under the button.
        let x = button.left - (PADDING * scale) as i32;
        let y = button.bottom + (8.0 * scale) as i32;
        unsafe {
            SetWindowPos(self.hwnd, Some(HWND_TOPMOST), x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW)?;
        }
        let resized = self.surface.as_ref().is_none_or(|surface| surface.width != width as u32 || surface.height != height as u32);
        if resized || self.scale != scale {
            self.surface = Some(graphics.surface(self.hwnd, width as u32, height as u32)?);
        }
        let names: Vec<(String, D2D_RECT_F)> = items.iter().map(|(item, rect)| (name(item), *rect)).collect();
        self.tips.place(&names, scale);
        self.items = items;
        self.size = size;
        self.scale = scale;
        self.hovered = None;
        self.shown = true;
        self.editing = false;
        self.typed.clear();
        self.selected = false;
        Ok(())
    }

    pub fn hide(&mut self) {
        self.shown = false;
        self.editing = false;
        unsafe {
            let _ = ShowWindow(self.hwnd, SW_HIDE);
        }
    }

    /// The item at a point in the window's client pixels.
    pub fn hit(&self, x: i32, y: i32) -> Option<Item> {
        self.index_at(x, y).map(|index| self.items[index].0.clone())
    }

    fn index_at(&self, x: i32, y: i32) -> Option<usize> {
        let (x, y) = (x as f32 / self.scale.max(1.0), y as f32 / self.scale.max(1.0));
        self.items.iter().position(|(_, rect)| x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom)
    }

    /// True when the pointer moved onto another item, so the picker needs drawing again.
    pub fn hover(&mut self, x: i32, y: i32) -> bool {
        let hovered = self.index_at(x, y);
        let changed = hovered != self.hovered;
        self.hovered = hovered;
        changed
    }

    // The hex field

    /// One more digit, 0 to 9 or A to F, up to six.
    pub fn type_digit(&mut self, digit: char) {
        if self.selected {
            self.typed.clear();
            self.selected = false;
        }
        if self.typed.len() < 6 {
            self.typed.push(digit.to_ascii_uppercase());
        }
    }

    pub fn backspace(&mut self) {
        if self.selected {
            self.typed.clear();
            self.selected = false;
        } else {
            self.typed.pop();
        }
    }

    /// A code pasted in, with or without the #; false for anything that is not one.
    pub fn paste(&mut self, text: &str) -> bool {
        let Some(hex) = Palette::hex_typed(text) else { return false };
        self.typed = hex[1..].to_string();
        self.selected = false;
        true
    }

    /// The colour typed, or None, and then what is typed is selected to type over.
    pub fn typed_color(&mut self) -> Option<String> {
        let color = Palette::hex_typed(&self.typed);
        self.selected = color.is_none();
        color
    }

    pub fn render(&self, graphics: &Graphics, chosen: &str) -> Result<()> {
        let Some(surface) = &self.surface else { return Ok(()) };
        if !self.shown {
            return Ok(());
        }
        let whole = D2D_RECT_F { left: 0.5, top: 0.5, right: self.size.0 - 0.5, bottom: self.size.1 - 0.5 };
        surface.frame(graphics, self.scale, |graphics| unsafe {
            let context = &graphics.context;
            let ground = D2D1_ROUNDED_RECT { rect: whole, radiusX: 14.0, radiusY: 14.0 };
            context.FillRoundedRectangle(&ground, &graphics.brush("#202020", 0.96)?);
            context.DrawRoundedRectangle(&ground, &graphics.brush("#FFFFFF", 0.14)?, 1.0, None);
            for (index, (item, rect)) in self.items.iter().enumerate() {
                let cell = D2D1_ROUNDED_RECT { rect: *rect, radiusX: 13.0, radiusY: 13.0 };
                if self.hovered == Some(index) && *item != Item::Hex {
                    context.FillRoundedRectangle(&cell, &graphics.brush("#FFFFFF", 0.12)?);
                }
                match item {
                    Item::Swatch(hex) => icons::swatch(graphics, *rect, hex, hex == chosen)?,
                    Item::Wheel => icons::wheel(graphics, *rect)?,
                    Item::Hex => self.render_field(graphics, *rect)?,
                }
            }
            Ok(())
        })
    }

    /// A well with the code typed, the placeholder while empty, and the caret while it takes keys.
    fn render_field(&self, graphics: &Graphics, rect: D2D_RECT_F) -> Result<()> {
        let context = &graphics.context;
        let field = D2D1_ROUNDED_RECT { rect, radiusX: 6.0, radiusY: 6.0 };
        unsafe {
            context.FillRoundedRectangle(&field, &graphics.brush("#FFFFFF", 0.08)?);
            if self.editing {
                context.DrawRoundedRectangle(&field, &graphics.brush("#4CC2FF", 1.0)?, 1.5, None);
            }
        }
        let text_rect = D2D_RECT_F { left: rect.left + 8.0, right: rect.right - 4.0, ..rect };
        if self.typed.is_empty() {
            graphics.draw_code("#RRGGBB", text_rect, &graphics.brush("#FFFFFF", 0.4)?);
        } else {
            let text = format!("#{}", self.typed);
            if self.selected {
                let width = graphics.code_width(&text);
                let band = D2D_RECT_F { left: text_rect.left - 1.0, top: rect.top + 5.0, right: text_rect.left + width + 1.0, bottom: rect.bottom - 5.0 };
                unsafe { context.FillRectangle(&band, &graphics.brush("#0078D4", 1.0)?) };
            }
            graphics.draw_code(&text, text_rect, &graphics.brush("#FFFFFF", 1.0)?);
        }
        if self.editing && !self.selected {
            let after = if self.typed.is_empty() { 0.0 } else { graphics.code_width(&format!("#{}", self.typed)) };
            let x = text_rect.left + after + 1.0;
            let top = crate::graphics::point(tinypen_core::Point::new(x, rect.top + 6.0));
            let bottom = crate::graphics::point(tinypen_core::Point::new(x, rect.bottom - 6.0));
            unsafe { context.DrawLine(top, bottom, &graphics.brush("#FFFFFF", 1.0)?, 1.0, None) };
        }
        Ok(())
    }
}

fn name(item: &Item) -> String {
    match item {
        Item::Swatch(hex) => match Palette::COLORS.iter().position(|color| color == hex) {
            Some(index) => format!("{} ({})", Palette::NAMES[index], index + 1),
            None => hex.clone(),
        },
        Item::Wheel => "Any colour".into(),
        Item::Hex => "Hex colour, Return to use it".into(),
    }
}

/// Every item's place, in device-independent pixels, and the picker's size: the six in a row, and
/// under them the recent colours, the wheel and the hex field.
fn layout(recent: &[String]) -> (Vec<(Item, D2D_RECT_F)>, (f32, f32)) {
    let rows: [Vec<(Item, f32)>; 2] = [
        Palette::COLORS.iter().map(|hex| (Item::Swatch((*hex).into()), BUTTON.0)).collect(),
        recent
            .iter()
            .map(|hex| (Item::Swatch(hex.clone()), BUTTON.0))
            .chain([(Item::Wheel, BUTTON.0), (Item::Hex, FIELD)])
            .collect(),
    ];
    let mut items = Vec::new();
    let mut widest: f32 = 0.0;
    for (number, row) in rows.into_iter().enumerate() {
        let top = PADDING + number as f32 * (BUTTON.1 + ROWS);
        let mut x = PADDING;
        for (index, (item, width)) in row.into_iter().enumerate() {
            if index > 0 {
                x += INSIDE;
            }
            items.push((item, D2D_RECT_F { left: x, top, right: x + width, bottom: top + BUTTON.1 }));
            x += width;
        }
        widest = widest.max(x);
    }
    (items, (widest + PADDING, PADDING * 2.0 + BUTTON.1 * 2.0 + ROWS))
}
