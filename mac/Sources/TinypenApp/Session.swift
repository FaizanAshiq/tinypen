import AppKit
import TinypenCore

/// Drawing mode, the tool in hand, the pointer effect and every display's layer. With a marking
/// tool in hand the layers take the mouse; otherwise they show what was drawn and the laser,
/// spotlight or lens, and pass every click through.
@MainActor
final class Session {
    private(set) var drawing = false
    /// The laser, the spotlight or the zoom lens, following the pointer; nil for none.
    private(set) var effect: Tool?
    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            onPreferences?(preferences)
            toolbar.refresh()
        }
    }
    private(set) var spotlightRadius = Spotlight.radius
    private(set) var magnification: CGFloat = 2
    private var overlays: [Overlay] = []
    private let zoom = ZoomFeed()
    private lazy var toolbar = Toolbar(session: self)
    /// Where a mark was drawn: its display, and on the board or not.
    private struct Turn: Hashable {
        let display: CGDirectDisplayID
        let onBoard: Bool
    }
    /// Where each mark was drawn, in order, so undo takes back the newest one showing, wherever it is.
    private var history: [Turn] = []
    private var lastWasClear = false
    /// The colour picker is open, and its hex field may want the keys.
    private var pickingColor = false
    /// Tinypen's own window wants the keys: Settings recording a hotkey, or a message.
    private var keysPaused = false
    /// Option is held, so the spotlight or the lens takes the scroll that sizes it.
    private var sizing = false
    /// A scroll while drawing goes on to the app under the drawing.
    private var passingScroll = false
    private var passingWatch: Any?
    private var passingPause: DispatchWorkItem?
    private var screens: NSObjectProtocol?
    private lazy var keys = DrawingKeys { [unowned self] key in
        _ = handleKey(code: key.code, command: key.command, character: key.character)
    }
    /// The app in front when drawing started, which gets the keyboard back when it stops.
    private var previousApp: NSRunningApplication?
    /// The display whose layer takes the keys while drawing.
    private var keyDisplay: CGDirectDisplayID?

    var onPreferences: ((Preferences) -> Void)?
    /// Drawing mode, the effect or the marks changed, for the menu.
    var onChange: (() -> Void)?
    /// Zoom could not read the screen, as Screen Recording is not allowed.
    var onZoomRefused: (() -> Void)?

    init(preferences: Preferences) {
        self.preferences = preferences
        rebuildOverlays()
        screens = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildOverlays() }
        }
        zoom.onRefused = { [weak self] in self?.zoomRefused() }
    }

    var markingTool: Tool { preferences.tool }
    var zoomDisplay: CGDirectDisplayID? { zoom.displayID }
    var zoomFrame: IOSurfaceRef? { zoom.frame }
    var hasMarks: Bool { overlays.contains { !$0.view.isEmpty } }
    /// Marks showing for Delete to clear; an empty board has none.
    var canClear: Bool { overlays.contains { !$0.view.canvas.marks.isEmpty } }

    func overlay(for id: CGDirectDisplayID) -> Overlay? {
        overlays.first { $0.displayID == id }
    }

    private var overlayUnderPointer: Overlay? {
        overlays.first { $0.pointer() != nil } ?? overlays.first
    }

    /// A layer for every display, kept for those still there, so a display plugged in or out
    /// mid talk gets or loses its own.
    private func rebuildOverlays() {
        let screens = NSScreen.screens
        overlays.removeAll { overlay in
            guard let screen = screens.first(where: { $0.displayID == overlay.displayID }) else {
                overlay.panel.orderOut(nil)
                return true
            }
            overlay.fit(screen)
            return false
        }
        for screen in screens where !overlays.contains(where: { $0.displayID == screen.displayID }) {
            overlays.append(Overlay(screen: screen, session: self))
        }
        refresh()
    }

    // MARK: Modes

    func toggleDrawing() {
        drawing ? stopDrawing() : startDrawing()
    }

    /// Esc and the tool keys are held while drawing (refresh does it), so they reach Tinypen and not
    /// the app in front. Tinypen asks for the keyboard too, which macOS may refuse, for the colour
    /// picker's hex field. Reported: Esc in drawing mode went to the terminal behind the layer instead.
    func startDrawing() {
        drawing = true
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current { previousApp = front }
        NSApp.activate()
        refresh()
        guard let target = overlayUnderPointer else { return }
        keyDisplay = target.displayID
        takeKeys()
        toolbar.show(over: target.panel.frame)
    }

    /// The drawing layer takes the keys, again after the colour picker had them for its hex field.
    private func takeKeys() {
        guard drawing, let target = overlays.first(where: { $0.displayID == keyDisplay }) ?? overlayUnderPointer else { return }
        target.panel.makeKeyAndOrderFront(nil)
        target.panel.makeFirstResponder(target.view)
    }

    /// The marks stay and every click goes back to the apps under them, and the keyboard to the app
    /// that had it, unless Tinypen is about to show a window of its own.
    func stopDrawing(returningFocus: Bool = true) {
        overlays.forEach { $0.view.finishStroke() }
        overlays.forEach { $0.view.closeBoard() }
        stopPassingScroll()
        drawing = false
        toolbar.hide()
        overlays.filter(\.panel.isKeyWindow).forEach { $0.panel.orderOut(nil) }
        refresh()
        if returningFocus, let previousApp { previousApp.activate(from: NSRunningApplication.current, options: []) }
        previousApp = nil
    }

    /// Esc: with anything drawn, it erases it all, whatever tool is in hand, and undo brings it back;
    /// with nothing drawn, it switches every tool off: the laser, spotlight or lens, and drawing mode.
    /// An open colour picker goes first, as Esc puts away anything open.
    func escape() {
        if closePalette() { return }
        overlays.forEach { $0.view.finishStroke() }
        guard !hasMarks else {
            keepCleared()
            overlays.forEach { $0.view.erase() }
            lastWasClear = true
            refresh()
            return
        }
        effect = nil
        drawing ? stopDrawing() : refresh()
    }

    /// The toolbar's done button: every mark and board gone, the effect off, and drawing mode left.
    func leave() {
        overlays.forEach { $0.view.reset() }
        history = []
        lastWasClear = false
        effect = nil
        stopDrawing()
    }

    func toggleEffect(_ tool: Tool) {
        effect = effect == tool ? nil : tool
        refresh()
    }

    /// A marking tool to draw with, or an effect to follow the pointer.
    func pick(_ tool: Tool) {
        if tool.drawsMarks {
            effect = nil
            preferences.tool = tool
        } else {
            effect = effect == tool ? nil : tool
        }
        refresh()
    }

    /// Delete, with marks showing. With none, as on an empty board, it does nothing, so a second press
    /// leaves the first one for undo to bring back.
    func clearAll() {
        guard canClear else { return }
        keepCleared()
        overlays.forEach { $0.view.clear() }
        lastWasClear = true
        refresh()
    }

    /// Something to undo: what Delete or Esc cleared, or a mark showing. Reported: the toolbar's Undo
    /// was off after Delete, just when it had something to bring back.
    var canUndo: Bool {
        lastWasClear || history.contains { overlay(for: $0.display)?.view.canvas.showsBoard == $0.onBoard }
    }

    /// After Delete or Esc, everything they cleared comes back; otherwise the newest mark showing goes.
    /// Reported: with the board open, undo spent the turn of a mark hidden under it, which could then
    /// never be undone.
    func undo() {
        if lastWasClear {
            overlays.forEach { $0.view.undo() }
            lastWasClear = false
        } else if let index = history.lastIndex(where: { overlay(for: $0.display)?.view.canvas.showsBoard == $0.onBoard }) {
            overlay(for: history.remove(at: index).display)?.view.undo()
        }
        refresh()
    }

    func drew(on id: CGDirectDisplayID, onBoard: Bool) {
        history.append(Turn(display: id, onBoard: onBoard))
        keepCleared()
        toolbar.refresh()
        onChange?()
    }

    /// The last Delete or Esc is for good, as something came after it: no display brings back what it
    /// cleared, and the turns of the marks it took go, so each turn left is a mark undo can take back.
    /// Found testing: after Delete and a new mark, Undo stayed on and did nothing once for every mark
    /// Delete had taken.
    private func keepCleared() {
        guard lastWasClear else { return }
        lastWasClear = false
        overlays.forEach { $0.view.keepCleared() }
        var left: [Turn: Int] = [:]
        history = history.reversed().filter { turn in
            let marks = left[turn] ?? overlay(for: turn.display)?.view.canvas.count(onBoard: turn.onBoard) ?? 0
            left[turn] = marks - 1
            return marks > 0
        }.reversed()
    }

    func cycleBoard() {
        overlayUnderPointer?.view.cycleBoard()
        refresh()
    }

    func pickColor(_ index: Int) {
        guard Palette.colors.indices.contains(index) else { return }
        preferences.colorHex = Palette.colors[index]
    }

    /// True when the colour picker was open and this put it away.
    func closePalette() -> Bool {
        toolbar.closePalette()
    }

    /// The hex field may want the keys, so only Esc stays held, to put the picker away.
    func paletteOpened() {
        pickingColor = true
        holdKeys()
    }

    /// A custom colour picked is kept beside the six, and the keys go back to the drawing layer.
    func paletteClosed() {
        pickingColor = false
        preferences.recentColors = Palette.recent(adding: preferences.colorHex, to: preferences.recentColors)
        holdKeys()
        takeKeys()
    }

    /// Tinypen's own window wants the keys, or is done with them. Reported: with marks on screen, Esc
    /// in Settings erased them instead of backing out of a hotkey being recorded.
    func pauseKeys(_ paused: Bool) {
        keysPaused = paused
        holdKeys()
    }

    /// Where the toolbar was dragged to, to put it there next time.
    func toolbarMoved(to spot: ToolbarSpot) {
        preferences.toolbarSpot = spot
    }

    func pickSize(_ size: Int) {
        preferences.size = min(max(size, 0), Sizes.widths.count - 1)
    }

    func stepSize(_ step: Int) {
        pickSize(preferences.size + step)
    }

    /// A scroll reached the layer while drawing. It takes the mouse to draw, and scrolling went nowhere,
    /// as reported. Now the mouse goes through to the app under the drawing, so the page scrolls, for as
    /// long as scrolls keep coming, the pointer moving or not, and comes back half a second after the
    /// last one, for the next click to draw. Reported: a first try handed it back as soon as the pointer
    /// moved, so scrolling while moving went nowhere. The scroll that got here is lost: handing it on
    /// would need the Accessibility permission.
    func passScroll() {
        if !passingScroll {
            passingScroll = true
            overlays.forEach { $0.panel.ignoresMouseEvents = !screen.takesMouse }
            // Scrolls in other apps can be watched without any permission, unlike keys: each one puts
            // the mouse coming back off.
            passingWatch = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
                MainActor.assumeIsolated { self?.pauseLater() }
            }
        }
        pauseLater()
    }

    private func pauseLater() {
        passingPause?.cancel()
        let pause = DispatchWorkItem { [weak self] in self?.stopPassingScroll() }
        passingPause = pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: pause)
    }

    private func stopPassingScroll() {
        guard passingScroll else { return }
        passingScroll = false
        passingPause?.cancel()
        if let passingWatch { NSEvent.removeMonitor(passingWatch) }
        passingWatch = nil
        overlays.forEach { $0.panel.ignoresMouseEvents = !screen.takesMouse }
    }

    /// Option held or let go, read each frame while a pointer tool is on: held over the spotlight or
    /// the lens, the layer takes the mouse so a scroll sizes them, and lets it go again after.
    func optionHeld(_ held: Bool) {
        guard held != sizing else { return }
        sizing = held
        overlays.forEach { $0.panel.ignoresMouseEvents = !screen.takesMouse }
    }

    /// A scroll with Option held, in notches: the spotlight grows, the lens zooms.
    func scrolled(_ notches: CGFloat) {
        switch effect {
        case .spotlight: spotlightRadius = Spotlight.radius(spotlightRadius, scrolled: notches)
        case .zoom: magnification = Lens.magnification(magnification, scrolled: notches)
        default: return
        }
        overlays.forEach { $0.view.effects.needsDisplay = true }
    }

    /// Called each frame by the display the pointer is on.
    func pointer(isOn id: CGDirectDisplayID, at point: CGPoint) {
        if effect == .zoom, zoom.displayID != id { startZoom(on: id) }
    }

    private func startZoom(on id: CGDirectDisplayID) {
        guard ScreenAccess.isGranted else {
            zoomRefused()
            return
        }
        zoom.start(on: id)
    }

    private func zoomRefused() {
        guard effect == .zoom else { return }
        effect = nil
        refresh()
        onZoomRefused?()
    }

    private var screen: Screen {
        Screen(drawing: drawing, effect: effect, hasMarks: hasMarks, pickingColor: pickingColor, sizing: sizing,
               passingScroll: passingScroll, keysPaused: keysPaused)
    }

    private func holdKeys() {
        keys.hold(screen.heldKeys)
    }

    /// Every layer shown or hidden, taking the mouse or not, and the keys held, as the mode now says.
    func refresh() {
        let visible = drawing || effect != nil || hasMarks
        holdKeys()
        for overlay in overlays {
            overlay.panel.ignoresMouseEvents = !screen.takesMouse
            if visible {
                overlay.panel.orderFrontRegardless()
            } else {
                overlay.panel.orderOut(nil)
            }
            overlay.view.effects.refresh()
        }
        if effect == .zoom {
            if let id = overlays.first(where: { $0.pointer() != nil })?.displayID { startZoom(on: id) }
        } else {
            zoom.stop()
        }
        toolbar.refresh()
        onChange?()
    }

    // MARK: Keys

    /// A key the drawing layer heard, when Tinypen has the keyboard.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        guard flags.subtracting([.command, .shift]).isEmpty, flags != [.command, .shift] else { return false }
        return handleKey(code: event.keyCode, command: flags.contains(.command),
                         character: event.charactersIgnoringModifiers?.lowercased().first)
    }

    /// The keys of drawing mode, from the drawing layer or held as hotkeys. False for one it does
    /// not use.
    func handleKey(code: UInt16, command: Bool, character: Character?) -> Bool {
        switch code {
        case 53:
            escape()
            return true
        case 51, 117:
            clearAll()
            return true
        default:
            break
        }
        if command, character == "z" {
            undo()
            return true
        }
        guard !command, let key = character else { return false }
        if let tool = Tool.forKey(key) {
            pick(tool)
            return true
        }
        switch key {
        case "w": cycleBoard()
        case "1"..."6": pickColor(Int(String(key))! - 1)
        case "[": stepSize(-1)
        case "]": stepSize(1)
        default: return false
        }
        return true
    }
}
