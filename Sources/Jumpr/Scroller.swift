import AppKit
import JumprCore

/// Scrolls an area with wheel events aimed at its centre (docs/design.md, Scroll mode).
/// The event carries the position, so the pointer never moves. Posting to the app's own
/// process instead scrolled nothing in any app tried; posting at the system's event tap
/// with a position did exactly what moving the pointer there and scrolling did.
final class Scroller {
    /// The gap between the events of one burst (`ScrollAmount.wheelSteps`).
    private static let gap = 0.008
    /// When the burst going out now ends. A key repeat that arrives before then sends one
    /// event instead of another burst: a held key would otherwise send six events per
    /// repeat, about 180 a second, and Mail's web content stopped answering after such a
    /// hold.
    private var burstEndsAt = 0.0

    func scroll(_ area: Area, by amount: ScrollAmount) {
        let at = CGPoint(x: area.rect.midX, y: area.rect.midY)
        let steps = amount.wheelSteps(areaHeight: area.rect.height, burst: now() >= burstEndsAt)
        burstEndsAt = now() + Self.gap * Double(steps.count - 1)
        for (i, pixels) in steps.enumerated() {
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
