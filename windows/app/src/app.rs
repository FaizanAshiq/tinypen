//! The whole app: drawing mode, the tool in hand, the pointer effect, every monitor's layer, the
//! toolbar, the lens, the tray icon and the hotkeys, on one thread.

use crate::graphics::Graphics;
use crate::icons::Button;
use crate::lens::{LensWindow, LENS_CLASS};
use crate::overlay::{Overlay, Scene, OVERLAY_CLASS};
use crate::picker::{Item, Picker, PICKER_CLASS};
use crate::system::{self, Monitor};
use crate::toolbar::{Look, Toolbar, TOOLBAR_CLASS};
use crate::tray::{self, Entry, Tray, TRAY_MESSAGE};
use std::cell::RefCell;
use std::path::PathBuf;
use std::time::{Instant, SystemTime};
use tinypen_core::{HeldKeys, HotKeyAction, Lens, Palette, Preferences, Screen, Spotlight, Tool, ToolbarSpot, WIDTHS};
use windows::core::{w, Result, PCWSTR};
use windows::Win32::Foundation::{COLORREF, HGLOBAL, HINSTANCE, HWND, LPARAM, LRESULT, POINT, WPARAM};
use windows::Win32::System::DataExchange::{CloseClipboard, GetClipboardData, OpenClipboard};
use windows::Win32::System::Diagnostics::Debug::MessageBeep;
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Memory::{GlobalLock, GlobalUnlock};
use windows::Win32::UI::Controls::Dialogs::*;
use windows::Win32::UI::HiDpi::{SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2};
use windows::Win32::UI::Input::KeyboardAndMouse::*;
use windows::Win32::UI::WindowsAndMessaging::*;

const MESSAGE_CLASS: PCWSTR = w!("TinypenMessage");
/// Sent by a second copy of Tinypen, started while this one runs.
const OPENED_AGAIN: u32 = WM_APP + 2;
/// The monitors changed: the layers are rebuilt once the message that said so is done.
const REBUILD: u32 = WM_APP + 3;
const TICK: usize = 1;
// The mouse message flags for the left button and Shift.
const MK_LBUTTON: usize = 0x1;
const MK_SHIFT: usize = 0x4;
const CF_UNICODETEXT: u32 = 13;
const SETTINGS_CHECK: usize = 2;
/// The first hotkey id of the keys Tinypen holds while it shows something, after the four actions.
const HELD: i32 = 100;

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

