import AppKit

// Tooltips name each button and its key. The system waits about a second before showing one, by
// which time the pointer has usually moved on.
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
