import AppKit
import TinypenCore

/// Drawing mode's floating toolbar, at the top of the display being drawn on. It never takes the
/// keys from the drawing layer, so the tool keys keep working while it shows.
@MainActor
final class Toolbar: NSObject, NSPopoverDelegate {
    private unowned let session: Session
    private let panel: NSPanel
    private var toolButtons: [Tool: ToolButton] = [:]
    private var colorButton: ColorButton!
    private var sizeButtons: [ToolButton] = []
    private var undo: ToolButton!
    private var clear: ToolButton!
    private var palette: NSPopover?
    private var picker: ColorPicker?

    init(session: Session) {
        self.session = session
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
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
        colorButton = ColorButton(hex: session.preferences.colorHex, tip: "Colour") { [unowned self] in togglePalette() }
        sizeButtons = Sizes.widths.indices.map { index in
            ToolButton(image: Self.line(weight: 1 + CGFloat(index) * 2),
                       tip: "Size \(index + 1) of \(Sizes.widths.count), [ and ] to step") { [unowned self] in
                session.pickSize(index)
            }
        }
        undo = ToolButton(symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)") { [unowned self] in session.undo() }
        clear = ToolButton(symbol: "trash", tip: "Clear (Delete)") { [unowned self] in session.clearAll() }
        let done = ToolButton(symbol: "xmark", tip: "Clear and stop drawing") { [unowned self] in session.leave() }

        let row = NSStackView(views: [marking, pointer, group([colorButton]), group(sizeButtons), group([undo, clear]), done])
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
        palette?.close()
        panel.orderOut(nil)
    }

    func refresh() {
        let chosen = session.effect ?? session.markingTool
        for (tool, button) in toolButtons { button.isChosen = tool == chosen }
        let hex = session.preferences.colorHex
        colorButton?.hex = hex
        colorButton?.toolTip = "Colour \(hex), 1 to 6 for the six"
        colorButton?.setAccessibilityLabel("Colour \(hex)")
        picker?.chosen = hex
        for (index, button) in sizeButtons.enumerated() { button.isChosen = index == session.preferences.size }
        undo?.isEnabled = session.hasMarks
        clear?.isEnabled = session.hasMarks
    }

    // MARK: Colour

    /// The six, the custom colours picked lately, any colour from the colour panel and a hex code,
    /// under the colour button. A second click on the button puts it away.
    private func togglePalette() {
        if let palette, palette.isShown {
            palette.close()
            return
        }
        let picker = ColorPicker(chosen: session.preferences.colorHex, recent: session.preferences.recentColors) {
            [unowned self] hex, finished in
            session.preferences.colorHex = hex
            if finished { palette?.close() }
        }
        let popover = NSPopover()
        popover.contentViewController = picker
        // Semitransient, so working the colour panel does not close it; a click on the drawing
        // layer does, through closePalette.
        popover.behavior = .semitransient
        popover.animates = false
        popover.delegate = self
        popover.show(relativeTo: colorButton.bounds, of: colorButton, preferredEdge: .minY)
        palette = popover
        self.picker = picker
    }

    /// True when the picker was open: the click that puts it away draws nothing.
    func closePalette() -> Bool {
        guard let palette, palette.isShown else { return false }
        palette.close()
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        picker?.closeColorPanel()
        picker = nil
        palette = nil
        session.paletteClosed()
    }

