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
    /// The displays drawn on, in order, so undo takes back the newest mark wherever it is.
    private var history: [CGDirectDisplayID] = []
    private var lastWasClear = false
    /// The colour picker is open, and its hex field may want the keys.
    private var pickingColor = false
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

    func clearAll() {
        guard hasMarks else { return }
        overlays.forEach { $0.view.clear() }
        lastWasClear = true
        refresh()
    }

    func undo() {
        if lastWasClear {
            overlays.forEach { $0.view.undo() }
            lastWasClear = false
        } else if let id = history.popLast() {
            overlay(for: id)?.view.undo()
        }
        refresh()
    }

    func drew(on id: CGDirectDisplayID) {
        history.append(id)
        lastWasClear = false
        toolbar.refresh()
        onChange?()
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

    func pickSize(_ size: Int) {
        preferences.size = min(max(size, 0), Sizes.widths.count - 1)
    }

    /// [ and ]: while the spotlight or the lens is on, the spotlight grows by 20 points a step and the
    /// lens zooms, as scrolling did before scrolling reached the app under them; otherwise the pen.
    func stepSize(_ step: Int) {
        switch effect {
        case .spotlight: spotlightRadius = Spotlight.radius(spotlightRadius, stepped: CGFloat(step) * 20)
        case .zoom: magnification = Lens.magnification(magnification, stepped: CGFloat(step))
        default: return pickSize(preferences.size + step)
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
        Screen(drawing: drawing, effect: effect, hasMarks: hasMarks, pickingColor: pickingColor)
    }

    private func holdKeys() {
        keys.hold(screen.heldKeys)
    }

    /// Every layer shown or hidden, taking the mouse or not, and the keys held, as the mode now says.
    func refresh() {
        let visible = drawing || effect != nil || hasMarks
        holdKeys()
        for overlay in overlays {
            overlay.panel.ignoresMouseEvents = !screen.takesClicks
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
