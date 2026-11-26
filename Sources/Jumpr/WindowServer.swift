import AppKit
import JumprCore

enum WindowServer {
    /// Everything on screen, front to back, in global top-left coordinates. Jumpr's own
    /// windows are included so its panel hides what is behind it (`Win.occludes`; the label
    /// overlays sit at layer 1000 and never do). Callers that list apps by their windows
    /// leave Jumpr out: its icon and panel are reached as a menu bar extra instead.
    static func windows() -> [Win] {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return raw.compactMap { d in
            guard let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t,
                  let b = d[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b)
            else { return nil }
            return Win(id: id, pid: pid,
                       name: d[kCGWindowOwnerName as String] as? String ?? "?",
                       bounds: r,
                       layer: d[kCGWindowLayer as String] as? Int ?? 0,
                       alpha: d[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }

    /// The window list for a trigger, with the sidebar-layer windows that clicks pass through
    /// (`clicksPassThrough`: a notification banner's window covers its display and takes
    /// clicks only on the banner). The window server is asked where a mouse-down would land:
    /// one question while a banner is up, 25 with the sidebar open, none otherwise. Not an
    /// accessibility call, so no app can hold it up. Main thread only: it goes through AppKit.
    static func snapshot() -> WindowStack {
        dispatchPrecondition(condition: .onQueue(.main))
        let wins = windows()
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let clickThrough = wins.filter { w in
            w.layer == Win.sidebarLayer && w.occludes && clicksPassThrough(w) { p in
                let n = NSWindow.windowNumber(at: NSPoint(x: p.x, y: primaryHeight - p.y), belowWindowWithWindowNumber: 0)
                return n > 0 ? WindowID(n) : nil
            }
        }
        return WindowStack(wins, clickThrough: Set(clickThrough.map(\.id)))
    }
}
