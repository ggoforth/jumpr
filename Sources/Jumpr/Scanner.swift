import AppKit
import ApplicationServices
import JumprCore

/// `window == nil` means the app's system pieces (menu bar, extras, or the Dock).
/// For a window scan, `element` is the window's element if the caller already has it.
struct ScanRequest {
    let pid: Int32
    let window: WindowID?
    let element: AXUIElement?
}

struct WindowScan {
    let pid: Int32
    let window: WindowID?
    let targets: [Target]
    let nodes: Int
    let startedAt: Double
    let ms: Double
    let timedOut: Bool

    /// Nothing scanned: the window is hidden, gone, or (`timedOut`) the app did not answer.
    static func empty(pid: Int32, window: WindowID?, startedAt: Double, ms: Double = 0,
                      timedOut: Bool = false) -> WindowScan {
        WindowScan(pid: pid, window: window, targets: [], nodes: 0, startedAt: startedAt, ms: ms, timedOut: timedOut)
    }
}

/// `.cannotComplete` after the full request timeout = the app did not answer.
/// (Processes with no accessibility at all fail the same way, but at once.)
private func didNotAnswer(_ err: AXError, after elapsed: Double) -> Bool {
    err == .cannotComplete && elapsed >= Double(axRequestTimeout) * 0.9
}

/// Reads live accessibility trees. Every AX call runs on the target app's own serial
/// queue: apps scan in parallel, and never two scans of the same app at once.
final class Scanner {
    /// Per-app (or per-request) scan budget, seconds.
    static let budget = 0.5

    private let lock = NSLock()
    private var queues: [Int32: DispatchQueue] = [:]
    private var pending: [Int32: Int] = [:]

    init() {}

    /// True while work for `pid` is queued or running.
    func isScanning(pid: Int32) -> Bool {
        lock.withLock { pending[pid, default: 0] > 0 }
    }

    /// Runs `work` on `pid`'s serial queue — for other AX work on that app (e.g. `TreeRegistry`).
    func perform(pid: Int32, background: Bool, _ work: @escaping () -> Void) {
        let q: DispatchQueue = lock.withLock {
            pending[pid, default: 0] += 1
            if let q = queues[pid] { return q }
            let q = DispatchQueue(label: "jumpr.scan.\(pid)")
            queues[pid] = q
            return q
        }
        q.async(qos: background ? .utility : .userInteractive, flags: .enforceQoS) { [self] in
            work()
            lock.withLock {
                pending[pid, default: 1] -= 1
                if pending[pid] == 0 { pending[pid] = nil }
            }
        }
    }

    /// The app's windows with their window-server IDs. Makes AX calls: only call it from
    /// `pid`'s queue (inside `perform`), never from the main thread.
    func appWindows(pid: Int32) -> [(id: WindowID, element: AXUIElement)] {
        guard let a = axMulti(axApp(pid), windowsAttr), a.count == 1 else { return [] }
        return resolveWindows(axElements(a[0]), pid: pid, stack: nil)
    }

