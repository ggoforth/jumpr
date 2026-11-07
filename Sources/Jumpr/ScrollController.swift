import AppKit
import JumprCore

/// Scroll mode end to end (docs/design.md, Scroll mode): the shortcut turns it on, every
/// app's areas are scanned and lettered as they arrive, keys go to `ScrollSession`, and
/// its commands are drawn here and scrolled by `Scroller`. Runs on the main thread; the
/// accessibility work goes through `scanner` on the apps' own queues.
///
/// The same generation rule as `Controller`: every start and every leave bumps
/// `generation`, and a scan callback from an older one is dropped before it touches the
/// overlays or the session.
final class ScrollController {
    private(set) var isActive = false
    private var generation = 0 { didSet { sharedGeneration.value = generation } }
    private let sharedGeneration = SharedGeneration()

    private let scanner: Scanner
    private let tap: KeyTap
    private let scroller: Scroller
    private let statusItem: StatusItem
    /// The label controller's overlays, one per display.
    private let overlays: () -> [Overlay]

    private var session = ScrollSession(letterLength: 1)
    /// Every area found in this session, lettered or not.
    private var found: [Area] = []
    /// Areas the previous session found, for sizing this one's letters.
    private var lastCount: Int?
    /// The area scrolled last in each window: where the next session in that window starts.
    private var lastScrolled: [WindowID: Area] = [:]
    private var frontPid: Int32?
    private var frontWindow: WindowID?
    /// Where the front app's keyboard focus is, once read; nil if it reports none.
    private var focusFrame: CGRect?
    private var pendingApps = 0
    private var screens: [CGRect] = []
    private var style = LabelStyle.current()

    private var outline: CALayer?
    /// The SCROLL tag's rectangle, global top-left; the outlined area's letter goes beside it.
    private var tag: CGRect?
    private var letterLayers: [String: CALayer] = [:]
    /// What ends scroll mode from outside the keys, installed only while it is on.
    private var monitors: [Any] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(scanner: Scanner, tap: KeyTap, scroller: Scroller, statusItem: StatusItem, overlays: @escaping () -> [Overlay]) {
        self.scanner = scanner
        self.tap = tap
        self.scroller = scroller
        self.statusItem = statusItem
        self.overlays = overlays
    }

    private func isCurrent(_ gen: Int) -> Bool { gen == generation && isActive }

    /// The shortcut: on, or off again.
    func toggle() {
        if isActive { leave("shortcut"); return }
        if tap.paused { log("scroll mode ignored: paused"); return }
        // Nothing can be read while locked, and the key listener must not capture at a lock screen.
        if screenIsLocked() { log("scroll mode ignored: locked"); return }
        start()
    }

    private func start() {
        generation += 1
        let gen = generation
        isActive = true
        tap.capturing = true
        statusItem.holdsHighlight = true
        session = ScrollSession(letterLength: ScrollLetters.length(previousCount: lastCount))
        found = []
        focusFrame = nil
        style = LabelStyle.current()
        screens = overlays().map(\.frame)
        watchExits()

        let stack = WindowServer.snapshot()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        frontPid = front
        frontWindow = stack.wins.first { $0.pid == front && $0.layer == 0 }?.id
        let pids = stack.appsToScan(excluding: getpid(), front: nil)
        var names: [Int32: String] = [:]
        for w in stack.wins where names[w.pid] == nil { names[w.pid] = w.name }
        pendingApps = pids.count
        log("scroll mode: on, \(pids.count) apps")
        if pids.isEmpty { finish(); return }

        // Queued ahead of the front app's area scan, on its own queue: a bonus for the
        // starting outline, never waited for.
        if let front, pids.contains(front) {
            scanner.perform(pid: front, background: false) { [weak self, scanner] in
                let frame = scanner.focusFrame(pid: front)
                DispatchQueue.main.async { self?.noteFocus(frame, gen: gen) }
            }
        }
        let isStale = { [sharedGeneration] in sharedGeneration.value != gen }
        for pid in pids {
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? names[pid] ?? "?"
            let t0 = now()
            var count = 0
            var timedOut = false
            scanner.scanAreas(pid: pid, stack: stack, isStale: isStale,
                              each: { [weak self] s in
                                  guard let self, isCurrent(gen) else { return }
                                  count += s.areas.count
                                  timedOut = timedOut || s.timedOut
                                  receive(s.areas)
                              },
                              done: { [weak self] _ in
                                  guard let self, isCurrent(gen) else { return }
                                  log(String(format: "scroll scan %@: %d areas, %.0f ms%@", name, count,
                                             (now() - t0) * 1000, timedOut ? " TIMEOUT" : ""))
                                  pendingApps -= 1
                                  if pendingApps == 0 { finish() }
                              })
        }
    }

    /// One window's areas: each gets a letter as it arrives, and may be where the session starts.
    private func receive(_ areas: [Area]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for area in areas {
            guard screenIndex(area) != nil else { continue }
            found.append(area)
            if let letter = session.add(area) { drawLetter(letter, area) }
        }
        CATransaction.commit()
        outlineStart()
    }

