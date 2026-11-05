import AppKit
import JumprCore

/// Ties hotkey → scan → labels → typing. Everything here runs on the main thread;
/// all accessibility work goes through `scanner` on the apps' own queues.
///
/// Generation rule: every trigger and every cancel bumps `generation`. Each scan
/// callback captures the generation it was issued under and is dropped, before it
/// touches overlays, the session or the readout, unless it still matches and the
/// session is active (`isCurrent`).
final class Controller {
    var onMatched: (Target, CGRect) -> Void = { _, _ in }
    /// True while the screen is locked (or the displays sleep, or the screen saver runs).
    /// Nothing can be read then, and the key listener must not capture at a lock screen.
    var isLocked: () -> Bool = { false }
    let readout = Readout()
    private(set) var isActive = false
    /// Identifies the current session; changes on every trigger and cancel.
    private(set) var generation = 0

    private let scanner: Scanner
    private let registry: TreeRegistry
    private let tap: KeyTap
    private var overlays: [Overlay] = []

    private struct Placed {
        let target: Target
        let rect: CGRect  // where the label was drawn, global top-left
        let layer: CALayer
        let overlay: Int
    }

    private var session = LabelSession()
    private var pool = LabelPool(length: 1)
    private var placed: [String: Placed] = [:]
    private var overflow = 0
    private var pendingApps = 0
    private var screens: [CGRect] = []
    private var style = LabelStyle.current()
    /// Labels needed by the previous complete trigger, for sizing the next one's labels.
    private var lastTotal: Int?

    private let debugLabels = ProcessInfo.processInfo.environment["JUMPR_DEBUG_LABELS"] != nil

    init(scanner: Scanner, registry: TreeRegistry, tap: KeyTap) {
        self.scanner = scanner
        self.registry = registry
        self.tap = tap
        rebuildOverlays()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [unowned self] _ in
            cancel()
            rebuildOverlays()
            log("displays changed: \(overlays.count) overlays")
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [unowned self] _ in
            if isActive { cancel() }
        }
    }

    private func isCurrent(_ gen: Int) -> Bool { gen == generation && isActive }

    // MARK: - Trigger

    func trigger(capture: Bool = true) {
        if isActive { cancel(); return }
        if tap.paused { log("trigger ignored: paused"); return }
        if isLocked() { log("trigger ignored: locked"); return }
        generation += 1
        let gen = generation
        isActive = true
        tap.capturing = capture

        session = LabelSession()
        placed = [:]
        overflow = 0
        style = LabelStyle.current()
        readout.begin()

        let stack = WindowServer.snapshot()
        let lockedAtStart = screenIsLocked()  // for noteScan: locked scans see no windows
        screens = overlays.map(\.frame)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var pids: [Int32] = []
        var names: [Int32: String] = [:]
        for w in stack.wins where names[w.pid] == nil {
            pids.append(w.pid)
            names[w.pid] = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? w.name
        }
        pool = LabelPool(length: Labels.length(forEstimate: lastTotal ?? 200))
        pendingApps = pids.count
        readout.listed(apps: pids.count)

        if pids.isEmpty { finish(); return }
        for pid in pids {
            let name = names[pid] ?? "?"
            let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            let isDock = bundle == "com.apple.dock"
            let hasVisibleWindow = stack.wins.contains { $0.pid == pid && $0.layer == 0 && stack.anyVisible($0.id) }
            if hasVisibleWindow && !isDock {
                scanner.perform(pid: pid, background: false) { [registry] in
                    registry.enableIfNeeded(pid: pid, bundleID: bundle)
                }
            }
            // Registry bookkeeping for the app, kept even if this trigger goes stale.
            var windowNodes = 0
            scanner.scanApp(pid: pid, stack: stack, screens: screens, frontPid: front, isDock: isDock, background: false,
                            each: { [weak self] s in
                                if s.window != nil { windowNodes += s.nodes }
                                guard let self, isCurrent(gen) else { return }  // stale: drop
                                receive(s, name: name)
                            },
                            done: { [weak self, scanner, registry] in
                                if hasVisibleWindow {
                                    let n = windowNodes
                                    // Locked at any point while this app was scanned: its zero nodes mean nothing.
                                    let locked = lockedAtStart || screenIsLocked()
                                    scanner.perform(pid: pid, background: true) {
                                        registry.noteScan(pid: pid, bundleID: bundle, windowNodes: n, screenLocked: locked)
                                    }
                                }
                                guard let self, isCurrent(gen) else { return }  // stale: drop
                                pendingApps -= 1
                                if pendingApps == 0 { finish() }
                            })
        }
    }

    /// Paints one scan's targets. Only called for the current generation.
    private func receive(_ s: WindowScan, name: String) {
        let t0 = now()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for t in s.targets {
            guard let i = Labels.screenIndex(for: CGPoint(x: t.rect.midX, y: t.rect.midY), screens: screens) else { continue }
            guard let label = pool.next() else { overflow += 1; continue }
            let rect = Labels.frame(length: pool.length, target: t.rect, screen: screens[i],
                                    fontSize: style.size, advance: style.advance)
            let layer = overlays[i].add(label: label, at: rect, style: style)
            layer.isHidden = !label.hasPrefix(session.typed)  // the user may already be typing
            placed[label] = Placed(target: t, rect: rect, layer: layer, overlay: i)
            session.labels.insert(label)
        }
        CATransaction.commit()
        readout.note(s, name: name, paint: now() - t0)
    }

    /// Every app has answered for the current generation.
    private func finish() {
        CATransaction.flush()
        lastTotal = placed.count + overflow
        readout.painted(labels: placed.count, overflow: overflow, on: overlays.first)
        if debugLabels {
            for (label, p) in placed.sorted(by: { $0.key < $1.key }) {
                let r = p.target.rect
                let l = p.rect
                let win = p.target.window.map { "\($0)" } ?? "-"
                log("label \(label) \(p.target.role) pid=\(p.target.pid) win=\(win) "
                    + "rect=\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height)) "
                    + "label=\(Int(l.minX)),\(Int(l.minY)),\(Int(l.width)),\(Int(l.height))")
            }
        }
        // Nothing to type at: a capturing session would only swallow keys.
        if tap.capturing && placed.isEmpty {
            log("cancelled: no labels")
            cancel()
        }
    }

    // MARK: - Keys

    /// Called by the key tap while capturing. Returns true to swallow the key.
    func handle(_ key: Key) -> Bool {
        guard isActive else { return false }
        switch session.handle(key) {
        case .passThrough:
            return false
        case .swallow:
            return true
        case .narrowed(let prefix):
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (label, p) in placed { p.layer.isHidden = !label.hasPrefix(prefix) }
            CATransaction.commit()
            return true
        case .cancelled:
            cancel()
            return true
        case .matched(let label):
            let hit = placed[label]
            cancel()
            if let hit { onMatched(hit.target, hit.rect) }
            return true
        }
    }

    // MARK: - Cancel

    func cancel() {
        let wasActive = isActive
        generation += 1  // every in-flight result is now stale
        isActive = false
        tap.capturing = false
        overlays.forEach { $0.clear() }
        CATransaction.flush()
        placed = [:]
        session = LabelSession()
        pendingApps = 0
        if wasActive {
            log("cancelled layers=\(overlays.reduce(0) { $0 + $1.layerCount })")
        }
    }

    private func rebuildOverlays() {
        overlays.forEach { $0.close() }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        overlays = NSScreen.screens.map { Overlay($0, primaryHeight: primaryHeight) }
    }
}
