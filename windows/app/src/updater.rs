//! Keeps Tinypen up to date. Once a week it asks GitHub for the latest release. Where it can write
//! beside itself, it downloads the app for this processor, checks it against the SHA-256 GitHub gives
//! for it, and installs it the first minute nothing of Tinypen's shows and nothing drawn would be
//! lost: the new file takes this one's place and starts, and this copy quits. It says nothing while
//! it does, as a message must never come up over someone's slides. A copy that cannot write beside
//! itself names the new version in its menu.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::mpsc::{channel, Receiver};
use std::time::{SystemTime, UNIX_EPOCH};
use tinypen_core::update::{self, HOUR};
use tinypen_core::{NewRelease, Preferences};
use windows::core::{w, HSTRING, PCWSTR};
use windows::Win32::Foundation::{CloseHandle, HWND, LPARAM, WPARAM};
use windows::Win32::Networking::WinHttp::*;
use windows::Win32::Security::Cryptography::{BCryptHash, BCRYPT_SHA256_ALG_HANDLE};
use windows::Win32::System::SystemInformation::GetLocalTime;
use windows::Win32::System::Threading::{OpenProcess, WaitForSingleObject, PROCESS_SYNCHRONIZE};
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::{KillTimer, PostMessageW, SetTimer, SW_SHOWNORMAL, WM_APP};

/// Sent by the look, made on a thread of its own, once it has an answer.
pub const LOOKED: u32 = WM_APP + 4;
/// The timer that checks whether a look is due, and whether a downloaded update can install.
pub const TIMER: usize = 4;

const LATEST: &str = "https://api.github.com/repos/FaizanAshiq/tinypen/releases/latest";
const ASSET: &str = if cfg!(target_arch = "aarch64") { "Tinypen-win-arm64.exe" } else { "Tinypen-win-x64.exe" };
const CURRENT: &str = env!("CARGO_PKG_VERSION");
/// Where updates come from instead of GitHub: a folder holding `latest.json`, shaped as GitHub's
/// answer, so the end-to-end test can update to a build of its own.
const FEED: &str = "TINYPEN_UPDATE_FEED";
/// Given to the new copy, with this one's process id, so it waits for this one to quit.
const AFTER: &str = "--after";
/// Seconds after a start to the first look, when one is due.
const FIRST: u64 = 10;
/// Seconds between tries to install, while something shows.
const RETRY: u64 = 60;

enum Outcome {
    /// Downloaded and checked, beside the app: this version.
    Ready(String),
    /// Newer, and not installed by this copy.
    Available(String),
    Nothing,
}

pub struct Updater {
    window: HWND,
    stamp: PathBuf,
    /// When the last look was, in seconds since 1970.
    last: u64,
    looking: Option<Receiver<Outcome>>,
    /// The version downloaded and checked, waiting to install.
    ready: Option<String>,
    /// The newer version, when this copy does not install it itself, for the menu.
    pub available: Option<String>,
}

impl Updater {
    /// `downloaded`: an update was waiting from before, which `clear_away` removed, so the next look
    /// comes at once rather than a week on.
    pub fn new(window: HWND, downloaded: bool) -> Updater {
        let stamp = Preferences::default_path().with_file_name("last-update-check");
        let last = if downloaded { 0 } else { std::fs::read_to_string(&stamp).ok().and_then(|text| text.trim().parse().ok()).unwrap_or(0) };
        let updater = Updater { window, stamp, last, looking: None, ready: None, available: None };
        updater.schedule(update::wait(last, now()).max(FIRST));
        updater
    }

    fn schedule(&self, seconds: u64) {
        unsafe {
            SetTimer(Some(self.window), TIMER, (seconds * 1000) as u32, None);
        }
    }

