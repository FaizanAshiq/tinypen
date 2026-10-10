//! One Direct3D device, one Direct2D device context and one DirectComposition device for every
//! window, and a see-through surface per window drawn on the graphics card.

use tinypen_core::{arrow_outline, smooth, Mark, MarkKind, Palette, Point};
use windows::core::{Interface, Result};
use windows::Win32::Foundation::HWND;
use windows::Win32::Graphics::Direct2D::Common::*;
use windows::Win32::Graphics::Direct2D::*;
use windows::Win32::Graphics::Direct3D::*;
use windows::Win32::Graphics::Direct3D11::*;
use windows::Win32::Graphics::DirectComposition::*;
use windows::Win32::Graphics::Dxgi::Common::*;
use windows::Win32::Graphics::Dxgi::*;
use windows_numerics::{Matrix3x2, Vector2};

pub struct Graphics {
    pub factory: ID2D1Factory1,
    pub context: ID2D1DeviceContext,
    dxgi: IDXGIDevice,
    dxgi_factory: IDXGIFactory2,
    pub composition: IDCompositionDevice,
    pub round: ID2D1StrokeStyle1,
    pub flat: ID2D1StrokeStyle1,
}

impl Graphics {
    pub fn new() -> Result<Self> {
        unsafe {
            let mut device = None;
            D3D11CreateDevice(
                None,
                D3D_DRIVER_TYPE_HARDWARE,
                Default::default(),
                D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                None,
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                None,
            )?;
            let device: ID3D11Device = device.unwrap();
            let dxgi: IDXGIDevice = device.cast()?;
            let factory: ID2D1Factory1 = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, None)?;
            let context = factory.CreateDevice(&dxgi)?.CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE)?;
            let dxgi_factory: IDXGIFactory2 = CreateDXGIFactory2(DXGI_CREATE_FACTORY_FLAGS(0))?;
            let composition: IDCompositionDevice = DCompositionCreateDevice(&dxgi)?;
            let style = |cap, join| {
                factory.CreateStrokeStyle(
                    &D2D1_STROKE_STYLE_PROPERTIES1 {
                        startCap: cap,
                        endCap: cap,
                        dashCap: cap,
                        lineJoin: join,
                        miterLimit: 10.0,
                        dashStyle: D2D1_DASH_STYLE_SOLID,
                        dashOffset: 0.0,
                        transformType: D2D1_STROKE_TRANSFORM_TYPE_NORMAL,
                    },
                    None,
                )
            };
            let round = style(D2D1_CAP_STYLE_ROUND, D2D1_LINE_JOIN_ROUND)?;
            let flat = style(D2D1_CAP_STYLE_FLAT, D2D1_LINE_JOIN_ROUND)?;
            Ok(Graphics { factory, context, dxgi, dxgi_factory, composition, round, flat })
        }
    }

    /// A see-through surface covering `hwnd`, `width` by `height` pixels.
    pub fn surface(&self, hwnd: HWND, width: u32, height: u32) -> Result<Surface> {
        unsafe {
            let description = DXGI_SWAP_CHAIN_DESC1 {
                Width: width.max(1),
                Height: height.max(1),
                Format: DXGI_FORMAT_B8G8R8A8_UNORM,
                SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
                BufferUsage: DXGI_USAGE_RENDER_TARGET_OUTPUT,
                BufferCount: 2,
                SwapEffect: DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
                AlphaMode: DXGI_ALPHA_MODE_PREMULTIPLIED,
                ..Default::default()
            };
            let chain = self.dxgi_factory.CreateSwapChainForComposition(&self.dxgi, &description, None)?;
            let target = self.composition.CreateTargetForHwnd(hwnd, true)?;
            let visual = self.composition.CreateVisual()?;
            visual.SetContent(&chain)?;
            target.SetRoot(&visual)?;
            self.composition.Commit()?;
            Ok(Surface { chain, _target: target, _visual: visual, width, height })
        }
    }

    pub fn brush(&self, hex: &str, alpha: f32) -> Result<ID2D1SolidColorBrush> {
        let (r, g, b) = Palette::rgb(hex);
        unsafe { self.context.CreateSolidColorBrush(&D2D1_COLOR_F { r, g, b, a: alpha }, None) }
    }

    /// A path through `points`, smoothed, open or closed.
    pub fn path(&self, points: &[Point], curve: bool, closed: bool) -> Result<ID2D1PathGeometry1> {
        unsafe {
            let geometry = self.factory.CreatePathGeometry()?;
            let sink = geometry.Open()?;
            if let Some(first) = points.first() {
                sink.BeginFigure(point(*first), if closed { D2D1_FIGURE_BEGIN_FILLED } else { D2D1_FIGURE_BEGIN_HOLLOW });
                if points.len() == 1 {
                    // A round cap on a zero length line is a dot.
                    sink.AddLine(point(*first));
                } else if curve {
                    for (one, two, end) in smooth(points) {
                        sink.AddBezier(&D2D1_BEZIER_SEGMENT { point1: point(one), point2: point(two), point3: point(end) });
                    }
                } else {
                    for each in &points[1..] {
                        sink.AddLine(point(*each));
                    }
                }
                sink.EndFigure(if closed { D2D1_FIGURE_END_CLOSED } else { D2D1_FIGURE_END_OPEN });
            }
            sink.Close()?;
            Ok(geometry)
        }
    }

    /// Draws one mark, as the Mac app does: the highlighter faded as a whole so it never darkens
    /// where it crosses itself, the arrow filled and stroked round.
    pub fn draw_mark(&self, mark: &Mark) -> Result<()> {
        let context = &self.context;
        let brush = self.brush(&mark.color, 1.0)?;
        unsafe {
            match &mark.kind {
                MarkKind::Stroke(points) => {
                    context.DrawGeometry(&self.path(points, true, false)?, &brush, mark.width, &self.round);
                }
                MarkKind::Highlight(points) => {
                    let parameters = D2D1_LAYER_PARAMETERS1 {
                        contentBounds: D2D_RECT_F { left: f32::MIN, top: f32::MIN, right: f32::MAX, bottom: f32::MAX },
                        maskTransform: identity(),
                        opacity: 0.4,
                        ..Default::default()
                    };
                    context.PushLayer(&parameters, None);
                    context.DrawGeometry(&self.path(points, true, false)?, &brush, mark.width, &self.flat);
                    context.PopLayer();
                }
                MarkKind::Arrow { from, to } => {
                    let outline = self.path(&arrow_outline(*from, *to, mark.width), false, true)?;
                    context.FillGeometry(&outline, &brush, None);
                    context.DrawGeometry(&outline, &brush, mark.width * 0.5, &self.round);
                }
                MarkKind::Box(rect) => {
                    let corners = D2D_RECT_F { left: rect.x, top: rect.y, right: rect.x + rect.width, bottom: rect.y + rect.height };
                    context.DrawRectangle(&corners, &brush, mark.width, &self.round);
                }
            }
        }
        Ok(())
    }
}

