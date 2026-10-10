//! The toolbar's icons, drawn as shapes so they are sharp at every scale and need no font.

use crate::graphics::{point, Graphics};
use tinypen_core::{arrow_outline, Point, Tool, WIDTHS};
use windows::core::Result;
use windows::Win32::Graphics::Direct2D::Common::*;
use windows::Win32::Graphics::Direct2D::*;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Button {
    Tool(Tool),
    Board,
    /// The colour in hand, which opens the colour picker.
    Color,
    /// One of the five sizes, an index into `WIDTHS`.
    Size(usize),
    Undo,
    Clear,
    Done,
}

impl Button {
    /// What the button is called, with its key.
    pub fn name(self) -> String {
        match self {
            Button::Tool(tool) => format!("{} ({})", tool.title(), tool.key().to_ascii_uppercase()),
            Button::Board => "Board, white then black (W)".into(),
            Button::Color => "Colour, 1 to 6 for the six".into(),
            Button::Size(index) => format!("Size {} of {}, [ and ] to step", index + 1, WIDTHS.len()),
            Button::Undo => "Undo (Ctrl+Z)".into(),
            Button::Clear => "Clear (Delete)".into(),
            Button::Done => "Clear and stop drawing".into(),
        }
    }
}

/// Draws `button`'s icon centred in `cell`, in `ink`; the colour button shows `color`.
pub fn draw(graphics: &Graphics, button: Button, cell: D2D_RECT_F, ink: &ID2D1SolidColorBrush, color: &str) -> Result<()> {
    let (cx, cy) = ((cell.left + cell.right) / 2.0, (cell.top + cell.bottom) / 2.0);
    let at = |x: f32, y: f32| point(Point::new(cx + x, cy + y));
    let context = &graphics.context;
    let round = &graphics.round;
    unsafe {
        match button {
            Button::Tool(Tool::Pen) => {
                context.DrawLine(at(-6.0, 6.0), at(6.0, -6.0), ink, 2.6, round);
                context.FillEllipse(&D2D1_ELLIPSE { point: at(-7.0, 7.0), radiusX: 1.6, radiusY: 1.6 }, ink);
            }
            Button::Tool(Tool::Highlighter) => {
                context.PushLayer(&layer(0.6), None);
                context.DrawLine(at(-7.0, 5.0), at(7.0, -5.0), ink, 6.0, &graphics.flat);
                context.PopLayer();
            }
            Button::Tool(Tool::Arrow) => {
                let outline = arrow_outline(Point::new(cx - 7.0, cy + 7.0), Point::new(cx + 7.0, cy - 7.0), 2.4);
                let path = graphics.path(&outline, false, true)?;
                context.FillGeometry(&path, ink, None);
                context.DrawGeometry(&path, ink, 1.0, round);
            }
            Button::Tool(Tool::Box) => {
                context.DrawRectangle(&D2D_RECT_F { left: cx - 7.0, top: cy - 5.0, right: cx + 7.0, bottom: cy + 5.0 }, ink, 1.8, round);
            }
            Button::Tool(Tool::Laser) => {
                context.FillEllipse(&D2D1_ELLIPSE { point: at(0.0, 0.0), radiusX: 3.0, radiusY: 3.0 }, ink);
                context.DrawEllipse(&D2D1_ELLIPSE { point: at(0.0, 0.0), radiusX: 7.0, radiusY: 7.0 }, ink, 1.4, round);
            }
            Button::Tool(Tool::Spotlight) => {
                context.PushLayer(&layer(0.35), None);
                context.FillEllipse(&D2D1_ELLIPSE { point: at(0.0, 0.0), radiusX: 7.0, radiusY: 7.0 }, ink);
                context.PopLayer();
                context.DrawEllipse(&D2D1_ELLIPSE { point: at(0.0, 0.0), radiusX: 7.0, radiusY: 7.0 }, ink, 1.6, round);
            }
            Button::Tool(Tool::Zoom) => {
                context.DrawEllipse(&D2D1_ELLIPSE { point: at(-2.0, -2.0), radiusX: 5.5, radiusY: 5.5 }, ink, 1.8, round);
                context.DrawLine(at(2.2, 2.2), at(7.0, 7.0), ink, 2.4, round);
                context.DrawLine(at(-4.5, -2.0), at(0.5, -2.0), ink, 1.4, round);
                context.DrawLine(at(-2.0, -4.5), at(-2.0, 0.5), ink, 1.4, round);
            }
            Button::Board => {
                context.FillRectangle(&D2D_RECT_F { left: cx - 7.0, top: cy - 5.0, right: cx + 7.0, bottom: cy + 5.0 }, ink);
            }
            Button::Color => swatch(graphics, cell, color, false)?,
            Button::Size(index) => {
                // A line as heavy as the size, as the Mac app shows it.
                let weight = 1.0 + index as f32 * 2.0;
                let reach = 9.0 - weight / 2.0;
                context.DrawLine(at(-reach, 0.0), at(reach, 0.0), ink, weight, round);
            }
            Button::Undo => {
                let geometry = graphics.factory.CreatePathGeometry()?;
                let sink = geometry.Open()?;
                sink.BeginFigure(at(6.0, 6.0), D2D1_FIGURE_BEGIN_HOLLOW);
                sink.AddBezier(&D2D1_BEZIER_SEGMENT { point1: at(7.0, -4.0), point2: at(0.0, -5.0), point3: at(-5.0, -2.0) });
                sink.EndFigure(D2D1_FIGURE_END_OPEN);
                sink.Close()?;
                context.DrawGeometry(&geometry, ink, 1.8, round);
                context.DrawLine(at(-5.0, -2.0), at(-1.0, -6.0), ink, 1.8, round);
                context.DrawLine(at(-5.0, -2.0), at(-0.5, 1.0), ink, 1.8, round);
            }
            Button::Clear => {
                context.DrawRectangle(&D2D_RECT_F { left: cx - 5.0, top: cy - 4.0, right: cx + 5.0, bottom: cy + 7.0 }, ink, 1.6, round);
                context.DrawLine(at(-7.0, -5.0), at(7.0, -5.0), ink, 1.6, round);
                context.DrawLine(at(-2.0, -7.0), at(2.0, -7.0), ink, 1.6, round);
            }
            Button::Done => {
                context.DrawLine(at(-5.0, -5.0), at(5.0, 5.0), ink, 1.8, round);
                context.DrawLine(at(-5.0, 5.0), at(5.0, -5.0), ink, 1.8, round);
            }
        }
    }
    Ok(())
}

