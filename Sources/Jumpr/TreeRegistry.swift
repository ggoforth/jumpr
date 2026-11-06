import AppKit
import ApplicationServices
import JumprCore

/// Web-based apps (Electron, Chromium) keep their accessibility tree off until asked.
/// Records only the trees Jumpr itself switched on, so it can switch exactly those back
/// off. An `AXEnhancedUserInterface` another tool switched on is left alone; an
/// `AXManualAccessibility` cannot be read back, so Jumpr cannot tell (design: Known limits).
/// `enableIfNeeded` and `noteScan` make AX calls: call them off the main thread (on the
/// pid's scan queue). `disableAll` and `allowEnabling` may be called from main.
final class TreeRegistry {
    static let chromiumIDs: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]

    private static let manualAttr = "AXManualAccessibility"
    private static let enhancedAttr = "AXEnhancedUserInterface"

    private let lock = NSLock()
    private var seen = Set<Int32>()
    private var manual = Set<Int32>()
    private var enhanced = Set<Int32>()
    /// Apps whose `AXEnhancedUserInterface` was already on: never touched again.
    private var enhancedByOthers = Set<Int32>()
    private var scans: [Int32: Int] = [:]
    /// When Jumpr last switched each app's tree on, by either attribute (`now()`), for `sinceEnabled`.
    private var enabledAt: [Int32: Double] = [:]
    /// False from `disableAll` until `allowEnabling`: work queued before a pause
    /// must not switch a tree back on after it.
    private var enabling = true
    /// Set once the locked-screen skip in `noteScan` has been logged, until the screen unlocks.
    private var loggedLockedSkip = false

    var enabledPids: Set<Int32> { lock.withLock { manual } }

    /// Seconds since Jumpr switched this app's web tree on, or nil if it never did. The tree
    /// arrives some time after (see `treeMayStillBeBuilding`). Safe from any thread.
    func sinceEnabled(_ pid: Int32) -> Double? {
        lock.withLock { enabledAt[pid].map { now() - $0 } }
    }

    /// Whether `enableIfNeeded` already ran for `pid` (cheap; safe from any thread).
    func hasSeen(_ pid: Int32) -> Bool { lock.withLock { seen.contains(pid) } }

    /// The caller has seen a visible window for `pid`. On first sight of a regular app,
    /// sets `AXManualAccessibility`, and records the pid only if the app accepted it.
    func enableIfNeeded(pid: Int32, bundleID: String?) {
        guard lock.withLock({ enabling && seen.insert(pid).inserted }) else { return }
        guard NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { return }
        let app = axApp(pid)
        // No "already on" check here: `AXManualAccessibility` is write-only in practice (a
        // read never returns true), unlike `AXEnhancedUserInterface` in `noteScan`.
        // Record the pid before switching the tree on, so a `disableAll` that starts during
        // the call still switches it off (its work queues behind this on the pid's queue).
        guard record(pid, in: \.manual) else { return }
        let err = AXUIElementSetAttributeValue(app, Self.manualAttr as CFString, kCFBooleanTrue)
        switch err {
        case .success:
            lock.withLock { enabledAt[pid] = now() }
            log("tree on: AXManualAccessibility \(bundleID ?? "pid \(pid)")")
        case .cannotComplete:
            // Did not answer in time: try again next sight.
            lock.withLock { _ = manual.remove(pid); _ = seen.remove(pid) }
        default:
            lock.withLock { _ = manual.remove(pid) }  // native apps don't support it; their tree is always on
        }
    }

    /// Records one finished scan of the app. A Chromium browser whose page is missing from
    /// its tree (`webTreeLooksEmpty`) also gets `AXEnhancedUserInterface`, unless it is
    /// already on: at once if it refused `AXManualAccessibility` (Chrome), else from its
    /// second scan (`mayAskForEnhancedTree`). Skipped when the screen was locked during
    /// the scan (`screenLocked`, taken by the caller when the scan ran): every window scan
    /// is empty then.
    func noteScan(pid: Int32, bundleID: String?, walkedWindow: Bool, webTargets: Int, screenLocked locked: Bool) {
        let (count, manualAccepted): (Int, Bool) = lock.withLock {
            scans[pid, default: 0] += 1
            return (scans[pid]!, manual.contains(pid))
        }
        guard mayAskForEnhancedTree(scan: count, manualAccepted: manualAccepted),
              webTreeLooksEmpty(walkedWindow: walkedWindow, webTargets: webTargets),
              let bundleID, Self.chromiumIDs.contains(bundleID),
              lock.withLock({ enabling && !enhanced.contains(pid) && !enhancedByOthers.contains(pid) })
        else { return }
        let logSkip: Bool = lock.withLock {
            defer { loggedLockedSkip = locked }
            return locked && !loggedLockedSkip
        }
        if logSkip { log("tree: AXEnhancedUserInterface not considered while the screen is locked") }
        if locked { return }
        let app = axApp(pid)
        if Self.isOn(app, Self.enhancedAttr) {
            lock.withLock { _ = enhancedByOthers.insert(pid) }
            log("tree already on: AXEnhancedUserInterface \(bundleID), left alone")
            return
        }
        guard record(pid, in: \.enhanced) else { return }  // before the call, as in `enableIfNeeded`
        // Go by what the attribute reads back, not by the result: Chrome answers "not
        // implemented" (-25208) and switches its page tree on all the same.
        AXUIElementSetAttributeValue(app, Self.enhancedAttr as CFString, kCFBooleanTrue)
        if Self.isOn(app, Self.enhancedAttr) {
            lock.withLock { enabledAt[pid] = now() }
            log("tree on: AXEnhancedUserInterface \(bundleID)")
        } else {
            lock.withLock { _ = enhanced.remove(pid) }
        }
    }

    /// Forgets every record, stops further enabling until `allowEnabling`, and switches
    /// off the trees Jumpr switched on. Each app's AX calls go through `perform` (its
    /// scan queue); the returned group finishes when all of them have run.
    @discardableResult
    func disableAll(using perform: (Int32, @escaping () -> Void) -> Void) -> DispatchGroup {
        let (m, e): (Set<Int32>, Set<Int32>) = lock.withLock {
            defer {
                enabling = false
                seen.removeAll(); manual.removeAll(); enhanced.removeAll()
                enhancedByOthers.removeAll(); scans.removeAll(); enabledAt.removeAll()
            }
            return (manual, enhanced)
        }
        let pids = m.union(e).sorted()
        log("trees disabled: \(pids.isEmpty ? "none" : pids.map(String.init).joined(separator: ", "))")
        let group = DispatchGroup()
        for pid in pids {
            group.enter()
            perform(pid) {
                let app = axApp(pid)
                if e.contains(pid) {
                    AXUIElementSetAttributeValue(app, Self.enhancedAttr as CFString, kCFBooleanFalse)
                }
                if m.contains(pid) {
                    AXUIElementSetAttributeValue(app, Self.manualAttr as CFString, kCFBooleanFalse)
                }
                group.leave()
            }
        }
        return group
    }

    /// Lets trees be switched on again (after a resume); they come back on the next trigger.
    func allowEnabling() {
        lock.withLock { enabling = true }
    }

    /// Adds `pid` to a record set unless disabling has begun. False: do not switch anything on.
    private func record(_ pid: Int32, in set: ReferenceWritableKeyPath<TreeRegistry, Set<Int32>>) -> Bool {
        lock.withLock {
            guard enabling else { return false }
            self[keyPath: set].insert(pid)
            return true
        }
    }

    private static func isOn(_ app: AXUIElement, _ attr: String) -> Bool {
        (axCopy(app, attr) as? Bool) == true
    }
}

/// True while the login session's screen is locked. Not an accessibility call.
func screenIsLocked() -> Bool {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (d["CGSSessionScreenIsLocked"] as? Bool) == true
}
