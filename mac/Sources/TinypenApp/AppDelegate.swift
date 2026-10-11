import AppKit
import TinypenCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var session: Session!
    private var hotkeys: HotKeyCenter!
    private var updater: Updater!
    private var settings: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var taken: Set<HotKeyAction> = []
    /// The hotkeys as last registered, so other changes leave them be.
    private var registered: HotKeys?
    private var pendingSave: DispatchWorkItem?
    /// Whether zoom could read the screen when Tinypen started. A Screen Recording grant made
    /// later only takes once Tinypen restarts, which System Settings offers as Quit and Reopen.
    private var couldReadScreenAtLaunch = false
    private var suppressRelaunchOnQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        couldReadScreenAtLaunch = ScreenAccess.isGranted
        let url = Preferences.defaultFileURL
        let firstLaunch = !FileManager.default.fileExists(atPath: url.path)
        let preferences = Preferences.load(from: url)
        session = Session(preferences: preferences)
        hotkeys = HotKeyCenter { [weak self] action in self?.perform(action) }
        register(preferences.hotkeys)
        session.onPreferences = { [weak self] preferences in self?.changed(preferences) }
        session.onChange = { [weak self] in self?.refreshStatusItem() }
        session.onZoomRefused = { [weak self] in self?.explainZoom() }
        MainMenu.install(settings: #selector(showSettings(_:)), quit: #selector(quit), target: self)
        refreshStatusItem()
        // First, as a copy opened from Downloads may move itself to Applications and start again there.
        updater = Updater(isIdle: { [weak self] in self?.isIdle ?? false }, quit: { [weak self] in
            // Not the relaunch a fresh Screen Recording grant asks for: the update starts the new copy.
            self?.suppressRelaunchOnQuit = true
            NSApp.terminate(nil)
        })
        updater.start()
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

    /// Found reading: every change, each step of a drag in the colour wheel among them, registered
    /// every hotkey again and wrote the file. Now the hotkeys are registered again only when they
    /// change, and the file is written a moment after the last change, and at quit.
    private func changed(_ preferences: Preferences) {
        pendingSave?.cancel()
        let save = DispatchWorkItem { try? preferences.save(to: Preferences.defaultFileURL) }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: save)
        if preferences.hotkeys != registered { register(preferences.hotkeys) }
        refreshStatusItem()
    }

    private func register(_ keys: HotKeys) {
        taken = hotkeys.register(keys)
        registered = keys
    }

    /// Nothing shows and nothing would be lost, so an update can restart Tinypen.
    private var isIdle: Bool {
        session.isIdle && settings?.window?.isVisible != true
    }

    @objc private func quit() {
        suppressRelaunchOnQuit = true
        NSApp.terminate(nil)
    }

    /// Something other than our own Quit is ending this run, and the screen became readable while it
    /// ran: that is System Settings' Quit and Reopen, whose reopen half left Tinypen gone (11 Oct,
    /// after allowing zoom). Tinypen opens again once this copy is gone, as the hotkeys are held
    /// exclusively until then, and only if macOS has not already opened it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !suppressRelaunchOnQuit, ScreenAccess.isGranted, !couldReadScreenAtLaunch else { return .terminateNow }
        _ = Updater.launch(#"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; sleep 1; pgrep -qf "$2/Contents/MacOS/" || open "$2""#,
                           [Bundle.main.bundlePath])
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingSave?.perform()
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
        if let line = updater.updatedLine {
            // No action, so it shows as a line of text rather than something to click.
            menu.addItem(NSMenuItem(title: line, action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        }
        if let release = updater.available {
            let download = NSMenuItem(title: "Download Tinypen \(release.version)...", action: #selector(downloadUpdate), keyEquivalent: "")
            download.target = self
            menu.addItem(download)
            menu.addItem(.separator())
        }
        for action in HotKeyAction.allCases {
            let binding = session.preferences.hotkeys[action]
            var title = action.title
            if binding != nil, taken.contains(action) { title += " (taken)" }
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
        let clear = NSMenuItem(title: "Clear Drawings", action: session.canClear ? #selector(clearDrawings) : nil, keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Quit Tinypen", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
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

    @objc private func downloadUpdate() {
        updater.openDownload()
    }

    @objc private func clearDrawings() {
        session.clearAll()
    }

    /// Out of drawing mode first, or the window would open under the layer that takes the clicks.
    @objc func showSettings(_ sender: Any?) {
        if session.drawing { session.stopDrawing(returningFocus: false) }
        if settings == nil {
            settings = SettingsWindowController(session: session, taken: { [weak self] in self?.taken ?? [] },
                                                onRecordingChange: { [weak self] recording in
                                                    guard let self else { return }
                                                    // Esc backs out of recording, so Tinypen lets go of it.
                                                    session.pauseKeys(recording)
                                                    if recording {
                                                        hotkeys.unregisterAll()
                                                    } else {
                                                        register(session.preferences.hotkeys)
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
        session.stopDrawing(returningFocus: false)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Zoom needs Screen Recording"
        alert.informativeText = "Allow Tinypen under Privacy & Security, Screen Recording in System Settings, then quit and "
            + "open Tinypen again. Nothing else in Tinypen needs it, and nothing it sees leaves your Mac."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        // Esc answers Not Now, so Tinypen lets go of it while the message shows.
        session.pauseKeys(true)
        let answer = alert.runModal()
        session.pauseKeys(false)
        guard answer == .alertFirstButtonReturn else { return }
        // Asking puts Tinypen in the Screen Recording list, where it can be switched on.
        ScreenAccess.request()
        ScreenAccess.openSettings()
    }
}
