/// Whether pressing a target must end persistent mode, so the press goes through and the
/// session comes down.
/// A text field means the next keys are for the field, not for labels: with the session up
/// they would be swallowed as label letters. The role must be in `Roles.text`; web text that
/// merely takes focus (each day in a date picker is an `AXStaticText`) is a control, so it is
/// not on the list and the run goes on. A right-click opens a menu that is not labelled, and
/// with the session up its arrow keys and Return would be swallowed, so it ends the mode too.
public func endsPersistentMode(role: String, kind: ClickKind) -> Bool {
    Roles.text.contains(role) || kind == .right
}

/// When a settle window re-scans after a press.
/// A press changes the screen after the app has answered, not at the moment of the press: a
/// menu opens, a page swaps, a window comes forward. These are starting values taken from
/// the design; a later task sets them from measurement. After the last one nothing runs
/// until the next press.
public enum Settle {
    public static let moments: [Double] = [0.15, 0.5, 1.0, 2.0, 3.5]
}

/// The apps a settle window scans: every app pressed since the last window finished, plus
/// the one in front now, without Jumpr itself, in ascending order.
/// A press into Finder and, half a second later, one into Safari starts a second window
/// while the first is still pending; Finder must still be scanned in it, so the window takes
/// the set of everything touched rather than just the latest press.
public func settleApps(touched: Set<Int32>, frontNow: Int32?, excluding me: Int32) -> [Int32] {
    var apps = touched
    if let frontNow { apps.insert(frontNow) }
    apps.remove(me)
    return apps.sorted()
}

/// What follows one app's reconcile in a settle window.
public enum AfterReconcile: Equatable {
    case carryOn
    /// One fresh trigger, persistent mode kept on, with labels sized from the new count.
    case refresh
    /// Nothing left to type at.
    case end
}

/// Decides, once an app's reconcile is done, whether the run goes on.
/// A pool that ran out (`overflow`) left targets with no letters; a fresh trigger gives
/// everything letters at a length sized for the new count. No labels left ends the session
/// only at the last moment: a page swap removes the old page's labels at one moment and its
/// new labels arrive at the next.
public func afterReconcile(overflow: Int, labelsLeft: Int, lastMoment: Bool) -> AfterReconcile {
    if overflow > 0 { return .refresh }
    if lastMoment && labelsLeft == 0 { return .end }
    return .carryOn
}
