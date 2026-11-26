import AppKit
import ApplicationServices
import JumprCore

struct WindowScan {
    let pid: Int32
    let window: WindowID?
    let targets: [Target]
    let nodes: Int
    let startedAt: Double
    let ms: Double
    let timedOut: Bool
    /// Web areas the walk met in this window, empty ones included.
    var webAreas = 0
    /// Elements in the walk that did not answer; their subtrees were skipped.
    var unanswered = 0
    /// Areas to scroll, from a scan for scroll mode (`Scanner.scanAreas`).
    var areas: [Area] = []

    /// Whether this scan may have missed things the app still has. A rescan must not remove
    /// labels on the strength of an incomplete scan.
    var incomplete: Bool { timedOut || unanswered > 0 }

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
    /// Apps that quit while work for them was still queued: their queue goes when it drains.
    private var quit = Set<Int32>()

    init() {}

    /// The app quit: drop its queue, now if nothing is queued for it, else once the
    /// work already queued has run (dropping it earlier would let new work for the same
    /// pid start on a fresh queue alongside it).
    func forget(pid: Int32) {
        lock.withLock {
            if pending[pid] == nil { queues[pid] = nil } else { quit.insert(pid) }
        }
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
                if pending[pid] == 0 {
                    pending[pid] = nil
                    if quit.remove(pid) != nil { queues[pid] = nil }
                }
            }
        }
    }

    /// The app's windows with their window-server IDs. Makes AX calls: only call it from
    /// `pid`'s queue (inside `perform`), never from the main thread.
    func appWindows(pid: Int32) -> [(id: WindowID, element: AXUIElement)] {
        guard let a = axMulti(axApp(pid), windowsAttr), a.count == 1 else { return [] }
        return resolveWindows(axElements(a[0]), pid: pid, stack: nil).wins
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
                                   menus: openMenus(pid: pid, app: app, stack: stack, deadline: deadline).roots,
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

            let menus = openMenus(pid: pid, app: app, stack: stack, deadline: deadline)
            let (wins, unresolved) = resolveWindows(axElements(a[0]), pid: pid, stack: stack)
            let ids = Set(wins.map(\.id))
            for w in wins {
                if isStale() { cut = true; return }
                if stack.win(w.id) == nil || !stack.anyVisible(w.id) {
                    deliver(.empty(pid: pid, window: w.id, startedAt: now()))
                } else {
                    deliver(scanWindow(pid: pid, id: w.id, element: w.element, appWindows: ids,
                                       stack: stack, deadline: deadline, under: menus.covered))
                }
            }
            if isStale() { cut = true; return }
            var system = scanSystem(pid: pid, app: app, isDock: false, isFront: pid == frontPid,
                                    pieces: (axElementValue(a[1]), axElementValue(a[2])), menus: menus.roots,
                                    screens: screens, stack: stack, deadline: deadline)
            // A window that could not be named because it did not answer was not scanned, so
            // the app's scan is not complete: a reconcile must not remove the labels that
            // window may still have. An entry that answered with no on-screen window (Finder's
            // desktop) is not counted, or every reconcile of Finder would remove nothing.
            system.unanswered += unresolved
            deliver(system)
        }
    }

    /// The areas to scroll in every visible window of the app, for scroll mode: the same
    /// queue, budget, timeout and staleness check as `scanApp`, without the menu bar and
    /// extras, which hold nothing to scroll. Each window's result reaches `each` on main;
    /// `done` follows on main, false if the scan stopped early because it went stale.
    func scanAreas(pid: Int32, stack: WindowStack, isStale: @escaping () -> Bool,
                   each: @escaping (WindowScan) -> Void, done: @escaping (_ complete: Bool) -> Void) {
        perform(pid: pid, background: false) { [self] in
            let t0 = now()
            let deadline = t0 + Scanner.budget
            let deliver = { (s: WindowScan) in DispatchQueue.main.async { each(s) } }
            var cut = false
            defer { DispatchQueue.main.async { [cut] in done(!cut) } }
            if isStale() { cut = true; return }
            let (values, err) = axMultiResult(axApp(pid), windowsAttr)
            guard let a = values, a.count == 1 else {
                let elapsed = now() - t0
                if didNotAnswer(err, after: elapsed) {
                    deliver(.empty(pid: pid, window: nil, startedAt: t0, ms: elapsed * 1000, timedOut: true))
                }
                return
            }
            let wins = resolveWindows(axElements(a[0]), pid: pid, stack: stack).wins
            let ids = Set(wins.map(\.id))
            for w in wins {
                if isStale() { cut = true; return }
                guard stack.win(w.id) != nil, stack.anyVisible(w.id) else { continue }
                deliver(scanWindow(pid: pid, id: w.id, element: w.element, appWindows: ids,
                                   stack: stack, deadline: deadline, finding: .areas))
            }
        }
    }

    /// The frame of the element holding the app's keyboard focus, or nil if it reports none
    /// (some web-based apps do not while they are not in front). Two requests, once per
    /// scroll mode: only call it from `pid`'s queue (inside `perform`).
    func focusFrame(pid: Int32) -> CGRect? {
        guard let focused = axCopy(axApp(pid), kAXFocusedUIElementAttribute as String).flatMap(axElementValue)
        else { return nil }
        return axFrame(axTimed(focused))
    }

    // MARK: - Private (all run on the pid's queue)

    private let windowsAttr = ["AXWindows"] as CFArray
    private let appAttrs = ["AXWindows", "AXMenuBar", "AXExtrasMenuBar"] as CFArray

    /// Window IDs from `_AXUIElementGetWindow`; on error, the same app's on-screen window
    /// whose bounds match the element's frame (within 1 pt per edge). Entries neither way
    /// names are left out (`windowNaming`). `unresolved` counts only those whose frame
    /// request did not answer: one that answered with a frame no on-screen window has is not
    /// a window that can hold labels. Finder's desktop is that case: an `AXWindows` entry the
    /// size of all displays together, with no window ID and no window-server window.
    private func resolveWindows(_ elements: [AXUIElement], pid: Int32, stack: WindowStack?)
        -> (wins: [(id: WindowID, element: AXUIElement)], unresolved: Int) {
        var fallback = stack
        var unresolved = 0
        let wins: [(id: WindowID, element: AXUIElement)] = elements.compactMap { el in
            axTimed(el)
            var id = CGWindowID(0)
            if _AXUIElementGetWindow(el, &id) == .success, id != 0 { return (id, el) }
            let s = fallback ?? WindowServer.snapshot()
            fallback = s
            let f = axFrameResult(el)
            let w = f.frame.flatMap { f in s.wins.first(where: { $0.pid == pid && sameWindowFrame($0.bounds, f) }) }
            switch windowNaming(idFound: false, frameAnswered: f.answered, frameMatches: w != nil) {
            case .named: return w.map { ($0.id, el) }
            case .notOnScreen: return nil
            case .unread: unresolved += 1; return nil
            }
        }
        return (wins, unresolved)
    }

    private func scanWindow(pid: Int32, id: WindowID, element: AXUIElement?, appWindows: Set<WindowID>,
                            stack: WindowStack, deadline: Double, finding: Finding = .targets,
                            under menus: [CGRect] = []) -> WindowScan {
        let t0 = now()
        guard let element, let bounds = stack.win(id)?.bounds else {
            return .empty(pid: pid, window: id, startedAt: t0)
        }
        let r = walk(root: AXElementNode(element), pid: pid,
                     scope: .window(id: id, bounds: bounds, appWindows: appWindows),
                     stack: stack, deadline: deadline, now: now, finding: finding)
        return WindowScan(pid: pid, window: id, targets: targets(r.targets, clearOf: menus), nodes: r.nodes, startedAt: t0,
                          ms: (now() - t0) * 1000, timedOut: r.timedOut, webAreas: r.webAreas,
                          unanswered: r.unanswered, areas: r.areas)
    }

    /// The app's open menus. `roots`: the ones no walk reaches from a window or the menu
    /// bar (a right-click's, a button's, a Dock item's), each once however many submenus
    /// are open. `covered`: the window of every open menu, the menu bar's included, for
    /// `targets(_:clearOf:)`. Each window at the menu layer is asked for the element under
    /// its middle, then climbed (`openMenu`): one hit-test and a short climb apiece, and
    /// nothing at all while no menu is open. All of it is inside the scan's budget and stops
    /// at `deadline`, as the walk does: a slow app's climbs ran past the budget before the walk.
    private func openMenus(pid: Int32, app: AXUIElement, stack: WindowStack,
                           deadline: Double) -> (roots: [AXUIElement], covered: [CGRect]) {
        var roots: [AXUIElement] = []
        var covered: [CGRect] = []
        var seen = Set<ElementID>()
        for w in stack.openMenus(pid: pid) {
            if now() >= deadline { break }
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(app, Float(w.bounds.midX), Float(w.bounds.midY), &hit) == .success,
                  let hit, let menu = openMenu(from: AXElementNode(hit), deadline: deadline, now: now) else { continue }
            covered.append(w.bounds)
            if !menu.inMenuBar, let root = menu.root as? AXElementNode, seen.insert(root.id).inserted {
                roots.append(root.element)
            }
        }
        return (roots, covered)
    }

    /// Dock: the whole application tree. Otherwise the menu bar (front app only) and extras.
    /// Then, in either case, `menus`: the app's open menus that those do not reach.
    /// `pieces` is (menu bar, extras), already fetched by the caller (unused for the Dock).
    private func scanSystem(pid: Int32, app: AXUIElement, isDock: Bool, isFront: Bool,
                            pieces: (AXUIElement?, AXUIElement?), menus: [AXUIElement], screens: [CGRect],
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
        roots += menus
        var targets: [Target] = []
        var nodes = 0
        var timedOut = false
        var unanswered = 0
        for root in roots {
            let r = walk(root: AXElementNode(root), pid: pid, scope: .system(screens: screens),
                         stack: stack, deadline: deadline, now: now)
            targets += r.targets
            nodes += r.nodes
            timedOut = timedOut || r.timedOut
            unanswered += r.unanswered
        }
        return WindowScan(pid: pid, window: nil, targets: targets, nodes: nodes, startedAt: t0,
                          ms: (now() - t0) * 1000, timedOut: timedOut, unanswered: unanswered)
    }
}
