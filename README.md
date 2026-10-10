# Tinypen

Draw on the live screen while you present, teach or share your screen: pen, highlighter, arrows
and boxes, a laser pointer, a spotlight, a zoom lens and a white or black board. Free, with
nothing to sign up for and nothing collected.

| | Mac | Windows |
| --- | --- | --- |
| Start drawing | ⌥⇧D | Ctrl+Shift+D |
| Stop drawing, marks kept | the same hotkey | the same hotkey |
| Clear and stop | Esc | Esc |

While drawing: P pen, H highlighter, A arrow, R box, L laser, S spotlight, Z zoom, W board,
1 to 6 colours, [ and ] size, undo with Command Z or Ctrl+Z, Delete clears.

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
