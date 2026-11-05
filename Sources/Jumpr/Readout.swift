import AppKit
import JumprCore

/// Timing for one trigger. Always written to the log; drawn as a panel on the first
/// overlay only when `enabled`.
final class Readout {
    var enabled = false

    private struct App {
        var name: String
        var finished = 0.0  // absolute time its last result finished
        var nodes = 0
        var labels = 0
        var timedOut = false
    }

    private var t0 = 0.0
    private var tList = 0.0
    private var tEnd = 0.0
    private var paintTime = 0.0
    private var apps: [Int32: App] = [:]
    private var appCount = 0
    private var labels = 0
    private var overflow = 0

    private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)

    /// The trigger started.
    func begin() {
        t0 = now()
        tList = t0
        tEnd = t0
        paintTime = 0
        apps = [:]
        appCount = 0
        labels = 0
        overflow = 0
    }

    /// The window list is read; `apps` scans are about to be dispatched.
    func listed(apps n: Int) {
        tList = now()
        appCount = n
    }

    /// One scan result arrived; `paint` is the seconds spent painting its labels.
    func note(_ scan: WindowScan, name: String, paint: Double = 0) {
        var a = apps[scan.pid] ?? App(name: name)
        a.finished = max(a.finished, scan.startedAt + scan.ms / 1000)
        a.nodes += scan.nodes
        a.labels += scan.targets.count
        a.timedOut = a.timedOut || scan.timedOut
        apps[scan.pid] = a
        paintTime += paint
    }

    /// Every app has answered and its labels are on screen. Logs the readout and, when
    /// enabled, draws it on `overlay`.
    func painted(labels: Int, overflow: Int, on overlay: Overlay?) {
        tEnd = now()
        self.labels = labels
        self.overflow = overflow
        let lines = lines()
        lines.forEach { log($0) }
        guard enabled, let overlay else { return }
        let hud = CATextLayer()
        hud.string = lines.joined(separator: "\n")
        hud.font = Self.font
        hud.fontSize = 11
        hud.foregroundColor = .white
        hud.backgroundColor = CGColor(gray: 0, alpha: 0.8)
        hud.cornerRadius = 6
        let h = CGFloat(lines.count) * 14 + 6
        let f = overlay.frame
        overlay.add(layer: hud, at: CGRect(x: f.minX + 16, y: f.maxY - h - 140, width: 620, height: h))
    }

    func lines() -> [String] {
        func ms(_ s: Double) -> String { String(format: "%.0f", s * 1000) }
        let total = tEnd - t0
        let windows = tList - t0
        let scan = max(0, total - windows - paintTime)
        var first = "total \(ms(total)) ms = windows \(ms(windows)) + scan \(ms(scan)) + paint \(ms(paintTime))"
            + "   |   \(labels) labels, \(appCount) apps"
        if overflow > 0 { first += ", \(overflow) OVERFLOW" }
        var out = [first]
        for a in apps.values.sorted(by: { $0.finished > $1.finished }) {
            out.append(String(format: "%5.0f ms %6d nodes %4d labels  ", max(0, a.finished - t0) * 1000, a.nodes, a.labels)
                + a.name + (a.timedOut ? "  TIMEOUT" : ""))
        }
        return out
    }
}
