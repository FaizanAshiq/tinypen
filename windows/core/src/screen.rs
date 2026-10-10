//! What Tinypen shows and what follows from it, the same as the Mac app: which clicks the layer
//! takes and which keys Tinypen holds.

use crate::tool::Tool;

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
}