pub fn run() {
    if !system::first_copy() {
        unsafe {
            if let Ok(window) = FindWindowW(MESSAGE_CLASS, None) {
                let _ = PostMessageW(Some(window), OPENED_AGAIN, WPARAM(0), LPARAM(0));
            }
        }
        return;
    }
    unsafe {
        let _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        let instance: HINSTANCE = GetModuleHandleW(None).map(Into::into).unwrap_or_default();
        for class in [MESSAGE_CLASS, OVERLAY_CLASS, TOOLBAR_CLASS, PICKER_CLASS, LENS_CLASS] {
            let description = WNDCLASSEXW {
                cbSize: size_of::<WNDCLASSEXW>() as u32,
                lpfnWndProc: Some(window_proc),
                hInstance: instance,
                hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
                lpszClassName: class,
                ..Default::default()
            };
            RegisterClassExW(&description);
        }
        match App::new(instance) {
            Ok(app) => APP.with(|cell| *cell.borrow_mut() = Some(app)),
            Err(error) => {
                let text = windows::core::HSTRING::from(format!("Tinypen could not start: {error}"));
                MessageBoxW(None, &text, w!("Tinypen"), MB_ICONERROR);
                return;
            }
        }
        let mut message = MSG::default();
        while GetMessageW(&mut message, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        APP.with(|cell| cell.borrow_mut().take());
    }
}

/// Every window's messages. Windows can call this again while a handler runs, as when one shows a
/// window; the app is busy then, and the message gets Windows' own handling.
unsafe extern "system" fn window_proc(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    let handled = APP.with(|cell| match cell.try_borrow_mut() {
        Ok(mut app) => app.as_mut().and_then(|app| app.handle(window, message, wparam, lparam)),
        Err(_) => None,
    });
    handled.unwrap_or_else(|| unsafe { DefWindowProcW(window, message, wparam, lparam) })
}

struct App {
    instance: HINSTANCE,
    graphics: Graphics,
    preferences: Preferences,
    path: PathBuf,
    stamp: Option<SystemTime>,
    window: HWND,
    overlays: Vec<Overlay>,
    toolbar: Toolbar,
    picker: Picker,
    lens: Option<LensWindow>,
    tray: Tray,
    drawing: bool,
    effect: Option<Tool>,
    spotlight_radius: f32,
    magnification: f32,
    /// The monitors drawn on, in order, so undo takes back the newest mark wherever it is.
    history: Vec<isize>,
    last_was_clear: bool,
    previous: Option<HWND>,
    taken: Vec<HotKeyAction>,
    /// The keys held as hotkeys now, and each one's modifiers and virtual key, by id from `HELD`.
    holding: HeldKeys,
    held: Vec<(HOT_KEY_MODIFIERS, u16)>,
    clock: Instant,
    ticking: bool,
}

impl App {
    fn new(instance: HINSTANCE) -> Result<App> {
        let path = Preferences::default_path();
        let preferences = Preferences::load(&path);
        if !path.exists() {
            let _ = preferences.save(&path);
        }
        unsafe {
            let window = CreateWindowExW(WINDOW_EX_STYLE(0), MESSAGE_CLASS, w!("Tinypen"), WS_POPUP, 0, 0, 0, 0, None, None,
                                         Some(instance), None)?;
            let graphics = Graphics::new()?;
            let toolbar = Toolbar::new(instance)?;
            let picker = Picker::new(instance)?;
            let tray = Tray::new(window);
            let mut app = App {
                instance,
                graphics,
                stamp: modified(&path),
                preferences,
                path,
                window,
                overlays: Vec::new(),
                toolbar,
                picker,
                lens: None,
                tray,
                drawing: false,
                effect: None,
                spotlight_radius: Spotlight::RADIUS,
                magnification: 2.0,
                history: Vec::new(),
                last_was_clear: false,
                previous: None,
                taken: Vec::new(),
                holding: HeldKeys::None,
                held: Vec::new(),
                clock: Instant::now(),
                ticking: false,
            };
            app.rebuild_overlays();
            app.register_hotkeys();
            app.tray.set_shown(app.preferences.show_tray_icon);
            SetTimer(Some(window), SETTINGS_CHECK, 2000, None);
            Ok(app)
        }
    }

    fn now(&self) -> f64 {
        self.clock.elapsed().as_secs_f64()
    }

    fn has_marks(&self) -> bool {
        self.overlays.iter().any(|overlay| !overlay.is_empty())
    }

    /// A layer for every monitor, kept for those still there, so a monitor plugged in or out mid
    /// talk gets or loses its own.
    fn rebuild_overlays(&mut self) {
        let monitors = system::monitors();
        let kept: Vec<Overlay> = std::mem::take(&mut self.overlays)
            .into_iter()
            .filter_map(|overlay| {
                if monitors.contains(&overlay.monitor) {
                    Some(overlay)
                } else {
                    overlay.destroy();
                    None
                }
            })
            .collect();
        self.overlays = kept;
        for monitor in monitors {
            if !self.overlays.iter().any(|overlay| overlay.monitor == monitor)
                && let Ok(overlay) = Overlay::new(&self.graphics, self.instance, monitor) {
                    self.overlays.push(overlay);
                }
        }
        self.refresh();
    }

    fn register_hotkeys(&mut self) {
        self.taken.clear();
        for (index, action) in HotKeyAction::ALL.into_iter().enumerate() {
            let id = index as i32 + 1;
            unsafe {
                let _ = UnregisterHotKey(Some(self.window), id);
                if let Some(key) = self.preferences.hotkeys.get(action) {
                    let modifiers = HOT_KEY_MODIFIERS(key.modifiers) | MOD_NOREPEAT;
                    if RegisterHotKey(Some(self.window), id, modifiers, key.key_code).is_err() {
                        self.taken.push(action);
                    }
                }
            }
        }
    }

    /// Takes in a settings file changed by hand since it was read.
    fn reload_if_changed(&mut self) {
        let stamp = modified(&self.path);
        if stamp == self.stamp {
            return;
        }
        self.stamp = stamp;
        self.preferences = Preferences::load(&self.path);
        self.register_hotkeys();
        self.tray.set_shown(self.preferences.show_tray_icon);
        self.refresh();
    }

    fn save(&mut self) {
        let _ = self.preferences.save(&self.path);
        self.stamp = modified(&self.path);
    }

    fn monitor_under_pointer(&self) -> Option<Monitor> {
        let mut at = POINT::default();
        unsafe { GetCursorPos(&mut at).ok()? };
        self.overlays
            .iter()
            .map(|overlay| overlay.monitor)
            .find(|monitor| at.x >= monitor.rect.left && at.x < monitor.rect.right && at.y >= monitor.rect.top && at.y < monitor.rect.bottom)
            .or_else(|| self.overlays.first().map(|overlay| overlay.monitor))
    }

    // Modes

    fn toggle_drawing(&mut self) {
        if self.drawing { self.stop_drawing() } else { self.start_drawing() }
    }

    fn screen(&self) -> Screen {
        Screen { drawing: self.drawing, effect: self.effect, has_marks: self.has_marks(), picking_color: self.picker.shown }
    }

    /// Holds the keys Tinypen needs as hotkeys while it shows something, so they reach it whichever
    /// app is in front and never that app, as the Mac app does; lets them go when it shows nothing.
    fn hold_keys(&mut self) {
        let holding = self.screen().held_keys();
        if holding == self.holding {
            return;
        }
        for id in 0..self.held.len() {
            unsafe {
                let _ = UnregisterHotKey(Some(self.window), HELD + id as i32);
            }
        }
        let none = HOT_KEY_MODIFIERS(0);
        let mut keys = Vec::new();
        if holding != HeldKeys::None {
            keys.push((none, VK_ESCAPE.0));
        }
        if matches!(holding, HeldKeys::EscapeAndSize | HeldKeys::All) {
            keys.extend([(none, VK_OEM_4.0), (none, VK_OEM_6.0)]);
        }
        if holding == HeldKeys::All {
            keys.extend([(none, VK_DELETE.0), (none, VK_BACK.0), (MOD_CONTROL, 0x5A), (none, 0x57)]);
            keys.extend(Tool::ALL.iter().map(|tool| (none, tool.key().to_ascii_uppercase() as u16)));
            keys.extend((0x31..=0x36).map(|code| (none, code)));
        }
        self.held.clear();
        for (modifiers, key) in keys {
            let id = HELD + self.held.len() as i32;
            // A key another app holds already is left to the drawing layer.
            if unsafe { RegisterHotKey(Some(self.window), id, modifiers, key as u32) }.is_ok() {
                self.held.push((modifiers, key));
            }
        }
        self.holding = holding;
    }

    fn start_drawing(&mut self) {
        self.drawing = true;
        self.previous = Some(unsafe { GetForegroundWindow() });
        self.refresh();
        if let Some(monitor) = self.monitor_under_pointer() {
            if let Some(overlay) = self.overlays.iter().find(|overlay| overlay.monitor == monitor) {
                unsafe {
                    let _ = SetForegroundWindow(overlay.hwnd);
                    let _ = SetFocus(Some(overlay.hwnd));
                }
            }
            let _ = self.toolbar.show(&self.graphics, &monitor, self.preferences.toolbar_spot);
            self.render_toolbar();
        }
    }

    /// The marks stay and every click goes back to the apps under them, and the keys to the app
    /// that had them.
    fn stop_drawing(&mut self) {
        self.close_picker();
        self.finish_strokes();
        self.drawing = false;
        self.toolbar.hide();
        self.refresh();
        if let Some(previous) = self.previous.take() {
            unsafe {
                if IsWindow(Some(previous)).as_bool() {
                    let _ = SetForegroundWindow(previous);
                }
            }
        }
    }

    /// Esc: with anything drawn, it erases it all, whatever tool is in hand, and undo brings it back;
    /// with nothing drawn, it switches every tool off: the laser, spotlight or lens, and drawing mode.
    /// An open colour picker goes first, as Esc puts away anything open.
    fn escape(&mut self) {
        if self.picker.shown {
            self.close_picker();
            return;
        }
        self.finish_strokes();
        if self.has_marks() {
            self.overlays.iter_mut().for_each(Overlay::erase);
            self.last_was_clear = true;
            self.refresh();
            return;
        }
        self.effect = None;
        if self.drawing { self.stop_drawing() } else { self.refresh() }
    }

    /// Any stroke still being drawn becomes a mark, as when the button comes up.
    fn finish_strokes(&mut self) {
        for overlay in &mut self.overlays {
            if overlay.finish_stroke() {
                self.history.push(overlay.monitor.handle);
                self.last_was_clear = false;
            }
        }
    }

    /// The toolbar's done button: every mark and board gone, the effect off, and drawing mode left.
    fn leave(&mut self) {
        self.overlays.iter_mut().for_each(Overlay::reset);
        self.history.clear();
        self.last_was_clear = false;
        self.effect = None;
        self.stop_drawing();
    }

    fn toggle_effect(&mut self, tool: Tool) {
        self.effect = if self.effect == Some(tool) { None } else { Some(tool) };
        self.refresh();
    }

    fn pick(&mut self, tool: Tool) {
        if tool.draws_marks() {
            self.effect = None;
            self.preferences.tool = tool;
            self.save();
        } else {
            self.effect = if self.effect == Some(tool) { None } else { Some(tool) };
        }
        self.refresh();
    }

    fn clear_all(&mut self) {
        if !self.has_marks() {
            return;
        }
        self.overlays.iter_mut().for_each(Overlay::clear);
        self.last_was_clear = true;
        self.refresh();
    }

    fn undo(&mut self) {
        if self.last_was_clear {
            self.overlays.iter_mut().for_each(Overlay::undo);
            self.last_was_clear = false;
        } else if let Some(handle) = self.history.pop()
            && let Some(overlay) = self.overlays.iter_mut().find(|overlay| overlay.monitor.handle == handle) {
                overlay.undo();
            }
        self.refresh();
    }

    fn cycle_board(&mut self) {
        if let Some(monitor) = self.monitor_under_pointer()
            && let Some(overlay) = self.overlays.iter_mut().find(|overlay| overlay.monitor == monitor) {
                overlay.cycle_board();
            }
        self.refresh();
    }

    fn pick_color(&mut self, index: usize) {
        if let Some(color) = Palette::COLORS.get(index) {
            self.set_color((*color).into());
        }
    }

    fn set_color(&mut self, hex: String) {
        self.preferences.color = hex;
        self.save();
        self.render_toolbar();
    }

    fn pick_size(&mut self, size: usize) {
        self.preferences.size = size.min(WIDTHS.len() - 1);
        self.save();
        self.render_toolbar();
    }

    /// [ and ]: while the spotlight or the lens is on, the spotlight grows by 20 pixels a step and the
    /// lens zooms, as the wheel did before the wheel reached the app under them; otherwise the pen.
    fn step_size(&mut self, step: i32) {
        match self.effect {
            Some(Tool::Spotlight) => self.spotlight_radius = Spotlight::radius(self.spotlight_radius, step as f32 * 20.0),
            Some(Tool::Zoom) => self.magnification = Lens::magnification(self.magnification, step as f32),
            _ => return self.pick_size((self.preferences.size as i32 + step).max(0) as usize),
        }
        self.tick();
    }

    // The colour picker

    fn toggle_picker(&mut self) {
        if self.picker.shown {
            self.close_picker();
            return;
        }
        let Some((button, scale)) = self.toolbar.color_button() else { return };
        if self.picker.show(&self.graphics, button, scale, &self.preferences.recent_colors).is_ok() {
            // The hex field may want the keys, so only Esc stays held, to put the picker away.
            self.hold_keys();
            self.render_toolbar();
        }
    }

    /// Put away, with a custom colour picked kept beside the six.
    fn close_picker(&mut self) {
        if !self.picker.shown {
            return;
        }
        self.picker.hide();
        self.hold_keys();
        let recent = Palette::recent(&self.preferences.color, &self.preferences.recent_colors);
        if recent != self.preferences.recent_colors {
            self.preferences.recent_colors = recent;
            self.save();
        }
    }

    /// A colour picked is a finished choice, and puts the picker away.
    fn picked(&mut self, hex: String) {
        self.set_color(hex);
        self.close_picker();
    }

    /// Windows' colour dialog, raised over the drawing layer, or it would open under it out of reach.
    fn choose_color(&mut self) {
        let colorref = |hex: &str| {
            let (r, g, b) = Palette::rgb(hex);
            let byte = |value: f32| (value * 255.0).round() as u32;
            COLORREF(byte(r) | byte(g) << 8 | byte(b) << 16)
        };
        let mut custom = [COLORREF(0x00FF_FFFF); 16];
        for (slot, hex) in custom.iter_mut().zip(&self.preferences.recent_colors) {
            *slot = colorref(hex);
        }
        let mut choose = CHOOSECOLORW {
            lStructSize: size_of::<CHOOSECOLORW>() as u32,
            hwndOwner: unsafe { GetForegroundWindow() },
            rgbResult: colorref(&self.preferences.color),
            lpCustColors: custom.as_mut_ptr(),
            Flags: CC_RGBINIT | CC_FULLOPEN | CC_ANYCOLOR | CC_ENABLEHOOK,
            lpfnHook: Some(raise_dialog),
            ..Default::default()
        };
        if unsafe { ChooseColorW(&mut choose) }.as_bool() {
            let value = choose.rgbResult.0;
            self.picked(format!("#{:02X}{:02X}{:02X}", value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF));
        }
    }

    /// The hex field's keys, while it takes them: digits and A to F, Backspace, Return, and Ctrl+V.
    fn hex_key(&mut self, key: VIRTUAL_KEY, control: bool) {
        match key {
            VK_RETURN => match self.picker.typed_color() {
                Some(hex) => return self.picked(hex),
                None => unsafe {
                    let _ = MessageBeep(MB_OK);
                },
            },
            VK_BACK | VK_DELETE => self.picker.backspace(),
            VIRTUAL_KEY(0x56) if control => {
                if !self.picker.paste(&clipboard_text()) {
                    unsafe {
                        let _ = MessageBeep(MB_OK);
                    }
                }
            }
            _ if control => return,
            VIRTUAL_KEY(code @ (0x30..=0x39 | 0x41..=0x46)) => self.picker.type_digit(char::from(code as u8)),
            VIRTUAL_KEY(code @ 0x60..=0x69) => self.picker.type_digit(char::from(b'0' + (code - 0x60) as u8)),
            _ => return,
        }
        let _ = self.picker.render(&self.graphics, &self.preferences.color);
    }

    /// Let go after a drag: kept wholly on the monitor it was dropped on, and remembered for next time.
    fn toolbar_dropped(&mut self) {
        let Some(frame) = self.toolbar.end_drag() else { return };
        let (cx, cy) = ((frame.x + frame.width / 2.0) as i32, (frame.y + frame.height / 2.0) as i32);
        let Some(monitor) = self.overlays.iter().map(|overlay| overlay.monitor).find(|monitor| {
            cx >= monitor.rect.left && cx < monitor.rect.right && cy >= monitor.rect.top && cy < monitor.rect.bottom
        }) else { return };
        let spot = ToolbarSpot::of(frame, crate::toolbar::rect(monitor.work));
        self.preferences.toolbar_spot = Some(spot);
        self.save();
        let _ = self.toolbar.show(&self.graphics, &monitor, Some(spot));
        self.render_toolbar();
    }

    fn toolbar_button(&mut self, button: Option<Button>) {
        match button {
            Some(Button::Tool(tool)) => self.pick(tool),
            Some(Button::Board) => self.cycle_board(),
            Some(Button::Color) => self.toggle_picker(),
            Some(Button::Size(size)) => self.pick_size(size),
            Some(Button::Undo) => self.undo(),
            Some(Button::Clear) => self.clear_all(),
            Some(Button::Done) => self.leave(),
            None => {}
        }
    }

    fn handle_picker(&mut self, message: u32, lparam: LPARAM) -> Option<LRESULT> {
        let (x, y) = (lparam.0 as i16 as i32, (lparam.0 >> 16) as i16 as i32);
        match message {
            WM_LBUTTONDOWN => match self.picker.hit(x, y) {
                Some(Item::Swatch(hex)) => self.picked(hex),
                Some(Item::Wheel) => self.choose_color(),
                Some(Item::Hex) => {
                    self.picker.editing = true;
                    let _ = self.picker.render(&self.graphics, &self.preferences.color);
                }
                None => {}
            },
            WM_MOUSEMOVE => {
                if self.picker.hover(x, y) {
                    let _ = self.picker.render(&self.graphics, &self.preferences.color);
                }
            }
            WM_MOUSEACTIVATE => return Some(LRESULT(MA_NOACTIVATE as isize)),
            _ => return None,
        }
        Some(LRESULT(0))
    }

    /// Every layer shown or hidden, taking the mouse or not, and the keys held, as the mode now says,
    /// and drawn.
    fn refresh(&mut self) {
        let visible = self.drawing || self.effect.is_some() || self.has_marks();
        let takes_clicks = self.screen().takes_clicks();
        self.hold_keys();
        for overlay in &mut self.overlays {
            overlay.take_clicks(takes_clicks);
            overlay.show(visible);
        }
        if self.drawing {
            self.toolbar.raise();
        }
        if self.effect == Some(Tool::Zoom) {
            if self.lens.is_none() {
                self.lens = LensWindow::new(self.instance).ok();
            }
            let mut hide: Vec<HWND> = self.overlays.iter().map(|overlay| overlay.hwnd).collect();
            hide.push(self.toolbar.hwnd);
            if let Some(lens) = &self.lens {
                lens.exclude(&hide);
            }
        } else if let Some(lens) = &self.lens {
            lens.hide();
        }
        let ticking = self.effect.is_some();
        if ticking != self.ticking {
            unsafe {
                if ticking {
                    SetTimer(Some(self.window), TICK, 16, None);
                } else {
                    let _ = KillTimer(Some(self.window), TICK);
                }
            }
            self.ticking = ticking;
        }
        self.render_all();
        self.render_toolbar();
    }

    fn scene(&self) -> Scene {
        Scene { effect: self.effect, spotlight_radius: self.spotlight_radius, now: self.now() }
    }

    fn render_all(&mut self) {
        let scene = self.scene();
        for overlay in &mut self.overlays {
            let _ = overlay.render(&self.graphics, &scene);
        }
    }

    fn render_toolbar(&self) {
        if !self.drawing {
            return;
        }
        let look = Look {
            chosen: self.effect.unwrap_or(self.preferences.tool),
            color: self.preferences.color.clone(),
            size: self.preferences.size,
            has_marks: self.has_marks(),
        };
        let _ = self.toolbar.render(&self.graphics, &look);
        let _ = self.picker.render(&self.graphics, &self.preferences.color);
    }

    /// Each frame while an effect is on: follow the pointer, fade the laser, move the lens.
    fn tick(&mut self) {
        let mut at = POINT::default();
        if unsafe { GetCursorPos(&mut at) }.is_err() {
            return;
        }
        let now = self.now();
        let scene = self.scene();
        for overlay in &mut self.overlays {
            let before = overlay.pointer;
            overlay.track_pointer(at.x, at.y, self.effect, now);
            let fading = overlay.is_fading(now);
            if overlay.pointer != before || fading || self.effect == Some(Tool::Spotlight) {
                let _ = overlay.render(&self.graphics, &scene);
            }
        }
        if self.effect == Some(Tool::Zoom) {
            let scale = self
                .overlays
                .iter()
                .find(|overlay| overlay.pointer.is_some())
                .map_or(1.0, |overlay| overlay.monitor.scale);
            if let Some(lens) = &mut self.lens {
                lens.place((at.x, at.y), scale, self.magnification);
            }
        }
    }

    // Input

    fn handle(&mut self, window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
        if window == self.window {
            return self.handle_app(message, wparam, lparam);
        }
        if window == self.toolbar.hwnd {
            return self.handle_toolbar(message, lparam);
        }
        if window == self.picker.hwnd {
            return self.handle_picker(message, lparam);
        }
        let index = self.overlays.iter().position(|overlay| overlay.hwnd == window)?;
        self.handle_overlay(index, message, wparam, lparam)
    }

    fn handle_app(&mut self, message: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
        match message {
            WM_HOTKEY if wparam.0 >= HELD as usize => {
                if let Some(&(_, key)) = self.held.get(wparam.0 - HELD as usize) {
                    self.key(key);
                }
            }
            WM_HOTKEY => {
                self.reload_if_changed();
                match HotKeyAction::ALL.get(wparam.0.wrapping_sub(1)) {
                    Some(HotKeyAction::Draw) => self.toggle_drawing(),
                    Some(HotKeyAction::Laser) => self.toggle_effect(Tool::Laser),
                    Some(HotKeyAction::Spotlight) => self.toggle_effect(Tool::Spotlight),
                    Some(HotKeyAction::Zoom) => self.toggle_effect(Tool::Zoom),
                    None => {}
                }
            }
            WM_TIMER if wparam.0 == TICK => self.tick(),
            WM_TIMER if wparam.0 == SETTINGS_CHECK => self.reload_if_changed(),
            TRAY_MESSAGE => match lparam.0 as u32 {
                WM_LBUTTONUP => self.toggle_drawing(),
                WM_RBUTTONUP | WM_CONTEXTMENU => self.show_menu(),
                _ => {}
            },
            OPENED_AGAIN => system::open_in_notepad(&self.path),
            REBUILD | WM_DISPLAYCHANGE => self.rebuild_overlays(),
            _ => return None,
        }
        Some(LRESULT(0))
    }

    fn show_menu(&mut self) {
        self.reload_if_changed();
        let line = |command, action: HotKeyAction, checked| {
            let mut title = action.title().to_string();
            if let Some(key) = self.preferences.hotkeys.get(action) {
                title += &format!("\t{}", key.display());
                if self.taken.contains(&action) {
                    title += " (taken)";
                }
            }
            Some(Entry { command, title, checked, enabled: true })
        };
        let entries = [
            line(tray::DRAW, HotKeyAction::Draw, self.drawing),
            line(tray::LASER, HotKeyAction::Laser, self.effect == Some(Tool::Laser)),
            line(tray::SPOTLIGHT, HotKeyAction::Spotlight, self.effect == Some(Tool::Spotlight)),
            line(tray::ZOOM, HotKeyAction::Zoom, self.effect == Some(Tool::Zoom)),
            None,
            Some(Entry { command: tray::CLEAR, title: "Clear Drawings".into(), checked: false, enabled: self.has_marks() }),
            None,
            Some(Entry { command: tray::OPEN_AT_LOGIN, title: "Open Tinypen when you sign in".into(), checked: system::opens_at_login(), enabled: true }),
            Some(Entry { command: tray::SETTINGS, title: "Edit Settings...".into(), checked: false, enabled: true }),
            None,
            Some(Entry { command: tray::QUIT, title: "Quit Tinypen".into(), checked: false, enabled: true }),
        ];
        match self.tray.menu(&entries) {
            Ok(Some(tray::DRAW)) => self.toggle_drawing(),
            Ok(Some(tray::LASER)) => self.toggle_effect(Tool::Laser),
            Ok(Some(tray::SPOTLIGHT)) => self.toggle_effect(Tool::Spotlight),
            Ok(Some(tray::ZOOM)) => self.toggle_effect(Tool::Zoom),
            Ok(Some(tray::CLEAR)) => self.clear_all(),
            Ok(Some(tray::OPEN_AT_LOGIN)) => {
                if !system::set_opens_at_login(!system::opens_at_login()) {
                    unsafe {
                        MessageBoxW(None, w!("Windows did not change whether Tinypen opens when you sign in."), w!("Tinypen"), MB_ICONWARNING);
                    }
                }
            }
            Ok(Some(tray::SETTINGS)) => system::open_in_notepad(&self.path),
            Ok(Some(tray::QUIT)) => unsafe { PostQuitMessage(0) },
            _ => {}
        }
    }

    fn handle_toolbar(&mut self, message: u32, lparam: LPARAM) -> Option<LRESULT> {
        let (x, y) = (lparam.0 as i16 as i32, (lparam.0 >> 16) as i16 as i32);
        match message {
            WM_LBUTTONDOWN => {
                let hit = self.toolbar.hit(x, y);
                // Any other button puts the colour picker away, as a click on the drawing layer does.
                if hit != Some(Button::Color) {
                    self.close_picker();
                }
                match hit {
                    Some(_) => self.toolbar_button(hit),
                    None => self.toolbar.begin_drag(),
                }
            }
            WM_MOUSEMOVE => {
                if !self.toolbar.drag() && self.toolbar.hover(x, y) {
                    self.render_toolbar();
                }
            }
            WM_LBUTTONUP | WM_CAPTURECHANGED => self.toolbar_dropped(),
            WM_MOUSEACTIVATE => return Some(LRESULT(MA_NOACTIVATE as isize)),
            _ => return None,
        }
        Some(LRESULT(0))
    }

    fn handle_overlay(&mut self, index: usize, message: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
        let (x, y) = (lparam.0 as i16 as i32, (lparam.0 >> 16) as i16 as i32);
        let shift = wparam.0 & MK_SHIFT != 0;
        let tool = self.preferences.tool;
        let marking = self.drawing && self.effect.is_none();
        match message {
            // The click that puts the colour picker away draws nothing.
            WM_LBUTTONDOWN if self.picker.shown => self.close_picker(),
            WM_LBUTTONDOWN if marking => {
                let overlay = &mut self.overlays[index];
                let at = overlay.local(x, y);
                overlay.press(at, tool, shift, &self.preferences);
                unsafe {
                    SetCapture(overlay.hwnd);
                }
                let scene = self.scene();
                let _ = self.overlays[index].render(&self.graphics, &scene);
            }
            WM_MOUSEMOVE if marking && wparam.0 & MK_LBUTTON != 0 => {
                let overlay = &mut self.overlays[index];
                let at = overlay.local(x, y);
                overlay.drag(at, tool, shift, &self.preferences);
                let scene = self.scene();
                let _ = self.overlays[index].render(&self.graphics, &scene);
            }
            WM_LBUTTONUP => {
                unsafe {
                    let _ = ReleaseCapture();
                }
                let overlay = &mut self.overlays[index];
                let at = overlay.local(x, y);
                if overlay.release(at, tool, shift, &self.preferences) {
                    self.history.push(overlay.monitor.handle);
                    self.last_was_clear = false;
                }
                let scene = self.scene();
                let _ = self.overlays[index].render(&self.graphics, &scene);
                self.render_toolbar();
            }
            WM_DPICHANGED | WM_DISPLAYCHANGE => unsafe {
                let _ = PostMessageW(Some(self.window), REBUILD, WPARAM(0), LPARAM(0));
            },
            WM_SETCURSOR if self.drawing => unsafe {
                SetCursor(LoadCursorW(None, IDC_CROSS).ok());
                return Some(LRESULT(1));
            },
            WM_KEYDOWN => {
                if !self.key(wparam.0 as u16) {
                    return None;
                }
            }
            _ => return None,
        }
        Some(LRESULT(0))
    }

    /// The keys of drawing mode. False for one it does not use.
    fn key(&mut self, key: u16) -> bool {
        let control = unsafe { GetKeyState(VK_CONTROL.0 as i32) } < 0;
        // Typing a code: every key but Esc goes to the field, so no letter switches the tool.
        if self.picker.editing && VIRTUAL_KEY(key) != VK_ESCAPE {
            self.hex_key(VIRTUAL_KEY(key), control);
            return true;
        }
        match VIRTUAL_KEY(key) {
            VK_ESCAPE => self.escape(),
            VK_DELETE | VK_BACK => self.clear_all(),
            VK_OEM_4 => self.step_size(-1),
            VK_OEM_6 => self.step_size(1),
            VIRTUAL_KEY(0x5A) if control => self.undo(),
            _ if control => return false,
            VIRTUAL_KEY(0x57) => self.cycle_board(),
            VIRTUAL_KEY(code @ 0x31..=0x36) => self.pick_color((code - 0x31) as usize),
            VIRTUAL_KEY(code @ 0x41..=0x5A) => match Tool::for_key(char::from(code as u8)) {
                Some(tool) => self.pick(tool),
                None => return false,
            },
            _ => return false,
        }
        true
    }
}

/// Raises Windows' colour dialog over the drawing layer as it opens.
unsafe extern "system" fn raise_dialog(dialog: HWND, message: u32, _: WPARAM, _: LPARAM) -> usize {
    if message == WM_INITDIALOG {
        unsafe {
            let _ = SetWindowPos(dialog, Some(HWND_TOPMOST), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
        }
    }
    0
}

/// The text on the clipboard, or nothing.
fn clipboard_text() -> String {
    unsafe {
        if OpenClipboard(None).is_err() {
            return String::new();
        }
        let mut text = String::new();
        if let Ok(handle) = GetClipboardData(CF_UNICODETEXT) {
            let memory = HGLOBAL(handle.0);
            let start = GlobalLock(memory) as *const u16;
            if !start.is_null() {
                let mut length = 0;
                while *start.add(length) != 0 {
                    length += 1;
                }
                text = String::from_utf16_lossy(std::slice::from_raw_parts(start, length));
                let _ = GlobalUnlock(memory);
            }
        }
        let _ = CloseClipboard();
        text
    }
}

fn modified(path: &std::path::Path) -> Option<SystemTime> {
    std::fs::metadata(path).and_then(|metadata| metadata.modified()).ok()
}
