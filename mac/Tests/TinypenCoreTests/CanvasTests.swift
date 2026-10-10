import CoreGraphics
import Testing
@testable import TinypenCore

/// One display's marks and its board, with Esc, Delete and undo.
struct CanvasTests {
    private func mark(_ x: CGFloat) -> Mark {
        Mark(kind: .stroke([CGPoint(x: x, y: 0), CGPoint(x: x + 10, y: 10)]), colorHex: "#FF3B30", width: 4)
    }

    /// Reported: Esc erased the board's marks too, and undo brought back only the screen's.
    @Test func undoAfterEscBringsBackTheBoardAsItWas() {
        var canvas = Canvas()
        canvas.add(mark(1))
        canvas.cycleBoard()
        canvas.add(mark(2))
        canvas.erase()
        #expect(canvas.board == nil && canvas.isEmpty)
        canvas.undo()
        #expect(canvas.board == .white)
        #expect(canvas.marks == [mark(2)])
        canvas.cycleBoard()
        canvas.cycleBoard()
        #expect(canvas.marks == [mark(1)])
    }

    /// An update restarts Tinypen only when that loses nothing: no marks, a closed board's
    /// included, and nothing an Esc or Delete cleared that undo could still bring back.
    @Test func blankOnlyWithNothingARestartWouldLose() {
        var canvas = Canvas()
        #expect(canvas.isBlank)
        canvas.add(mark(1))
        #expect(!canvas.isBlank)
        canvas.erase()
        #expect(canvas.isEmpty && !canvas.isBlank)
        canvas.keepCleared()
        #expect(canvas.isBlank)
        canvas.cycleBoard()
        canvas.add(mark(2))
        canvas.closeBoard()
        #expect(canvas.isEmpty && !canvas.isBlank)
        canvas.reset()
        #expect(canvas.isBlank)
    }

    @Test func aMarkDrawnAfterEscIsWhatUndoTakesBack() {
        var canvas = Canvas()
        canvas.add(mark(1))
        canvas.erase()
        canvas.add(mark(2))
        canvas.undo()
        #expect(canvas.isEmpty)
    }

    /// Esc on an empty screen must not bring back marks Delete cleared long before.
    @Test func escLeavesAnOlderDeleteAlone() {
        var canvas = Canvas()
        canvas.add(mark(1))
        canvas.clear()
        canvas.cycleBoard()
        canvas.add(mark(2))
        canvas.erase()
        canvas.undo()
        #expect(canvas.marks == [mark(2)])
        canvas.cycleBoard()
        canvas.cycleBoard()
        #expect(canvas.marks.isEmpty)
    }

    /// Reported: leaving drawing mode with the board open left it over the whole screen while clicks
    /// went to the apps it hid. It closes, keeping its marks for next time.
    @Test func closingTheBoardKeepsItsMarksForNextTime() {
        var canvas = Canvas()
        canvas.cycleBoard()
        canvas.add(mark(1))
        canvas.closeBoard()
        #expect(canvas.board == nil && canvas.isEmpty)
        canvas.cycleBoard()
        #expect(canvas.marks == [mark(1)])
    }

    /// Undo after Delete brings back what that Delete cleared and nothing older. Found testing: with
    /// nothing showing, Delete cleared nothing and undo brought back marks an older Delete had cleared.
    @Test func undoAfterDeleteBringsBackOnlyWhatThatDeleteCleared() {
        var canvas = Canvas()
        canvas.cycleBoard()
        canvas.add(mark(1))
        canvas.clear()
        canvas.cycleBoard()
        canvas.cycleBoard()
        canvas.add(mark(2))
        canvas.cycleBoard()
        canvas.clear()
        canvas.undo()
        #expect(canvas.marks.isEmpty)
        canvas.cycleBoard()
        canvas.cycleBoard()
        #expect(canvas.marks == [mark(2)])
    }

    @Test func undoAfterDeleteNeverTakesAMarkAway() {
        var canvas = Canvas()
        canvas.add(mark(1))
        canvas.cycleBoard()
        canvas.clear()
        canvas.cycleBoard()
        canvas.cycleBoard()
        canvas.undo()
        #expect(canvas.marks == [mark(1)])
    }

    /// Found testing: after Esc and a new mark, undo with the board open brought back the board marks
    /// Esc had erased, though the screen's stayed gone.
    @Test func aNewMarkAfterEscKeepsTheBoardsMarksGoneToo() {
        var canvas = Canvas()
        canvas.cycleBoard()
        canvas.add(mark(1))
        canvas.closeBoard()
        canvas.add(mark(2))
        canvas.erase()
        canvas.add(mark(3))
        canvas.cycleBoard()
        canvas.undo()
        #expect(canvas.marks.isEmpty)
    }

    /// Undo brings back only the last Delete: one before it is for good.
    @Test func aSecondDeleteMakesTheFirstForGood() {
        var canvas = Canvas()
        canvas.add(mark(1))
        canvas.clear()
        canvas.cycleBoard()
        canvas.clear()
        canvas.undo()
        canvas.closeBoard()
        canvas.undo()
        #expect(canvas.marks.isEmpty)
    }

    /// Something new drawn on another display makes a Delete for good here too.
    @Test func aClearKeptForGoodStaysGone() {
        var canvas = Canvas()
        canvas.add(mark(1))
        canvas.clear()
        canvas.keepCleared()
        canvas.undo()
        #expect(canvas.marks.isEmpty)
    }

    @Test func marksAreCountedOnTheScreenAndOnTheBoard() {
        var canvas = Canvas()
        canvas.add(mark(1))
        canvas.cycleBoard()
        canvas.add(mark(2))
        canvas.add(mark(3))
        canvas.closeBoard()
        #expect(canvas.count(onBoard: false) == 1)
        #expect(canvas.count(onBoard: true) == 2)
    }

    @Test func onlyWhatShowsCounts() {
        var canvas = Canvas()
        #expect(canvas.isEmpty)
        canvas.cycleBoard()
        #expect(!canvas.isEmpty)
        #expect(canvas.showsBoard)
    }
}
