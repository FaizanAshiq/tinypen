import CoreGraphics

/// Which keys Tinypen holds while it shows something, so they reach it whichever app is in front.
public enum HeldKeys: Equatable, Sendable {
    /// Nothing on screen: every key is the apps' own.
    case none
    /// Esc only: marks left on screen, the laser, or the colour picker, whose hex field wants the rest.
    case escape
    /// Esc, and [ and ] to size the spotlight or the zoom lens.
    case escapeAndSize
    /// Every key of drawing mode, as the layer takes the clicks and no other app is in reach.
    case all
}

/// What Tinypen shows, and what follows from it, the same however a tool was switched on: from its
/// hotkey, the menu or the toolbar.
public struct Screen: Equatable, Sendable {
    public var drawing: Bool
    /// The laser, the spotlight or the zoom lens; nil for a marking tool, or none.
    public var effect: Tool?
    public var hasMarks: Bool
    public var pickingColor: Bool

    public init(drawing: Bool, effect: Tool?, hasMarks: Bool = false, pickingColor: Bool = false) {
        self.drawing = drawing
        self.effect = effect
        self.hasMarks = hasMarks
        self.pickingColor = pickingColor
    }

    /// Only a marking tool takes clicks. The laser, the spotlight and the zoom lens let every click
    /// through to the app under them. Reported: picked from the toolbar they blocked clicks, which
    /// from their hotkeys they did not.
    public var takesClicks: Bool { drawing && effect == nil }

    public var heldKeys: HeldKeys {
        if takesClicks { return pickingColor ? .escape : .all }
        if effect == .spotlight || effect == .zoom { return .escapeAndSize }
        return drawing || effect != nil || hasMarks ? .escape : .none
    }
}

/// Where the toolbar sits: its centre as a fraction of a display's usable area, across from the left
/// and down from the top, so a spot picked on one display means the same place on another.
public struct ToolbarSpot: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    /// The spot of a toolbar dropped at `frame`, in AppKit's coordinates, up from the bottom.
    public init(frame: CGRect, in visible: CGRect) {
        self.init(x: (frame.midX - visible.minX) / visible.width, y: (visible.maxY - frame.midY) / visible.height)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try container.decode(Double.self, forKey: .x), y: try container.decode(Double.self, forKey: .y))
    }

    /// The toolbar's frame on a display, wholly inside its usable area; without a spot, at the top in
    /// the middle, 12 points down.
    public static func frame(size: CGSize, in visible: CGRect, spot: ToolbarSpot?) -> CGRect {
        let centre = spot.map { CGPoint(x: visible.minX + $0.x * visible.width, y: visible.maxY - $0.y * visible.height) }
            ?? CGPoint(x: visible.midX, y: visible.maxY - 12 - size.height / 2)
        let x = min(max(centre.x - size.width / 2, visible.minX), visible.maxX - size.width)
        let y = min(max(centre.y - size.height / 2, visible.minY), visible.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
