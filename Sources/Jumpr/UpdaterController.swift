import AppKit
import Combine
import JumprCore
import Sparkle

/// Owns Sparkle's standard updater, the app's only network use (the appcast check).
/// The feed address and public key are written into Info.plist by scripts/build-app.sh;
/// a development build carries neither for real, so its updater is never started and
/// "Check for Updates…" stays disabled. Main thread only.
final class UpdaterController: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    /// Sparkle's own setting, mirrored for SwiftUI; there is no second stored copy.
    @Published private(set) var automaticallyChecks = false
    let isConfigured: Bool

    private var controller: SPUStandardUpdaterController!
    private var watch: AnyCancellable?

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        isConfigured = UpdatePolicy.isConfigured(feedURL: info["SUFeedURL"] as? String,
                                                 publicKey: info["SUPublicEDKey"] as? String)
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        watch = updater.publisher(for: \.automaticallyChecksForUpdates, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.automaticallyChecks = $0 }
    }

    var updater: SPUUpdater { controller.updater }

    /// Called once the run loop is running. Does nothing in a development build.
    func start() {
        guard isConfigured else {
            log("updates: off (no release feed or key in this build)")
            return
        }
        controller.startUpdater()
        log("updates: started, automatic checks \(updater.automaticallyChecksForUpdates ? "on" : "off")")
    }

    var canCheckForUpdates: Bool { isConfigured && updater.canCheckForUpdates }

    func setAutomaticallyChecks(_ on: Bool) { updater.automaticallyChecksForUpdates = on }

    /// Jumpr has no Dock icon and is rarely the active app: activate it first so Sparkle's
    /// window opens in front instead of behind the app the user is in.
    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate
    // Gentle reminders, as Sparkle documents for background apps
    // (sparkle-project.org/documentation/gentle-reminders). Jumpr has no Dock icon, so a
    // scheduled alert Sparkle opened behind other apps could go unseen; instead Jumpr marks
    // its menu bar icon and the user brings the alert forward from the menu.

    /// Called with true while a scheduled update waits for the user, false once it has had
    /// their attention or the session is over.
    var onUpdatePending: (Bool) -> Void = { _ in }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows a scheduled update itself only when it would be in utmost focus (just
    /// after launch, or after the user was idle); otherwise Jumpr shows the reminder.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if state.userInitiated {
            NSApp.activate()
        } else if !handleShowingUpdate {
            log("updates: \(update.displayVersionString) available, reminder shown in the menu bar")
            onUpdatePending(true)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onUpdatePending(false)
    }

    func standardUserDriverWillFinishUpdateSession() {
        onUpdatePending(false)
    }
}
