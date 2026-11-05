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

    /// `drawn` is where the element's label was painted, global top-left. The completion
    /// also gets the raw `AXError` that `AXPress` returned, or nil if it was not called.
    func press(_ t: Target, drawn: CGRect, completion: @escaping (PressResult, Int32?) -> Void) {
        guard let el = axElement(t.id) else {
            DispatchQueue.main.async { completion(.skipped, nil) }
            return
        }
        scanner.perform(pid: t.pid, background: false) { [scanner] in
            let (result, axError) = Presser.run(t, element: el, drawn: drawn, scanner: scanner)
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
    private static func run(_ t: Target, element el: AXUIElement, drawn: CGRect,
                            scanner: Scanner) -> (PressResult, axError: Int32?) {
        guard pressDecision(drawn: drawn, current: axFrame(el)) == .press else { return (.skipped, nil) }

        if let wid = t.window {  // bring the owning app + window forward first
            AXUIElementSetAttributeValue(axApp(t.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if let w = scanner.appWindows(pid: t.pid).first(where: { $0.id == wid })?.element {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
        }

        var axError: Int32?
        if !Roles.text.contains(t.role) {
            let err = AXUIElementPerformAction(el, kAXPressAction as CFString).rawValue
            axError = err
            switch afterAXPress(err) {
            case .pressed: return (.pressed, err)
            case .skip: return (.skipped, err)
            case .click: usleep(40_000)  // let the raise land
            }
        } else if t.window != nil {
            usleep(40_000)  // let the raise land
        }

        // The raise (and a failed press) may have moved or closed it: check again, from now.
        let fresh = axFrame(el)
        guard pressDecision(drawn: drawn, current: fresh) == .press, let fresh else { return (.skipped, axError) }
        click(at: clickPoint(visible: t.rect, drawn: drawn, current: fresh))
        return (.clicked, axError)
    }

    private static func click(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
}
