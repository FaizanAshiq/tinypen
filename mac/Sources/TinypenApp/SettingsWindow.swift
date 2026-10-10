import AppKit
import ServiceManagement
import TinypenCore

/// The hotkeys, open at login and the menu bar icon, and the keys of drawing mode to read.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private unowned let session: Session
    private var recorders: [HotKeyAction: HotKeyRecorderView] = [:]
    private let loginCheckbox = NSButton(checkboxWithTitle: "Open Tinypen when you log in", target: nil, action: nil)
    private let iconCheckbox = NSButton(checkboxWithTitle: "Show the menu bar icon", target: nil, action: nil)
    /// The hotkeys another app holds.
    private let taken: () -> Set<HotKeyAction>
    /// Pauses Tinypen's hotkeys while a field records, so the combination reaches the field.
    private let onRecordingChange: (Bool) -> Void

    init(session: Session, taken: @escaping () -> Set<HotKeyAction>, onRecordingChange: @escaping (Bool) -> Void) {
        self.session = session
        self.taken = taken
        self.onRecordingChange = onRecordingChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Tinypen Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        load()
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is created in code only")
    }

    private func build() {
        var rows: [(String, NSView)] = []
        for action in HotKeyAction.allCases {
            let recorder = HotKeyRecorderView(binding: session.preferences.hotkeys[action])
            recorder.accessibilityName = "\(action.title) hotkey"
            recorder.onRecord = { [weak self] binding in self?.record(binding, for: action) ?? false }
            recorder.onRecordingChange = { [weak self] recording in self?.onRecordingChange(recording) }
            recorder.widthAnchor.constraint(equalToConstant: 200).isActive = true
            recorders[action] = recorder
            rows.append((action.title, recorder))
        }
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginChanged)
        iconCheckbox.target = self
        iconCheckbox.action = #selector(iconChanged)
        iconCheckbox.toolTip = "Hidden, the hotkeys still work, and opening Tinypen again shows Settings"
        rows.append(("", loginCheckbox))
        rows.append(("", iconCheckbox))

        let keys = NSTextField(wrappingLabelWithString: """
            P pen, H highlighter, A arrow, R box, L laser, S spotlight, Z zoom, W board. \
            1 to 6 colours, [ and ] size, Command Z undo, Delete clears, Esc clears and stops drawing.
            """)
        keys.textColor = .secondaryLabelColor
        keys.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        keys.preferredMaxLayoutWidth = 262
        rows.append(("While drawing", keys))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for (label, control) in rows {
            let row = NSStackView()
            row.spacing = 12
            row.alignment = .firstBaseline
            let text = NSTextField(labelWithString: label)
            text.alignment = .right
            text.widthAnchor.constraint(equalToConstant: 110).isActive = true
            row.addArrangedSubview(text)
            row.addArrangedSubview(control)
            stack.addArrangedSubview(row)
        }
        window?.contentView = stack
        window?.setContentSize(NSSize(width: max(stack.fittingSize.width, 420), height: stack.fittingSize.height))
    }

    /// Every control from the preferences and the system as they are now.
    func load() {
        let held = taken()
        for (action, recorder) in recorders {
            recorder.binding = session.preferences.hotkeys[action]
            recorder.isTaken = held.contains(action)
        }
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        iconCheckbox.state = session.preferences.showMenuBarIcon ? .on : .off
    }

    /// Refuses a combination another Tinypen action already uses.
    private func record(_ binding: HotKeyBinding?, for action: HotKeyAction) -> Bool {
        if let binding, let owner = session.preferences.hotkeys.action(using: binding), owner != action { return false }
        session.preferences.hotkeys[action] = binding
        load()
        return true
    }

    /// Asked of macOS every time rather than stored, so it never disagrees with Login Items.
    @objc private func loginChanged() {
        do {
            if loginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "macOS did not change the login item."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        load()
    }

    @objc private func iconChanged() {
        session.preferences.showMenuBarIcon = iconCheckbox.state == .on
    }

    /// The controller outlives the window, so a recorder left listening would reopen still listening.
    func windowWillClose(_ notification: Notification) {
        recorders.values.forEach { $0.stopRecording() }
    }

    func show() {
        load()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
