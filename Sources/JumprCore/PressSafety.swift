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

/// Press only if the element still exists and still overlaps where it was when it was
/// labelled (`scanned`, its visible part at scan time). The label itself is no reference:
/// it hangs beside a small target rather than on it (see `Labels.frame`).
public func pressDecision(scanned: CGRect, current: CGRect?) -> PressDecision {
    guard let current, current.intersects(scanned) else { return .skip }
    return .press
}

/// Whether to press through `AXPress` at all; otherwise the element gets a synthetic click.
/// - Text fields always get a click (it puts the caret in them).
/// - Web content (`inWeb`) always gets a click: it answers success to `AXPress` and may do
///   nothing. Dia does not even offer the action; Linear offers it, answers success, and
///   does not navigate. Only a real click is trustworthy there.
/// - Any click but a plain one is a real click: `AXPress` is a left press and nothing else.
/// - Elsewhere, `actions` are the element's action names (nil if they could not be read):
///   an element that does not offer `AXPress` is clicked.
public func usesAXPress(role: String, actions: [String]?, inWeb: Bool = false, kind: ClickKind = .plain) -> Bool {
    if Roles.text.contains(role) || inWeb || kind != .plain { return false }
    return actions?.contains("AXPress") ?? true
}

/// What to do after `AXPress` returned `axError` (the raw `AXError` value).
public enum AfterAXPress: Equatable {
    /// Count it as pressed.
    case pressed
    /// The element is gone; do nothing.
    case skip
    /// Fall back to a synthetic click, after re-checking the element (docs/design.md, Pressing).
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
/// when scanned, as it is now (docs/design.md, Pressing, step 6).
/// Only called after `pressDecision` said `.press`, so `visible ∩ current` is not empty.
public func clickPoint(visible: CGRect, current: CGRect) -> CGPoint {
    let r = visible.intersection(current)
    return CGPoint(x: r.midX, y: r.midY)
}

/// One mouse event of a synthetic click.
public struct ClickEvent: Equatable {
    public enum Phase: Equatable { case move, down, up }
    public let phase: Phase
    /// The right button rather than the left.
    public let right: Bool
    /// Which press of a run this is: 2 on the second press of a double-click.
    public let count: Int
    /// The modifiers the event says are held.
    public let held: UInt64

    public init(_ phase: Phase, right: Bool = false, count: Int = 1, held: UInt64 = 0) {
        self.phase = phase
        self.right = right
        self.count = count
        self.held = held
    }
}

/// The mouse events that make one click of `kind`, in order, all at the same point.
/// - A modifier still held from typing the label must not ride along, so `held` is stated
///   for every event: nothing, except ⌘ for a ⌘-click. A browser reads it from the click.
/// - A double-click is two presses, the second counted 2: an app tells it from two single
///   clicks by that count, not by timing.
public func clickEvents(_ kind: ClickKind) -> [ClickEvent] {
    let held = kind == .command ? Modifiers.command : 0
    let right = kind == .right
    func press(_ count: Int) -> [ClickEvent] {
        [ClickEvent(.down, right: right, count: count, held: held),
         ClickEvent(.up, right: right, count: count, held: held)]
    }
    return [ClickEvent(.move, held: held)] + press(1) + (kind == .double ? press(2) : [])
}

public enum ClickReadiness: Equatable {
    /// Click now.
    case ready
    /// Ask again shortly.
    case wait
    /// It never came forward; click anyway and say so in the log.
    case giveUp
}

/// Whether a synthetic click can be sent yet. A click on a window that is not in front only
/// brings it forward: browsers do not pass that first click on to the page. So after asking
/// the app forward, wait until it says it is frontmost and the target's window is its main
/// window. `nil` means the app did not answer; `waited` and `limit` are seconds.
///
/// One click, never two: an app that does pass the first click on would get a double click.
public func clickReadiness(appFrontmost: Bool?, windowMain: Bool?, waited: Double, limit: Double = 0.5) -> ClickReadiness {
    if appFrontmost == true && windowMain != false { return .ready }
    if appFrontmost == nil && waited >= 0.04 { return .ready }  // cannot tell: the old fixed pause
    return waited >= limit ? .giveUp : .wait
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
