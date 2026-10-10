// No console window behind the app.
#![cfg_attr(windows, windows_subsystem = "windows")]

#[cfg(windows)]
mod app;
#[cfg(windows)]
mod graphics;
#[cfg(windows)]
mod icons;
#[cfg(windows)]
mod lens;
#[cfg(windows)]
mod overlay;
#[cfg(windows)]
mod picker;
#[cfg(windows)]
mod system;
#[cfg(windows)]
mod tips;
#[cfg(windows)]
mod toolbar;
#[cfg(windows)]
mod tray;

fn main() {
    #[cfg(windows)]
    app::run();
    #[cfg(not(windows))]
    eprintln!("This is Tinypen for Windows. On a Mac, build the app in ../mac.");
}
