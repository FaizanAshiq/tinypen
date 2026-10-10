//! One monitor's see-through layer, above every app. Outside drawing mode every click passes
//! through it to the apps underneath.

use crate::graphics::{point, Graphics, Surface};
use crate::system::Monitor;
use tinypen_core::{highlighter_width, Drag, LaserTrail, Lens, Mark, MarkKind, Marks, Point, Preferences, StrokeBuilder, Tool};
use windows::core::{w, Result, PCWSTR};
use windows::Win32::Foundation::{COLORREF, HINSTANCE, HWND};
use windows::Win32::Graphics::Direct2D::Common::*;
use windows::Win32::Graphics::Direct2D::*;
use windows::Win32::Graphics::Dxgi::Common::*;
use windows::Win32::UI::WindowsAndMessaging::*;

pub const OVERLAY_CLASS: PCWSTR = w!("TinypenOverlay");

#[derive(Clone, Copy, PartialEq)]
pub enum Board {
    White,
    Black,
}

/// What every layer shows besides its marks.
pub struct Scene {
    pub effect: Option<Tool>,
    pub spotlight_radius: f32,
    pub now: f64,
}

pub struct Overlay {
    pub hwnd: HWND,
    pub monitor: Monitor,
    surface: Surface,
    screen_marks: Marks,
    board_marks: Marks,
    pub board: Option<Board>,
    stroke: StrokeBuilder,
    drag_start: Option<Point>,
    live: Option<Mark>,
    trail: LaserTrail,
    /// Where the pointer is, in device-independent pixels from the monitor's top left; None when
    /// it is on another monitor.
    pub pointer: Option<Point>,
    cache: Option<ID2D1Bitmap1>,
    cache_dirty: bool,
    visible: bool,
}

impl Overlay {
    pub fn new(graphics: &Graphics, instance: HINSTANCE, monitor: Monitor) -> Result<Overlay> {
        let rect = monitor.rect;
        let (width, height) = ((rect.right - rect.left) as u32, (rect.bottom - rect.top) as u32);
        unsafe {
            let hwnd = CreateWindowExW(
                WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOREDIRECTIONBITMAP | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE,
                OVERLAY_CLASS,
                w!("Tinypen drawing"),
                WS_POPUP,
                rect.left,
                rect.top,
                width as i32,
                height as i32,
                None,
                None,
                Some(instance),
                None,
            )?;
            // Layered only so WS_EX_TRANSPARENT lets clicks through; what shows is the surface.
            let _ = SetLayeredWindowAttributes(hwnd, COLORREF(0), 255, LWA_ALPHA);
            let surface = graphics.surface(hwnd, width, height)?;
            Ok(Overlay {
                hwnd,
                monitor,
                surface,
                screen_marks: Marks::default(),
                board_marks: Marks::default(),
                board: None,
                stroke: StrokeBuilder::default(),
                drag_start: None,
                live: None,
                trail: LaserTrail::default(),
                pointer: None,
                cache: None,
                cache_dirty: true,
                visible: false,
            })
        }
    }

    pub fn destroy(&self) {
        unsafe {
            let _ = DestroyWindow(self.hwnd);
        }
    }

