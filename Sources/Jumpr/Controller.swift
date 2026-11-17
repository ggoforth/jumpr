import AppKit
import Carbon.HIToolbox  // IsSecureEventInputEnabled
import JumprCore

/// Ties hotkey → scan → labels → typing. Everything here runs on the main thread;
/// all accessibility work goes through `scanner` on the apps' own queues.
///
/// Generation rule: every trigger and every cancel bumps `generation`. Each scan
/// callback captures the generation it was issued under and is dropped, before it
/// touches overlays, the session or the readout, unless it still matches and the
/// session is active (`isCurrent`). Scans already queued for a stale generation stop
/// early through `isStale`, which reads `sharedGeneration`. A settle window follows the
/// same rule with `settleID` beside `generation`: a callback from an older settle window is
/// dropped the same way, and its queued scans stop through `sharedSettleID`.
final class Controller {
    var onMatched: (Target, ClickKind) -> Void = { _, _ in }
    /// Persistent mode went on or off; the menu bar icon shows it.
    var onPersistentChanged: (Bool) -> Void = { _ in }
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
    /// One per display; scroll mode draws on them too (`ScrollController`).
    private(set) var overlays: [Overlay] = []

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
    /// A press in persistent mode has not reported yet. A label typed meanwhile is held
    /// (`heldMatch`) rather than pressed, which keeps presses in order and lets the settle
    /// window follow the last one.
    private var pressInFlight = false
    /// The latest label typed while a press was in flight; an earlier one is replaced.
    private var heldMatch: (Target, ClickKind)?
    /// The apps pressed into in persistent mode, and the app in front at each press: what a
    /// settle window will scan once the screen has had time to change.
    private var touched = Set<Int32>()
    /// Identifies the current settle window, beside `generation` and under the same rule: a
    /// new press, Space switching the mode off, and every cancel bump it, and a moment or
    /// reconcile callback from an older window is dropped before it touches anything.
    private var settleID = 0 { didSet { sharedSettleID.value = settleID } }
    /// A copy of `settleID` that the scan queues may read; written only here, on main.
    private let sharedSettleID = SharedGeneration()
    /// Apps with a reconcile scan still running; a moment skips them rather than queue a
    /// second scan behind the first.
    private var scanning = Set<Int32>()
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
        colorWatchers = [Keys.labelColor, Keys.labelTextColor, Keys.labelTextMode].map { key in
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
            // A press that quit its app: its labels point at nothing, and waiting for a settle
            // moment would leave them up until it came.
            if isActive {
                for (label, p) in placed where p.target.pid == pid { remove(label) }
                labelsRemoved()
                touched.remove(pid)
            }
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

    /// Switches web trees on now, so the first trigger already finds them built
    /// (docs/design.md, Web content: these apps build the tree some time after being asked). Called when
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

    func trigger(capture: Bool = true, persistent: Bool = false) {
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

        // Read on each trigger, as the label style is, so a change in the panel or by
        // `defaults write` holds from the next press of the hotkey.
        session = LabelSession(clickKeys: ClickKeys(stored: UserDefaults.standard.string(forKey: Keys.clickKeys)),
                               persistent: persistent)
        if persistent { onPersistentChanged(true) }
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
        // Debug only: an app that simply shows no page (Mail with no message open) would
        // write this on every press.
        if debugLabels && webView && !switchedOn && !isRepeat {
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
            if place(t) { added += 1 }
        }
        CATransaction.commit()
        if !late { readout.note(s, name: name, paint: now() - t0) }
        return added
    }

    /// Labels one target, unless it is on no display, already labelled (the look-again pass
    /// and a reconcile can both find it), or the pool has run out. True if a label was added.
    private func place(_ t: Target) -> Bool {
        guard let i = Labels.screenIndex(for: CGPoint(x: t.rect.midX, y: t.rect.midY), screens: screens) else { return false }
        guard !placedIDs.contains(t.id) else { return false }
        guard let label = pool.next() else { overflow += 1; return false }
        placedIDs.insert(t.id)
        let rect = Labels.frame(length: pool.length, target: t.rect, screen: screens[i],
                                fontSize: style.size, advance: style.advance)
        let layer = overlays[i].add(label: label, at: rect, style: style)
        layer.isHidden = !label.hasPrefix(session.typed)  // the user may already be typing
        placed[label] = Placed(target: t, rect: rect, layer: layer, overlay: i)
        session.labels.insert(label)
        return true
    }

    /// Takes a label off the screen and gives its letters back. Does nothing for a label no
    /// longer placed (its app quit, or an earlier result removed it): `pool.release` does not
    /// check, and letters released twice would later sit on two elements.
    private func remove(_ label: String) {
        guard let p = placed.removeValue(forKey: label) else { return }
        overlays[p.overlay].remove(p.layer)
        placedIDs.remove(p.target.id)
        session.labels.remove(label)
        pool.release(label)
    }

    /// After labels were removed: if what was typed now starts no label, it is cleared and
    /// every label shows. Otherwise a removed label would leave every key swallowed until
    /// Backspace. Flushed so the change shows at once.
    private func labelsRemoved() {
        if session.clearTypedIfNothingMatches() { show(prefix: "") }
        CATransaction.flush()
    }

    /// The label's element is still there at a new rectangle (a toolbar that reflowed): same
    /// letters, new place. On no display any more, it goes.
    private func move(_ label: String, to t: Target) {
        // Letters released and handed out again since the scan began belong to someone else.
        guard let p = placed[label], p.target.id == t.id else { return }
        guard let i = Labels.screenIndex(for: CGPoint(x: t.rect.midX, y: t.rect.midY), screens: screens) else {
            remove(label)
            return
        }
        let rect = Labels.frame(length: pool.length, target: t.rect, screen: screens[i],
                                fontSize: style.size, advance: style.advance)
        let layer: CALayer
        if i == p.overlay {
            layer = p.layer
            overlays[i].move(layer, to: rect)
        } else {
            overlays[p.overlay].remove(p.layer)
            layer = overlays[i].add(label: label, at: rect, style: style)
        }
        layer.isHidden = !label.hasPrefix(session.typed)
        placed[label] = Placed(target: t, rect: rect, layer: layer, overlay: i)
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
        case .persistent(let on):
            // Switched off mid-run: the next match ends the session as today, so a label
            // held for a press in flight must not be pressed later either.
            // The settle moments still pending go too; the labels stay as they are.
            if !on {
                heldMatch = nil
                settleID += 1
            }
            onPersistentChanged(on)
            log("persistent: \(on ? "on" : "off")")
            return true
        case .refresh:
            return true  // a later change gives Tab its behaviour
        case .narrowed(let prefix):
            show(prefix: prefix)
            if debugLabels {
                log("narrowed \(prefix.isEmpty ? "-" : prefix): \(placed.keys.filter { $0.hasPrefix(prefix) }.count) of \(placed.count) shown")
            }
            return true
        case .cancelled:
            cancel()
            return true
        case .matched(let label, let kind):
            let hit = placed[label]
            if session.persistent, let hit, !endsPersistentMode(role: hit.target.role, kind: kind) {
                // The session cleared what was typed; the labels stay up for the next press.
                show(prefix: "")
                if pressInFlight { heldMatch = (hit.target, kind) } else { press(hit.target, kind) }
                return true
            }
            cancel()
            if let hit { onMatched(hit.target, kind) }
            return true
        }
    }

