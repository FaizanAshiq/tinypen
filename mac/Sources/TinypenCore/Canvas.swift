/// White or black, over the whole display, to sketch on.
public enum Board: Sendable {
    case white, black
}

/// What one display shows: its marks, and a white or black board over them with marks of its own.
public struct Canvas: Sendable {
    public private(set) var board: Board?
    private var screen = Marks()
    private var sheet = Marks()
    /// What the last Delete or Esc cleared, so undo brings back exactly that, with the board Esc closed
    /// open again; nil once anything else changes. Found testing: Delete with nothing showing cleared
    /// nothing, and undo brought back marks an older Delete had cleared, or took one away.
    private var cleared: (screen: Bool, sheet: Bool, reopen: Board?)?

    public init() {}

    /// The marks showing: the board's while it is open, the screen's otherwise.
    public var marks: [Mark] { board == nil ? screen.all : sheet.all }
    public var showsBoard: Bool { board != nil }

    /// Nothing showing: no board, and no marks on the screen. Marks on a closed board wait for it.
    public var isEmpty: Bool { board == nil && screen.isEmpty }

    public mutating func add(_ mark: Mark) {
        change { $0.add(mark) }
    }

    /// Delete: what shows is cleared, and undo brings it back.
    public mutating func clear() {
        cleared = (board == nil && !screen.isEmpty, board != nil && !sheet.isEmpty, nil)
        if board == nil { screen.clear() } else { sheet.clear() }
    }

    public mutating func undo() {
        guard let cleared else { return change { $0.undo() } }
        self.cleared = nil
        if cleared.screen { screen.undo() }
        if cleared.sheet { sheet.undo() }
        if let reopen = cleared.reopen { board = reopen }
    }

    /// Esc: everything drawn gone, on the screen and on the board, and the board closed. Undo brings
    /// it all back. Reported: undo brought back only the screen's marks, and the board's were lost.
    public mutating func erase() {
        cleared = (!screen.isEmpty, !sheet.isEmpty, board)
        screen.clear()
        sheet.clear()
        board = nil
    }

    /// Every mark gone, the board too: the screen as it was.
    public mutating func reset() {
        self = Canvas()
    }

    /// White, then black, then off.
    public mutating func cycleBoard() {
        switch board {
        case nil: board = .white
        case .white: board = .black
        case .black: board = nil
        }
    }

    /// Drawing mode ended: the board closes and keeps its marks for next time. Reported: left open, it
    /// hid every app while clicks went through to them.
    public mutating func closeBoard() {
        board = nil
    }

    private mutating func change(_ change: (inout Marks) -> Void) {
        cleared = nil
        if board == nil { change(&screen) } else { change(&sheet) }
    }
}
