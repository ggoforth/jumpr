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

/// Whether to press through `AXPress` at all; otherwise the element gets a synthetic click.
/// Text fields always get a click (it puts the caret in them). `actions` are the element's
/// action names, nil if they could not be read: an element that does not offer `AXPress`
/// is clicked, because some web content (Dia) answers success to an `AXPress` it does not
/// offer and then does nothing.
public func usesAXPress(role: String, actions: [String]?) -> Bool {
    if Roles.text.contains(role) { return false }
    return actions?.contains("AXPress") ?? true
}

/// What to do after `AXPress` returned `axError` (the raw `AXError` value).
public enum AfterAXPress: Equatable {
    /// Count it as pressed.
    case pressed
    /// The element is gone; do nothing.
    case skip
    /// Fall back to a synthetic click, after re-checking the element (design §7.6).
    case click
}

public func afterAXPress(_ axError: Int32) -> AfterAXPress {
    switch axError {
    case 0, -25204: return .pressed       // .success; .cannotComplete = the app is busy tracking
                                          // what we just opened (menus do this)
    case -25202: return .skip             // .invalidUIElement
    default: return .click
    }
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

/// A press that opened a menu labels it right away: a menu bar item or menu item the
/// press left selected (its menu or submenu opened). Menu-bar extras share the
/// `AXMenuBarItem` role but open panels, not menus, so they are not relabelled unless selected.
public func relabelsAfterPress(role: String, result: PressResult, selected: Bool) -> Bool {
    guard result == .pressed else { return false }
    switch role {
    case "AXMenuBarItem", "AXMenuItem": return selected
    default: return false
    }
}
