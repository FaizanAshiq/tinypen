import Foundation
import Testing
@testable import TinypenCore

/// Any colour, typed or picked, and the custom ones picked lately kept beside the six.
struct ColorTests {
    @Test func sixDigitsWithOrWithoutTheHashAreTaken() {
        #expect(Palette.hex(typed: "1e90ff") == "#1E90FF")
        #expect(Palette.hex(typed: " #FF3B30 ") == "#FF3B30")
    }

    @Test func anythingElseIsNot() {
        #expect(Palette.hex(typed: "blue") == nil)
        #expect(Palette.hex(typed: "#12345") == nil)
        #expect(Palette.hex(typed: "") == nil)
    }

    @Test func aColourFromThePanelBecomesSixDigits() {
        #expect(Palette.hex(red: 30 / 255, green: 144 / 255, blue: 1) == "#1E90FF")
        #expect(Palette.hex(red: -0.2, green: 0, blue: 1.3) == "#0000FF")
    }

    @Test func aCustomColourGoesFirstAndOneOfTheSixIsLeftOut() {
        #expect(Palette.recent(adding: "#1e90ff", to: []) == ["#1E90FF"])
        #expect(Palette.recent(adding: "#FF3B30", to: ["#1E90FF"]) == ["#1E90FF"])
    }

    @Test func aColourPickedAgainMovesToTheFrontOnce() {
        #expect(Palette.recent(adding: "#1E90FF", to: ["#00FF00", "#1E90FF"]) == ["#1E90FF", "#00FF00"])
    }

    @Test func onlyTheLastThreeAreKept() {
        #expect(Palette.recent(adding: "#000004", to: ["#000001", "#000002", "#000003"]) == ["#000004", "#000001", "#000002"])
    }

    @Test func recentColoursAreSavedAndAnOlderFileHasNone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tinypen-\(UUID().uuidString)/preferences.json")
        var preferences = Preferences.defaults
        preferences.recentColors = ["#1E90FF"]
        preferences.colorHex = "#1E90FF"
        try preferences.save(to: url)
        #expect(Preferences.load(from: url).recentColors == ["#1E90FF"])
        #expect(Preferences.load(from: url).colorHex == "#1E90FF")
        try Data(#"{"size": 1}"#.utf8).write(to: url)
        #expect(Preferences.load(from: url).recentColors == [])
    }
}
