import CoreGraphics

/// What the pointer does in drawing mode. The first four leave marks; the rest follow the
/// pointer and keep nothing.
public enum Tool: String, CaseIterable, Codable, Sendable {
    case pen, highlighter, arrow, box, laser, spotlight, zoom

    /// The letter that picks it in drawing mode.
    public var key: Character {
        switch self {
        case .pen: "p"
        case .highlighter: "h"
        case .arrow: "a"
        case .box: "r"
        case .laser: "l"
        case .spotlight: "s"
        case .zoom: "z"
        }
    }

    public var title: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .arrow: "Arrow"
        case .box: "Box"
        case .laser: "Laser"
        case .spotlight: "Spotlight"
        case .zoom: "Zoom"
        }
    }

    public var drawsMarks: Bool { self == .pen || self == .highlighter || self == .arrow || self == .box }

    public static func forKey(_ key: Character) -> Tool? {
        allCases.first { $0.key == Character(key.lowercased()) }
    }
}

/// The toolbar's colours, picked with 1 to 6.
public enum Palette {
    public static let colors = ["#FF3B30", "#FFCC00", "#34C759", "#007AFF", "#FFFFFF", "#000000"]
    public static let names = ["Red", "Yellow", "Green", "Blue", "White", "Black"]

    /// The sRGB components of "#RRGGBB", or red for anything else.
    public static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return CGColor(srgbRed: 1, green: 59 / 255, blue: 48 / 255, alpha: alpha)
        }
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
}

/// The five widths, stepped with [ and ].
public enum Sizes {
    public static let widths: [CGFloat] = [2, 4, 6, 10, 16]

    /// A highlighter is as wide as a marker pen, whatever size the pen is at.
    public static func highlighterWidth(_ width: CGFloat) -> CGFloat { max(14, width * 3) }
}
