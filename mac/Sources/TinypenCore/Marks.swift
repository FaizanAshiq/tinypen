import CoreGraphics

/// One stroke or shape on the screen, in points from the display's top left corner.
public struct Mark: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case stroke([CGPoint])
        case highlight([CGPoint])
        case arrow(from: CGPoint, to: CGPoint)
        case box(CGRect)
    }

    public var kind: Kind
    public var colorHex: String
    public var width: CGFloat

    public init(kind: Kind, colorHex: String, width: CGFloat) {
        self.kind = kind
        self.colorHex = colorHex
        self.width = width
    }

    /// The outline the renderer fills (arrow) or strokes (the rest).
    public var path: CGPath {
        switch kind {
        case let .stroke(points), let .highlight(points): Smoothing.path(through: points)
        case let .arrow(from, to): ArrowShape.path(from: from, to: to, width: width)
        case let .box(rect): CGPath(rect: rect, transform: nil)
        }
    }
}

/// Every mark on one display, newest last, with undo. Clearing is undoable too, so a slip of
/// the Delete key mid talk is one undo away.
public struct Marks: Sendable {
    public private(set) var all: [Mark] = []
    private var cleared: [Mark]?

    public init() {}

    public var isEmpty: Bool { all.isEmpty }

    public mutating func add(_ mark: Mark) {
        all.append(mark)
        cleared = nil
    }

    public mutating func undo() {
        if let cleared, all.isEmpty {
            all = cleared
            self.cleared = nil
            return
        }
        guard !all.isEmpty else { return }
        all.removeLast()
    }

    public mutating func clear() {
        guard !all.isEmpty else { return }
        cleared = all
        all = []
    }
}

/// Turning a press and a release into a shape.
public enum Drag {
    /// The arrow's tip, kept to the nearest 45 degrees with Shift.
    public static func arrowEnd(from origin: CGPoint, to point: CGPoint, shift: Bool) -> CGPoint {
        shift ? point.snapped45(from: origin) : point
    }

    /// The box, a square in the direction dragged with Shift.
    public static func box(from origin: CGPoint, to point: CGPoint, shift: Bool) -> CGRect {
        var dx = point.x - origin.x
        var dy = point.y - origin.y
        if shift {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: min(origin.x, origin.x + dx), y: min(origin.y, origin.y + dy), width: abs(dx), height: abs(dy))
    }

    /// The arrow or box a drag makes; nil for a click, which would only leave a speck.
    public static func mark(_ tool: Tool, from origin: CGPoint, to point: CGPoint, shift: Bool, colorHex: String,
                            width: CGFloat) -> Mark? {
        switch tool {
        case .arrow:
            let end = arrowEnd(from: origin, to: point, shift: shift)
            guard origin.distance(to: end) >= 4 else { return nil }
            return Mark(kind: .arrow(from: origin, to: end), colorHex: colorHex, width: width)
        case .box:
            let rect = box(from: origin, to: point, shift: shift)
            guard rect.width >= 3 || rect.height >= 3 else { return nil }
            return Mark(kind: .box(rect), colorHex: colorHex, width: width)
        default:
            return nil
        }
    }
}

/// A freehand stroke's points as the pointer gives them, leaving out ones too close to the last
/// to change the line.
public struct StrokeBuilder: Sendable {
    public private(set) var points: [CGPoint] = []

    public init() {}

    public mutating func add(_ point: CGPoint) {
        if let last = points.last, last.distance(to: point) < 0.5 { return }
        points.append(point)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    /// This point moved onto the nearest of the eight 45 degree directions from `origin`,
    /// projected rather than rotated, so a drag along an axis keeps its exact length.
    func snapped45(from origin: CGPoint) -> CGPoint {
        let dx = x - origin.x
        let dy = y - origin.y
        let ax = abs(dx)
        let ay = abs(dy)
        let tan22 = 0.41421356237
        if ay <= ax * tan22 { return CGPoint(x: origin.x + dx, y: origin.y) }
        if ax <= ay * tan22 { return CGPoint(x: origin.x, y: origin.y + dy) }
        let diagonal = (ax + ay) / 2
        return CGPoint(x: origin.x + (dx < 0 ? -diagonal : diagonal), y: origin.y + (dy < 0 ? -diagonal : diagonal))
    }
}