    /// A size chip's glyph: a line as heavy as the size, tinted like the symbols.
    private static func line(weight: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 14), flipped: false) { rect in
            let line = NSBezierPath()
            line.move(to: NSPoint(x: rect.minX + weight / 2 + 1, y: rect.midY))
            line.line(to: NSPoint(x: rect.maxX - weight / 2 - 1, y: rect.midY))
            line.lineWidth = weight
            line.lineCapStyle = .round
            NSColor.black.setStroke()
            line.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// A toolbar button that works on the first click, as the panel is never key, and shows the
/// tool in hand filled with the accent colour.
final class ToolButton: NSButton {
    private let run: () -> Void
    var isChosen = false { didSet { paint() } }

    convenience init(symbol: String, tip: String, run: @escaping () -> Void) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        self.init(image: image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)),
                  tip: tip, run: run)
    }

    init(image: NSImage?, tip: String, run: @escaping () -> Void) {
        self.run = run
        super.init(frame: .zero)
        self.image = image
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
    override func accessibilityValue() -> Any? { isChosen ? "selected" : nil }

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

/// A colour as a dot: the toolbar's colour button, or one to pick in the picker, ringed when it is
/// the one in hand.
final class ColorButton: NSButton {
    var hex: String { didSet { needsDisplay = true } }
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
        widthAnchor.constraint(equalToConstant: 32).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("ColorButton is created in code only")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityValue() -> Any? { isChosen ? "selected" : nil }

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

/// The colour picker under the colour button: the six on top, then the custom colours picked
/// lately, any colour from the colour panel, and a hex code.
@MainActor
final class ColorPicker: NSViewController {
    var chosen: String { didSet { swatches.forEach { $0.isChosen = $0.hex == chosen } } }
    private let recent: [String]
    /// A colour, and whether it is a finished choice that puts the picker away.
    private let onPick: (_ hex: String, _ finished: Bool) -> Void
    private var swatches: [ColorButton] = []

    init(chosen: String, recent: [String], onPick: @escaping (_ hex: String, _ finished: Bool) -> Void) {
        self.chosen = chosen
        self.recent = recent
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ColorPicker is created in code only")
    }

    override func loadView() {
        let six = Palette.colors.enumerated().map { index, hex in swatch(hex, tip: "\(Palette.names[index]) (\(index + 1))") }
        let wheel = ToolButton(image: Self.wheel, tip: "Any colour") { [unowned self] in showColorPanel() }
        // Return takes it; anything that is not a colour is selected to type over.
        let field = NSTextField()
        field.placeholderString = "#RRGGBB"
        field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.setAccessibilityLabel("Hex colour")
        field.cell?.sendsActionOnEndEditing = false
        field.target = self
        field.action = #selector(typedHex(_:))
        field.widthAnchor.constraint(equalToConstant: 84).isActive = true
        let first = NSStackView(views: six)
        let second = NSStackView(views: recent.map { swatch($0, tip: $0) } + [wheel, field])
        for row in [first, second] { row.spacing = 2 }
        let column = NSStackView(views: [first, second])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view = column
        // Told, or the popover picks a size of its own and squeezes the insets away.
        preferredContentSize = column.fittingSize
    }

    private func swatch(_ hex: String, tip: String) -> ColorButton {
        let button = ColorButton(hex: hex, tip: tip) { [unowned self] in
            chosen = hex
            onPick(hex, true)
        }
        button.isChosen = hex == chosen
        swatches.append(button)
        return button
    }

    @objc private func typedHex(_ sender: NSTextField) {
        guard let hex = Palette.hex(typed: sender.stringValue) else {
            NSSound.beep()
            sender.selectText(nil)
            return
        }
        chosen = hex
        onPick(hex, true)
    }

    /// Raised over the drawing layer, or it would open under it out of reach, and on every Space,
    /// so a full-screen slideshow is not left for another Space to show it.
    private func showColorPanel() {
        let panel = NSColorPanel.shared
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The colour first, while the panel points nowhere: setting it in code sends the action as
        // if it had been picked.
        panel.setTarget(nil)
        panel.color = NSColor(cgColor: Palette.color(chosen)) ?? .systemRed
        Self.colorPanelOwner = self
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.orderFront(nil)
    }

    /// Applied as it changes, so the next stroke is in it; kept when the picker closes.
    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        guard let color = sender.color.usingColorSpace(.sRGB) else { return }
        chosen = Palette.hex(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
        onPick(chosen, false)
    }

    /// The colour panel goes with the picker. It is let go first, or a later change in it would
    /// still recolour the pen.
    func closeColorPanel() {
        guard Self.colorPanelOwner === self else { return }
        Self.colorPanelOwner = nil
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NSColorPanel.shared.orderOut(nil)
    }

    /// NSColorPanel does not say who its target is, so the picker that took it last is remembered,
    /// and only that one lets it go.
    private static weak var colorPanelOwner: ColorPicker?

    /// A hue wheel, in full colour rather than tinted like the symbols.
    private static let wheel = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let steps = 36
        for step in 0..<steps {
            let wedge = NSBezierPath()
            wedge.move(to: centre)
            wedge.appendArc(withCenter: centre, radius: rect.width / 2, startAngle: CGFloat(step) * 10,
                            endAngle: CGFloat(step + 1) * 10 + 0.5)
            wedge.close()
            NSColor(hue: CGFloat(step) / CGFloat(steps), saturation: 0.85, brightness: 1, alpha: 1).setFill()
            wedge.fill()
        }
        return true
    }
}
