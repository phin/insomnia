import AppKit

// Insomnia — menu bar app entry point.
//
// `.accessory` activation policy + `LSUIElement` in Info.plist make this an
// agent app: a menu bar item, no Dock icon, no app menu, no focus stealing.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
