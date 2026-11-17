import CoreGraphics

/// One scan of one app being reconciled, turned into what to do with its labels.
public struct Reconcile {
    public enum Change: Equatable { case keep, move(label: String), add }

    /// For the log line; `Controller` counts what it moved and added itself, as it paints them.
    public private(set) var kept = 0
    /// False once any result was cut short: a partial answer says nothing about what it did not reach.
    public private(set) var complete = true

    private let placed: [ElementID: (label: String, rect: CGRect)]
    private var seen = Set<ElementID>()

    /// `placed`: letters and target rectangle of every element now labelled in those apps.
    public init(placed: [ElementID: (label: String, rect: CGRect)]) {
        self.placed = placed
    }

    /// Called for every target as window results arrive. An element named by two window
    /// results is one element, so the second time changes nothing.
    public mutating func note(_ t: Target) -> Change {
        guard seen.insert(t.id).inserted else { return .keep }
        guard let old = placed[t.id] else { return .add }
        if old.rect == t.rect {
            kept += 1
            return .keep
        }
        return .move(label: old.label)
    }

    public mutating func noteIncomplete() {
        complete = false
    }

    /// Labels whose element no result named, sorted. Empty unless the scan was complete.
    public func removals() -> [String] {
        guard complete else { return [] }
        return placed.filter { !seen.contains($0.key) }.map(\.value.label).sorted()
    }
}

/// Labels in apps that were not scanned whose target a window now covers, or whose window
/// is gone, sorted. A label with no window (menu bar, extras, Dock) is never returned.
public func coveredLabels(_ placed: [String: Target], stack: WindowStack, scanned: Set<Int32>) -> [String] {
    // A helper window of the app (a popover over its own window) does not cover the app's
    // labelled windows, so only the windows that carry labels count as the app's own.
    var labelled: [Int32: Set<WindowID>] = [:]
    for t in placed.values {
        if let w = t.window { labelled[t.pid, default: []].insert(w) }
    }
    return placed.compactMap { label, t -> String? in
        guard !scanned.contains(t.pid), let w = t.window else { return nil }
        guard stack.win(w) != nil else { return label }
        let centre = CGPoint(x: t.rect.midX, y: t.rect.midY)
        let visible = stack.isVisible(centre, window: w, pid: t.pid, appWindows: labelled[t.pid] ?? [])
        return visible ? nil : label
    }.sorted()
}
