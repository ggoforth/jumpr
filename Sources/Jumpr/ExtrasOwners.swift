import AppKit
import ApplicationServices

/// The apps that own menu bar extras (Control Center, Wi-Fi, a password manager's icon).
/// The menu bar's windows belong to the window server, so the window list never names
/// these apps and a trigger would not scan them. They are found by asking each running
/// app once, off the main thread, and kept up to date as apps launch and quit; a trigger
/// only reads the remembered set.
///
/// An app that adds its icon later in its life is picked up at the next `refreshAll`
/// (trust, resume, unlock).
final class ExtrasOwners {
    private let lock = NSLock()
    private var pids = Set<Int32>()
    /// One queue for the lookups: each is a single short request, not a tree walk.
    private let queue = DispatchQueue(label: "jumpr.extras", qos: .utility)

    /// The owners known so far. Safe from any thread.
    var current: Set<Int32> { lock.withLock { pids } }

    /// Asks every running app again.
    func refreshAll() {
        let all = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        queue.async { [self] in
            let found = Set(all.filter(Self.hasExtras))
            lock.withLock { pids = found }
            log("menu bar extras: \(found.count) apps")
        }
    }

    /// Asks one app (after it launched).
    func check(pid: Int32) {
        queue.async { [self] in
            if Self.hasExtras(pid) { lock.withLock { _ = pids.insert(pid) } }
        }
    }

    func forget(pid: Int32) {
        lock.withLock { _ = pids.remove(pid) }
    }

    private static func hasExtras(_ pid: Int32) -> Bool {
        guard pid != getpid() else { return false }
        return axCopy(axApp(pid), "AXExtrasMenuBar") != nil
    }
}
