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

    @Test func onlyWhatShowsCounts() {
        var canvas = Canvas()
        #expect(canvas.isEmpty)
        canvas.cycleBoard()
        #expect(!canvas.isEmpty)
        #expect(canvas.showsBoard)
    }
}
