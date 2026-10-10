//! Tinypen's tools, marks, shapes, the laser's fade, the lens and the settings: everything that
//! can be tested without a window, the same as the Mac app's core.

mod canvas;
mod geometry;
mod marks;
mod preferences;
mod screen;
mod tool;

pub use canvas::{Board, Canvas};
pub use geometry::{arrow_outline, smooth, Lens, LaserTrail, Point, Rect, Spotlight};
pub use marks::{Drag, Mark, MarkKind, Marks, StrokeBuilder};
pub use screen::{HeldKeys, Screen, ToolbarSpot};
pub use preferences::{HotKey, HotKeyAction, HotKeys, Preferences, MOD_ALT, MOD_CONTROL, MOD_SHIFT, MOD_WIN};
pub use tool::{highlighter_width, Palette, Tool, WIDTHS};
