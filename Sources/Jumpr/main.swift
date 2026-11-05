import AppKit
import JumprCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusItem = StatusItem()
let scanner = Scanner()
let treeRegistry = TreeRegistry()
let keyTap = KeyTap()
let controller = Controller(scanner: scanner, registry: treeRegistry, tap: keyTap)
let onboarding = Onboarding()
let loginItem = LoginItem()
let updaterController = UpdaterController()

// Power: battery, Low Power Mode, lock and pause (pause is only reflected; `applyPaused` acts on it).
// `onChange` belongs to the watcher (Task 13).
let powerSource = PowerSource()
// A capturing key listener must never be live at a lock screen. Driven by every lock
// event, not by a change in the combined state, so a stale cause cannot hide a lock.
powerSource.onLockEvent = {
    guard controller.isActive else { return }
    controller.cancel()
    log("cancelled: locked")
}
// Web trees skipped while locked (e.g. at launch) are switched on once it unlocks.
powerSource.onUnlock = { controller.enableTrees("unlock") }
log("launch")
log("trusted: \(AXIsProcessTrusted())")
powerSource.start()

let defaults = UserDefaults.standard
/// The stored hotkey, or the default when none is stored; nil for a value that does not
/// parse or has no ⌘/⌃/⌥ (ignored, the current hotkey stays).
func storedHotkey() -> Hotkey? {
    guard let s = defaults.string(forKey: Keys.hotkey) else { return .default }
    guard let h = Hotkey(stored: s), h.isValid else { return nil }
    return h
}
func applyHotkey(_ h: Hotkey) {
    guard h != keyTap.hotkey else { return }
    keyTap.hotkey = h
    log("hotkey applied: \(h.display(keyName: characterForKey)) (\(h.stored))")
}
keyTap.hotkey = storedHotkey() ?? .default
// Live, like `paused` and `showReadout`: the Settings recorder and `defaults write` both land here.
let hotkeyWatcher = DefaultsWatcher(Keys.hotkey) {
    if let h = storedHotkey() { applyHotkey(h) } else { log("hotkey: stored value ignored, not a valid hotkey") }
}
controller.readout.enabled = defaults.bool(forKey: Keys.showReadout)
let readoutWatcher = DefaultsWatcher(Keys.showReadout) {
    let on = defaults.bool(forKey: Keys.showReadout)
    guard on != controller.readout.enabled else { return }
    controller.readout.enabled = on
    log("readout: \(on ? "enabled" : "disabled")")
}

let settingsWindow = SettingsWindow(
    onboarding: onboarding, loginItem: loginItem, updater: updaterController,
    onRecording: { recording in
        keyTap.suspended = recording
        log("hotkey recorder: \(recording ? "recording, key listener suspended" : "done, key listener resumed")")
    },
    onHotkey: { applyHotkey($0) })  // usually already applied by `hotkeyWatcher`
statusItem.onSettings = { settingsWindow.show() }
statusItem.onCheckForUpdates = { updaterController.checkForUpdates() }
statusItem.canCheckForUpdates = { updaterController.canCheckForUpdates }
// The tap callback must return at once: the trigger runs on main's next turn.
// A real hotkey press proves the displays are awake and no screen saver runs.
keyTap.onHotkey = {
    DispatchQueue.main.async {
        powerSource.noteUserActivity()
        controller.trigger()
    }
}
keyTap.onKey = { controller.handle($0) }
keyTap.onDisabled = {
    // Off the tap's callback: losing trust stops (invalidates) the tap itself.
    DispatchQueue.main.async {
        if AXIsProcessTrusted() {
            log("key tap: re-enabled after the system switched it off")
        } else {
            onboarding.recheck()
        }
    }
}
let presser = Presser(scanner: scanner)
controller.onMatched = { target, drawn in
    let t0 = now()
    presser.press(target, drawn: drawn) { result, axError in
        // The raw AXPress error whenever it was not success (e.g. on a click fallback).
        let ax = axError.map { $0 == 0 ? "" : " (axpress=\($0))" } ?? ""
        let app = NSRunningApplication(processIdentifier: target.pid)?.localizedName ?? "pid \(target.pid)"
        log(String(format: "→ %@ %@ %.0f ms%@ in %@", target.role, "\(result)", (now() - t0) * 1000, ax, app))
        presser.openedMenu(target, result: result) { opened in
            guard opened else { return }
            // Label the menu the press just opened, unless a session started meanwhile.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !controller.isActive { controller.trigger() }
            }
        }
    }
}

// Pause: the `paused` default is the single source of truth. The menu item writes it;
// `defaults write com.greggoforth.jumpr paused -bool true|false` works the same way.
func applyPaused() {
    let paused = defaults.bool(forKey: Keys.paused)
    guard paused != keyTap.paused else { return }
    if paused {
        if controller.isActive { controller.cancel() }
        keyTap.paused = true
        statusItem.setPaused(true)
        log("paused")
        treeRegistry.disableAll { pid, work in scanner.perform(pid: pid, background: true, work) }
    } else {
        keyTap.paused = false
        treeRegistry.allowEnabling()
        statusItem.setPaused(false)
        log("resumed")
        controller.enableTrees("resume")
    }
}
statusItem.onTogglePause = { defaults.set(!defaults.bool(forKey: Keys.paused), forKey: Keys.paused) }
let pausedWatcher = DefaultsWatcher(Keys.paused) { applyPaused() }
applyPaused()

onboarding.start(
    onTrusted: {
        let ok = keyTap.start()
        log("key tap: \(ok)")
        controller.enableTrees("trusted")
        loginItem.autoRegisterIfFirstLaunch()
        return ok
    },
    onLost: {
        keyTap.stop()
        if controller.isActive { controller.cancel() }
        log("key tap: stopped")
        settingsWindow.show()
    })
if !onboarding.trusted {
    log("key tap: false")
    settingsWindow.show()  // the permission step is at the top
}

// Quit: switch off the trees Jumpr switched on, waiting briefly since the process is exiting.
let quitObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.willTerminateNotification, object: nil, queue: .main
) { _ in
    if controller.isActive { controller.cancel() }
    let done = treeRegistry.disableAll { pid, work in scanner.perform(pid: pid, background: false, work) }
    let finished = done.wait(timeout: .now() + 0.5) == .success
    log("quit\(finished ? "" : " (trees still switching off after 0.5 s)")")
    flushLog()
}

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

// Sparkle starts on the first turn of the run loop, once the app is running.
DispatchQueue.main.async { updaterController.start() }

// Debug: `kill -USR2 <pid>` = open Settings, the same path as the menu item.
signal(SIGUSR2, SIG_IGN)
let settingsSignal = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
settingsSignal.setEventHandler {
    log("settings: opened by SIGUSR2")
    statusItem.onSettings()
}
settingsSignal.resume()

// SIGTERM (`pkill`, logout) and SIGINT take the normal quit path above, so the trees
// Jumpr switched on are switched off.
let quitSignals: [DispatchSourceSignal] = [SIGTERM, SIGINT].map { sig in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        log("quit: \(sig == SIGTERM ? "SIGTERM" : "SIGINT")")
        NSApp.terminate(nil)
    }
    source.resume()
    return source
}

app.run()
