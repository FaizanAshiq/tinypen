import CoreGraphics

/// A straight arrow whose body widens from a thin tail to a swept back head, as Tinysnap draws
/// it. The renderer fills it and strokes it with round joins, which rounds the tip and barbs.
enum ArrowShape {
    static func path(from tail: CGPoint, to tip: CGPoint, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let length = tail.distance(to: tip)
        guard length > 0 else { return path }
        let ux = (tip.x - tail.x) / length
        let uy = (tip.y - tail.y) / length
        let nx = -uy
        let ny = ux
        let head = min(length * 0.5, width * 4.2)
        let headHalf = head * 0.62
        let neckHalf = min(width * 0.6, headHalf * 0.5)
        let tailHalf = width * 0.18
        let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
        // The barbs sit a little behind the neck, which sweeps the head back.
        let barb = CGPoint(x: base.x - ux * head * 0.12, y: base.y - uy * head * 0.12)
        func at(_ point: CGPoint, _ offset: CGFloat) -> CGPoint {
            CGPoint(x: point.x + nx * offset, y: point.y + ny * offset)
        }
        path.addLines(between: [
            at(tail, tailHalf), at(base, neckHalf), at(barb, headHalf), tip,
            at(barb, -headHalf), at(base, -neckHalf), at(tail, -tailHalf),
        ])
        path.closeSubpath()
        return path
    }
}

/// A smooth curve through a freehand stroke's points, Catmull-Rom style, as Tinysnap draws it.
public enum Smoothing {
    public static func path(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            // A single point still draws: a round cap on a zero length line is a dot.
            if points.count == 1 { path.addLine(to: first) }
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }
}

/// The laser pointer's trail: where the pointer has been in the last 0.7 s, each point fading
/// as it ages. Nothing of it is kept.
public struct LaserTrail: Sendable {
    public static let fade: Double = 0.7
    private var points: [(point: CGPoint, time: Double)] = []

    public init() {}

    public mutating func add(_ point: CGPoint, at time: Double) {
        points.append((point, time))
    }

    /// The points still showing at `now`, oldest first, with how opaque each is.
    public func visible(at now: Double) -> [(point: CGPoint, alpha: CGFloat)] {
        points.compactMap { entry in
            let age = now - entry.time
            guard age < Self.fade else { return nil }
            return (entry.point, CGFloat(1 - max(0, age) / Self.fade))
        }
    }

    public mutating func prune(at now: Double) {
        points.removeAll { now - $0.time >= Self.fade }
    }

    /// Nothing left to fade, so the screen need not be redrawn until the pointer moves again.
    public func isIdle(at now: Double) -> Bool {
        visible(at: now).isEmpty
    }
}

/// The zoom lens: a circle on the pointer showing the screen under it magnified.
public enum Lens {
    public static let radius: CGFloat = 120
    public static let range: ClosedRange<CGFloat> = 1.5...6

    /// The magnification after a scroll of `delta` points, about 1.15 times per notch.
    public static func magnification(_ current: CGFloat, scrolled delta: CGFloat) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, current * pow(1.15, delta)))
    }

    /// The part of the screen the lens shows, centred on the pointer.
    public static func source(center: CGPoint, radius: CGFloat, magnification: CGFloat) -> CGRect {
        let half = radius / magnification
        return CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2)
    }
}

/// The spotlight: every display dimmed except a circle round the pointer.
public enum Spotlight {
    public static let radius: CGFloat = 140
    public static let range: ClosedRange<CGFloat> = 60...600

    public static func radius(_ current: CGFloat, scrolled delta: CGFloat) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, current + delta))
    }
}
