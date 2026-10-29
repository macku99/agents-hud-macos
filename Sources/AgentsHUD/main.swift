import AppKit
import HUDApp

let app = NSApplication.shared
let composition = AppComposition()
app.delegate = composition
app.setActivationPolicy(.accessory)
app.run()
