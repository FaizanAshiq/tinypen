import CoreGraphics
import Foundation
import Testing
@testable import TinypenCore

/// Which clicks and keys Tinypen takes for what it shows, the same however a tool was switched on.
struct ScreenTests {
    @Test func onlyAMarkingToolTakesClicks() {
        #expect(Screen(drawing: true, effect: nil).takesClicks)
        for effect in [Tool.laser, .spotlight, .zoom] {
            #expect(!Screen(drawing: true, effect: effect).takesClicks)
            #expect(!Screen(drawing: false, effect: effect).takesClicks)
        }
        #expect(!Screen(drawing: false, effect: nil, hasMarks: true).takesClicks)
    }

    @Test func aMarkingToolHoldsEveryKeyButTheHexFieldsWhileThePickerIsOpen() {
        #expect(Screen(drawing: true, effect: nil).heldKeys == .all)
        #expect(Screen(drawing: true, effect: nil, pickingColor: true).heldKeys == .escape)
    }

    /// Clicks pass through to other apps, so only the keys Tinypen needs are held, never letters.
    @Test func aPointerToolHoldsEscAndItsSizeKeys() {
        #expect(Screen(drawing: true, effect: .spotlight).heldKeys == .escapeAndSize)
        #expect(Screen(drawing: false, effect: .zoom).heldKeys == .escapeAndSize)
        #expect(Screen(drawing: false, effect: .laser).heldKeys == .escape)
    }

    @Test func marksLeftOnScreenHoldEscAndNothingShownHoldsNothing() {
        #expect(Screen(drawing: false, effect: nil, hasMarks: true).heldKeys == .escape)
        #expect(Screen(drawing: false, effect: nil).heldKeys == HeldKeys.none)
    }
}

/// Where the toolbar sits, kept as a place on any display.
struct ToolbarSpotTests {
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 600, height: 40)

    @Test func withoutASpotItSitsAtTheTopInTheMiddle() {
        let frame = ToolbarSpot.frame(size: size, in: visible, spot: nil)
        #expect(frame == CGRect(x: 200, y: 748, width: 600, height: 40))
    }

    @Test func aSpotComesBackWhereItWasDropped() {
        let dropped = CGRect(x: 300, y: 100, width: 600, height: 40)
        let spot = ToolbarSpot(frame: dropped, in: visible)
        #expect(ToolbarSpot.frame(size: size, in: visible, spot: spot) == dropped)
    }

    @Test func itStaysWhollyOnTheDisplayEvenOnASmallerOne() {
        let spot = ToolbarSpot(x: 0.95, y: 0.99)
        let frame = ToolbarSpot.frame(size: size, in: CGRect(x: 1000, y: 0, width: 700, height: 500), spot: spot)
        #expect(frame.minX >= 1000 && frame.maxX <= 1700 && frame.minY >= 0 && frame.maxY <= 500)
    }

    @Test func aSpotIsSavedAndAnOlderFileHasNone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tinypen-\(UUID().uuidString)/preferences.json")
        var preferences = Preferences.defaults
        preferences.toolbarSpot = ToolbarSpot(x: 0.25, y: 0.75)
        try preferences.save(to: url)
        #expect(Preferences.load(from: url).toolbarSpot == ToolbarSpot(x: 0.25, y: 0.75))
        try Data(#"{"size": 1, "toolbarSpot": {"x": 7, "y": -2}}"#.utf8).write(to: url)
        #expect(Preferences.load(from: url).toolbarSpot == ToolbarSpot(x: 1, y: 0))
        try Data(#"{"size": 1}"#.utf8).write(to: url)
        #expect(Preferences.load(from: url).toolbarSpot == nil)
    }
}
