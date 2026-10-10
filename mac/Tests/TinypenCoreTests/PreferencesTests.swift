import Foundation
import Testing
@testable import TinypenCore

struct PreferencesTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tinypen-\(UUID().uuidString)/preferences.json")
    }

    @Test func theDefaultsAreOptionShiftWithTheToolsLetter() {
        let keys = Preferences.defaults.hotkeys
        #expect(keys.draw?.displayString == "⌥⇧D")
        #expect(keys.laser?.displayString == "⌥⇧L")
        #expect(keys.spotlight?.displayString == "⌥⇧S")
        #expect(keys.zoom?.displayString == "⌥⇧Z")
    }

    /// The menu lines shortcuts up on the right, as macOS does, from the key's own character.
    @Test func aMenuShowsTheKeysCharacter() {
        #expect(Preferences.defaults.hotkeys.draw?.menuCharacter == "d")
        #expect(HotKeyBinding(keyCode: 18, modifiers: [.command]).menuCharacter == "1")
        #expect(HotKeyBinding(keyCode: 36, modifiers: [.command]).menuCharacter == nil)
    }

    /// A hotkey is held in every app. Found testing: Settings took Shift or Command alone, so a Draw
    /// hotkey of Shift A swallowed every capital A, and Command C every copy.
    @Test func aHotkeyNeedsControlOrOptionOrCommandWithAnother() {
        #expect(HotKeyBinding(keyCode: 2, modifiers: [.option, .shift]).isAllowed)
        #expect(HotKeyBinding(keyCode: 2, modifiers: [.control]).isAllowed)
        #expect(HotKeyBinding(keyCode: 2, modifiers: [.command, .shift]).isAllowed)
        #expect(!HotKeyBinding(keyCode: 0, modifiers: [.shift]).isAllowed)
        #expect(!HotKeyBinding(keyCode: 8, modifiers: [.command]).isAllowed)
        #expect(!HotKeyBinding(keyCode: 2, modifiers: []).isAllowed)
    }

    /// One written by hand that every app would lose a key to takes its default instead.
    @Test func aFileWithAHotkeyNoAppCouldSpareTakesTheDefault() throws {
        let url = file()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"hotkeys": {"draw": {"keyCode": 0, "modifiers": ["shift"]}, "laser": {"keyCode": 8, "modifiers": []}}}"#.utf8)
            .write(to: url)
        let keys = Preferences.load(from: url).hotkeys
        #expect(keys.draw == HotKeys.defaults.draw)
        #expect(keys.laser == HotKeys.defaults.laser)
    }

    @Test func noFileMeansDefaults() {
        #expect(Preferences.load(from: file()) == .defaults)
    }

    /// A damaged file starts Tinypen with defaults rather than stopping it.
    @Test func aDamagedFileMeansDefaults() throws {
        let url = file()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        #expect(Preferences.load(from: url) == .defaults)
    }

    @Test func whatIsSavedComesBack() throws {
        let url = file()
        var preferences = Preferences.defaults
        preferences.colorHex = "#007AFF"
        preferences.size = 4
        preferences.tool = .highlighter
        preferences.hotkeys.zoom = nil
        try preferences.save(to: url)
        #expect(Preferences.load(from: url) == preferences)
    }

    /// A file from an older Tinypen, or edited by hand, keeps what it has and takes defaults for
    /// the rest; a hotkey written as null stays cleared.
    @Test func missingFieldsTakeTheirDefaults() throws {
        let url = file()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"size": 1, "hotkeys": {"zoom": null}, "unknown": true}"#.utf8).write(to: url)
        let loaded = Preferences.load(from: url)
        #expect(loaded.size == 1)
        #expect(loaded.colorHex == Preferences.defaults.colorHex)
        #expect(loaded.hotkeys.zoom == nil)
        #expect(loaded.hotkeys.draw == Preferences.defaults.hotkeys.draw)
    }

    @Test func aSizeOutOfRangeIsBroughtIn() throws {
        let url = file()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"size": 40}"#.utf8).write(to: url)
        #expect(Preferences.load(from: url).size == Sizes.widths.count - 1)
    }
}
