import AppKit
import IOKit.ps
import JumprCore

/// The system-facing source of `PowerState`: battery, Low Power Mode, lock and pause.
/// Everything here runs on the main thread: `start()`, every observer, every
/// `onChange`. `onChange` fires only when the state actually changes.
final class PowerSource {
    var onChange: (PowerState) -> Void = { _ in }
    private(set) var state = PowerState(onBattery: false, lowPower: false, locked: false, paused: false)

    private var lock = LockCauses()
    private var started = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pausedWatcher: DefaultsWatcher?
    private var batterySource: CFRunLoopSource?

    init() {}

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !started else { return }
        started = true

        // Lock: the session flag is readable now; display sleep too. The screen saver
        // has no cheap query, so it starts false and follows its notifications.
        lock = LockCauses(sessionLocked: screenIsLocked(),
                          displaysAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0,
                          screenSaver: false)

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, "com.apple.screenIsLocked") { $0.lock.sessionLocked = true }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.lock.sessionLocked = false }
        observe(distributed, "com.apple.screensaver.didstart") { $0.lock.screenSaver = true }
        observe(distributed, "com.apple.screensaver.didstop") { $0.lock.screenSaver = false }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { $0.lock.displaysAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { $0.lock.displaysAsleep = false }
        // Posted on an arbitrary thread; the observer queue brings it to main.
        observe(NotificationCenter.default, NSNotification.Name.NSProcessInfoPowerStateDidChange.rawValue) { _ in }

        pausedWatcher = DefaultsWatcher(Keys.paused) { [weak self] in self?.refresh() }

        // Battery: the callback is a C function, so `self` travels as the context pointer.
        // The source lives as long as `self` (removed in deinit), so unretained is safe.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerSource>.fromOpaque(context).takeUnretainedValue().refresh()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            batterySource = source
        } else {
            log("power: battery notifications unavailable")
        }

        state = read()
        logState()
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
        if let batterySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .defaultMode) }
    }

    /// Runs `update` on main for each `name` posted to `center`, then re-reads the state.
    private func observe(_ center: NotificationCenter, _ name: String, _ update: @escaping (PowerSource) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            update(self)
            refresh()
        }
        observers.append((center, token))
    }

    private func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        let next = read()
        guard next != state else { return }
        state = next
        logState()
        onChange(next)
    }

    private func read() -> PowerState {
        PowerState(onBattery: Self.onBattery(),
                   lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                   locked: lock.locked,
                   paused: UserDefaults.standard.bool(forKey: Keys.paused))
    }

    /// True when the Mac is running on battery. A Mac without a battery never is.
    private static func onBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    private func logState() {
        let s = state
        log("power: battery=\(s.onBattery) lowPower=\(s.lowPower) locked=\(s.locked) paused=\(s.paused)")
    }
}