    /// One window, or the app's system pieces when `req.window == nil`.
    func scan(_ req: ScanRequest, stack: WindowStack, screens: [CGRect], frontPid: Int32?,
              background: Bool, completion: @escaping (WindowScan) -> Void) {
        perform(pid: req.pid, background: background) { [self] in
            let t0 = now()
            let deadline = t0 + Scanner.budget
            let result: WindowScan
            if let wid = req.window {
                if stack.win(wid) == nil || !stack.anyVisible(wid) {
                    result = .empty(pid: req.pid, window: wid, startedAt: t0)
                } else {
                    let (values, err) = axMultiResult(axApp(req.pid), windowsAttr)
                    if values == nil, didNotAnswer(err, after: now() - t0) {
                        result = .empty(pid: req.pid, window: wid, startedAt: t0, ms: (now() - t0) * 1000, timedOut: true)
                    } else {
                        var wins: [(id: WindowID, element: AXUIElement)] = []
                        if let a = values, a.count == 1 { wins = resolveWindows(axElements(a[0]), pid: req.pid, stack: nil) }
                        let element = req.element ?? wins.first { $0.id == wid }?.element
                        result = scanWindow(pid: req.pid, id: wid, element: element, appWindows: Set(wins.map(\.id)),
                                            stack: stack, deadline: deadline)
                    }
                }
            } else {
                let isDock = NSRunningApplication(processIdentifier: req.pid)?.bundleIdentifier == "com.apple.dock"
                let app = axApp(req.pid)
                var pieces: (AXUIElement?, AXUIElement?) = (nil, nil)
                var err = AXError.success
                if !isDock {  // the Dock is walked from the application element itself
                    let (values, e) = axMultiResult(app, systemAttrs)
                    if let a = values, a.count == 2 { pieces = (axElementValue(a[0]), axElementValue(a[1])) }
                    else { err = e }
                }
                if didNotAnswer(err, after: now() - t0) {
                    result = .empty(pid: req.pid, window: nil, startedAt: t0, ms: (now() - t0) * 1000, timedOut: true)
                } else {
                    result = scanSystem(pid: req.pid, app: app, isDock: isDock, isFront: req.pid == frontPid,
                                        pieces: pieces, screens: screens, stack: stack, deadline: deadline)
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Every window of the app plus its system pieces, under one per-app budget.
    /// Each result reaches `each` on the main queue as it finishes; `done` follows on main,
    /// with false if the scan stopped early because `isStale` (called on this app's queue,
    /// before the first AX call and between windows) said its trigger is gone.
    func scanApp(pid: Int32, stack: WindowStack, screens: [CGRect], frontPid: Int32?, isDock: Bool,
                 background: Bool, isStale: @escaping () -> Bool,
                 each: @escaping (WindowScan) -> Void, done: @escaping (_ complete: Bool) -> Void) {
        perform(pid: pid, background: background) { [self] in
            let t0 = now()
            let deadline = t0 + Scanner.budget
            let deliver = { (s: WindowScan) in DispatchQueue.main.async { each(s) } }
            var cut = false  // stopped early: the trigger went stale
            defer { DispatchQueue.main.async { [cut] in done(!cut) } }
            if isStale() { cut = true; return }
            let app = axApp(pid)

            if isDock {
                deliver(scanSystem(pid: pid, app: app, isDock: true, isFront: false, pieces: (nil, nil),
                                   screens: screens, stack: stack, deadline: deadline))
                return
            }

            let (values, err) = axMultiResult(app, appAttrs)
            guard let a = values, a.count == 3 else {
                let elapsed = now() - t0
                if didNotAnswer(err, after: elapsed) {
                    deliver(.empty(pid: pid, window: nil, startedAt: t0, ms: elapsed * 1000, timedOut: true))
                }
                return
            }

            let wins = resolveWindows(axElements(a[0]), pid: pid, stack: stack)
            let ids = Set(wins.map(\.id))
            for w in wins {
                if isStale() { cut = true; return }
                if stack.win(w.id) == nil || !stack.anyVisible(w.id) {
                    deliver(.empty(pid: pid, window: w.id, startedAt: now()))
                } else {
                    deliver(scanWindow(pid: pid, id: w.id, element: w.element, appWindows: ids,
                                       stack: stack, deadline: deadline))
                }
            }
            if isStale() { cut = true; return }
            deliver(scanSystem(pid: pid, app: app, isDock: false, isFront: pid == frontPid,
                               pieces: (axElementValue(a[1]), axElementValue(a[2])),
                               screens: screens, stack: stack, deadline: deadline))
        }
    }

    // MARK: - Private (all run on the pid's queue)

    private let windowsAttr = ["AXWindows"] as CFArray
    private let appAttrs = ["AXWindows", "AXMenuBar", "AXExtrasMenuBar"] as CFArray
    private let systemAttrs = ["AXMenuBar", "AXExtrasMenuBar"] as CFArray

    /// Window IDs from `_AXUIElementGetWindow`; on error, the same app's on-screen window
    /// whose bounds match the element's frame (within 1 pt per edge).
    private func resolveWindows(_ elements: [AXUIElement], pid: Int32,
                                stack: WindowStack?) -> [(id: WindowID, element: AXUIElement)] {
        var fallback = stack
        return elements.compactMap { el in
            axTimed(el)
            var id = CGWindowID(0)
            if _AXUIElementGetWindow(el, &id) == .success, id != 0 { return (id, el) }
            let s = fallback ?? WindowServer.snapshot()
            fallback = s
            guard let f = axFrame(el), let w = s.wins.first(where: { $0.pid == pid && sameWindowFrame($0.bounds, f) }) else { return nil }
            return (w.id, el)
        }
    }

    private func scanWindow(pid: Int32, id: WindowID, element: AXUIElement?, appWindows: Set<WindowID>,
                            stack: WindowStack, deadline: Double) -> WindowScan {
        let t0 = now()
        guard let element, let bounds = stack.win(id)?.bounds else {
            return .empty(pid: pid, window: id, startedAt: t0)
        }
        let r = walk(root: AXElementNode(element), pid: pid,
                     scope: .window(id: id, bounds: bounds, appWindows: appWindows),
                     stack: stack, deadline: deadline, now: now)
        return WindowScan(pid: pid, window: id, targets: r.targets, nodes: r.nodes, startedAt: t0,
                          ms: (now() - t0) * 1000, timedOut: r.timedOut)
    }

    /// Dock: the whole application tree. Otherwise the menu bar (front app only) and extras.
    /// `pieces` is (menu bar, extras), already fetched by the caller (unused for the Dock).
    private func scanSystem(pid: Int32, app: AXUIElement, isDock: Bool, isFront: Bool,
                            pieces: (AXUIElement?, AXUIElement?), screens: [CGRect],
                            stack: WindowStack, deadline: Double) -> WindowScan {
        let t0 = now()
        var roots: [AXUIElement] = []
        if isDock {
            roots = [app]
        } else {
            let (bar, extras) = pieces
            if isFront, let bar { roots.append(bar) }
            if let extras { roots.append(extras) }
        }
        var targets: [Target] = []
        var nodes = 0
        var timedOut = false
        for root in roots {
            let r = walk(root: AXElementNode(root), pid: pid, scope: .system(screens: screens),
                         stack: stack, deadline: deadline, now: now)
            targets += r.targets
            nodes += r.nodes
            timedOut = timedOut || r.timedOut
        }
        return WindowScan(pid: pid, window: nil, targets: targets, nodes: nodes, startedAt: t0,
                          ms: (now() - t0) * 1000, timedOut: timedOut)
    }
}
