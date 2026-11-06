import AppKit
import JumprCore

/// Scrolls an area with wheel events aimed at its centre (docs/design.md, Scroll mode).
/// The event carries the position, so the pointer never moves. Posting to the app's own
/// process instead scrolled nothing in any app tried; posting at the system's event tap
/// with a position did exactly what moving the pointer there and scrolling did.
final class Scroller {
    /// The gap between the events of one burst (`ScrollAmount.wheelSteps`).
    private static let gap = 0.008

    func scroll(_ area: Area, by amount: ScrollAmount) {
        let at = CGPoint(x: area.rect.midX, y: area.rect.midY)
        for (i, pixels) in amount.wheelSteps(areaHeight: area.rect.height).enumerated() {
            if i == 0 {
                Self.post(pixels, at: at)
            } else {
                // One-shot delays within a burst, not a timer.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.gap * Double(i)) { Self.post(pixels, at: at) }
            }
        }
        let app = NSRunningApplication(processIdentifier: area.pid)?.localizedName ?? "pid \(area.pid)"
        log("scroll: \(amount.logName) in \(app)")
    }

    /// `pixels` > 0 scrolls up.
    private static func post(_ pixels: Int32, at p: CGPoint) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                              wheel1: pixels, wheel2: 0, wheel3: 0) else { return }
        e.location = p
        e.flags = []  // a Shift still held from Shift G must not ride along: it makes a wheel scroll sideways
        e.post(tap: .cghidEventTap)
    }
}

private extension ScrollAmount {
    var logName: String {
        switch self {
        case .line(let d): return "line \(d)"
        case .half(let d): return "half \(d)"
        case .top: return "top"
        case .bottom: return "bottom"
        }
    }
}
