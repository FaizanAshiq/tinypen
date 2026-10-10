use serde::{Deserialize, Serialize};

/// What the pointer does in drawing mode. The first four leave marks; the rest follow the
/// pointer and keep nothing.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Tool {
    Pen,
    Highlighter,
    Arrow,
    Box,
    Laser,
    Spotlight,
    Zoom,
}

impl Tool {
    pub const ALL: [Tool; 7] = [Tool::Pen, Tool::Highlighter, Tool::Arrow, Tool::Box, Tool::Laser, Tool::Spotlight, Tool::Zoom];

    /// The letter that picks it in drawing mode.
    pub fn key(self) -> char {
        match self {
            Tool::Pen => 'p',
            Tool::Highlighter => 'h',
            Tool::Arrow => 'a',
            Tool::Box => 'r',
            Tool::Laser => 'l',
            Tool::Spotlight => 's',
            Tool::Zoom => 'z',
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Tool::Pen => "Pen",
            Tool::Highlighter => "Highlighter",
            Tool::Arrow => "Arrow",
            Tool::Box => "Box",
            Tool::Laser => "Laser",
            Tool::Spotlight => "Spotlight",
            Tool::Zoom => "Zoom",
        }
    }

    pub fn draws_marks(self) -> bool {
        matches!(self, Tool::Pen | Tool::Highlighter | Tool::Arrow | Tool::Box)
    }

    pub fn for_key(key: char) -> Option<Tool> {
        let key = key.to_ascii_lowercase();
        Tool::ALL.into_iter().find(|tool| tool.key() == key)
    }
}

/// The toolbar's colours, picked with 1 to 6.
pub struct Palette;

impl Palette {
    pub const COLORS: [&'static str; 6] = ["#FF3B30", "#FFCC00", "#34C759", "#007AFF", "#FFFFFF", "#000000"];
    pub const NAMES: [&'static str; 6] = ["Red", "Yellow", "Green", "Blue", "White", "Black"];

    /// Red, green and blue from 0 to 1 for "#RRGGBB", or red for anything else.
    pub fn rgb(hex: &str) -> (f32, f32, f32) {
        let digits = hex.strip_prefix('#').unwrap_or(hex);
        match (digits.len(), u32::from_str_radix(digits, 16)) {
            (6, Ok(value)) => (
                ((value >> 16) & 0xFF) as f32 / 255.0,
                ((value >> 8) & 0xFF) as f32 / 255.0,
                (value & 0xFF) as f32 / 255.0,
            ),
            _ => (1.0, 59.0 / 255.0, 48.0 / 255.0),
        }
    }
}

/// The five widths, in device-independent pixels, stepped with [ and ].
pub const WIDTHS: [f32; 5] = [2.0, 4.0, 6.0, 10.0, 16.0];

/// A highlighter is as wide as a marker pen, whatever size the pen is at.
pub fn highlighter_width(width: f32) -> f32 {
    (width * 3.0).max(14.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_tool_has_its_own_letter() {
        assert_eq!(Tool::for_key('R'), Some(Tool::Box));
        assert_eq!(Tool::for_key('z'), Some(Tool::Zoom));
        assert_eq!(Tool::for_key('q'), None);
    }

    #[test]
    fn colours_read_from_hex_and_fall_back_to_red() {
        assert_eq!(Palette::rgb("#007AFF"), (0.0, 122.0 / 255.0, 1.0));
        assert_eq!(Palette::rgb("green"), (1.0, 59.0 / 255.0, 48.0 / 255.0));
    }
}
