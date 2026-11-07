import AppKit
import JumprCore
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusItem = StatusItem()
let scanner = Scanner()
let treeRegistry = TreeRegistry()
let keyTap = KeyTap()
let controller = Controller(scanner: scanner, registry: treeRegistry, tap: keyTap)
let scrollController = ScrollController(scanner: scanner, tap: keyTap, scroller: Scroller(), statusItem: statusItem,
                                        overlays: { controller.overlays })
let onboarding = Onboarding()
let loginItem = LoginItem()
let updaterController = UpdaterController()

// Power: battery, Low Power Mode, lock and pause (pause is only reflected; `applyPaused` acts on it).
// Only the lock and unlock events are acted on today; battery and Low Power Mode are only logged.
let powerSource = PowerSource()
// A capturing key listener must never be live at a lock screen. Driven by every lock
// event, not by a change in the combined state, so a stale cause cannot hide a lock.
powerSource.onLockEvent = {
    scrollController.leave("locked")
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
/// The stored hotkey under `key`, or `fallback` when none is stored; nil for a value that
/// does not parse or has no ⌘/⌃/⌥ (ignored, the current hotkey stays).
func storedHotkey(_ key: String = Keys.hotkey, fallback: Hotkey = .default) -> Hotkey? {
    guard let s = defaults.string(forKey: key) else { return fallback }
    guard let h = Hotkey(stored: s), h.isValid else { return nil }
    return h
}
func applyHotkey(_ h: Hotkey) {
    guard h != keyTap.hotkey else { return }
    keyTap.hotkey = h
    log("hotkey applied: \(h.display(keyName: characterForKey)) (\(h.stored))")
}
keyTap.hotkey = storedHotkey() ?? .default
// Live, like `paused` and `showReadout`: the panel's recorder and `defaults write` both land here.
let hotkeyWatcher = DefaultsWatcher(Keys.hotkey) {
    if let h = storedHotkey() { applyHotkey(h) } else { log("hotkey: stored value ignored, not a valid hotkey") }
}
func storedScrollHotkey() -> Hotkey? { storedHotkey(Keys.scrollHotkey, fallback: .defaultScroll) }
keyTap.scrollHotkey = storedScrollHotkey() ?? .defaultScroll
let scrollHotkeyWatcher = DefaultsWatcher(Keys.scrollHotkey) {
    guard let h = storedScrollHotkey() else { log("scroll hotkey: stored value ignored, not a valid hotkey"); return }
    guard h != keyTap.scrollHotkey else { return }
    keyTap.scrollHotkey = h
    log("scroll hotkey applied: \(h.display(keyName: characterForKey)) (\(h.stored))")
}
controller.readout.enabled = defaults.bool(forKey: Keys.showReadout)
let readoutWatcher = DefaultsWatcher(Keys.showReadout) {
    let on = defaults.bool(forKey: Keys.showReadout)
    guard on != controller.readout.enabled else { return }
    controller.readout.enabled = on
    log("readout: \(on ? "enabled" : "disabled")")
}

let panel = NSHostingController(rootView: PanelView(
    close: { statusItem.closePanel() },
    onRecording: { recording in
        keyTap.suspended = recording
        log("hotkey recorder: \(recording ? "recording, key listener suspended" : "done, key listener resumed")")
    },
    onHotkey: { applyHotkey($0) },  // usually already applied by `hotkeyWatcher`
    onboarding: onboarding, loginItem: loginItem, updater: updaterController))
// The popover follows the panel's size as banners and "More" come and go.
panel.sizingOptions = [.preferredContentSize]
statusItem.panel = panel
statusItem.willShow = { loginItem.refresh() }  // the status can change outside Jumpr
updaterController.onUpdatePending = { statusItem.setUpdatePending($0) }
// The tap callback must return at once: the trigger runs on main's next turn.
// A real hotkey press proves the displays are awake and no screen saver runs.
// Labels and scroll mode never run at once: each shortcut ends the other first.
keyTap.onHotkey = {
    DispatchQueue.main.async {
        powerSource.noteUserActivity()
        scrollController.leave("label shortcut")
        controller.trigger()
    }
}
keyTap.onScrollHotkey = {
    DispatchQueue.main.async {
        powerSource.noteUserActivity()
        if controller.isActive {
            controller.cancel()
            log("cancelled: scroll shortcut")
        }
        scrollController.toggle()
    }
}
keyTap.onKey = { scrollController.isActive ? scrollController.handle($0) : controller.handle($0) }
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
controller.onMatched = { target in
    let t0 = now()
    presser.press(target) { result, axError in
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

// Pause: the `paused` default is the single source of truth. The panel's switch writes it;
// `defaults write com.greggoforth.jumpr paused -bool true|false` works the same way.
func applyPaused() {
    let paused = defaults.bool(forKey: Keys.paused)
    guard paused != keyTap.paused else { return }
    if paused {
        if controller.isActive { controller.cancel() }
        scrollController.leave("paused")
        keyTap.paused = true
        log("paused")
        treeRegistry.disableAll { pid, work in scanner.perform(pid: pid, background: true, work) }
    } else {
        keyTap.paused = false
        treeRegistry.allowEnabling()
        log("resumed")
        controller.enableTrees("resume")
    }
}
let pausedWatcher = DefaultsWatcher(Keys.paused) { applyPaused() }
applyPaused()

onboarding.start(
    onTrusted: {
        let ok = keyTap.start()
        log("key tap: \(ok)")
        controller.enableTrees("trusted")
        loginItem.refresh()  // start at login is opt-in: only read its state
        return ok
    },
    onLost: {
        keyTap.stop()
        if controller.isActive { controller.cancel() }
        scrollController.leave("permission lost")
        log("key tap: stopped")
        statusItem.showPanel()
    })
if !onboarding.trusted {
    log("key tap: false")
    // The permission banner is at the top. On the run loop's first turn, once the menu bar
    // has placed the icon the panel hangs from.
    DispatchQueue.main.async { statusItem.showPanel() }
}

// Quit: switch off the trees Jumpr switched on, waiting briefly since the process is exiting.
let quitObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.willTerminateNotification, object: nil, queue: .main
) { _ in
    if controller.isActive { controller.cancel() }
    scrollController.leave("quit")
    let done = treeRegistry.disableAll { pid, work in scanner.perform(pid: pid, background: false, work) }
    let finished = done.wait(timeout: .now() + 0.5) == .success
    log("quit\(finished ? "" : " (trees still switching off after 0.5 s)")")
    flushLog()
}

// Sparkle starts on the first turn of the run loop, once the app is running.
DispatchQueue.main.async { updaterController.start() }

// Debug hooks for checking the app without the keyboard. Both signals are always ignored
// (their default action would end the process); they do something only when Jumpr is
// started with JUMPR_DEBUG_SIGNALS set, so a normal copy has no such hook.
//   kill -USR1 <pid>   scan + paint without capturing keys, cancelled after 2 s
//   kill -USR2 <pid>   open the panel, the same path as a click on the menu bar icon
signal(SIGUSR1, SIG_IGN)
signal(SIGUSR2, SIG_IGN)
var debugSignals: [DispatchSourceSignal] = []
if ProcessInfo.processInfo.environment["JUMPR_DEBUG_SIGNALS"] != nil {
    let scan = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    scan.setEventHandler {
        controller.trigger(capture: false)
        guard controller.isActive else { return }  // that signal cancelled a running session
        let gen = controller.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if controller.isActive && controller.generation == gen { controller.cancel() }
        }
    }
    let open = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
    open.setEventHandler {
        log("panel: opened by SIGUSR2")
        statusItem.showPanel()
    }
    debugSignals = [scan, open]
    debugSignals.forEach { $0.resume() }
    log("debug signals: on")
}

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
