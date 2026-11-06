import CoreGraphics
import Foundation
import JumprCore

enum WindowServer {
    /// Everything on screen, front to back, in global top-left coordinates. Jumpr's own
    /// windows are included so the panel hides what is behind it (the label overlays sit at
    /// layer 1000 and never occlude); callers that list apps to scan leave Jumpr out.
    static func snapshot() -> WindowStack {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let wins: [Win] = raw.compactMap { d in
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
        return WindowStack(wins)
    }
}
