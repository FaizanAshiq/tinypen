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
