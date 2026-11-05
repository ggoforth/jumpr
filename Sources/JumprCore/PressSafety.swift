import CoreGraphics

public enum PressDecision: Equatable {
    case press
    case skip
}

public enum PressResult: Equatable {
    case skipped
    case pressed
    case clicked
}

/// Press only if the element still exists and still overlaps where its label was drawn.
public func pressDecision(drawn: CGRect, current: CGRect?) -> PressDecision {
    guard let current, current.intersects(drawn) else { return .skip }
    return .press
}

/// Where a synthetic click lands: the center of the part of the element that was visible
/// when scanned, as it is now (design §7.6 step 4). If the element has moved off that
/// spot but is still under its label, the center of the part under the label.
/// Only called after `pressDecision` said `.press`, so `drawn ∩ current` is not empty.
public func clickPoint(visible: CGRect, drawn: CGRect, current: CGRect) -> CGPoint {
    var r = visible.intersection(current)
    if r.isEmpty { r = drawn.intersection(current) }
    return CGPoint(x: r.midX, y: r.midY)
}

/// A press that opened a menu labels it right away: any menu bar item, or a menu item
/// the press left selected (its submenu opened).
public func relabelsAfterPress(role: String, result: PressResult, selected: Bool) -> Bool {
    guard result == .pressed else { return false }
    switch role {
    case "AXMenuBarItem": return true
    case "AXMenuItem": return selected
    default: return false
    }
}
