import AppKit
import TinypenCore

/// Click it, press a combination, done. Delete clears it.
///
/// Deliberately small: it records one binding and hands it back, and knows nothing
/// about where that binding is stored or what it will be used for.
final class HotKeyRecorderView: NSView {
    var binding: HotKeyBinding? { didSet { needsDisplay = true } }
    /// Another app holds this combination, so it does nothing right now.
    var isTaken = false { didSet { needsDisplay = true } }
    /// Return false to refuse a combination, for example one already used here.
    var onRecord: ((HotKeyBinding?) -> Bool)?
    /// Recording started or stopped. Tinypen's own hotkeys are paused meanwhile:
    /// Carbon takes a registered combination before the key event reaches any view, so
    /// pressing one here fired its action instead of being refused.
    var onRecordingChange: ((Bool) -> Void)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
            if isRecording != oldValue { onRecordingChange?(isRecording) }
        }
    }

    init(binding: HotKeyBinding?) {
        self.binding = binding
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
    }

    required init?(coder: NSCoder) {
        fatalError("HotKeyRecorderView is created in code only")
    }

    /// What VoiceOver reads for the field, for example "Capture Area hotkey".
    var accessibilityName = "Hotkey"

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 24) }

    /// Where the centred text's baseline falls, so a form can line the field up with its
    /// label rather than with its bottom edge.
    override var firstBaselineOffsetFromTop: CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        return (intrinsicContentSize.height - (font.ascender - font.descender + font.leading)) / 2 + font.ascender
    }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    // A button to accessibility, so VoiceOver finds it and can arm it, which it could
    // not while the field answered only to the mouse.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { accessibilityName }
    override func accessibilityValue() -> Any? { displayText }

    override func accessibilityPerformPress() -> Bool {
        startRecording()
        return true
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    /// Stops recording without binding anything. Closing a window does not resign its
    /// first responder, so a field left armed would come back armed and rebind on the
    /// next key pressed anywhere in the window.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            // Space or Return arms it from the keyboard.
            if event.keyCode == 49 || event.keyCode == 36 {
                startRecording()
            } else {
                super.keyDown(with: event)
            }
            return
        }

        switch event.keyCode {
        case 53:
            // Escape backs out rather than binding escape itself.
            isRecording = false
            return
        case 51, 117:
            finish(with: nil)
            return
        default:
            break
        }

        var modifiers: [ModifierKey] = []
        if event.modifierFlags.contains(.control) { modifiers.append(.control) }
        if event.modifierFlags.contains(.option) { modifiers.append(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.append(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.append(.command) }

        // A hotkey is registered system wide, so one with no modifier, Shift alone or Command
        // alone would swallow a key, a capital, a copy or a quit in every other app as well.
        let binding = HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard binding.isAllowed else {
            NSSound.beep()
            return
        }
        finish(with: binding)
    }

    private func finish(with binding: HotKeyBinding?) {
        isRecording = false
        guard onRecord?(binding) ?? true else {
            NSSound.beep()
            return
        }
        self.binding = binding
    }

    private var displayText: String {
        if isRecording { return "Press a combination" }
        guard let binding else { return "None" }
        return isTaken ? "\(binding.displayString)  taken" : binding.displayString
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)

        NSColor.controlBackgroundColor.setFill()
        path.fill()
        let border: NSColor = isRecording ? .controlAccentColor : isTaken ? .systemRed : .separatorColor
        border.setStroke()
        path.lineWidth = isRecording || isTaken ? 2 : 1
        path.stroke()

        let string = NSAttributedString(string: displayText, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: isRecording || binding == nil ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
        let size = string.size()
        string.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
