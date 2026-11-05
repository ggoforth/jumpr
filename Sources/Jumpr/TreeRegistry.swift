import AppKit
import ApplicationServices

/// Web-based apps (Electron, Chromium) keep their accessibility tree off until asked.
/// Records only the trees Jumpr itself switched on, so it can switch exactly those back
/// off: a tree another tool (VoiceOver, another labeler) switched on is left alone.
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
    /// False from `disableAll` until `allowEnabling`: work queued before a pause
    /// must not switch a tree back on after it.
    private var enabling = true
    /// Set once the locked-screen skip in `noteScan` has been logged, until the screen unlocks.
    private var loggedLockedSkip = false

    var enabledPids: Set<Int32> { lock.withLock { manual } }

    /// The caller has seen a visible window for `pid`. On first sight of a regular app,
    /// sets `AXManualAccessibility` unless it is already on, and records the pid only
    /// if Jumpr switched it on.
    func enableIfNeeded(pid: Int32, bundleID: String?) {
        guard lock.withLock({ enabling && seen.insert(pid).inserted }) else { return }
        guard NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { return }
        let app = axApp(pid)
        if Self.isOn(app, Self.manualAttr) {
            log("tree already on: AXManualAccessibility \(bundleID ?? "pid \(pid)"), left alone")
            return
        }
        let err = AXUIElementSetAttributeValue(app, Self.manualAttr as CFString, kCFBooleanTrue)
        switch err {
        case .success:
            lock.withLock { _ = manual.insert(pid) }
            log("tree on: AXManualAccessibility \(bundleID ?? "pid \(pid)")")
        case .cannotComplete:
            lock.withLock { _ = seen.remove(pid) }  // did not answer in time: try again next sight
        default:
            break  // native apps don't support it; their tree is always on
        }
    }

    /// Records one finished scan of the app. A Chromium browser whose windows gave zero
    /// nodes on its second scan or later also gets `AXEnhancedUserInterface`, unless it
    /// is already on. Skipped while the screen is locked: every window scan is empty then.
    func noteScan(pid: Int32, bundleID: String?, windowNodes: Int) {
        let count: Int = lock.withLock {
            scans[pid, default: 0] += 1
            return scans[pid]!
        }
        guard count >= 2, windowNodes == 0, let bundleID, Self.chromiumIDs.contains(bundleID),
              lock.withLock({ enabling && !enhanced.contains(pid) && !enhancedByOthers.contains(pid) })
        else { return }
        let locked = screenIsLocked()
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
        if AXUIElementSetAttributeValue(app, Self.enhancedAttr as CFString, kCFBooleanTrue) == .success {
            lock.withLock { _ = enhanced.insert(pid) }
            log("tree on: AXEnhancedUserInterface \(bundleID)")
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
                enhancedByOthers.removeAll(); scans.removeAll()
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

    private static func isOn(_ app: AXUIElement, _ attr: String) -> Bool {
        (axCopy(app, attr) as? Bool) == true
    }
}

/// True while the login session's screen is locked. Not an accessibility call.
func screenIsLocked() -> Bool {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (d["CGSSessionScreenIsLocked"] as? Bool) == true
}
