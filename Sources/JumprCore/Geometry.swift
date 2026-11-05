import CoreGraphics

public typealias WindowID = UInt32

public struct Win: Equatable {
    public let id: WindowID
    public let pid: Int32
    public let name: String
    public let bounds: CGRect
    public let layer: Int
    public let alpha: Double

    public init(id: WindowID, pid: Int32, name: String, bounds: CGRect, layer: Int, alpha: Double) {
        self.id = id
        self.pid = pid
        self.name = name
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
    }

    /// Normal-layer, non-transparent windows hide whatever is behind them.
    public var occludes: Bool { (0..<20).contains(layer) && alpha > 0 }
}

public struct WindowStack {
    /// On-screen windows, front to back.
    public let wins: [Win]

    public init(_ wins: [Win]) {
        self.wins = wins
    }

    public func win(_ id: WindowID) -> Win? {
        wins.first { $0.id == id }
    }

    public func top(at p: CGPoint) -> Win? {
        wins.first { $0.occludes && $0.bounds.contains(p) }
    }

    /// True if `window` (or a helper window of the same app that is not in
    /// `appWindows`) is the topmost occluding window at `p`.
    public func isVisible(_ p: CGPoint, window: WindowID, pid: Int32, appWindows: Set<WindowID>) -> Bool {
        guard let t = top(at: p) else { return false }
        return t.id == window || (t.pid == pid && !appWindows.contains(t.id))
    }

    /// Samples a 5x5 grid inside the window's bounds.
    public func anyVisible(_ window: WindowID) -> Bool {
        guard let w = win(window) else { return false }
        let r = w.bounds
        for i in 1...5 {
            for j in 1...5 {
                let p = CGPoint(x: r.minX + r.width * CGFloat(i) / 6,
                                y: r.minY + r.height * CGFloat(j) / 6)
                if top(at: p)?.id == window { return true }
            }
        }
        return false
    }

    /// The apps one trigger scans: each window owner once, front to back, never `me`
    /// (Jumpr, whose own windows stay in the stack so they occlude). The front app is
    /// added last if it has no on-screen window, so its menu bar is still labelled.
    public func appsToScan(excluding me: Int32, front: Int32?) -> [Int32] {
        var seen: Set<Int32> = [me]
        var pids = wins.map(\.pid).filter { seen.insert($0).inserted }
        if let front, seen.insert(front).inserted { pids.append(front) }
        return pids
    }

    /// Apps with at least one visible normal-layer window, front to back, never `me`:
    /// the ones whose accessibility tree is worth switching on.
    public func appsWithVisibleWindow(excluding me: Int32) -> [Int32] {
        var seen: Set<Int32> = [me]
        return wins.filter { $0.layer == 0 && $0.pid != me && !seen.contains($0.pid) && anyVisible($0.id) }
            .map(\.pid).filter { seen.insert($0).inserted }
    }
}

/// Whether an accessibility window frame and a window-server bounds describe the same
/// window: every edge within 1 pt (the two round differently).
public func sameWindowFrame(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) <= 1 && abs(a.maxX - b.maxX) <= 1
        && abs(a.minY - b.minY) <= 1 && abs(a.maxY - b.maxY) <= 1
}