/// A colour as a dot, ringed when it is the one in hand.
pub fn swatch(graphics: &Graphics, cell: D2D_RECT_F, color: &str, chosen: bool) -> Result<()> {
    let centre = point(Point::new((cell.left + cell.right) / 2.0, (cell.top + cell.bottom) / 2.0));
    let dot = D2D1_ELLIPSE { point: centre, radiusX: 8.0, radiusY: 8.0 };
    unsafe {
        graphics.context.FillEllipse(&dot, &graphics.brush(color, 1.0)?);
        graphics.context.DrawEllipse(&dot, &graphics.brush("#FFFFFF", 0.35)?, 1.0, &graphics.round);
        if chosen {
            let ring = D2D1_ELLIPSE { point: centre, radiusX: 11.5, radiusY: 11.5 };
            graphics.context.DrawEllipse(&ring, &graphics.brush("#4CC2FF", 1.0)?, 2.0, &graphics.round);
        }
    }
    Ok(())
}

/// A hue wheel, for any colour.
pub fn wheel(graphics: &Graphics, cell: D2D_RECT_F) -> Result<()> {
    let centre = Point::new((cell.left + cell.right) / 2.0, (cell.top + cell.bottom) / 2.0);
    let steps = 36;
    let rim = |at: f32| {
        let angle = at / steps as f32 * std::f32::consts::TAU;
        Point::new(centre.x + 9.0 * angle.cos(), centre.y + 9.0 * angle.sin())
    };
    for step in 0..steps {
        // A little over a step wide, so no seam shows between wedges.
        let wedge = graphics.path(&[centre, rim(step as f32), rim(step as f32 + 1.05)], false, true)?;
        let brush = graphics.brush(&hue_hex(step as f32 / steps as f32), 1.0)?;
        unsafe {
            graphics.context.FillGeometry(&wedge, &brush, None);
        }
    }
    Ok(())
}

/// A fully saturated colour at `hue`, 0 to 1 round the wheel, as "#RRGGBB".
fn hue_hex(hue: f32) -> String {
    let channel = |offset: f32| {
        let k = (offset + hue * 6.0) % 6.0;
        let value = 1.0 - (k.min(4.0 - k).clamp(0.0, 1.0)) * 0.85;
        (value * 255.0).round() as u8
    };
    format!("#{:02X}{:02X}{:02X}", channel(5.0), channel(3.0), channel(1.0))
}

fn layer(opacity: f32) -> D2D1_LAYER_PARAMETERS1 {
    D2D1_LAYER_PARAMETERS1 {
        contentBounds: D2D_RECT_F { left: f32::MIN, top: f32::MIN, right: f32::MAX, bottom: f32::MAX },
        maskTransform: crate::graphics::identity(),
        opacity,
        ..Default::default()
    }
}