    /// Shows the labels that start with `prefix` and hides the rest.
    private func show(prefix: String) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (label, p) in placed { p.layer.isHidden = !label.hasPrefix(prefix) }
        CATransaction.commit()
        CATransaction.flush()  // show it now, not at the next run loop pass
    }

    /// A press in persistent mode; the session stays up.
    private func press(_ t: Target, _ kind: ClickKind) {
        pressInFlight = true
        touched.insert(t.pid)
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { touched.insert(front) }
        onMatched(t, kind)
    }

    /// `Presser` reported on a press made under `generation`. A press from an earlier
    /// session, or one made as the session ended (today's path cancels first), finds no
    /// current session and does nothing. The held label, if any, is pressed now, unless
    /// persistent mode was switched off meanwhile; with none held, the settle window starts.
    func pressFinished(generation gen: Int) {
        guard isCurrent(gen) else { return }
        // Cleared even when the mode is off now: switched on again, a stuck flag would hold
        // every later label forever.
        pressInFlight = false
        guard let held = heldMatch else {
            if session.persistent { startSettle() }
            return
        }
        heldMatch = nil
        if session.persistent { press(held.0, held.1) }
    }

    // MARK: - Settle window

    /// A press changes the screen after the app has answered it: a menu opens, a page swaps,
    /// a window comes forward. So the touched apps are scanned again at fixed moments after
    /// the press reported. One-shot delays caused by the press, not a timer; a newer press
    /// replaces the moments still pending (`settleID`).
    private func startSettle() {
        settleID += 1
        let gen = generation
        let id = settleID
        for (n, delay) in Settle.moments.enumerated() {
            let last = n == Settle.moments.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, isCurrent(gen), settleID == id else { return }  // stale: drop
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                reconcile(pids: settleApps(touched: touched, frontNow: front, excluding: getpid()), last: last)
            }
        }
    }

    /// One settle moment: drop labels another window now covers, then scan `pids` again and
    /// bring their labels in line with what is there now (`Reconcile`).
    private func reconcile(pids: [Int32], last: Bool) {
        // Jumpr can no longer hear Esc: a password field took the keys.
        if IsSecureEventInputEnabled() {
            log("persistent: ended, secure input")
            cancel()
            return
        }
        let gen = generation
        let id = settleID
        let stack = WindowServer.snapshot()
        screens = overlays.map(\.frame)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let running = Self.runningApps()

        // Apps not scanned now: geometry on the window list, no accessibility call.
        let covered = coveredLabels(placed.mapValues(\.target), stack: stack, scanned: Set(pids))
        if !covered.isEmpty {
            covered.forEach(remove)
            labelsRemoved()
        }

        let pids = pids.filter { !scanning.contains($0) }
        // The last moment's ending checks, here when it starts no scan at all.
        if pids.isEmpty {
            if last { settleEnded() }
            return
        }
        var left = pids.count  // apps of this moment still scanning
        for pid in pids {
            scanning.insert(pid)
            let name = running[pid]?.localizedName ?? stack.wins.first { $0.pid == pid }?.name ?? "?"
            // A press on a Dock icon puts the Dock in `touched`; it is scanned as a trigger does.
            let isDock = running[pid]?.bundleIdentifier == Self.dockID
            let mine = placed.filter { $0.value.target.pid == pid }
            // The element each label stood for when the scan began, to tell its letters from
            // the same letters released and handed to another element meanwhile.
            let ids = mine.mapValues(\.target.id)
            var rec = Reconcile(placed: Dictionary(mine.map { ($0.value.target.id, (label: $0.key, rect: $0.value.target.rect)) },
                                                   uniquingKeysWith: { a, _ in a }))
            var moved = 0
            var added = 0
            var removed = 0
            let t0 = now()
            scanner.scanApp(pid: pid, stack: stack, screens: screens, frontPid: front, isDock: isDock, background: false,
                            isStale: { [sharedGeneration, sharedSettleID] in
                                sharedGeneration.value != gen || sharedSettleID.value != id
                            },
                            each: { [weak self] s in
                                guard let self, isCurrent(gen), settleID == id else { return }  // stale: drop
                                if s.incomplete { rec.noteIncomplete() }
                                CATransaction.begin()
                                CATransaction.setDisableActions(true)
                                for t in s.targets {
                                    switch rec.note(t) {
                                    case .keep:
                                        break
                                    case .move(let label):
                                        let had = placed[label] != nil
                                        move(label, to: t)
                                        if placed[label] != nil { moved += 1 } else if had { removed += 1 }
                                    case .add:
                                        if place(t) { added += 1 }
                                    }
                                }
                                CATransaction.commit()
                            },
                            done: { [weak self] complete in
                                guard let self else { return }
                                scanning.remove(pid)
                                guard isCurrent(gen), settleID == id else { return }  // stale: drop
                                if !complete { rec.noteIncomplete() }
                                // Removals wait for the app's last window: a target missing
                                // from one window's result may be in another's.
                                for label in rec.removals() where placed[label]?.target.id == ids[label] {
                                    remove(label)
                                    removed += 1
                                }
                                labelsRemoved()
                                log(String(format: "reconcile %@: kept %d moved %d removed %d added %d, %.0f ms%@",
                                           name, rec.kept, moved, removed, added, (now() - t0) * 1000,
                                           rec.complete ? "" : " incomplete"))
                                left -= 1
                                // The window has finished once every app of its last moment answered.
                                let finished = last && left == 0
                                switch afterReconcile(overflow: overflow, labelsLeft: placed.count, windowFinished: finished) {
                                case .refresh:
                                    lastTotal = placed.count + overflow  // the fresh trigger sizes from this
                                    cancel()
                                    trigger(persistent: true)
                                case .end:
                                    log("persistent: ended, no labels")
                                    cancel()
                                case .carryOn:
                                    if finished { touched = [] }
                                }
                            })
        }
    }

    /// The last moment of a settle window started no scan, so it has finished here: what was
    /// touched has been looked at, and a session with nothing left to type at ends, as a
    /// trigger with no labels does.
    private func settleEnded() {
        touched = []
        if placed.isEmpty {
            log("persistent: ended, no labels")
            cancel()
        }
    }

    // MARK: - Colours

    /// A colour changed in the panel while labels are up: repaint the labels on screen now
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
        settleID += 1  // and every settle moment still pending
        isActive = false
        tap.capturing = false
        overlays.forEach { $0.clear() }
        CATransaction.flush()
        placed = [:]
        // Only when this session held the highlight: scroll mode holds it too, and the
        // scroll shortcut cancels labels on its way in.
        if session.persistent { onPersistentChanged(false) }
        pressInFlight = false
        heldMatch = nil
        touched = []
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
