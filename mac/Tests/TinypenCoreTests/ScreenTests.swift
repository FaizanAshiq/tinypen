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

    /// Clicks pass through to other apps, so only Esc is held, never a letter or [ and ].
    @Test func aPointerToolHoldsOnlyEsc() {
        #expect(Screen(drawing: true, effect: .spotlight).heldKeys == .escape)
        #expect(Screen(drawing: false, effect: .zoom).heldKeys == .escape)
        #expect(Screen(drawing: false, effect: .laser).heldKeys == .escape)
    }

    /// Option (Alt on Windows) held over the spotlight or the lens: the layer takes the mouse, so a
    /// scroll sizes them; let go, and clicks and scrolls go to the apps again.
    @Test func holdingOptionLetsTheSpotlightAndTheLensTakeTheScroll() {
        #expect(Screen(drawing: false, effect: .spotlight, sizing: true).takesMouse)
        #expect(Screen(drawing: true, effect: .zoom, sizing: true).takesMouse)
        #expect(!Screen(drawing: false, effect: .spotlight).takesMouse)
    }

    /// Reported: scrolling did nothing while drawing. A scroll lets the mouse through to the app under
    /// the drawing for a moment, while the keys stay with Tinypen.
    @Test func aScrollWhileDrawingLetsTheMouseThroughForAMoment() {
        let passing = Screen(drawing: true, effect: nil, passingScroll: true)
        #expect(!passing.takesMouse)
        #expect(passing.heldKeys == .all)
        #expect(Screen(drawing: true, effect: nil).takesMouse)
    }

    /// Reported: with marks on screen, Esc in Settings erased them instead of backing out of a hotkey
    /// being recorded. While Tinypen's own window wants the keys, none is held.
    @Test func noKeyIsHeldWhileTinypensOwnWindowWantsThem() {
        #expect(Screen(drawing: false, effect: nil, hasMarks: true, keysPaused: true).heldKeys == HeldKeys.none)
        #expect(Screen(drawing: false, effect: .laser, keysPaused: true).heldKeys == HeldKeys.none)
    }

    /// Option is everyone's key: with nothing to size, it never stops a click reaching an app.
    @Test func optionAloneTakesNothing() {
        #expect(!Screen(drawing: false, effect: .laser, sizing: true).takesMouse)
        #expect(!Screen(drawing: false, effect: nil, hasMarks: true, sizing: true).takesMouse)
        #expect(!Screen(drawing: false, effect: nil, sizing: true).takesMouse)
        #expect(Screen(drawing: true, effect: nil).takesMouse)
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

    /// A display with no size yet, as one being plugged in, gives the middle rather than a spot that
    /// cannot be saved: JSON has no NaN, and the whole file would stop saving.
    @Test func aDisplayWithNoSizeGivesTheMiddle() throws {
        let spot = ToolbarSpot(frame: CGRect(x: 10, y: 10, width: 600, height: 40), in: .zero)
        #expect(spot == ToolbarSpot(x: 0.5, y: 0.5))
        #expect(ToolbarSpot(x: .nan, y: .infinity) == ToolbarSpot(x: 0.5, y: 0.5))
        var preferences = Preferences.defaults
        preferences.toolbarSpot = spot
        _ = try JSONEncoder().encode(preferences)
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