    /// Takes the mouse and the keys while drawing; otherwise every click goes through.
    pub fn set_drawing(&self, drawing: bool) {
        unsafe {
            let style = GetWindowLongPtrW(self.hwnd, GWL_EXSTYLE);
            let through = (WS_EX_TRANSPARENT | WS_EX_NOACTIVATE).0 as isize;
            let changed = if drawing { style & !through } else { style | through };
            if changed != style {
                SetWindowLongPtrW(self.hwnd, GWL_EXSTYLE, changed);
                let _ = SetWindowPos(self.hwnd, None, 0, 0, 0, 0,
                                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
            }
        }
    }

    /// Raised over every other window only as it appears, so the toolbar and the lens, raised
    /// after it, stay on top of it.
    pub fn show(&mut self, visible: bool) {
        if visible == self.visible {
            return;
        }
        self.visible = visible;
        unsafe {
            let _ = ShowWindow(self.hwnd, if visible { SW_SHOWNOACTIVATE } else { SW_HIDE });
            if visible {
                let _ = SetWindowPos(self.hwnd, Some(HWND_TOPMOST), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
        }
    }

    pub fn marks(&self) -> &Marks {
        if self.board.is_none() { &self.screen_marks } else { &self.board_marks }
    }

    pub fn is_empty(&self) -> bool {
        self.screen_marks.is_empty() && self.board_marks.is_empty() && self.board.is_none()
    }

    fn change(&mut self, change: impl FnOnce(&mut Marks)) {
        if self.board.is_none() { change(&mut self.screen_marks) } else { change(&mut self.board_marks) }
        self.cache_dirty = true;
    }

    pub fn undo(&mut self) {
        self.change(Marks::undo);
    }

    pub fn clear(&mut self) {
        self.change(Marks::clear);
    }

    /// Esc's first press: everything drawn gone, the board too. Undo brings the marks back.
    pub fn erase(&mut self) {
        self.screen_marks.clear();
        self.board_marks.clear();
        self.board = None;
        self.live = None;
        self.cache_dirty = true;
    }

    /// Every mark and the board gone: the screen as it was.
    pub fn reset(&mut self) {
        self.screen_marks = Marks::default();
        self.board_marks = Marks::default();
        self.board = None;
        self.live = None;
        self.drag_start = None;
        self.trail = LaserTrail::default();
        self.cache_dirty = true;
    }

    /// White, then black, then off.
    pub fn cycle_board(&mut self) {
        self.board = match self.board {
            None => Some(Board::White),
            Some(Board::White) => Some(Board::Black),
            Some(Board::Black) => None,
        };
        self.cache_dirty = true;
    }

    /// A point in this window's client pixels, in device-independent pixels.
    pub fn local(&self, x: i32, y: i32) -> Point {
        Point::new(x as f32 / self.monitor.scale, y as f32 / self.monitor.scale)
    }

    /// Where the pointer is now, from its screen position in physical pixels.
    pub fn track_pointer(&mut self, x: i32, y: i32, effect: Option<Tool>, now: f64) {
        let rect = self.monitor.rect;
        let inside = x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;
        let pointer = inside.then(|| self.local(x - rect.left, y - rect.top));
        if effect == Some(Tool::Laser)
            && let Some(point) = pointer.filter(|point| Some(*point) != self.pointer) {
                self.trail.add(point, now);
            }
        self.trail.prune(now);
        self.pointer = pointer;
    }

    /// The laser still has a trail to fade.
    pub fn is_fading(&self, now: f64) -> bool {
        !self.trail.is_idle(now)
    }

    // Drawing

    pub fn press(&mut self, at: Point, tool: Tool, shift: bool, preferences: &Preferences) {
        self.drag_start = Some(at);
        self.stroke = StrokeBuilder::default();
        if matches!(tool, Tool::Pen | Tool::Highlighter) {
            self.stroke.add(at);
        }
        self.update_live(at, tool, shift, preferences);
    }

    pub fn drag(&mut self, to: Point, tool: Tool, shift: bool, preferences: &Preferences) {
        if self.drag_start.is_none() {
            return;
        }
        if matches!(tool, Tool::Pen | Tool::Highlighter) {
            self.stroke.add(to);
        }
        self.update_live(to, tool, shift, preferences);
    }

    /// True when the release left a mark.
    pub fn release(&mut self, at: Point, tool: Tool, shift: bool, preferences: &Preferences) -> bool {
        if self.drag_start.is_none() {
            return false;
        }
        self.update_live(at, tool, shift, preferences);
        self.drag_start = None;
        match self.live.take() {
            Some(mark) => {
                self.change(|marks| marks.add(mark));
                true
            }
            None => false,
        }
    }

    fn update_live(&mut self, to: Point, tool: Tool, shift: bool, preferences: &Preferences) {
        let Some(start) = self.drag_start else { return };
        let (color, width) = (preferences.color.clone(), preferences.width());
        self.live = match tool {
            Tool::Pen => Some(Mark { kind: MarkKind::Stroke(self.stroke.points.clone()), color, width }),
            Tool::Highlighter => {
                Some(Mark { kind: MarkKind::Highlight(self.stroke.points.clone()), color, width: highlighter_width(width) })
            }
            _ => Drag::mark(tool, start, to, shift, &color, width),
        };
    }

    // Rendering

    /// The finished marks into their cached picture, only when they changed.
    fn refresh_cache(&mut self, graphics: &Graphics) -> Result<()> {
        if !self.cache_dirty && self.cache.is_some() {
            return Ok(());
        }
        let dpi = 96.0 * self.monitor.scale;
        unsafe {
            if self.cache.is_none() {
                let properties = D2D1_BITMAP_PROPERTIES1 {
                    pixelFormat: D2D1_PIXEL_FORMAT { format: DXGI_FORMAT_B8G8R8A8_UNORM, alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED },
                    dpiX: dpi,
                    dpiY: dpi,
                    bitmapOptions: D2D1_BITMAP_OPTIONS_TARGET,
                    ..Default::default()
                };
                let size = D2D_SIZE_U { width: self.surface.width, height: self.surface.height };
                self.cache = Some(graphics.context.CreateBitmap(size, None, 0, &properties)?);
            }
            let context = &graphics.context;
            let Some(cache) = self.cache.as_ref() else { return Ok(()) };
            context.SetTarget(cache);
            context.SetDpi(dpi, dpi);
            context.BeginDraw();
            context.Clear(Some(&D2D1_COLOR_F { r: 0.0, g: 0.0, b: 0.0, a: 0.0 }));
            let drawn = self.marks().all().iter().try_for_each(|mark| graphics.draw_mark(mark));
            context.EndDraw(None, None)?;
            context.SetTarget(None);
            drawn?;
        }
        self.cache_dirty = false;
        Ok(())
    }

    pub fn render(&mut self, graphics: &Graphics, scene: &Scene) -> Result<()> {
        self.refresh_cache(graphics)?;
        let size = (self.surface.width as f32 / self.monitor.scale, self.surface.height as f32 / self.monitor.scale);
        let whole = D2D_RECT_F { left: 0.0, top: 0.0, right: size.0, bottom: size.1 };
        let (board, cache, live, pointer) = (self.board, self.cache.clone(), self.live.clone(), self.pointer);
        let trail = self.trail.visible(scene.now);
        self.surface.frame(graphics, self.monitor.scale, |graphics| unsafe {
            let context = &graphics.context;
            if let Some(board) = board {
                let color = if board == Board::White { "#FFFFFF" } else { "#000000" };
                context.FillRectangle(&whole, &graphics.brush(color, 1.0)?);
            }
            if let Some(cache) = &cache {
                context.DrawBitmap(cache, None, 1.0, D2D1_INTERPOLATION_MODE_NEAREST_NEIGHBOR, None, None);
            }
            if let Some(live) = &live {
                graphics.draw_mark(live)?;
            }
            match scene.effect {
                Some(Tool::Spotlight) => {
                    // Everything dimmed but a circle round the pointer; a monitor without the
                    // pointer is dimmed whole, so the eye goes to the one that has it.
                    let dim = graphics.brush("#000000", 0.6)?;
                    let area: ID2D1Geometry = graphics.factory.CreateRectangleGeometry(&whole)?.into();
                    let mut parts = vec![Some(area)];
                    if let Some(at) = pointer {
                        let radius = scene.spotlight_radius;
                        let hole = D2D1_ELLIPSE { point: point(at), radiusX: radius, radiusY: radius };
                        parts.push(Some(graphics.factory.CreateEllipseGeometry(&hole)?.into()));
                    }
                    let group = graphics.factory.CreateGeometryGroup(D2D1_FILL_MODE_ALTERNATE, &parts)?;
                    context.FillGeometry(&group, &dim, None);
                }
                Some(Tool::Laser) => {
                    let count = trail.len().max(1) as f32;
                    for (index, pair) in trail.windows(2).enumerate() {
                        let fade = pair[1].1;
                        let width = 2.0 + 4.0 * fade * (index + 1) as f32 / count;
                        context.DrawLine(point(pair[0].0), point(pair[1].0), &graphics.brush("#FF2A1F", 0.25 * fade)?, width * 3.0, &graphics.round);
                        context.DrawLine(point(pair[0].0), point(pair[1].0), &graphics.brush("#FF2A1F", fade)?, width, &graphics.round);
                    }
                    if let Some(at) = pointer {
                        let glow = D2D1_ELLIPSE { point: point(at), radiusX: 14.0, radiusY: 14.0 };
                        context.FillEllipse(&glow, &graphics.brush("#FF2A1F", 0.25)?);
                        let dot = D2D1_ELLIPSE { point: point(at), radiusX: 8.0, radiusY: 8.0 };
                        context.FillEllipse(&dot, &graphics.brush("#FF2A1F", 1.0)?);
                        let core = D2D1_ELLIPSE { point: point(at), radiusX: 3.0, radiusY: 3.0 };
                        context.FillEllipse(&core, &graphics.brush("#FFFFFF", 0.9)?);
                    }
                }
                Some(Tool::Zoom) => {
                    // The ring round the lens window, which shows the magnified screen inside it.
                    if let Some(at) = pointer {
                        let ring = D2D1_ELLIPSE { point: point(at), radiusX: Lens::RADIUS + 2.0, radiusY: Lens::RADIUS + 2.0 };
                        context.DrawEllipse(&ring, &graphics.brush("#FFFFFF", 1.0)?, 3.0, &graphics.round);
                    }
                }
                _ => {}
            }
            Ok(())
        })
    }
}
