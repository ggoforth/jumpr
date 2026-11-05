import AppKit
import JumprCore

/// Presses a matched element (design §7.6). All accessibility work runs on the target
/// app's own serial queue, so a press never overlaps a scan of the same app; completions
/// come back on main.
final class Presser {
    private let scanner: Scanner

    init(scanner: Scanner) {
        self.scanner = scanner
    }

    /// The completion also gets the raw `AXError` that `AXPress` returned, or nil if it
    /// was not called.
    func press(_ t: Target, completion: @escaping (PressResult, Int32?) -> Void) {
        guard let el = axElement(t.id) else {
            DispatchQueue.main.async { completion(.skipped, nil) }
            return
        }
        scanner.perform(pid: t.pid, background: false) { [scanner] in
            let (result, axError) = Presser.run(t, element: el, scanner: scanner)
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
    private static func run(_ t: Target, element el: AXUIElement,
                            scanner: Scanner) -> (PressResult, axError: Int32?) {
        guard pressDecision(scanned: t.rect, current: axFrame(el)) == .press else { return (.skipped, nil) }

        var raised: AXUIElement?
        if let wid = t.window {  // bring the owning app + window forward first
            let err = AXUIElementSetAttributeValue(axApp(t.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if err != .success { log("press: asking pid \(t.pid) forward failed (ax=\(err.rawValue))") }
            if let w = scanner.appWindows(pid: t.pid).first(where: { $0.id == wid })?.element {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                raised = w
            }
        }

        var axError: Int32?
        // Web content never needs the action list: it is clicked regardless.
        if usesAXPress(role: t.role, actions: t.inWeb ? nil : axActionNames(el), inWeb: t.inWeb) {
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
        click(at: clickPoint(visible: t.rect, current: fresh))
        return (.clicked, axError)
    }

    /// Blocks until the target's app is in front and its window is the main one, so the
    /// click lands as a click rather than only bringing the window forward (see
    /// `clickReadiness`). Something with no window (a menu bar icon) gets a short fixed pause.
    private static func waitUntilForward(_ t: Target, window: AXUIElement?) {
        guard t.window != nil else { usleep(40_000); return }
        let app = axApp(t.pid)
        let t0 = now()
        var waited = false
        while true {
            let front = axCopy(app, kAXFrontmostAttribute as String) as? Bool
            let main = window.flatMap { axCopy($0, kAXMainAttribute as String) as? Bool }
            switch clickReadiness(appFrontmost: front, windowMain: main, waited: now() - t0) {
            case .ready:
                guard waited else { return }  // it was already in front
                usleep(50_000)  // the app says it is active; let the window server catch up
                log(String(format: "press: pid %d came forward in %.0f ms", t.pid, (now() - t0) * 1000))
                return
            case .giveUp:
                log(String(format: "press: pid %d not in front after %.0f ms (frontmost=%@ main=%@), clicking anyway",
                           t.pid, (now() - t0) * 1000, "\(front as Any)", "\(main as Any)"))
                return
            case .wait:
                waited = true
                usleep(10_000)
            }
        }
    }

    private static func click(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p,
                                  mouseButton: .left) else { continue }
            e.flags = []  // a modifier still held from typing the label must not ride along
            e.post(tap: .cghidEventTap)
        }
    }
}
