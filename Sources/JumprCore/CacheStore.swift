/// Tuning for the background scan cache (design §7.4). Times are seconds.
public struct CacheConfig {
    /// Quiet time after the last change before a re-scan.
    public var settle = 0.3
    /// Floor on the gap between background scans of one app.
    public var minSpacing = 1.0
    /// Gap between background scans of one app, as a multiple of the last scan's duration (~5% load).
    public var spacingFactor = 20.0
    /// A change this soon after a scan finished counts as a strike.
    public var restlessWindow = 1.0
    /// Strikes in a row that mark a window restless.
    public var restlessStrikes = 3
    /// Quiet time a restless window needs before it is re-scanned.
    public var restlessQuiet = 2.0
    /// Delay after a press with no reported change before the priority re-scan.
    public var afterPress = 0.1

    public init() {}
}

/// What the cache can offer for a window right now.
public enum Served: Equatable {
    case clean([Target])
    case stale
    case never
}

/// A window whose background re-scan should start.
public struct Due: Equatable {
    public let window: WindowID
    public let pid: Int32

    public init(window: WindowID, pid: Int32) {
        self.window = window
        self.pid = pid
    }
}

/// Per-window scan cache and the rules for when a background re-scan may run.
/// Time is injected by the caller. Not thread-safe; main thread only.
public final class CacheStore {
    private struct Entry {
        var pid: Int32
        var targets: [Target]?
        var stale = true
        var lastChange = -Double.infinity
        var lastScanFinished: Double?
        var strikes = 0
        var restless = false
        var priority = false
        var pressedAt = 0.0
        var lastChangeSincePress: Double?
    }

    private let config: CacheConfig
    private var entries: [WindowID: Entry] = [:]
    /// Scans in progress per pid; a pid is scanning while its count is above zero.
    private var scanning: [Int32: Int] = [:]
    private var appNextAllowed: [Int32: Double] = [:]

    public init(config: CacheConfig = .init()) {
        self.config = config
    }

    public func changed(window: WindowID, pid: Int32, at t: Double) {
        var e = entries[window] ?? Entry(pid: pid)
        e.pid = pid
        if !e.stale {
            if let finished = e.lastScanFinished, t - finished < config.restlessWindow {
                e.strikes += 1
            } else {
                e.strikes = 0
            }
            if e.strikes >= config.restlessStrikes { e.restless = true }
        }
        e.stale = true
        e.lastChange = t
        if e.priority, t >= e.pressedAt { e.lastChangeSincePress = t }
        entries[window] = e
    }

    public func pressed(window: WindowID, pid: Int32, at t: Double) {
        var e = entries[window] ?? Entry(pid: pid)
        e.pid = pid
        e.stale = true
        e.priority = true
        e.pressedAt = t
        e.lastChangeSincePress = nil
        entries[window] = e
    }

    public func scanStarted(window: WindowID, pid: Int32, at t: Double) {
        scanning[pid, default: 0] += 1
    }

    public func scanFinished(window: WindowID, pid: Int32, targets: [Target], startedAt: Double,
                             at t: Double, background: Bool, failed: Bool) {
        let running = scanning[pid] ?? 0
        let wasScanning = running > 0
        scanning[pid] = running > 1 ? running - 1 : nil
        if var e = entries[window] {
            // A press after the scan started is not reflected in its result.
            let pressedMidScan = e.priority && e.pressedAt > startedAt
            if !failed {
                e.targets = targets
                e.lastScanFinished = t
                e.stale = e.lastChange > startedAt || pressedMidScan
                if e.restless && !e.stale {
                    e.restless = false
                    e.strikes = 0
                }
            }
            if !pressedMidScan {
                e.priority = false
                e.lastChangeSincePress = nil
            }
            entries[window] = e
        } else if !wasScanning {
            return  // window and app both forgotten: nothing to space
        }
        if background {
            appNextAllowed[pid] = t + max(config.minSpacing, config.spacingFactor * (t - startedAt))
        }
    }

    public func windowGone(_ w: WindowID) {
        entries[w] = nil
    }

    public func appGone(pid: Int32) {
        entries = entries.filter { $0.value.pid != pid }
        scanning[pid] = nil
        appNextAllowed[pid] = nil
    }

    public func served(_ w: WindowID) -> Served {
        guard let e = entries[w], let targets = e.targets else { return .never }
        return e.stale ? .stale : .clean(targets)
    }

    public func count(_ w: WindowID) -> Int? {
        entries[w]?.targets?.count
    }

    public func isRestless(_ w: WindowID) -> Bool {
        entries[w]?.restless ?? false
    }

    public func due(at t: Double, warm: (Due) -> Bool) -> [Due] {
        candidates(warm: warm)
            .filter { t >= $0.dueAt }
            .map(\.due)
    }

    /// Earliest time `due` could return something; `t` itself if something is already due.
    public func nextWake(after t: Double, warm: (Due) -> Bool) -> Double? {
        candidates(warm: warm).map(\.dueAt).min().map { max($0, t) }
    }

    /// Stale, warm windows whose app is not scanning, priority first then by window ID.
    private func candidates(warm: (Due) -> Bool) -> [(due: Due, dueAt: Double)] {
        entries
            .filter { $0.value.stale && scanning[$0.value.pid] == nil }
            .sorted { a, b in
                a.value.priority != b.value.priority ? a.value.priority : a.key < b.key
            }
            .map { (due: Due(window: $0.key, pid: $0.value.pid), dueAt: dueAt($0.value)) }
            .filter { warm($0.due) }
    }

    private func dueAt(_ e: Entry) -> Double {
        if e.priority {
            if let changedAt = e.lastChangeSincePress { return changedAt + config.settle }
            return e.pressedAt + config.afterPress
        }
        let spacedUntil = appNextAllowed[e.pid] ?? -.infinity
        if e.restless { return max(e.lastChange + config.restlessQuiet, spacedUntil) }
        return max(e.lastChange + config.settle, spacedUntil)
    }
}
