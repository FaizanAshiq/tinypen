import CoreGraphics
import Testing
@testable import TinypenCore

struct MarksTests {
    private func dot(_ x: CGFloat) -> Mark {
        Mark(kind: .stroke([CGPoint(x: x, y: 0)]), colorHex: Palette.colors[0], width: 4)
    }

    @Test func undoTakesTheLastMarkOff() {
        var marks = Marks()
        marks.add(dot(1))
        marks.add(dot(2))
        marks.undo()
        #expect(marks.all == [dot(1)])
    }

    /// Clearing by mistake mid talk is one undo away.
    @Test func undoAfterClearBringsEveryMarkBack() {
        var marks = Marks()
        marks.add(dot(1))
        marks.add(dot(2))
        marks.clear()
        #expect(marks.all.isEmpty)
        marks.undo()
        #expect(marks.all == [dot(1), dot(2)])
    }

    @Test func undoWithNothingLeftDoesNothing() {
        var marks = Marks()
        marks.undo()
        #expect(marks.all.isEmpty)
    }

    @Test func aNewMarkAfterClearMeansUndoTakesThatOneOnly() {
        var marks = Marks()
        marks.add(dot(1))
        marks.clear()
        marks.add(dot(2))
        marks.undo()
        #expect(marks.all.isEmpty)
    }
}

struct DragTests {
    private let origin = CGPoint(x: 100, y: 100)

    @Test func shiftKeepsAnArrowTo45Degrees() {
        #expect(Drag.arrowEnd(from: origin, to: CGPoint(x: 200, y: 110), shift: true) == CGPoint(x: 200, y: 100))
        #expect(Drag.arrowEnd(from: origin, to: CGPoint(x: 200, y: 110), shift: false) == CGPoint(x: 200, y: 110))
        #expect(Drag.arrowEnd(from: origin, to: CGPoint(x: 190, y: 210), shift: true) == CGPoint(x: 200, y: 200))
    }

    @Test func shiftMakesABoxSquareInTheDirectionDragged() {
        #expect(Drag.box(from: origin, to: CGPoint(x: 160, y: 120), shift: true) == CGRect(x: 100, y: 100, width: 60, height: 60))
        #expect(Drag.box(from: origin, to: CGPoint(x: 40, y: 80), shift: true) == CGRect(x: 40, y: 40, width: 60, height: 60))
        #expect(Drag.box(from: origin, to: CGPoint(x: 160, y: 120), shift: false) == CGRect(x: 100, y: 100, width: 60, height: 20))
    }

    /// A click with the arrow or the box makes nothing, rather than a speck.
    @Test func aClickIsNoShape() {
        #expect(Drag.mark(.arrow, from: origin, to: CGPoint(x: 102, y: 101), shift: false, colorHex: "#FF3B30", width: 4) == nil)
        #expect(Drag.mark(.box, from: origin, to: CGPoint(x: 101, y: 102), shift: false, colorHex: "#FF3B30", width: 4) == nil)
        #expect(Drag.mark(.box, from: origin, to: CGPoint(x: 150, y: 150), shift: false, colorHex: "#FF3B30", width: 4) != nil)
    }
}

struct SmoothingTests {
    @Test func aStrokeStartsAndEndsWhereThePointerDid() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 8)]
        let path = Smoothing.path(through: points)
        #expect(path.currentPoint == CGPoint(x: 30, y: 8))
        #expect(path.boundingBoxOfPath.minX == 0)
    }

    /// Points closer than half a point add nothing but work for the renderer.
    @Test func pointsTooCloseTogetherAreDropped() {
        var stroke = StrokeBuilder()
        stroke.add(CGPoint(x: 0, y: 0))
        stroke.add(CGPoint(x: 0.2, y: 0.1))
        stroke.add(CGPoint(x: 3, y: 0))
        #expect(stroke.points == [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0)])
    }
}

struct LaserTests {
    @Test func theTrailFadesOverSevenTenthsOfASecond() {
        var trail = LaserTrail()
        trail.add(CGPoint(x: 0, y: 0), at: 10)
        trail.add(CGPoint(x: 5, y: 0), at: 10.35)
        let visible = trail.visible(at: 10.35)
        #expect(visible.count == 2)
        #expect(abs(visible[0].alpha - 0.5) < 0.001)
        #expect(visible[1].alpha == 1)
    }

    @Test func pointsOlderThanTheFadeAreGone() {
        var trail = LaserTrail()
        trail.add(CGPoint(x: 0, y: 0), at: 10)
        trail.add(CGPoint(x: 5, y: 0), at: 10.5)
        trail.prune(at: 10.8)
        #expect(trail.visible(at: 10.8).map(\.point) == [CGPoint(x: 5, y: 0)])
        #expect(!trail.isIdle(at: 10.8))
        #expect(trail.isIdle(at: 11.3))
    }
}

struct LensTests {
    @Test func zoomStaysBetweenOneAndAHalfAndSix() {
        #expect(Lens.magnification(2, scrolled: 100) == 6)
        #expect(Lens.magnification(2, scrolled: -100) == 1.5)
        #expect(Lens.magnification(2, scrolled: 0) == 2)
        #expect(Lens.magnification(2, scrolled: 1) > 2)
    }

    /// At 2x a 120 point lens shows the 120 point square round the pointer.
    @Test func theLensShowsTheSquareRoundThePointer() {
        let source = Lens.source(center: CGPoint(x: 500, y: 300), radius: 120, magnification: 2)
        #expect(source == CGRect(x: 440, y: 240, width: 120, height: 120))
    }

    @Test func spotlightStaysBetween60And600Points() {
        #expect(Spotlight.radius(140, scrolled: 1000) == 600)
        #expect(Spotlight.radius(140, scrolled: -1000) == 60)
        #expect(Spotlight.radius(140, scrolled: 10) == 150)
    }
}