    /// Installs a downloaded update when nothing would be lost, and otherwise looks once a week is up.
    /// True when Tinypen should quit, for the new version to start.
    pub fn tick(&mut self, idle: bool) -> bool {
        unsafe {
            let _ = KillTimer(Some(self.window), TIMER);
        }
        if let Some(version) = &self.ready {
            if idle && install(version) {
                return true;
            }
            self.schedule(if idle { HOUR } else { RETRY });
            return false;
        }
        // A look underway schedules the next check when it answers.
        if self.looking.is_some() {
            return false;
        }
        let wait = update::wait(self.last, now());
        if wait > 0 {
            self.schedule(wait);
            return false;
        }
        self.last = now();
        if let Some(folder) = self.stamp.parent() {
            let _ = std::fs::create_dir_all(folder);
        }
        let _ = std::fs::write(&self.stamp, self.last.to_string());
        let (sender, receiver) = channel();
        self.looking = Some(receiver);
        let window = self.window.0 as isize;
        std::thread::spawn(move || {
            let _ = sender.send(look());
            unsafe {
                let _ = PostMessageW(Some(HWND(window as _)), LOOKED, WPARAM(0), LPARAM(0));
            }
        });
        false
    }

    pub fn looked(&mut self) {
        let Some(outcome) = self.looking.take().and_then(|receiver| receiver.try_recv().ok()) else { return };
        match outcome {
            Outcome::Ready(version) => self.ready = Some(version),
            Outcome::Available(version) => self.available = Some(version),
            Outcome::Nothing => {}
        }
        self.schedule(if self.ready.is_some() { 1 } else { HOUR });
    }

    /// The new version's release page, to download it from.
    pub fn open_download(&self) {
        let Some(version) = &self.available else { return };
        let page = HSTRING::from(format!("https://github.com/FaizanAshiq/tinypen/releases/tag/v{version}"));
        unsafe {
            ShellExecuteW(None, w!("open"), &page, None, None, SW_SHOWNORMAL);
        }
    }
}

/// Started by the copy it replaced, it waits for that one to quit, as only one Tinypen runs.
pub fn wait_for_replaced() {
    let mut arguments = std::env::args().skip(1);
    if arguments.next().as_deref() == Some(AFTER)
        && let Some(id) = arguments.next().and_then(|id| id.parse().ok()) {
            unsafe {
                if let Ok(process) = OpenProcess(PROCESS_SYNCHRONIZE, false, id) {
                    WaitForSingleObject(process, 10_000);
                    let _ = CloseHandle(process);
                }
            }
        }
}

/// What an update leaves beside the app goes, once this is the copy that runs: the copy replaced,
/// and a download never installed, as when Tinypen quit first. True when there was such a download.
pub fn clear_away() -> bool {
    let Ok(exe) = std::env::current_exe() else { return false };
    let _ = std::fs::remove_file(beside(&exe, ".old"));
    std::fs::remove_file(beside(&exe, ".update")).is_ok()
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |since| since.as_secs())
}

/// `Tinypen.exe.old` for `.old`: beside the app, so a rename never crosses drives.
fn beside(exe: &Path, suffix: &str) -> PathBuf {
    let mut name = exe.as_os_str().to_owned();
    name.push(suffix);
    PathBuf::from(name)
}

/// On its own thread: GitHub's answer, and the app for this processor downloaded and checked
/// beside this one when it is newer. Never panics, as a panic ends Tinypen.
fn look() -> Outcome {
    let feed = std::env::var_os(FEED).map(PathBuf::from);
    let answer = match &feed {
        Some(folder) => std::fs::read(folder.join("latest.json")).ok(),
        None => fetch(LATEST),
    };
    // Offline, or GitHub refusing: the next look tries again.
    let Some(release) = answer
        .and_then(|bytes| String::from_utf8(bytes).ok())
        .and_then(|answer| NewRelease::newer(&answer, CURRENT, ASSET)) else { return Outcome::Nothing };
    let version = release.version;
    let available = Outcome::Available(version.clone());
    let (Some(download), Ok(exe)) = (release.download, std::env::current_exe()) else { return available };
    // A test feed names a file on this PC; GitHub's answer only addresses on the web.
    let bytes = if download.url.starts_with("https://") {
        fetch(&download.url)
    } else if feed.is_some() {
        std::fs::read(&download.url).ok()
    } else {
        None
    };
    let Some(bytes) = bytes.filter(|bytes| sha256(bytes) == download.sha256) else { return available };
    // A folder this account cannot write to, as Program Files: the menu names the version instead.
    match std::fs::write(beside(&exe, ".update"), &bytes) {
        Ok(()) => Outcome::Ready(version),
        Err(_) => available,
    }
}

