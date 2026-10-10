//! What Tinypen shows and what follows from it, the same as the Mac app: which clicks the layer
//! takes, which keys Tinypen holds, and where the toolbar sits.

use crate::geometry::Rect;
use crate::tool::Tool;
use serde::{Deserialize, Serialize};

/// Which keys Tinypen holds while it shows something, so they reach it whichever app is in front.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HeldKeys {
    /// Nothing on screen: every key is the apps' own.
    None,
    /// Esc only: marks left on screen, the laser, or the colour picker, whose hex field wants the rest.
    Escape,
    /// Esc, and [ and ] to size the spotlight or the zoom lens.
    EscapeAndSize,
    /// Every key of drawing mode, as the layer takes the clicks and no other app is in reach.
    All,
}

/// What Tinypen shows, however a tool was switched on: from its hotkey, the tray menu or the toolbar.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct Screen {
    pub drawing: bool,
    /// The laser, the spotlight or the zoom lens; None for a marking tool, or none.
    pub effect: Option<Tool>,
    pub has_marks: bool,
    pub picking_color: bool,
}

impl Screen {
    /// Only a marking tool takes clicks. The laser, the spotlight and the zoom lens let every click
    /// through to the app under them, picked from the toolbar or switched on by their hotkeys alike.
    pub fn takes_clicks(&self) -> bool {
        self.drawing && self.effect.is_none()
    }

    pub fn held_keys(&self) -> HeldKeys {
        if self.takes_clicks() {
            return if self.picking_color { HeldKeys::Escape } else { HeldKeys::All };
        }
        if matches!(self.effect, Some(Tool::Spotlight | Tool::Zoom)) {
            return HeldKeys::EscapeAndSize;
        }
        if self.drawing || self.effect.is_some() || self.has_marks { HeldKeys::Escape } else { HeldKeys::None }
    }
}

/// Where the toolbar sits: its centre as a fraction of a monitor's work area, across from the left
/// and down from the top, so a spot picked on one monitor means the same place on another.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
#[serde(from = "RawSpot")]
pub struct ToolbarSpot {
    pub x: f32,
    pub y: f32,
}

#[derive(Deserialize)]
struct RawSpot {
    x: f32,
    y: f32,
}

impl From<RawSpot> for ToolbarSpot {
    fn from(raw: RawSpot) -> Self {
        ToolbarSpot::new(raw.x, raw.y)
    }
}

impl ToolbarSpot {
    pub fn new(x: f32, y: f32) -> ToolbarSpot {
        ToolbarSpot { x: x.clamp(0.0, 1.0), y: y.clamp(0.0, 1.0) }
    }

    /// The spot of a toolbar dropped at `frame` in `work`, y counting down.
    pub fn of(frame: Rect, work: Rect) -> ToolbarSpot {
        ToolbarSpot::new(
            (frame.x + frame.width / 2.0 - work.x) / work.width,
            (frame.y + frame.height / 2.0 - work.y) / work.height,
        )
    }

    /// The toolbar's frame in `work`, wholly inside it; without a spot, at the top in the middle,
    /// `gap` down.
    pub fn frame(width: f32, height: f32, work: Rect, spot: Option<ToolbarSpot>, gap: f32) -> Rect {
        let (cx, cy) = match spot {
            Some(spot) => (work.x + spot.x * work.width, work.y + spot.y * work.height),
            None => (work.x + work.width / 2.0, work.y + gap + height / 2.0),
        };
        let x = (cx - width / 2.0).min(work.x + work.width - width).max(work.x);
        let y = (cy - height / 2.0).min(work.y + work.height - height).max(work.y);
        Rect { x, y, width, height }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn screen(drawing: bool, effect: Option<Tool>) -> Screen {
        Screen { drawing, effect, ..Screen::default() }
    }

    #[test]
    fn only_a_marking_tool_takes_clicks() {
        assert!(screen(true, None).takes_clicks());
        for effect in [Tool::Laser, Tool::Spotlight, Tool::Zoom] {
            assert!(!screen(true, Some(effect)).takes_clicks());
            assert!(!screen(false, Some(effect)).takes_clicks());
        }
        assert!(!Screen { has_marks: true, ..Screen::default() }.takes_clicks());
    }

    #[test]
    fn a_marking_tool_holds_every_key_but_the_hex_fields_while_the_picker_is_open() {
        assert_eq!(screen(true, None).held_keys(), HeldKeys::All);
        assert_eq!(Screen { picking_color: true, ..screen(true, None) }.held_keys(), HeldKeys::Escape);
    }

    #[test]
    fn a_pointer_tool_holds_esc_and_its_size_keys() {
        assert_eq!(screen(true, Some(Tool::Spotlight)).held_keys(), HeldKeys::EscapeAndSize);
        assert_eq!(screen(false, Some(Tool::Zoom)).held_keys(), HeldKeys::EscapeAndSize);
        assert_eq!(screen(false, Some(Tool::Laser)).held_keys(), HeldKeys::Escape);
    }

    #[test]
    fn marks_left_on_screen_hold_esc_and_nothing_shown_holds_nothing() {
        assert_eq!(Screen { has_marks: true, ..Screen::default() }.held_keys(), HeldKeys::Escape);
        assert_eq!(Screen::default().held_keys(), HeldKeys::None);
    }

    const WORK: Rect = Rect { x: 0.0, y: 0.0, width: 1000.0, height: 800.0 };

    #[test]
    fn without_a_spot_it_sits_at_the_top_in_the_middle() {
        assert_eq!(ToolbarSpot::frame(600.0, 40.0, WORK, None, 12.0), Rect { x: 200.0, y: 12.0, width: 600.0, height: 40.0 });
    }

    #[test]
    fn a_spot_comes_back_where_it_was_dropped() {
        let dropped = Rect { x: 300.0, y: 660.0, width: 600.0, height: 40.0 };
        let spot = ToolbarSpot::of(dropped, WORK);
        assert_eq!(ToolbarSpot::frame(600.0, 40.0, WORK, Some(spot), 12.0), dropped);
    }

    #[test]
    fn it_stays_wholly_on_the_monitor_even_on_a_smaller_one() {
        let small = Rect { x: 1000.0, y: 0.0, width: 700.0, height: 500.0 };
        let frame = ToolbarSpot::frame(600.0, 40.0, small, Some(ToolbarSpot::new(0.95, 0.99)), 12.0);
        assert!(frame.x >= 1000.0 && frame.x + frame.width <= 1700.0 && frame.y >= 0.0 && frame.y + frame.height <= 500.0);
    }
}
