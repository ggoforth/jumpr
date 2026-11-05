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

    /// `drawn` is where the element's label was painted, global top-left.
    func press(_ t: Target, drawn: CGRect, completion: @escaping (PressResult) -> Void) {
        guard let el = axElement(t.id) else {
            DispatchQueue.main.async { completion(.skipped) }
            return
        }
        scanner.perform(pid: t.pid, background: false) { [scanner] in
            let result = Presser.run(t, element: el, drawn: drawn, scanner: scanner)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Whether `result` opened a menu that should be labelled at once. Reads `AXSelected`
    /// on the app's queue for a menu item; answers on main.
    func openedMenu(_ t: Target, result: PressResult, completion: @escaping (Bool) -> Void) {
        guard result == .pressed, t.role == "AXMenuItem", let el = axElement(t.id) else {
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
    private static func run(_ t: Target, element el: AXUIElement, drawn: CGRect, scanner: Scanner) -> PressResult {
        let current = axFrame(el)
        guard pressDecision(drawn: drawn, current: current) == .press, let current else { return .skipped }

        if let wid = t.window {  // bring the owning app + window forward first
            AXUIElementSetAttributeValue(axApp(t.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if let w = scanner.appWindows(pid: t.pid).first(where: { $0.id == wid })?.element {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
        }

        if !Roles.text.contains(t.role) {
            let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
            // .cannotComplete = the app is busy tracking what we just opened (menus do this).
            if r == .success || r == .cannotComplete { return .pressed }
            usleep(40_000)  // let the raise land
        } else if t.window != nil {
            usleep(40_000)  // let the raise land
        }

        click(at: clickPoint(visible: t.rect, drawn: drawn, current: current))
        return .clicked
    }

    private static func click(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
}
