# Tinypen

Draw on the live screen while you present, teach or share your screen: pen, highlighter, arrows
and boxes, a laser pointer, a spotlight, a zoom lens and a white or black board. Free, with
nothing to sign up for and nothing collected.

| | Mac | Windows |
| --- | --- | --- |
| Start drawing | ⌥⇧D | Ctrl+Shift+D |
| Stop drawing, marks kept | the same hotkey | the same hotkey |
| Erase what is drawn | Esc | Esc |
| Switch every tool off | Esc, with nothing drawn | Esc, with nothing drawn |

While drawing: P pen, H highlighter, A arrow, R box, L laser, S spotlight, Z zoom, W board,
1 to 6 colours, [ and ] size, undo with Command Z or Ctrl+Z, Delete clears. Hold Option (Alt on
Windows) and scroll to size the spotlight or the zoom lens. The toolbar's colour button also takes any colour or a hex code, and
keeps the last three you picked. Drag the toolbar by its edge to move it; it stays where you drop it.

Only the pen, highlighter, arrow and box take the mouse. Scrolling while drawing scrolls the page
under the drawing, moving or not; half a second after you stop, the next click draws again. The laser, spotlight and zoom let every
click through to the app underneath, whether switched on by their hotkey or from the toolbar.

## Download

From the [latest release](https://github.com/FaizanAshiq/tinypen/releases/latest):

| | |
| --- | --- |
| **Mac**, macOS 14 or later | `Tinypen-mac.zip`. Open it and drag Tinypen into Applications. The first time, macOS says it cannot check it for malware, as it does for any app not signed with a paid Apple developer account: open System Settings, Privacy & Security, and click Open Anyway. Zoom asks for Screen Recording the first time you use it. |
| **Windows** 10 or 11 | `Tinypen-win-x64.exe`, or `Tinypen-win-arm64.exe` on an ARM PC. Run it and it waits in the tray, by the clock. If SmartScreen warns about an unknown publisher, click More info, then Run anyway. |

Every copy then keeps itself up to date. Once a week Tinypen asks GitHub whether a newer version
is out; nothing about you or your drawings goes with the question. It downloads the new version,
checks it (on a Mac, that it is signed exactly as itself; on Windows, against the checksum GitHub
gives), and installs it the first moment nothing is on screen, starting again quietly, so no
message ever comes up over your slides. Keep it where it can change itself: Applications on a Mac,
any folder of your own on Windows. Anywhere else, its menu names the new version to download.

## Building

**Mac** (macOS 14 or later, Swift 6):

```
cd mac
./test.sh
./build.sh        # dist/Tinypen.app
```

**Windows** (Windows 10 or 11, Rust stable with the MSVC toolchain):

```
cd windows
cargo test -p tinypen-core
cargo build --release   # target\release\tinypen.exe
```

## Licence

MIT
