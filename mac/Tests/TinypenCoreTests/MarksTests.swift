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

    /// The pointer reports whole points, so a slow line arrives as a staircase. Reported: strokes came
    /// out rough, with a kink at every step.
    @Test func aSlowStraightLineComesOutStraight() {
        let points = (0...120).map { CGPoint(x: CGFloat($0), y: (CGFloat($0) * 0.3).rounded()) }
        let slope = atan2(0.3, 1.0)
        let worst = directions(Smoothing.path(through: points)).map { abs($0 - slope) }.max()!
        #expect(worst < 3 * .pi / 180)
    }

    /// A circle drawn slowly turns evenly, a little each point, with no corner anywhere.
    @Test func aSlowCircleTurnsEvenly() {
        let points = stride(from: 0.0, through: 330.0, by: 1.5).map { degrees in
            let angle = degrees * .pi / 180
            return CGPoint(x: (100 + 40 * cos(angle)).rounded(), y: (100 + 40 * sin(angle)).rounded())
        }
        let angles = directions(Smoothing.path(through: points))
        let worst = zip(angles, angles.dropFirst()).map { abs(remainder($1 - $0, 2 * .pi)) }.max()!
        #expect(worst < 4 * .pi / 180)
    }

    /// A quick stroke reports a point every several, each off by up to a point. The wave bends one
    /// way and then the other, without wobbling in between.
    @Test func aQuickWaveBendsWithoutWobbling() {
        let points = (0...60).map { index in
            let t = CGFloat(index) / 60
            let wobble = sin(CGFloat(index) * 12.9898) * 0.35
            return CGPoint(x: (240 + 140 * t + wobble).rounded(), y: (260 + 60 * sin(t * 3 * .pi) - wobble).rounded())
        }
        let angles = directions(Smoothing.path(through: points))
        let turns = zip(angles, angles.dropFirst()).map { remainder($1 - $0, 2 * .pi) }.filter { abs($0) > 0.5 * .pi / 180 }
        let flips = zip(turns, turns.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        #expect(flips <= 2)
    }

    /// Which way the path heads along each point of its length.
    private func directions(_ path: CGPath) -> [CGFloat] {
        var line: [CGPoint] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let p = element.points
            switch element.type {
            case .moveToPoint, .addLineToPoint:
                line.append(p[0])
            case .addQuadCurveToPoint:
                let a = line.last!
                for step in 1...32 {
                    let t = CGFloat(step) / 32, u = 1 - t
                    line.append(CGPoint(x: u * u * a.x + 2 * u * t * p[0].x + t * t * p[1].x,
                                        y: u * u * a.y + 2 * u * t * p[0].y + t * t * p[1].y))
                }
            case .addCurveToPoint:
                let a = line.last!
                for step in 1...32 {
                    let t = CGFloat(step) / 32, u = 1 - t
                    line.append(CGPoint(x: u * u * u * a.x + 3 * u * u * t * p[0].x + 3 * u * t * t * p[1].x + t * t * t * p[2].x,
                                        y: u * u * u * a.y + 3 * u * u * t * p[0].y + 3 * u * t * t * p[1].y + t * t * t * p[2].y))
                }
            default:
                break
            }
        }
        // Every point of length, so a dense stretch weighs no more than a sparse one.
        var even = [line[0]]
        var travelled: CGFloat = 0
        for (from, to) in zip(line, line.dropFirst()) {
            let length = hypot(to.x - from.x, to.y - from.y)
            guard length > 0 else { continue }
            var at = 1 - travelled
            while at <= length {
                even.append(CGPoint(x: from.x + (to.x - from.x) * at / length, y: from.y + (to.y - from.y) * at / length))
                at += 1
            }
            travelled = length - (at - 1)
        }
        return zip(even, even.dropFirst()).map { atan2($1.y - $0.y, $1.x - $0.x) }
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
