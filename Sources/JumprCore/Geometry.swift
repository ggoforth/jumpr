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

    /// The layer of a menu bar app's panel, open under its icon (Jumpr's own is one).
    public static let statusLayer = 25

    /// The layer of Notification Center's open sidebar and of its banners: one window across
    /// the whole display, transparent outside the sidebar or the banner. A click anywhere
    /// outside the open sidebar only closes it; a click outside a banner reaches the window
    /// behind (`clicksPassThrough` tells the two apart).
    public static let sidebarLayer = 21

    /// Non-transparent windows hide whatever is behind them, if they are at a normal layer,
    /// are a menu bar app's panel, or are the open sidebar. The layers between and above
    /// hold full-screen windows that hide nothing: the Dock (20), the menu bar (24), Jumpr's
    /// own label overlays (1000).
    public var occludes: Bool {
        ((0..<20).contains(layer) || layer == Win.statusLayer || layer == Win.sidebarLayer) && alpha > 0
    }
}

public struct WindowStack {
    /// On-screen windows, front to back.
    public let wins: [Win]
    /// Windows a click passes through (`clicksPassThrough`): they hide nothing behind them.
    public let clickThrough: Set<WindowID>

    public init(_ wins: [Win], clickThrough: Set<WindowID> = []) {
        self.wins = wins
        self.clickThrough = clickThrough
    }

    public func win(_ id: WindowID) -> Win? {
        wins.first { $0.id == id }
    }

    public func top(at p: CGPoint) -> Win? {
        wins.first { hides($0, at: p) }
    }

    private func hides(_ w: Win, at p: CGPoint) -> Bool {
        w.occludes && !clickThrough.contains(w.id) && w.bounds.contains(p)
    }

    /// Whether `window` is what shows at `p`. A click-through window is never the topmost
    /// occluding window, so it shows wherever no window in front of it hides it: the scan
    /// still walks Notification Center's window while a banner is up, and the banner gets
    /// its label.
    private func shows(_ window: WindowID, at p: CGPoint) -> Bool {
        guard clickThrough.contains(window) else { return top(at: p)?.id == window }
        return !wins.prefix { $0.id != window }.contains { hides($0, at: p) }
    }

    /// True if `window` (or a helper window of the same app that is not in
    /// `appWindows`) is the topmost occluding window at `p`.
    public func isVisible(_ p: CGPoint, window: WindowID, pid: Int32, appWindows: Set<WindowID>) -> Bool {
        if shows(window, at: p) { return true }
        guard let t = top(at: p) else { return false }
        return t.pid == pid && !appWindows.contains(t.id)
    }

    /// Samples a 5x5 grid inside the window's bounds.
    public func anyVisible(_ window: WindowID) -> Bool {
        guard let w = win(window) else { return false }
        return sampleGrid(w.bounds).contains { shows(window, at: $0) }
    }

    /// The apps one trigger scans for their windows: each window owner once, front to back,
    /// never `me` (Jumpr, whose own windows stay in the stack so they occlude; it is scanned
    /// as the owner of a menu bar extra instead). The front app is added last if it has no
    /// on-screen window, so its menu bar is still labelled.
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

/// The 5×5 grid of points inside `r` that decides whether a window shows at all.
private func sampleGrid(_ r: CGRect) -> [CGPoint] {
    (1...5).flatMap { i in
        (1...5).map { j in CGPoint(x: r.minX + r.width * CGFloat(i) / 6, y: r.minY + r.height * CGFloat(j) / 6) }
    }
}

/// Whether clicks pass through `w` to the windows behind it: true unless a mouse-down lands
/// on `w` at every sample point (`clickLandsOn` is the window server's answer). Notification
/// Center shows a banner in the same full-display window, at the same layer, as its open
/// sidebar, and the window list cannot tell them apart. With the sidebar open the click lands
/// on that window everywhere. A banner is smaller than the samples' spacing (344×58 pt on a
/// 3440×1440 display, samples 573×240 pt apart), so the click lands on the windows behind,
/// which lost every label for as long as a banner showed while bounds alone decided.
public func clicksPassThrough(_ w: Win, clickLandsOn: (CGPoint) -> WindowID?) -> Bool {
    !sampleGrid(w.bounds).allSatisfy { clickLandsOn($0) == w.id }
}

/// Whether an accessibility window frame and a window-server bounds describe the same
/// window: every edge within 1 pt (the two round differently).
public func sameWindowFrame(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) <= 1 && abs(a.maxX - b.maxX) <= 1
        && abs(a.minY - b.minY) <= 1 && abs(a.maxY - b.maxY) <= 1
}

/// What an app's `AXWindows` entry is, from how it was named.
public enum WindowNaming: Equatable {
    /// Tied to a window-server window, by ID or by frame: it is scanned.
    case named
    /// It answered with a frame no on-screen window has (Finder's desktop): left out, and the
    /// scan is still complete, since nothing on screen can hold a label for it.
    case notOnScreen
    /// Its frame request did not answer: left out, and the scan is incomplete, since the
    /// window may still have labels on screen.
    case unread
}

public func windowNaming(idFound: Bool, frameAnswered: Bool, frameMatches: Bool) -> WindowNaming {
    if idFound || frameMatches { return .named }
    return frameAnswered ? .notOnScreen : .unread
}
