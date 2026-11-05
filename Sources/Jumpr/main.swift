import AppKit
import JumprCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusItem = StatusItem()
let scanner = Scanner()
let treeRegistry = TreeRegistry()
let keyTap = KeyTap()
let controller = Controller(scanner: scanner, registry: treeRegistry, tap: keyTap)
log("launch")
let trusted = AXIsProcessTrusted()
log("trusted: \(trusted)")

let defaults = UserDefaults.standard
keyTap.hotkey = defaults.string(forKey: Keys.hotkey).flatMap { Hotkey(stored: $0) } ?? .default
controller.readout.enabled = defaults.bool(forKey: Keys.showReadout)
// The tap callback must return at once: the trigger runs on main's next turn.
keyTap.onHotkey = { DispatchQueue.main.async { controller.trigger() } }
keyTap.onKey = { controller.handle($0) }
keyTap.onDisabled = { log("key tap: re-enabled after the system switched it off") }
controller.onMatched = { target, _ in log("matched \(target.role)") }
log("key tap: \(trusted ? keyTap.start() : false)")

// Debug: `kill -USR1 <pid>` = scan + paint without the keyboard, cancelled after 2 s.
signal(SIGUSR1, SIG_IGN)
let debugSignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
debugSignal.setEventHandler {
    controller.trigger(capture: false)
    guard controller.isActive else { return }  // that signal cancelled a running session
    let gen = controller.generation
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        if controller.isActive && controller.generation == gen { controller.cancel() }
    }
}
debugSignal.resume()

app.run()
