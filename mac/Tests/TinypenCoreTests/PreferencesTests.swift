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
