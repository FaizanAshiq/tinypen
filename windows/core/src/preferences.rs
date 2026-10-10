use crate::screen::ToolbarSpot;
use crate::tool::{Palette, Tool, WIDTHS};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::path::{Path, PathBuf};

// RegisterHotKey's modifier flags.
pub const MOD_ALT: u32 = 0x1;
pub const MOD_CONTROL: u32 = 0x2;
pub const MOD_SHIFT: u32 = 0x4;
pub const MOD_WIN: u32 = 0x8;

/// A Windows virtual key code and the modifiers held with it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct HotKey {
    #[serde(rename = "keyCode")]
    pub key_code: u32,
    /// `MOD_ALT`, `MOD_CONTROL`, `MOD_SHIFT` and `MOD_WIN`, or'd together.
    pub modifiers: u32,
}

impl HotKey {
    /// The way Windows writes a shortcut, as Ctrl+Shift+D.
    pub fn display(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        for (flag, name) in [(MOD_CONTROL, "Ctrl"), (MOD_ALT, "Alt"), (MOD_SHIFT, "Shift"), (MOD_WIN, "Win")] {
            if self.modifiers & flag != 0 {
                parts.push(name.into());
            }
        }
        parts.push(match self.key_code {
            0x30..=0x39 | 0x41..=0x5A => char::from_u32(self.key_code).map(String::from).unwrap_or_default(),
            0x70..=0x87 => format!("F{}", self.key_code - 0x6F),
            code => format!("Key {code}"),
        });
        parts.join("+")
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HotKeyAction {
    Draw,
    Laser,
    Spotlight,
    Zoom,
}

impl HotKeyAction {
    pub const ALL: [HotKeyAction; 4] = [HotKeyAction::Draw, HotKeyAction::Laser, HotKeyAction::Spotlight, HotKeyAction::Zoom];

    pub fn title(self) -> &'static str {
        match self {
            HotKeyAction::Draw => "Draw",
            HotKeyAction::Laser => "Laser Pointer",
            HotKeyAction::Spotlight => "Spotlight",
            HotKeyAction::Zoom => "Zoom",
        }
    }

    fn key(self) -> &'static str {
        match self {
            HotKeyAction::Draw => "draw",
            HotKeyAction::Laser => "laser",
            HotKeyAction::Spotlight => "spotlight",
            HotKeyAction::Zoom => "zoom",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HotKeys {
    pub draw: Option<HotKey>,
    pub laser: Option<HotKey>,
    pub spotlight: Option<HotKey>,
    pub zoom: Option<HotKey>,
}

impl HotKeys {
    /// Only drawing mode has a default: Ctrl+Shift with S, Z or L is Save As, Redo or a filter in
    /// most Windows apps. In drawing mode L, S and Z work anyway.
    pub const DEFAULTS: HotKeys = HotKeys {
        draw: Some(HotKey { key_code: 0x44, modifiers: MOD_CONTROL | MOD_SHIFT }),
        laser: None,
        spotlight: None,
        zoom: None,
    };

    pub fn get(&self, action: HotKeyAction) -> Option<HotKey> {
        match action {
            HotKeyAction::Draw => self.draw,
            HotKeyAction::Laser => self.laser,
            HotKeyAction::Spotlight => self.spotlight,
            HotKeyAction::Zoom => self.zoom,
        }
    }

    fn set(&mut self, action: HotKeyAction, key: Option<HotKey>) {
        match action {
            HotKeyAction::Draw => self.draw = key,
            HotKeyAction::Laser => self.laser = key,
            HotKeyAction::Spotlight => self.spotlight = key,
            HotKeyAction::Zoom => self.zoom = key,
        }
    }
}

/// Everything Tinypen remembers, in one small file. Nothing else is written anywhere.
#[derive(Clone, Debug, PartialEq)]
pub struct Preferences {
    pub hotkeys: HotKeys,
    pub color: String,
    /// Index into `WIDTHS`.
    pub size: usize,
    /// The marking tool in hand when drawing mode starts.
    pub tool: Tool,
    pub show_tray_icon: bool,
    /// Custom colours picked lately, newest first, shown beside the six.
    pub recent_colors: Vec<String>,
    /// Where the toolbar was dragged to; None for the top in the middle.
    pub toolbar_spot: Option<ToolbarSpot>,
}

impl Default for Preferences {
    fn default() -> Self {
        Preferences {
            hotkeys: HotKeys::DEFAULTS,
            color: Palette::COLORS[0].into(),
            size: 1,
            tool: Tool::Pen,
            show_tray_icon: true,
            recent_colors: Vec::new(),
            toolbar_spot: None,
        }
    }
}

impl Preferences {
    /// `%APPDATA%\Tinypen\preferences.json`.
    pub fn default_path() -> PathBuf {
        let base = std::env::var_os("APPDATA").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
        base.join("Tinypen").join("preferences.json")
    }

    pub fn width(&self) -> f32 {
        WIDTHS[self.size.min(WIDTHS.len() - 1)]
    }

    /// Defaults for a missing or damaged file, and for each field one leaves out: Tinypen always
    /// starts. A hotkey written as null stays cleared.
    pub fn load(path: &Path) -> Preferences {
        let Ok(text) = std::fs::read_to_string(path) else { return Preferences::default() };
        let Ok(Value::Object(object)) = serde_json::from_str::<Value>(&text) else { return Preferences::default() };
        Self::from_object(&object)
    }

    fn from_object(object: &Map<String, Value>) -> Preferences {
        let defaults = Preferences::default();
        let mut hotkeys = defaults.hotkeys;
        if let Some(Value::Object(keys)) = object.get("hotkeys") {
            for action in HotKeyAction::ALL {
                match keys.get(action.key()) {
                    None => {}
                    Some(Value::Null) => hotkeys.set(action, None),
                    Some(value) => {
                        if let Ok(key) = serde_json::from_value::<HotKey>(value.clone()) {
                            hotkeys.set(action, Some(key));
                        }
                    }
                }
            }
        }
        let color = object
            .get("color")
            .and_then(Value::as_str)
            .filter(|hex| hex.starts_with('#'))
            .and_then(Palette::hex_typed)
            .unwrap_or(defaults.color);
        let size = object.get("size").and_then(Value::as_u64).map_or(defaults.size, |size| (size as usize).min(WIDTHS.len() - 1));
        let tool = object
            .get("tool")
            .and_then(|value| serde_json::from_value::<Tool>(value.clone()).ok())
            .filter(|tool| tool.draws_marks())
            .unwrap_or(defaults.tool);
        let show_tray_icon = object.get("showTrayIcon").and_then(Value::as_bool).unwrap_or(defaults.show_tray_icon);
        let recent_colors = match object.get("recentColors") {
            Some(Value::Array(list)) => {
                list.iter().filter_map(Value::as_str).filter_map(Palette::hex_typed).take(Palette::RECENT_COUNT).collect()
            }
            _ => Vec::new(),
        };
        let toolbar_spot = object.get("toolbarSpot").and_then(|value| serde_json::from_value::<ToolbarSpot>(value.clone()).ok());
        Preferences { hotkeys, color, size, tool, show_tray_icon, recent_colors, toolbar_spot }
    }

    /// Written to a file beside it first, then moved over, so a crash mid write never leaves half a file.
    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(folder) = path.parent() {
            std::fs::create_dir_all(folder)?;
        }
        let mut keys = Map::new();
        for action in HotKeyAction::ALL {
            keys.insert(action.key().into(), serde_json::to_value(self.hotkeys.get(action)).unwrap_or(Value::Null));
        }
        let mut object = Map::new();
        object.insert("hotkeys".into(), Value::Object(keys));
        object.insert("color".into(), Value::String(self.color.clone()));
        object.insert("size".into(), Value::from(self.size));
        object.insert("tool".into(), serde_json::to_value(self.tool).unwrap_or(Value::Null));
        object.insert("showTrayIcon".into(), Value::Bool(self.show_tray_icon));
        object.insert("recentColors".into(), Value::from(self.recent_colors.clone()));
        if let Some(spot) = self.toolbar_spot {
            object.insert("toolbarSpot".into(), serde_json::to_value(spot).unwrap_or(Value::Null));
        }
        let text = serde_json::to_string_pretty(&Value::Object(object)).unwrap_or_default();
        let temporary = path.with_extension("json.new");
        std::fs::write(&temporary, text)?;
        std::fs::rename(temporary, path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(name: &str) -> PathBuf {
        let folder = std::env::temp_dir().join(format!("tinypen-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        folder.join("preferences.json")
    }

    #[test]
    fn the_default_is_ctrl_shift_d_for_drawing_and_nothing_else() {
        assert_eq!(HotKeys::DEFAULTS.draw.unwrap().display(), "Ctrl+Shift+D");
        assert!(HotKeys::DEFAULTS.laser.is_none() && HotKeys::DEFAULTS.zoom.is_none());
    }

    #[test]
    fn no_file_means_defaults() {
        assert_eq!(Preferences::load(&file("none")), Preferences::default());
    }

    #[test]
    fn a_damaged_file_means_defaults() {
        let path = file("damaged");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, "{ not json").unwrap();
        assert_eq!(Preferences::load(&path), Preferences::default());
    }

    #[test]
    fn what_is_saved_comes_back() {
        let path = file("saved");
        let preferences = Preferences {
            color: "#007AFF".into(),
            size: 4,
            tool: Tool::Highlighter,
            hotkeys: HotKeys {
                draw: None,
                zoom: Some(HotKey { key_code: 0x5A, modifiers: MOD_CONTROL | MOD_ALT }),
                ..HotKeys::DEFAULTS
            },
            ..Preferences::default()
        };
        preferences.save(&path).unwrap();
        assert_eq!(Preferences::load(&path), preferences);
    }

    #[test]
    fn missing_fields_take_their_defaults_and_null_stays_cleared() {
        let path = file("partial");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, r#"{"size": 1, "hotkeys": {"draw": null}, "unknown": true}"#).unwrap();
        let loaded = Preferences::load(&path);
        assert_eq!(loaded.size, 1);
        assert_eq!(loaded.color, Preferences::default().color);
        assert!(loaded.hotkeys.draw.is_none());
    }

    #[test]
    fn recent_colours_are_saved_and_an_older_file_has_none() {
        let path = file("recent");
        let preferences = Preferences { color: "#1E90FF".into(), recent_colors: vec!["#1E90FF".into()], ..Preferences::default() };
        preferences.save(&path).unwrap();
        assert_eq!(Preferences::load(&path), preferences);
        std::fs::write(&path, r##"{"size": 1, "recentColors": ["#00ff00", "green", "#000001", "#000002", "#000003"]}"##).unwrap();
        assert_eq!(Preferences::load(&path).recent_colors, vec!["#00FF00", "#000001", "#000002"]);
        std::fs::write(&path, r#"{"size": 1}"#).unwrap();
        assert!(Preferences::load(&path).recent_colors.is_empty());
    }

    #[test]
    fn a_toolbar_spot_is_saved_and_an_older_file_has_none() {
        let path = file("spot");
        let preferences = Preferences { toolbar_spot: Some(ToolbarSpot::new(0.25, 0.75)), ..Preferences::default() };
        preferences.save(&path).unwrap();
        assert_eq!(Preferences::load(&path), preferences);
        std::fs::write(&path, r#"{"size": 1, "toolbarSpot": {"x": 7, "y": -2}}"#).unwrap();
        assert_eq!(Preferences::load(&path).toolbar_spot, Some(ToolbarSpot::new(1.0, 0.0)));
        std::fs::write(&path, r#"{"size": 1}"#).unwrap();
        assert_eq!(Preferences::load(&path).toolbar_spot, None);
    }

    #[test]
    fn a_size_out_of_range_is_brought_in() {
        let path = file("size");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, r#"{"size": 40}"#).unwrap();
        assert_eq!(Preferences::load(&path).size, WIDTHS.len() - 1);
    }
}
