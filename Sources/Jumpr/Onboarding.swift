import AppKit
import ApplicationServices
import JumprCore
import ServiceManagement

/// Tracks the Accessibility permission. Trust changes are learned from the system's
/// `com.apple.accessibility.api` distributed notification, re-checked 0.5 s and again 2 s
/// after it fires (the answer lags the notification, sometimes by more than 0.5 s). Two
/// one-shot checks per notification; no polling. Main thread only.
final class Onboarding: ObservableObject {
    @Published private(set) var trusted = false
    /// The grant arrived but the key listener still could not start.
    @Published private(set) var needsRelaunch = false
    /// Set while a relaunch is in flight: a second click must not start a second instance.
    private var relaunching = false

    private var onTrusted: () -> Bool = { true }
    private var onLost: () -> Void = {}
    private var observer: DistributedObserver?

    static let accessibilityPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Reads the current trust. Trusted: calls `onTrusted` (starts the key listener; false
    /// means it could not). Not trusted: asks the system once to prompt, which also puts
    /// Jumpr in the Accessibility list. Then watches for changes.
    func start(onTrusted: @escaping () -> Bool, onLost: @escaping () -> Void) {
        self.onTrusted = onTrusted
        self.onLost = onLost
        trusted = AXIsProcessTrusted()
        if trusted {
            needsRelaunch = !onTrusted()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        // Delivered immediately even while Jumpr is not the active app (it rarely is).
        observer = DistributedObserver("com.apple.accessibility.api") { [weak self] in
            for delay in [0.5, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.recheck() }
            }
        }
    }

    /// Compares the system's answer with the last known trust and acts on a change.
    func recheck() {
        let now = AXIsProcessTrusted()
        guard now != trusted else { return }
        trusted = now
        log("trust: \(now ? "gained" : "lost")")
        if now {
            needsRelaunch = !onTrusted()
        } else {
            needsRelaunch = false
            onLost()
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(Self.accessibilityPane)
    }

    /// Starts a new instance of this bundle, then quits this one — only once the new
    /// instance is running. If it could not start, this one stays.
    func relaunch() {
        guard !relaunching else { return }
        relaunching = true
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { app, error in
            DispatchQueue.main.async {
                if let error {
                    log("relaunch: failed (\(error.localizedDescription)), staying")
                    self.relaunching = false
                    return
                }
                log("relaunch: new instance running (pid \(app.map { String($0.processIdentifier) } ?? "?"))")
                NSApp.terminate(nil)
            }
        }
    }
}

/// Start at login, backed by `SMAppService.mainApp`. `enabled` always mirrors the
/// service's real status. Main thread only.
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    /// The user flipped the toggle: the only way Jumpr ever registers a login item.
    func set(_ on: Bool) {
        Self.register(on)
        refresh()
    }

    /// Registers or unregisters the login item and logs the result. Any thread.
    private static func register(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
            log("login item: \(on ? "register" : "unregister") ok, status \(service.status.rawValue)")
        } catch {
            log("login item: \(on ? "register" : "unregister") failed (\(error.localizedDescription))")
        }
    }
}