/// A window's swap chain, shown through DirectComposition with its alpha kept.
pub struct Surface {
    pub chain: IDXGISwapChain1,
    _target: IDCompositionTarget,
    _visual: IDCompositionVisual,
    pub width: u32,
    pub height: u32,
}

impl Surface {
    /// Draws a frame at `scale` device-independent pixels per pixel, through `draw`, and shows it.
    pub fn frame(&self, graphics: &Graphics, scale: f32, draw: impl FnOnce(&Graphics) -> Result<()>) -> Result<()> {
        unsafe {
            let buffer: IDXGISurface = self.chain.GetBuffer(0)?;
            let dpi = 96.0 * scale;
            let properties = D2D1_BITMAP_PROPERTIES1 {
                pixelFormat: D2D1_PIXEL_FORMAT { format: DXGI_FORMAT_B8G8R8A8_UNORM, alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED },
                dpiX: dpi,
                dpiY: dpi,
                bitmapOptions: D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
                ..Default::default()
            };
            let target = graphics.context.CreateBitmapFromDxgiSurface(&buffer, Some(&properties))?;
            graphics.context.SetTarget(&target);
            graphics.context.SetDpi(dpi, dpi);
            graphics.context.BeginDraw();
            graphics.context.Clear(Some(&D2D1_COLOR_F { r: 0.0, g: 0.0, b: 0.0, a: 0.0 }));
            let drawn = draw(graphics);
            graphics.context.EndDraw(None, None)?;
            graphics.context.SetTarget(None);
            drawn?;
            // Not waiting for the display: with two monitors, waiting on each would halve the frame rate.
            self.chain.Present(0, DXGI_PRESENT(0)).ok()
        }
    }
}

pub fn point(p: Point) -> Vector2 {
    Vector2 { X: p.x, Y: p.y }
}

pub fn identity() -> Matrix3x2 {
    Matrix3x2::identity()
}
