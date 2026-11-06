import AppKit
import JumprCore

/// Ties hotkey → scan → labels → typing. Everything here runs on the main thread;
/// all accessibility work goes through `scanner` on the apps' own queues.
///
/// Generation rule: every trigger and every cancel bumps `generation`. Each scan
/// callback captures the generation it was issued under and is dropped, before it
/// touches overlays, the session or the readout, unless it still matches and the
/// session is active (`isCurrent`). Scans already queued for a stale generation stop
/// early through `isStale`, which reads `sharedGeneration`.
final class Controller {
    var onMatched: (Target) -> Void = { _ in }
    let readout = Readout()
    private(set) var isActive = false
    /// Identifies the current session; changes on every trigger and cancel.
    private(set) var generation = 0 { didSet { sharedGeneration.value = generation } }
    /// A copy of `generation` that the scan queues may read; written only here, on main.
    private let sharedGeneration = SharedGeneration()

    private let scanner: Scanner
    private let registry: TreeRegistry
    private let tap: KeyTap
    private let extras = ExtrasOwners()
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
    /// Elements labelled in this session, so a repeated scan of an app adds only what is new.
    private var placedIDs = Set<ElementID>()
    private var overflow = 0
    private var pendingApps = 0
    private var screens: [CGRect] = []
    private var style = LabelStyle.current()
    /// Labels needed by the previous complete trigger, for sizing the next one's labels.
    private var lastTotal: Int?
    /// Apps that have shown a web area in some scan, by bundle ID (see `rescanWhileTreeBuilds`).
    /// Kept across launches: a web view that is not built yet gives no sign of itself, so
    /// without this the first email after Jumpr starts would get no labels on its links.
    private var webHosts = Set(UserDefaults.standard.stringArray(forKey: Keys.webHostApps) ?? [])
    /// Apps known from the start to show their content in a WebKit view, which `webHosts`
    /// cannot learn in time: on a first press the unbuilt view shows no web area, so the
    /// page would get no labels until a later press. Safari's page was there 0.3 s after
    /// the first read.
    private static let webKitHostIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.apple.mail",
    ]

    private let debugLabels = ProcessInfo.processInfo.environment["JUMPR_DEBUG_LABELS"] != nil
    private var colorWatchers: [DefaultsWatcher] = []

    init(scanner: Scanner, registry: TreeRegistry, tap: KeyTap) {
        self.scanner = scanner
        self.registry = registry
        self.tap = tap
        rebuildOverlays()
        colorWatchers = [Keys.labelColor, Keys.labelTextColor].map { key in
            DefaultsWatcher(key) { [weak self] in self?.recolor() }
        }

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
        // A one-shot delay per launch (not a timer): the app needs a moment to open a window.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [unowned self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            let name = app.localizedName ?? "pid \(pid)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [unowned self] in
                enableTrees("launch of \(name)", only: pid)
            }
        }
        // An app coming to the front shows a window: switch its tree on then, for apps that
        // were hidden or covered at the earlier moments. Once per app (`hasSeen`), a
        // one-shot delay so its window is in front by the time the window list is read.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [unowned self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            guard pid != getpid(), !tap.paused, !registry.hasSeen(pid) else { return }
            let name = app.localizedName ?? "pid \(pid)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [unowned self] in
                guard !registry.hasSeen(pid) else { return }
                enableTrees("activation of \(name)", only: pid)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [unowned self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            extras.forget(pid: pid)
            // Queued behind any scan of the app still running, then the queue itself goes.
            scanner.perform(pid: pid, background: true) { [registry] in registry.forget(pid: pid) }
            scanner.forget(pid: pid)
        }
    }

    private func isCurrent(_ gen: Int) -> Bool { gen == generation && isActive }

    private static let dockID = "com.apple.dock"

    /// One lookup table per call instead of an `NSRunningApplication` lookup per app.
    private static func runningApps() -> [Int32: NSRunningApplication] {
        Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// The apps whose web tree is worth switching on: regular apps (not the Dock, not
    /// Jumpr) with a visible normal window. The single selection every enabling moment uses.
    private func treeCandidates(_ stack: WindowStack, _ running: [Int32: NSRunningApplication]) -> [Int32] {
        stack.appsWithVisibleWindow(excluding: getpid()).filter {
            guard let app = running[$0] else { return false }
            return app.activationPolicy == .regular && app.bundleIdentifier != Self.dockID
        }
    }

    // MARK: - Trees ahead of the first trigger

    /// Switches web trees on now, so the first trigger already finds them built (design
    /// §7.3: Chromium/Electron build the tree some time after being asked). Called when
    /// Jumpr becomes trusted, on resume, 2 s after an app launches and the first time an
    /// app comes to the front (`only` that app), and when the screen unlocks. Never while paused or locked; the AX work runs on each
    /// app's scan queue. The trigger's own enabling stays as the catch-all.
    func enableTrees(_ reason: String, only: Int32? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        if tap.paused { log("trees: enable on \(reason) skipped: paused"); return }
        if screenIsLocked() { log("trees: enable on \(reason) skipped: screen locked"); return }
        guard AXIsProcessTrusted() else { log("trees: enable on \(reason) skipped: not trusted"); return }
        // The same moments are when the owners of menu bar extras are looked up.
        if let only { extras.check(pid: only) } else { extras.refreshAll() }
        let running = Self.runningApps()
        var pids = treeCandidates(WindowServer.snapshot(), running)
        if let only { pids = pids.filter { $0 == only } }
        if only == nil || !pids.isEmpty { log("trees: enable on \(reason): \(pids.count) apps") }
        for pid in pids {
            let bundle = running[pid]?.bundleIdentifier
            scanner.perform(pid: pid, background: true) { [registry] in
                registry.enableIfNeeded(pid: pid, bundleID: bundle)
            }
        }
    }

    // MARK: - Trigger

    func trigger(capture: Bool = true) {
        if isActive { cancel(); return }
        if tap.paused { log("trigger ignored: paused"); return }
        // Live query, not the notification-tracked state: a stale flag must never make the
        // hotkey dead. Nothing can be read while locked, and the key listener must not
        // capture at a lock screen.
        if screenIsLocked() { log("trigger ignored: locked"); return }
        generation += 1
        let gen = generation
        let started = now()
        isActive = true
        tap.capturing = capture

        session = LabelSession()
        placed = [:]
        placedIDs = []
        overflow = 0
        style = LabelStyle.current()
        readout.begin()

        let stack = WindowServer.snapshot()
        let lockedAtStart = screenIsLocked()  // for noteScan: locked scans see no windows
        screens = overlays.map(\.frame)
        let running = Self.runningApps()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var pids = stack.appsToScan(excluding: getpid(), front: front)
        // Menu bar extras belong to apps the window list does not name (see `ExtrasOwners`).
        pids += extras.current.subtracting(pids).sorted()
        var names: [Int32: String] = [:]
        for w in stack.wins where names[w.pid] == nil { names[w.pid] = w.name }
        // Catch-all for apps the earlier moments missed (see `enableTrees`).
        let wake = Set(treeCandidates(stack, running))
        let visible = Set(stack.appsWithVisibleWindow(excluding: getpid()))
        pool = LabelPool(length: Labels.length(forEstimate: lastTotal ?? 200))
        pendingApps = pids.count
        readout.listed(apps: pids.count)

        if pids.isEmpty { finish(); return }
        for pid in pids {
            let name = running[pid]?.localizedName ?? names[pid] ?? "?"
            let bundle = running[pid]?.bundleIdentifier
            let isDock = bundle == Self.dockID
            let hasVisibleWindow = visible.contains(pid) && !isDock
            if wake.contains(pid) {
                scanner.perform(pid: pid, background: false) { [registry] in
                    registry.enableIfNeeded(pid: pid, bundleID: bundle)
                }
            }
            // Registry bookkeeping for the app, kept even if this trigger goes stale.
            var web = WebFound()
            scanner.scanApp(pid: pid, stack: stack, screens: screens, frontPid: front, isDock: isDock, background: false,
                            isStale: { [sharedGeneration] in sharedGeneration.value != gen },
                            each: { [weak self] s in
                                web.add(s)
                                guard let self, isCurrent(gen) else { return }  // stale: drop
                                receive(s, name: name)
                            },
                            done: { [weak self, scanner, registry] complete in
                                // A scan cut short by a newer trigger says nothing about the tree.
                                if hasVisibleWindow && complete {
                                    let found = web
                                    // Locked at any point while this app was scanned: its zero nodes mean nothing.
                                    let locked = lockedAtStart || screenIsLocked()
                                    scanner.perform(pid: pid, background: true) {
                                        registry.noteScan(pid: pid, bundleID: bundle, walkedWindow: found.walkedWindow,
                                                          webTargets: found.targets, screenLocked: locked)
                                    }
                                }
                                guard let self, isCurrent(gen) else { return }  // stale: drop
                                pendingApps -= 1
                                if pendingApps == 0 { finish() }
                                rescanWhileTreeBuilds(pid: pid, name: name, isDock: isDock, stack: stack,
                                                      front: front, gen: gen, web: web, started: started,
                                                      bundle: bundle)
                            })
        }
    }

    /// What one scan of an app met of web content: its web areas, and what there was to
    /// click inside them. `walkedWindow`: some window was on screen to look in at all.
    private struct WebFound {
        var areas = 0
        var targets = 0
        var walkedWindow = false
        mutating func add(_ s: WindowScan) {
            if s.window != nil && s.nodes > 0 { walkedWindow = true }
            areas += s.webAreas
            targets += s.targets.lazy.filter(\.inWeb).count
        }
    }

    /// The scan just finished may have come too early for the app's tree. While these
    /// labels are up, look at the app again every 0.4 s and add the labels that were missing.
    /// Two cases. A web tree Jumpr switched on moments ago is still being built (1Password
    /// takes 1 to 2 s), so the scan found an empty window. And a WebKit view (an email open
    /// in Mail) builds its tree only once asked: the scan that asked found nothing to click
    /// in it (`web`), so repeat until something is there or `started` is too long ago.
    private func rescanWhileTreeBuilds(pid: Int32, name: String, isDock: Bool, stack: WindowStack,
                                       front: Int32?, gen: Int, web: WebFound, started: Double,
                                       bundle: String?, isRepeat: Bool = false) {
        if web.areas > 0, let bundle, webHosts.insert(bundle).inserted {
            UserDefaults.standard.set(webHosts.sorted(), forKey: Keys.webHostApps)
        }
        let switchedOn = treeMayStillBeBuilding(sinceSwitchedOn: registry.sinceEnabled(pid))
        // An app with no window on screen (hidden, or on another Space) has no web view to
        // wait for. One with no bundle ID is never remembered, so never waited for. A
        // Chromium browser always hosts web content: with nothing to click in it, `noteScan`
        // is about to switch its page tree on (queued ahead of the look-again scan).
        let hostsWeb = bundle.map {
            webHosts.contains($0) || TreeRegistry.chromiumIDs.contains($0) || Self.webKitHostIDs.contains($0)
        } == true && web.walkedWindow
        let webView = webViewMayStillBeBuilding(hostsWeb: hostsWeb, webTargets: web.targets,
                                                sinceTrigger: now() - started)
        guard switchedOn || webView else { return }
        if webView && !switchedOn && !isRepeat {
            log("nothing to click in \(name)'s web view (\(web.areas) web areas): looking again")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, isCurrent(gen) else { return }
            var added = 0
            var web = WebFound()
            scanner.scanApp(pid: pid, stack: stack, screens: screens, frontPid: front, isDock: isDock, background: false,
                            isStale: { [sharedGeneration] in sharedGeneration.value != gen },
                            each: { [weak self] s in
                                guard let self, isCurrent(gen) else { return }
                                web.add(s)
                                added += receive(s, name: name, late: true)
                            },
                            done: { [weak self] _ in
                                guard let self, isCurrent(gen) else { return }
                                if added > 0 {
                                    CATransaction.flush()
                                    lastTotal = placed.count + overflow
                                    log("late labels: \(added) more in \(name), its tree was still building")
                                }
                                rescanWhileTreeBuilds(pid: pid, name: name, isDock: isDock, stack: stack,
                                                      front: front, gen: gen, web: web, started: started,
                                                      bundle: bundle, isRepeat: true)
                            })
        }
    }

    /// Paints one scan's targets and returns how many labels it added. Only called for the
    /// current generation. `late`: a repeated scan of an app (`rescanWhileTreeBuilds`); what
    /// is already labelled is skipped either way, and the readout is left alone.
    @discardableResult
    private func receive(_ s: WindowScan, name: String, late: Bool = false) -> Int {
        let t0 = now()
        var added = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for t in s.targets {
            guard let i = Labels.screenIndex(for: CGPoint(x: t.rect.midX, y: t.rect.midY), screens: screens) else { continue }
            guard !placedIDs.contains(t.id) else { continue }
            guard let label = pool.next() else { overflow += 1; continue }
            placedIDs.insert(t.id)
            added += 1
            let rect = Labels.frame(length: pool.length, target: t.rect, screen: screens[i],
                                    fontSize: style.size, advance: style.advance)
            let layer = overlays[i].add(label: label, at: rect, style: style)
            layer.isHidden = !label.hasPrefix(session.typed)  // the user may already be typing
            placed[label] = Placed(target: t, rect: rect, layer: layer, overlay: i)
            session.labels.insert(label)
        }
        CATransaction.commit()
        if !late { readout.note(s, name: name, paint: now() - t0) }
        return added
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
            CATransaction.flush()  // show it now, not at the next run loop pass
            if debugLabels {
                log("narrowed \(prefix.isEmpty ? "-" : prefix): \(placed.keys.filter { $0.hasPrefix(prefix) }.count) of \(placed.count) shown")
            }
            return true
        case .cancelled:
            cancel()
            return true
        case .matched(let label):
            let hit = placed[label]
            cancel()
            if let hit { onMatched(hit.target) }
            return true
        }
    }

    // MARK: - Colours

    /// A colour changed in Settings while labels are up: repaint the labels on screen now
    /// instead of at the next trigger. Labels added later in this session use the new
    /// colours too. Size is left as the session started (it would move every label).
    private func recolor() {
        guard isActive else { return }
        let new = LabelStyle.current()
        style.bg = new.bg
        style.fg = new.fg
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for p in placed.values {
            p.layer.backgroundColor = new.bg
            (p.layer as? CATextLayer)?.foregroundColor = new.fg
        }
        CATransaction.commit()
        CATransaction.flush()
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

/// An `Int` that any thread may read and write under a lock.
final class SharedGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
