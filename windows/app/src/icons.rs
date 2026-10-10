//! The toolbar's icons, drawn as shapes so they are sharp at every scale and need no font.

use crate::graphics::{point, Graphics};
use tinypen_core::{arrow_outline, Palette, Point, Tool};
use windows::core::Result;
use windows::Win32::Graphics::Direct2D::Common::*;
use windows::Win32::Graphics::Direct2D::*;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Button {
    Tool(Tool),
    Board,
    Color(usize),
    Thinner,
    Thicker,
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
            Button::Color(index) => format!("{} ({})", Palette::NAMES[index], index + 1),
            Button::Thinner => "Thinner ([)".into(),
            Button::Thicker => "Thicker (])".into(),
            Button::Undo => "Undo (Ctrl+Z)".into(),
            Button::Clear => "Clear (Delete)".into(),
            Button::Done => "Clear and stop drawing".into(),
        }
    }
}

/// Draws `button`'s icon centred in `cell`, in `ink`.
pub fn draw(graphics: &Graphics, button: Button, cell: D2D_RECT_F, ink: &ID2D1SolidColorBrush, chosen_color: bool) -> Result<()> {
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
            Button::Color(index) => {
                let dot = D2D1_ELLIPSE { point: at(0.0, 0.0), radiusX: 8.0, radiusY: 8.0 };
                context.FillEllipse(&dot, &graphics.brush(Palette::COLORS[index], 1.0)?);
                context.DrawEllipse(&dot, &graphics.brush("#FFFFFF", 0.35)?, 1.0, round);
                if chosen_color {
                    let ring = D2D1_ELLIPSE { point: at(0.0, 0.0), radiusX: 11.0, radiusY: 11.0 };
                    context.DrawEllipse(&ring, &graphics.brush("#4CC2FF", 1.0)?, 2.0, round);
                }
            }
            Button::Thinner => context.DrawLine(at(-6.0, 0.0), at(6.0, 0.0), ink, 1.8, round),
            Button::Thicker => {
                context.DrawLine(at(-6.0, 0.0), at(6.0, 0.0), ink, 1.8, round);
                context.DrawLine(at(0.0, -6.0), at(0.0, 6.0), ink, 1.8, round);
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

fn layer(opacity: f32) -> D2D1_LAYER_PARAMETERS1 {
    D2D1_LAYER_PARAMETERS1 {
        contentBounds: D2D_RECT_F { left: f32::MIN, top: f32::MIN, right: f32::MAX, bottom: f32::MAX },
        maskTransform: crate::graphics::identity(),
        opacity,
        ..Default::default()
    }
}