    private func noteFocus(_ frame: CGRect?, gen: Int) {
        guard isCurrent(gen) else { return }
        focusFrame = frame
        outlineStart()
    }

    /// Every app has answered.
    private func finish() {
        lastCount = found.count
        // Nothing to scroll: taking the keys would only swallow them.
        if found.isEmpty { leave("no areas") }
    }

    /// Outlines where the session starts, if that has changed and the person has not acted.
    private func outlineStart() {
        let last = frontWindow.flatMap { lastScrolled[$0] }
        let start = startingArea(last: last, focusFrame: focusFrame, areas: found.filter { $0.pid == frontPid })
        if session.suggest(start) { redraw() }
    }

    // MARK: - Keys

    /// Called by the key tap while scroll mode is on. Returns true to swallow the key.
    func handle(_ key: Key) -> Bool {
        guard isActive else { return false }
        switch session.handle(key) {
        case .passThrough:
            return false
        case .swallow:
            return true
        case .leave:
            leave("Esc")
        case .showLetters, .outline:
            redraw()
        case .narrowed(let prefix):
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (letter, layer) in letterLayers { layer.isHidden = !letter.hasPrefix(prefix) }
            CATransaction.commit()
            CATransaction.flush()  // show it now, not at the next run loop pass
        case .scroll(let area, let amount):
            if !letterLayers.isEmpty { redraw() }
            lastScrolled[area.window] = area
            scroller.scroll(area, by: amount)
        }
        return true
    }

    // MARK: - Drawing

    private func screenIndex(_ a: Area) -> Int? {
        Labels.screenIndex(for: CGPoint(x: a.rect.midX, y: a.rect.midY), screens: screens)
    }

    /// Draws the outline and, while they show, the letters, as the session now has them.
    private func redraw() {
        let overlays = overlays()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline?.removeFromSuperlayer()
        outline = nil
        tag = nil
        if let a = session.outlined, let i = screenIndex(a), i < overlays.count {
            let font = NSFont.monospacedSystemFont(ofSize: max(10, (style.size * 0.75).rounded()), weight: .bold)
            let t = Labels.insideTopLeft(characters: 6, of: a.rect, after: nil, screen: screens[i],
                                         fontSize: font.pointSize, advance: font.maximumAdvancement.width)
            outline = overlays[i].add(outline: a.rect, tag: t, tagFont: font, style: style)
            tag = t
        }
        letterLayers.values.forEach { $0.removeFromSuperlayer() }
        letterLayers = [:]
        if session.lettersShown {
            for (letter, area) in session.letters { drawLetter(letter, area) }
        }
        CATransaction.commit()
        CATransaction.flush()
    }

    /// Drawn exactly like an ordinary label, in the area's top-left corner inside the outline.
    private func drawLetter(_ letter: String, _ area: Area) {
        guard session.lettersShown, let i = screenIndex(area), i < overlays().count else { return }
        let after = area.id == session.outlined?.id ? tag : nil
        // At the area's corner, or at a point of it that shows when the corner is covered.
        let rect = Labels.insideTopLeft(characters: letter.count, of: CGRect(origin: area.anchor, size: .zero),
                                        after: after, screen: screens[i], fontSize: style.size, advance: style.advance)
        let layer = overlays()[i].add(label: letter, at: rect, style: style)
        layer.isHidden = !letter.hasPrefix(session.typed)
        letterLayers[letter] = layer
    }

    // MARK: - Leaving

    /// Ends scroll mode and removes everything it drew. `reason` goes to the log.
    func leave(_ reason: String) {
        guard isActive else { return }
        generation += 1  // every in-flight result is now stale
        isActive = false
        tap.capturing = false
        statusItem.holdsHighlight = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        overlays().forEach { $0.clear() }
        CATransaction.flush()
        outline = nil
        tag = nil
        letterLayers = [:]
        found = []
        session = ScrollSession(letterLength: 1)
        log("scroll mode: off (\(reason))")
    }

    /// A click anywhere, the front app changing, the Space changing or a display change
    /// ends scroll mode. Installed when it turns on and removed when it leaves, so nothing
    /// watches while idle. Lock and Pause reach `leave` from where they end a label session.
    private func watchExits() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in self?.leave("click") }) {
            monitors.append(m)
        }
        // A click on Jumpr's own menu bar icon or panel never reaches the global monitor.
        if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] e in
            self?.leave("click")
            return e
        }) {
            monitors.append(m)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let exits: [(NotificationCenter, Notification.Name, String)] = [
            (workspace, NSWorkspace.didActivateApplicationNotification, "app switch"),
            // The areas found were on the Space that was showing.
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, "Space changed"),
            // The overlays are rebuilt, and the areas have moved.
            (.default, NSApplication.didChangeScreenParametersNotification, "displays changed"),
        ]
        for (center, name, reason) in exits {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.leave(reason) }
            observers.append((center, token))
        }
    }
}
