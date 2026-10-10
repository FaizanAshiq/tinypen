import AppKit

/// The menu bar while Settings is in front: Command comma, Command W and Command Q work as in
/// any Mac app. Tinypen has no Dock icon, so this is the only time it shows.
@MainActor
enum MainMenu {
    static func install(settings: Selector, target: AnyObject) {
        let bar = NSMenu()
        let app = NSMenu(title: "Tinypen")
        let settingsItem = NSMenuItem(title: "Settings...", action: settings, keyEquivalent: ",")
        settingsItem.target = target
        app.addItem(settingsItem)
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Quit Tinypen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        for menu in [app, window] {
            let item = NSMenuItem()
            item.submenu = menu
            bar.addItem(item)
        }
        NSApp.mainMenu = bar
    }
}