fn sha256(bytes: &[u8]) -> String {
    let mut digest = [0u8; 32];
    if unsafe { BCryptHash(BCRYPT_SHA256_ALG_HANDLE, None, bytes, &mut digest) }.is_err() {
        return String::new();
    }
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

/// What an HTTPS address holds, after the redirects GitHub's downloads take; None unless it
/// answers 200.
fn fetch(url: &str) -> Option<Vec<u8>> {
    let (host, path) = url.strip_prefix("https://")?.split_once('/')?;
    unsafe {
        let session = WinHttpOpen(w!("Tinypen"), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, PCWSTR::null(), PCWSTR::null(), 0);
        if session.is_null() {
            return None;
        }
        let _ = WinHttpSetTimeouts(session, 10_000, 10_000, 30_000, 30_000);
        let connect = WinHttpConnect(session, &HSTRING::from(host), INTERNET_DEFAULT_HTTPS_PORT, 0);
        let mut body = None;
        if !connect.is_null() {
            let request = WinHttpOpenRequest(connect, w!("GET"), &HSTRING::from(format!("/{path}")), PCWSTR::null(),
                                             PCWSTR::null(), std::ptr::null(), WINHTTP_FLAG_SECURE);
            if !request.is_null() {
                body = read(request);
                let _ = WinHttpCloseHandle(request);
            }
            let _ = WinHttpCloseHandle(connect);
        }
        let _ = WinHttpCloseHandle(session);
        body
    }
}

unsafe fn read(request: *mut core::ffi::c_void) -> Option<Vec<u8>> {
    unsafe {
        WinHttpSendRequest(request, None, None, 0, 0, 0).ok()?;
        WinHttpReceiveResponse(request, std::ptr::null_mut()).ok()?;
        let mut status = 0u32;
        let mut length = size_of::<u32>() as u32;
        WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, PCWSTR::null(),
                            Some(&mut status as *mut u32 as *mut _), &mut length, std::ptr::null_mut()).ok()?;
        if status != 200 {
            return None;
        }
        let mut body = Vec::new();
        let mut chunk = vec![0u8; 64 * 1024];
        loop {
            let mut read = 0u32;
            WinHttpReadData(request, chunk.as_mut_ptr() as *mut _, chunk.len() as u32, &mut read).ok()?;
            if read == 0 {
                return Some(body);
            }
            body.extend_from_slice(&chunk[..read as usize]);
        }
    }
}

/// The downloaded update takes this copy's place and starts, to wait for this one to quit. False
/// when Windows refused a step, with everything put back as it was.
fn install(version: &str) -> bool {
    let Ok(exe) = std::env::current_exe() else { return false };
    let marker = updated_marker_path();
    let _ = std::fs::write(&marker, update::updated_marker(version, &today()));
    let (update, old) = (beside(&exe, ".update"), beside(&exe, ".old"));
    let _ = std::fs::remove_file(&old);
    // Windows lets a running program be renamed, though not replaced.
    if std::fs::rename(&exe, &old).is_err() {
        let _ = std::fs::remove_file(&marker);
        return false;
    }
    if std::fs::rename(&update, &exe).is_err() {
        let _ = std::fs::rename(&old, &exe);
        let _ = std::fs::remove_file(&marker);
        return false;
    }
    if Command::new(&exe).arg(AFTER).arg(std::process::id().to_string()).spawn().is_err() {
        let _ = std::fs::rename(&exe, &update);
        let _ = std::fs::rename(&old, &exe);
        let _ = std::fs::remove_file(&marker);
        return false;
    }
    true
}

/// The version installed and the day, written just before the new version takes over, so its
/// menu says so for the rest of that day.
fn updated_marker_path() -> PathBuf {
    Preferences::default_path().with_file_name("updated-to")
}

/// "Updated to Tinypen X" for the menu, the day this version took over.
pub fn updated_line() -> Option<String> {
    let marker = std::fs::read_to_string(updated_marker_path()).ok();
    update::updated_line(marker.as_deref(), CURRENT, &today())
}

/// Today in local time, as yyyy-mm-dd.
fn today() -> String {
    let now = unsafe { GetLocalTime() };
    format!("{:04}-{:02}-{:02}", now.wYear, now.wMonth, now.wDay)
}
