/// White or black, over the whole display, to sketch on.
public enum Board: Sendable {
    case white, black
}

/// What one display shows: its marks, and a white or black board over them with marks of its own.
public struct Canvas: Sendable {
    public private(set) var board: Board?
    private var screen = Marks()
    private var sheet = Marks()
    /// What Esc erased, so undo brings all of it back, the board open as it was; nil once anything
    /// else changes.
    private var erased: (screen: Bool, sheet: Bool, board: Board?)?

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
        change { $0.clear() }
    }

    public mutating func undo() {
        guard let erased else { return change { $0.undo() } }
        self.erased = nil
        if erased.screen { screen.undo() }
        if erased.sheet { sheet.undo() }
        board = erased.board
    }

    /// Esc: everything drawn gone, on the screen and on the board, and the board closed. Undo brings
    /// it all back. Reported: undo brought back only the screen's marks, and the board's were lost.
    public mutating func erase() {
        erased = (!screen.isEmpty, !sheet.isEmpty, board)
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
        erased = nil
        if board == nil { change(&screen) } else { change(&sheet) }
    }
}
