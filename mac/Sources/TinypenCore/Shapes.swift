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

/// A freehand stroke as a smooth curve, for the pen and the highlighter.
public enum Smoothing {
    /// How far along the stroke, in points, a point is pulled towards its neighbours: at least
    /// this, more where a quick stroke spaced its points out, up to the most.
    static let reach: (least: CGFloat, most: CGFloat) = (3, 5)

    /// The pointer reports whole points, so a slow line arrives as a staircase, and a quick one
    /// zigzags by up to a point either way. Each point is pulled towards its neighbours within a
    /// few points of length either side, which irons that out and leaves a turn the hand made in
    /// place. The curve then runs through the middle
    /// of each pair of points rather than through the points, so it has no corner anywhere.
    /// Reported: drawn through every point, strokes came out rough, with a kink at every step.
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
        let smooth = smoothed(points)
        for index in 1..<(smooth.count - 1) {
            let point = smooth[index]
            let next = smooth[index + 1]
            path.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), control: point)
        }
        path.addLine(to: smooth[smooth.count - 1])
        return path
    }

    /// Every point but the first and last moved to the average of those near it along the stroke,
    /// the nearest counting most.
    static func smoothed(_ points: [CGPoint]) -> [CGPoint] {
        var along: [CGFloat] = [0]
        for (from, to) in zip(points, points.dropFirst()) { along.append(along[along.count - 1] + from.distance(to: to)) }
        var result = points
        var low = 0
        for index in 1..<(points.count - 1) {
            let reach = min(max((along[index + 1] - along[index - 1]) / 2, Self.reach.least), Self.reach.most)
            let span = reach * 3
            while along[index] - along[low] > span { low += 1 }
            var x: CGFloat = 0, y: CGFloat = 0, total: CGFloat = 0
            var near = low
            while near < points.count, along[near] - along[index] <= span {
                let gap = along[near] - along[index]
                let weight = exp(-gap * gap / (2 * reach * reach))
                x += points[near].x * weight
                y += points[near].y * weight
                total += weight
                near += 1
            }
            result[index] = CGPoint(x: x / total, y: y / total)
        }
        return result
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

    /// The magnification after `steps` presses of ] (or [ for fewer), about 1.15 times a step.
    public static func magnification(_ current: CGFloat, stepped steps: CGFloat) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, current * pow(1.15, steps)))
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

    /// The radius after growing or shrinking by `delta` points.
    public static func radius(_ current: CGFloat, stepped delta: CGFloat) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, current + delta))
    }
}
