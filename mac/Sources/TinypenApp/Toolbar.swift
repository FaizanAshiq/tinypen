import AppKit
import TinypenCore

/// Drawing mode's floating toolbar, at the top of the display being drawn on. It never takes the
/// keys from the drawing layer, so the tool keys keep working while it shows.
@MainActor
final class Toolbar {
    private unowned let session: Session
    private let panel: NSPanel
    private var toolButtons: [Tool: ToolButton] = [:]
    private var colorButtons: [ColorButton] = []
    private var thinner: ToolButton!
    private var thicker: ToolButton!
    private var undo: ToolButton!
    private var clear: ToolButton!

    init(session: Session) {
        self.session = session
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        build()
    }

    private func build() {
        func tool(_ tool: Tool, _ symbol: String) -> ToolButton {
            let button = ToolButton(symbol: symbol, tip: "\(tool.title) (\(tool.key.uppercased()))") { [unowned self] in
                session.pick(tool)
            }
            toolButtons[tool] = button
            return button
        }
        let marking = group([tool(.pen, "pencil.tip"), tool(.highlighter, "highlighter"), tool(.arrow, "arrow.up.right"),
                             tool(.box, "rectangle")])
        let pointer = group([tool(.laser, "smallcircle.filled.circle"), tool(.spotlight, "flashlight.on.fill"),
                             tool(.zoom, "plus.magnifyingglass"),
                             ToolButton(symbol: "rectangle.inset.filled", tip: "Board, white then black (W)") { [unowned self] in
                                 session.cycleBoard()
                             }])
        colorButtons = Palette.colors.enumerated().map { index, hex in
            ColorButton(hex: hex, tip: "\(Palette.names[index]) (\(index + 1))") { [unowned self] in session.pickColor(index) }
        }
        let colors = group(colorButtons)
        thinner = ToolButton(symbol: "minus", tip: "Thinner ([)") { [unowned self] in session.stepSize(-1) }
        thicker = ToolButton(symbol: "plus", tip: "Thicker (])") { [unowned self] in session.stepSize(1) }
        undo = ToolButton(symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)") { [unowned self] in session.undo() }
        clear = ToolButton(symbol: "trash", tip: "Clear (Delete)") { [unowned self] in session.clearAll() }
        let done = ToolButton(symbol: "xmark", tip: "Clear and stop drawing") { [unowned self] in session.leave() }

        let row = NSStackView(views: [marking, pointer, colors, group([thinner, thicker]), group([undo, clear]), done])
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

        let ground: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.contentView = row
            glass.cornerRadius = 22
            ground = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 22
            blur.layer?.masksToBounds = true
            row.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                row.topAnchor.constraint(equalTo: blur.topAnchor),
                row.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            ])
            ground = blur
        }
        panel.contentView = ground
        panel.setContentSize(row.fittingSize)
        refresh()
    }

    private func group(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 2
        return stack
    }

    /// Centred at the top of the display, just under the menu bar.
    func show(over screenFrame: NSRect) {
        let screen = NSScreen.screens.first { $0.frame == screenFrame } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? screenFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
        refresh()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func refresh() {
        let chosen = session.effect ?? session.markingTool
        for (tool, button) in toolButtons { button.isChosen = tool == chosen }
        for button in colorButtons { button.isChosen = button.hex == session.preferences.colorHex }
        thinner?.isEnabled = session.preferences.size > 0
        thicker?.isEnabled = session.preferences.size < Sizes.widths.count - 1
        undo?.isEnabled = session.hasMarks
        clear?.isEnabled = session.hasMarks
    }
}

/// A toolbar button that works on the first click, as the panel is never key, and shows the
/// tool in hand filled with the accent colour.
final class ToolButton: NSButton {
    private let run: () -> Void
    var isChosen = false { didSet { paint() } }

    init(symbol: String, tip: String, run: @escaping () -> Void) {
        self.run = run
        super.init(frame: .zero)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        self.image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 13
        toolTip = tip
        setAccessibilityLabel(tip)
        target = self
        action = #selector(pressed)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 32).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        paint()
    }

    required init?(coder: NSCoder) {
        fatalError("ToolButton is created in code only")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func pressed() { run() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = self.isChosen ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        }
        contentTintColor = isChosen ? .white : .labelColor
    }
}

/// One of the six colours, ringed when it is the one in hand.
final class ColorButton: NSButton {
    let hex: String
    private let run: () -> Void
    var isChosen = false { didSet { needsDisplay = true } }

    init(hex: String, tip: String, run: @escaping () -> Void) {
        self.hex = hex
        self.run = run
        super.init(frame: .zero)
        isBordered = false
        title = ""
        toolTip = tip
        setAccessibilityLabel(tip)
        target = self
        action = #selector(pressed)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("ColorButton is created in code only")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func pressed() { run() }

    override func draw(_ dirtyRect: NSRect) {
        let dot = NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16)
        NSColor(cgColor: Palette.color(hex))?.setFill()
        let circle = NSBezierPath(ovalIn: dot)
        circle.fill()
        NSColor.separatorColor.setStroke()
        circle.lineWidth = 1
        circle.stroke()
        guard isChosen else { return }
        let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -3.5, dy: -3.5))
        NSColor.controlAccentColor.setStroke()
        ring.lineWidth = 2
        ring.stroke()
    }
}
