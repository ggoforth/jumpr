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

    private var onTrusted: () -> Bool = { true }
    private var onLost: () -> Void = {}
    private var observer: NSObjectProtocol?

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
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
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
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { app, error in
            DispatchQueue.main.async {
                if let error {
                    log("relaunch: failed (\(error.localizedDescription)), staying")
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
    /// The "not registering" line is logged once per launch, however often trust returns.
    private var loggedNotInApplications = false

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    /// The user flipped the toggle. Also counts as setting the login item up, so Jumpr
    /// never registers itself on top of the user's choice.
    func set(_ on: Bool) {
        UserDefaults.standard.set(true, forKey: Keys.loginItemSetUp)
        apply(on)
    }

    /// Default on: on the first trusted launch from /Applications, register once.
    func autoRegisterIfFirstLaunch() {
        let path = Bundle.main.bundlePath
        let setUp = UserDefaults.standard.bool(forKey: Keys.loginItemSetUp)
        guard LoginItemPolicy.shouldAutoRegister(bundlePath: path, alreadySetUp: setUp) else {
            if !setUp && !loggedNotInApplications {
                loggedNotInApplications = true
                log("login item: not registering automatically, bundle is not in /Applications (\(path))")
            }
            return
        }
        UserDefaults.standard.set(true, forKey: Keys.loginItemSetUp)
        apply(true)
    }

    private func apply(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
            log("login item: \(on ? "register" : "unregister") ok, status \(service.status.rawValue)")
        } catch {
            log("login item: \(on ? "register" : "unregister") failed (\(error.localizedDescription))")
        }
        refresh()
    }
}
