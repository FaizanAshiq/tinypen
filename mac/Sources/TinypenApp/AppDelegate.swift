import AppKit
import TinypenCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var session: Session!
    private var hotkeys: HotKeyCenter!
    private var settings: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var taken: Set<HotKeyAction> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let url = Preferences.defaultFileURL
        let firstLaunch = !FileManager.default.fileExists(atPath: url.path)
        let preferences = Preferences.load(from: url)
        session = Session(preferences: preferences)
        hotkeys = HotKeyCenter { [weak self] action in self?.perform(action) }
        taken = hotkeys.register(preferences.hotkeys)
        session.onPreferences = { [weak self] preferences in self?.changed(preferences) }
        session.onChange = { [weak self] in self?.refreshStatusItem() }
        session.onZoomRefused = { [weak self] in self?.explainZoom() }
        MainMenu.install(settings: #selector(showSettings(_:)), target: self)
        refreshStatusItem()
        // The first time, Settings shows the hotkeys, so the way in is never a guess.
        if firstLaunch {
            try? preferences.save(to: url)
            showSettings(nil)
        }
    }

    /// Opened again from Finder or Spotlight, as with the menu bar icon hidden: Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return false
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .draw: session.toggleDrawing()
        case .laser: session.toggleEffect(.laser)
        case .spotlight: session.toggleEffect(.spotlight)
        case .zoom: session.toggleEffect(.zoom)
        }
    }

    private func changed(_ preferences: Preferences) {
        try? preferences.save(to: Preferences.defaultFileURL)
        taken = hotkeys.register(preferences.hotkeys)
        refreshStatusItem()
    }

    // MARK: Menu bar icon

    private func refreshStatusItem() {
        guard session.preferences.showMenuBarIcon else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(systemSymbolName: "scribble.variable", accessibilityDescription: "Tinypen")
            image?.isTemplate = true
            item.button?.image = image
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        statusItem?.button?.appearsDisabled = false
    }

    /// Rebuilt each time it opens, so the ticks and the hotkeys shown always match.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for action in HotKeyAction.allCases {
            let binding = session.preferences.hotkeys[action]
            var title = action.title
            if let binding, taken.contains(action) { title += " (taken)" }
            // On the right, as macOS menus show shortcuts; written after the name only for a key
            // a menu cannot show there.
            let character = binding?.menuCharacter
            if let binding, character == nil { title += "  \(binding.displayString)" }
            let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: character ?? "")
            if let binding, character != nil { item.keyEquivalentModifierMask = Self.flags(binding.modifiers) }
            item.representedObject = action.rawValue
            item.state = isOn(action) ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Drawings", action: session.hasMarks ? #selector(clearDrawings) : nil, keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quit = NSMenuItem(title: "Quit Tinypen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private static func flags(_ modifiers: [ModifierKey]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case .control: flags.insert(.control)
            case .option: flags.insert(.option)
            case .shift: flags.insert(.shift)
            case .command: flags.insert(.command)
            }
        }
        return flags
    }

    private func isOn(_ action: HotKeyAction) -> Bool {
        switch action {
        case .draw: session.drawing
        case .laser: session.effect == .laser
        case .spotlight: session.effect == .spotlight
        case .zoom: session.effect == .zoom
        }
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = HotKeyAction(rawValue: raw) else { return }
        perform(action)
    }

    @objc private func clearDrawings() {
        session.clearAll()
    }

    /// Out of drawing mode first, or the window would open under the layer that takes the clicks.
    @objc func showSettings(_ sender: Any?) {
        if session.drawing { session.stopDrawing() }
        if settings == nil {
            settings = SettingsWindowController(session: session, taken: { [weak self] in self?.taken ?? [] },
                                                onRecordingChange: { [weak self] recording in
                                                    guard let self else { return }
                                                    if recording {
                                                        hotkeys.unregisterAll()
                                                    } else {
                                                        taken = hotkeys.register(session.preferences.hotkeys)
                                                    }
                                                })
        }
        settings?.show()
    }

    /// Zoom reads the screen, which macOS asks about. Drawing mode is left first: its layer takes
    /// every click, and the message would sit under it out of the mouse's reach. Reported: the
    /// screen stopped taking clicks, with this message and macOS's own prompt both under the layer.
    /// macOS is asked only once the person chooses to, so one message shows at a time.
    private func explainZoom() {
        session.stopDrawing()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Zoom needs Screen Recording"
        alert.informativeText = "Allow Tinypen under Privacy & Security, Screen Recording in System Settings, then quit and "
            + "open Tinypen again. Nothing else in Tinypen needs it, and nothing it sees leaves your Mac."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Asking puts Tinypen in the Screen Recording list, where it can be switched on.
        ScreenAccess.request()
        ScreenAccess.openSettings()
    }
}
