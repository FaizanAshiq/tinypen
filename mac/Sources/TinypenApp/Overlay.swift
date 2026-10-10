import AppKit
import TinypenCore

extension NSScreen {
    /// The display id AppKit keeps in deviceDescription.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Borderless panels refuse to become key unless told otherwise, and drawing mode needs the keys.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// One display's see-through layer: above every app, full-screen ones too, on every Space.
/// Outside drawing mode every click passes through it to the apps underneath.
@MainActor
final class Overlay {
    let displayID: CGDirectDisplayID
    let panel: OverlayPanel
    let view: OverlayView

    init(screen: NSScreen, session: Session) {
        displayID = screen.displayID
        panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                             defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), session: session, displayID: screen.displayID)
        panel.contentView = view
        panel.setFrame(screen.frame, display: false)
    }

    /// The display moved or changed resolution.
    func fit(_ screen: NSScreen) {
        panel.setFrame(screen.frame, display: true)
    }

    /// Where the pointer is, in this display's points from its top left, or nil when it is on
    /// another display.
    func pointer() -> CGPoint? {
        let location = NSEvent.mouseLocation
        let frame = panel.frame
        guard frame.contains(location) else { return nil }
        return CGPoint(x: location.x - frame.minX, y: frame.maxY - location.y)
    }
}

/// White or black, over the whole display, to sketch on.
enum Board {
    case white, black
}

/// Everything drawn on one display. Finished marks are drawn once into their own view and redrawn
/// only when they change; the mark in progress and the pointer effects have views of their own,
/// so a long session never slows the pen.
@MainActor
final class OverlayView: NSView {
    private unowned let session: Session
    let displayID: CGDirectDisplayID
    private let boardView = PassThroughView()
    private let marksView: MarksView
    private let liveView = LiveView()
    let effects: EffectsView

    private(set) var board: Board?
    private var screenMarks = Marks()
    private var boardMarks = Marks()
    private var stroke = StrokeBuilder()
    private var dragStart: CGPoint?

    init(frame: NSRect, session: Session, displayID: CGDirectDisplayID) {
        self.session = session
        self.displayID = displayID
        marksView = MarksView()
        effects = EffectsView(session: session, displayID: displayID)
        super.init(frame: frame)
        wantsLayer = true
        for view in [boardView, marksView, liveView, effects] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        boardView.wantsLayer = true
        boardView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("OverlayView is created in code only")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var marks: Marks { board == nil ? screenMarks : boardMarks }
    var isEmpty: Bool { screenMarks.isEmpty && boardMarks.isEmpty && board == nil }

    private func changeMarks(_ change: (inout Marks) -> Void) {
        if board == nil { change(&screenMarks) } else { change(&boardMarks) }
        marksView.marks = marks.all
    }

    func undo() { changeMarks { $0.undo() } }
    func clear() { changeMarks { $0.clear() } }

    /// Esc's first press: everything drawn gone, the board too. Undo brings the marks back.
    func erase() {
        screenMarks.clear()
        boardMarks.clear()
        board = nil
        boardView.isHidden = true
        marksView.marks = screenMarks.all
        liveView.mark = nil
    }

    /// Every mark gone, the board too: the screen as it was.
    func reset() {
        screenMarks = Marks()
        boardMarks = Marks()
        board = nil
        boardView.isHidden = true
        marksView.marks = []
        liveView.mark = nil
    }

    /// White, then black, then off.
    func cycleBoard() {
        switch board {
        case nil: board = .white
        case .white: board = .black
        case .black: board = nil
        }
        boardView.isHidden = board == nil
        boardView.layer?.backgroundColor = board == .black ? NSColor.black.cgColor : NSColor.white.cgColor
        marksView.marks = marks.all
    }

    // MARK: Drawing

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let tool = session.markingTool
        guard session.effect == nil, !session.closePalette() else { return }
        dragStart = point
        stroke = StrokeBuilder()
        if tool == .pen || tool == .highlighter { stroke.add(point) }
        updateLive(to: point, shift: event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let tool = session.markingTool
        if tool == .pen || tool == .highlighter { stroke.add(point) }
        updateLive(to: point, shift: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        updateLive(to: convert(event.locationInWindow, from: nil), shift: event.modifierFlags.contains(.shift))
        finishStroke()
    }

    /// The mark being drawn becomes a mark, as when the button comes up. Esc or leaving drawing
    /// mode call this too. Reported: Esc pressed before the button came up stopped drawing instead
    /// of erasing, and left the stroke on screen where undo, clear and Esc could not reach it.
    func finishStroke() {
        guard dragStart != nil else { return }
        dragStart = nil
        if let mark = liveView.mark {
            changeMarks { $0.add(mark) }
            session.drew(on: displayID)
        }
        liveView.mark = nil
    }

    private func updateLive(to point: CGPoint, shift: Bool) {
        guard let start = dragStart else { return }
        let tool = session.markingTool
        let hex = session.preferences.colorHex
        let width = session.preferences.width
        switch tool {
        case .pen: liveView.mark = Mark(kind: .stroke(stroke.points), colorHex: hex, width: width)
        case .highlighter: liveView.mark = Mark(kind: .highlight(stroke.points), colorHex: hex, width: Sizes.highlighterWidth(width))
        default: liveView.mark = Drag.mark(tool, from: start, to: point, shift: shift, colorHex: hex, width: width)
        }
    }

    /// Reaches the layer while drawing, to go on to the app under the drawing, or while Option is held
    /// over the spotlight or the lens, to size them.
    override func scrollWheel(with event: NSEvent) {
        guard session.effect != nil else { return session.passScroll() }
        session.scrolled(Scroll.notches(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                                        momentum: event.momentumPhase != []))
    }

    override func keyDown(with event: NSEvent) {
        if !session.handleKey(event) { super.keyDown(with: event) }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // What VoiceOver reads for the layer: how much is drawn, and on what.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? {
        let count = marks.all.count
        let drawn = "Tinypen drawing, \(count) \(count == 1 ? "mark" : "marks")"
        switch board {
        case .white: return drawn + " on a white board"
        case .black: return drawn + " on a black board"
        case nil: return drawn
        }
    }

    /// How big the spotlight or the lens is, while one is on.
    override func accessibilityValue() -> Any? {
        switch session.effect {
        case .spotlight: "Spotlight, radius \(Int(session.spotlightRadius)) points"
        case .zoom: String(format: "Zoom %.1f times", session.magnification)
        default: nil
        }
    }
}

/// A view that never takes a click: the overlay under it handles every one.
class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }
}

/// The finished marks, drawn only when they change.
final class MarksView: PassThroughView {
    var marks: [Mark] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        marks.forEach { MarkRenderer.draw($0, in: context) }
    }
}

/// The mark being drawn.
final class LiveView: PassThroughView {
    var mark: Mark? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let mark, let context = NSGraphicsContext.current?.cgContext else { return }
        MarkRenderer.draw(mark, in: context)
    }
}
