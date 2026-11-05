import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusItem = StatusItem()
log("launch")
app.run()
