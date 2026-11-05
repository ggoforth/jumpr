import AppKit
import ApplicationServices

/// Web-based apps (Electron, Chromium) keep their accessibility tree off until asked.
/// Remembers which apps Jumpr switched on so they can be switched back off.
/// Every method makes AX calls: call them off the main thread (on the pid's scan queue).
final class TreeRegistry {
    static let chromiumIDs: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]

    private let lock = NSLock()
    private var seen = Set<Int32>()
    private var manual = Set<Int32>()
    private var enhanced = Set<Int32>()
    private var scans: [Int32: Int] = [:]

    var enabledPids: Set<Int32> { lock.withLock { manual } }

    /// The caller has seen a visible window for `pid`. On first sight of a regular app,
    /// sets `AXManualAccessibility` and records the pid if the app accepted it.
    func enableIfNeeded(pid: Int32, bundleID: String?) {
        guard lock.withLock({ seen.insert(pid).inserted }) else { return }
        guard NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { return }
        let err = AXUIElementSetAttributeValue(axApp(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
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
    /// nodes on its second scan or later also gets `AXEnhancedUserInterface`.
    func noteScan(pid: Int32, bundleID: String?, windowNodes: Int) {
        let count: Int = lock.withLock {
            scans[pid, default: 0] += 1
            return scans[pid]!
        }
        guard count >= 2, windowNodes == 0, let bundleID, Self.chromiumIDs.contains(bundleID),
              !lock.withLock({ enhanced.contains(pid) }) else { return }
        if AXUIElementSetAttributeValue(axApp(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) == .success {
            lock.withLock { _ = enhanced.insert(pid) }
            log("tree on: AXEnhancedUserInterface \(bundleID)")
        }
    }

    /// Switches every recorded app's tree back off and forgets them.
    func disableAll() {
        let (m, e): (Set<Int32>, Set<Int32>) = lock.withLock {
            defer { seen.removeAll(); manual.removeAll(); enhanced.removeAll(); scans.removeAll() }
            return (manual, enhanced)
        }
        for pid in e {
            AXUIElementSetAttributeValue(axApp(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        for pid in m {
            AXUIElementSetAttributeValue(axApp(pid), "AXManualAccessibility" as CFString, kCFBooleanFalse)
        }
        if !m.isEmpty || !e.isEmpty { log("tree off: \(m.count) manual, \(e.count) enhanced") }
    }
}
