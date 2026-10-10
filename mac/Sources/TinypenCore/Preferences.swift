import Foundation

public enum ModifierKey: String, Sendable, Codable, CaseIterable {
    case control
    case option
    case shift
    case command
}

public struct HotKeyBinding: Equatable, Sendable, Codable {
    /// A Carbon virtual key code. 2 is the D key.
    public var keyCode: UInt32
    public var modifiers: [ModifierKey]

    public init(keyCode: UInt32, modifiers: [ModifierKey]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A hotkey is held in every app, so it must leave their own keys alone: Control or Option, or
    /// Command with another. Shift alone would take a capital letter, Command alone a copy or a quit.
    public var isAllowed: Bool {
        let held = Set(modifiers)
        return held.contains(.control) || held.contains(.option) || held.contains(.command) && held.count > 1
    }

    /// The binding the way macOS prints it in a menu, for example "⌥⇧D", modifiers always in
    /// the system's order whatever order a hand edited file lists them in.
    public var displayString: String {
        let systemOrder: [(ModifierKey, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return systemOrder.filter { modifiers.contains($0.0) }.map(\.1).joined() + Self.label(for: keyCode)
    }

    private static let labels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    private static func label(for keyCode: UInt32) -> String {
        labels[keyCode] ?? "Key \(keyCode)"
    }

    /// The character a menu lines the binding up with on the right, as macOS menus show
    /// shortcuts: the letter or digit, or nil for a key a menu cannot show that way.
    public var menuCharacter: String? {
        guard let label = Self.labels[keyCode], label.count == 1, let character = label.first,
              character.isLetter || character.isNumber else { return nil }
        return label.lowercased()
    }
}

/// In the order the menu and Settings list them.
public enum HotKeyAction: String, CaseIterable, Sendable {
    case draw, laser, spotlight, zoom

    public var title: String {
        switch self {
        case .draw: "Draw"
        case .laser: "Laser Pointer"
        case .spotlight: "Spotlight"
        case .zoom: "Zoom"
        }
    }
}

public struct HotKeys: Equatable, Sendable, Codable {
    public var draw: HotKeyBinding?
    public var laser: HotKeyBinding?
    public var spotlight: HotKeyBinding?
    public var zoom: HotKeyBinding?

    /// Option Shift with the tool's letter: free in nearly every app, and easy to find.
    public static let defaults = HotKeys(
        draw: HotKeyBinding(keyCode: 2, modifiers: [.option, .shift]),
        laser: HotKeyBinding(keyCode: 37, modifiers: [.option, .shift]),
        spotlight: HotKeyBinding(keyCode: 1, modifiers: [.option, .shift]),
        zoom: HotKeyBinding(keyCode: 6, modifiers: [.option, .shift]))

    public init(draw: HotKeyBinding?, laser: HotKeyBinding?, spotlight: HotKeyBinding?, zoom: HotKeyBinding?) {
        self.draw = draw
        self.laser = laser
        self.spotlight = spotlight
        self.zoom = zoom
    }

    public subscript(action: HotKeyAction) -> HotKeyBinding? {
        get {
            switch action {
            case .draw: draw
            case .laser: laser
            case .spotlight: spotlight
            case .zoom: zoom
            }
        }
        set {
            switch action {
            case .draw: draw = newValue
            case .laser: laser = newValue
            case .spotlight: spotlight = newValue
            case .zoom: zoom = newValue
            }
        }
    }

    /// The action already using `binding`, so Settings can refuse a second one.
    public func action(using binding: HotKeyBinding) -> HotKeyAction? {
        HotKeyAction.allCases.first { self[$0] == binding }
    }

    /// A key left out takes its default; a key written as null stays cleared.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func binding(_ key: CodingKeys, _ fallback: HotKeyBinding?) -> HotKeyBinding? {
            guard container.contains(key) else { return fallback }
            guard (try? container.decodeNil(forKey: key)) != true else { return nil }
            return (try? container.decode(HotKeyBinding.self, forKey: key)).flatMap { $0.isAllowed ? $0 : nil } ?? fallback
        }
        draw = binding(.draw, Self.defaults.draw)
        laser = binding(.laser, Self.defaults.laser)
        spotlight = binding(.spotlight, Self.defaults.spotlight)
        zoom = binding(.zoom, Self.defaults.zoom)
    }

    /// Null is written as null, not left out, so a cleared hotkey stays cleared.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(draw, forKey: .draw)
        try container.encode(laser, forKey: .laser)
        try container.encode(spotlight, forKey: .spotlight)
        try container.encode(zoom, forKey: .zoom)
    }

    private enum CodingKeys: String, CodingKey { case draw, laser, spotlight, zoom }
}

/// Everything Tinypen remembers, in one small file. Nothing else is written anywhere.
public struct Preferences: Equatable, Sendable, Codable {
    public var hotkeys: HotKeys
    public var colorHex: String
    /// Index into `Sizes.widths`.
    public var size: Int
    /// The marking tool in hand when drawing mode starts.
    public var tool: Tool
    public var showMenuBarIcon: Bool
    /// Custom colours picked lately, newest first, shown beside the six.
    public var recentColors: [String] = []
    /// Where the toolbar was dragged to; nil for the top in the middle.
    public var toolbarSpot: ToolbarSpot?

    public static let defaults = Preferences(hotkeys: .defaults, colorHex: Palette.colors[0], size: 1, tool: .pen,
                                             showMenuBarIcon: true)

    public init(hotkeys: HotKeys, colorHex: String, size: Int, tool: Tool, showMenuBarIcon: Bool) {
        self.hotkeys = hotkeys
        self.colorHex = colorHex
        self.size = size
        self.tool = tool
        self.showMenuBarIcon = showMenuBarIcon
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tinypen/preferences.json")
    }

    public var width: CGFloat { Sizes.widths[min(max(size, 0), Sizes.widths.count - 1)] }

    /// Defaults for a missing or damaged file: Tinypen always starts.
    public static func load(from url: URL) -> Preferences {
        guard let data = try? Data(contentsOf: url), let loaded = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return .defaults
        }
        return loaded
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Each field left out takes its default, so an older or hand edited file still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        hotkeys = (try? container.decodeIfPresent(HotKeys.self, forKey: .hotkeys)) ?? defaults.hotkeys
        let hex = (try? container.decodeIfPresent(String.self, forKey: .colorHex)) ?? defaults.colorHex
        colorHex = hex.hasPrefix("#") ? Palette.hex(typed: hex) ?? defaults.colorHex : defaults.colorHex
        let stored = (try? container.decodeIfPresent(Int.self, forKey: .size)) ?? defaults.size
        size = min(max(stored, 0), Sizes.widths.count - 1)
        let picked = (try? container.decodeIfPresent(Tool.self, forKey: .tool)) ?? defaults.tool
        tool = picked.drawsMarks ? picked : defaults.tool
        showMenuBarIcon = (try? container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon)) ?? defaults.showMenuBarIcon
        let recent = (try? container.decodeIfPresent([String].self, forKey: .recentColors)) ?? []
        recentColors = Array(recent.compactMap(Palette.hex(typed:)).prefix(Palette.recentCount))
        toolbarSpot = try? container.decodeIfPresent(ToolbarSpot.self, forKey: .toolbarSpot)
    }

    private enum CodingKeys: String, CodingKey { case hotkeys, colorHex, size, tool, showMenuBarIcon, recentColors, toolbarSpot }
}
