import AppKit
import JumprCore

/// Presses a matched element (docs/design.md, Pressing). All accessibility work runs on the target
/// app's own serial queue, so a press never overlaps a scan of the same app; completions
/// come back on main.
final class Presser {
    private let scanner: Scanner

    init(scanner: Scanner) {
        self.scanner = scanner
    }

    /// The completion also gets the raw `AXError` that `AXPress` returned, or nil if it
    /// was not called.
    func press(_ t: Target, kind: ClickKind = .plain, completion: @escaping (PressResult, Int32?) -> Void) {
        guard let el = axElement(t.id) else {
            DispatchQueue.main.async { completion(.skipped, nil) }
            return
        }
        scanner.perform(pid: t.pid, background: false) { [scanner] in
            let (result, axError) = Presser.run(t, kind: kind, element: el, scanner: scanner)
            DispatchQueue.main.async { completion(result, axError) }
        }
    }

    /// Whether `result` opened a menu that should be labelled at once. Reads `AXSelected`
    /// on the app's queue for a menu bar item or menu item; answers on main.
    func openedMenu(_ t: Target, result: PressResult, completion: @escaping (Bool) -> Void) {
        guard result == .pressed, t.role == "AXMenuItem" || t.role == "AXMenuBarItem",
              let el = axElement(t.id) else {
            let opened = relabelsAfterPress(role: t.role, result: result, selected: false)
            DispatchQueue.main.async { completion(opened) }
            return
        }
        scanner.perform(pid: t.pid, background: false) {
            let selected = (axCopy(el, "AXSelected") as? Bool) == true
            let opened = relabelsAfterPress(role: t.role, result: result, selected: selected)
            DispatchQueue.main.async { completion(opened) }
        }
    }

    /// Runs on the app's queue.
    private static func run(_ t: Target, kind: ClickKind, element el: AXUIElement,
                            scanner: Scanner) -> (PressResult, axError: Int32?) {
        guard pressDecision(scanned: t.rect, current: axFrame(el)) == .press else { return (.skipped, nil) }

        var raised: AXUIElement?
        if let wid = t.window {  // bring the owning app + window forward first
            let err = AXUIElementSetAttributeValue(axApp(t.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if err != .success { log("press: asking pid \(t.pid) forward failed (ax=\(err.rawValue))") }
            Activation.activate(t.pid)  // macOS 27 ignores the accessibility request; ask publicly too
            if let w = scanner.appWindows(pid: t.pid).first(where: { $0.id == wid })?.element {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                raised = w
            }
        }

        var axError: Int32?
        // Web content never needs the action list: it is clicked regardless. Nor does any
        // click but a plain one.
        let actions = t.inWeb || kind != .plain ? nil : axActionNames(el)
        if usesAXPress(role: t.role, actions: actions, inWeb: t.inWeb, kind: kind) {
            let err = AXUIElementPerformAction(el, kAXPressAction as CFString).rawValue
            axError = err
            switch afterAXPress(err) {
            case .pressed: return (.pressed, err)
            case .skip: return (.skipped, err)
            case .click: waitUntilForward(t, window: raised)
            }
        } else if t.window != nil {
            waitUntilForward(t, window: raised)
        }

        // The raise (and a failed press) may have moved or closed it: check again, from now.
        let fresh = axFrame(el)
        guard pressDecision(scanned: t.rect, current: fresh) == .press, let fresh else { return (.skipped, axError) }
        click(at: clickPoint(visible: t.rect, current: fresh), kind: kind)
        return (.clicked, axError)
    }

    /// Blocks until the target's app is in front and its window is the main one, so the
    /// click lands as a click rather than only bringing the window forward (see
    /// `clickReadiness`). Something with no window (a menu bar icon) gets a short fixed pause.
    ///
    /// The app has already been asked forward through accessibility and `Activation.activate`.
    /// If it has not come by the end of a step, the next, stronger request is made (see
    /// `Activation`). The log names the step that worked.
    private static func waitUntilForward(_ t: Target, window: AXUIElement?) {
        guard let wid = t.window else { usleep(40_000); return }
        let app = axApp(t.pid)
        let t0 = now()

        /// True once the app is in front, false once `limit` seconds have passed.
        func inFront(within limit: Double) -> Bool {
            let start = now()
            while true {
                let front = axCopy(app, kAXFrontmostAttribute as String) as? Bool
                let main = window.flatMap { axCopy($0, kAXMainAttribute as String) as? Bool }
                switch clickReadiness(appFrontmost: front, windowMain: main, waited: now() - start, limit: limit) {
                case .ready: return true
                case .giveUp: return false
                case .wait: usleep(10_000)
                }
            }
        }

        if inFront(within: 0) { return }  // it was already in front: click at once
        let steps: [(name: String, limit: Double, ask: () -> Void)] = [
            ("activate", 0.15, {}),  // already asked, before the press
            ("open", 0.35, { Activation.open(t.pid) }),
            ("window server", 0.3, { Activation.windowServer(t.pid, window: CGWindowID(wid)) }),
        ]
        for step in steps {
            step.ask()
            guard inFront(within: step.limit) else { continue }
            if let window { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
            usleep(50_000)  // the app says it is active; let the window server catch up
            log(String(format: "press: pid %d came forward in %.0f ms (%@)", t.pid, (now() - t0) * 1000, step.name))
            return
        }
        log(String(format: "press: pid %d not in front after %.0f ms, clicking anyway", t.pid, (now() - t0) * 1000))
    }

    private static func click(at p: CGPoint, kind: ClickKind) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ev in clickEvents(kind) {
            let type: CGEventType = switch ev.phase {
            case .move: .mouseMoved
            case .down: ev.right ? .rightMouseDown : .leftMouseDown
            case .up: ev.right ? .rightMouseUp : .leftMouseUp
            }
            guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p,
                                  mouseButton: ev.right ? .right : .left) else { continue }
            // Stated, never inherited: a modifier still held from typing the label must not
            // ride along, and a ⌘-click must carry ⌘ whether or not the key is still down.
            e.flags = CGEventFlags(rawValue: ev.held)
            // Only the second press of a double-click is counted, so a plain click stays
            // the event it has always been.
            if ev.count > 1 { e.setIntegerValueField(.mouseEventClickState, value: Int64(ev.count)) }
            e.post(tap: .cghidEventTap)
        }
    }
}
