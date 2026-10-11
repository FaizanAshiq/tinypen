import AppKit

/// The menu bar while Settings or the colour picker is in front: Command comma, the editing keys,
/// Command W and Command Q work as in any Mac app. Tinypen has no Dock icon, so this is the only time it shows.
@MainActor
enum MainMenu {
    static func install(settings: Selector, quit: Selector, target: AnyObject) {
        let bar = NSMenu()
        let app = NSMenu(title: "Tinypen")
        let settingsItem = NSMenuItem(title: "Settings...", action: settings, keyEquivalent: ",")
        settingsItem.target = target
        app.addItem(settingsItem)
        app.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Tinypen", action: quit, keyEquivalent: "q")
        quitItem.target = target
        app.addItem(quitItem)
        // A text field takes Command V and the rest from here. Found testing: with no Edit menu, a hex
        // code could not be pasted into the colour picker.
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        for menu in [app, edit, window] {
            let item = NSMenuItem()
            item.submenu = menu
            bar.addItem(item)
        }
        NSApp.mainMenu = bar
    }
}
