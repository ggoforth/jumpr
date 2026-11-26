/// Whether pressing a target must end persistent mode, so the press goes through and the
/// session comes down.
/// A text field means the next keys are for the field, not for labels: with the session up
/// they would be swallowed as label letters. The role must be in `Roles.text`; web text that
/// merely takes focus (each day in a date picker is an `AXStaticText`) is a control, so it is
/// not on the list and the run goes on. A right-click opens a menu whose arrow keys and
/// Return would be swallowed with the session up, so it ends the mode too; the menu is then
/// labelled by a plain trigger once its window is up (`looksForMenuAfterPress`).
/// So does a pop-up or menu button, for the same reason: Finder's toolbar Group button opened
/// a menu with no labels and the keys were stuck until Esc. A menu bar menu is labelled by the
/// settle window's scan, so a menu bar item or menu item keeps the mode.
public func endsPersistentMode(role: String, kind: ClickKind) -> Bool {
    persistentModeEnding(role: role, kind: kind) != nil
}

/// The reason `endsPersistentMode` gives, in fixed words for the log, or nil when the press
/// keeps the mode. A right-click is named first: on a text field it opens a menu all the same.
public func persistentModeEnding(role: String, kind: ClickKind) -> String? {
    if kind == .right { return "right-click" }
    if Roles.text.contains(role) { return "text field" }
    if Roles.opensMenu.contains(role) { return "menu button" }
    return nil
}

/// When a settle window re-scans after a press.
/// A press changes the screen after the app has answered, not at the moment of the press: a
/// menu opens, a page swaps, a window comes forward. These are the design's starting values,
/// measured on 2026-11-16 and 2026-11-17 in two web-content apps (docs/design.md has the
/// numbers) and kept until native apps are measured. After the last one nothing runs until
/// the next press.
public enum Settle {
    public static let moments: [Double] = [0.15, 0.5, 1.0, 2.0, 3.5]
}

/// The apps a settle window scans: every app pressed since the last window finished, plus
/// the one in front now, in ascending order.
/// A press into Finder and, half a second later, one into Safari starts a second window
/// while the first is still pending; Finder must still be scanned in it, so the window takes
/// the set of everything touched rather than just the latest press.
/// Jumpr itself is scanned like any other app: it owns a menu bar extra, and its open panel's
/// controls sit under that icon, so a trigger scans it too. Leaving it out left the panel
/// opened from its own icon's label with no labels.
public func settleApps(touched: Set<Int32>, frontNow: Int32?) -> [Int32] {
    var apps = touched
    if let frontNow { apps.insert(frontNow) }
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
/// everything letters at a length sized for the new count, but only when that length is
/// longer than `poolLength`, the one in use: otherwise the fresh trigger would run out again
/// and refresh again, so the run carries on with what fits. No labels left ends the session
/// only once nothing that could add some is pending (`endsForWantOfLabels`): a page swap
/// removes the old page's labels at one moment and its new labels arrive at the next, and an
/// app that answers first with nothing placed says nothing about another app still scanning.
public func afterReconcile(overflow: Int, labelsLeft: Int, poolLength: Int, pending: Pending) -> AfterReconcile {
    if overflow > 0 && Labels.length(forEstimate: labelsLeft + overflow) > poolLength { return .refresh }
    if endsForWantOfLabels(labelsLeft: labelsLeft, pending: pending) { return .end }
    return .carryOn
}

/// What could still add labels to a session that has none.
public struct Pending: Equatable {
    /// A trigger's scans have not all answered.
    public var triggerScans: Bool
    /// A settle window has moments to come, or scans out.
    public var settleWindow: Bool
    /// A press has not reported; its settle window follows the report.
    public var press: Bool

    public init(triggerScans: Bool = false, settleWindow: Bool = false, press: Bool = false) {
        self.triggerScans = triggerScans
        self.settleWindow = settleWindow
        self.press = press
    }
}

/// A capturing session is never left with no labels and nothing pending that could add
/// some: it would swallow every key with nothing to type at. Asked after any removal. Case:
/// the pressed app quit and took the last labels with it, and the session went on.
public func endsForWantOfLabels(labelsLeft: Int, pending: Pending) -> Bool {
    labelsLeft == 0 && !pending.triggerScans && !pending.settleWindow && !pending.press
}

/// One settle window's bookkeeping: the apps it scans, and whether it has finished. It has
/// finished when its last moment has fired and every scan it started, at any of its moments,
/// has answered. The moments' timing and staleness stay with the caller.
public struct SettleWindow {
    /// The apps pressed into, the app in front at each press, and the app in front at each
    /// shortcut that passed through, since the last window finished.
    public private(set) var touched = Set<Int32>()
    /// Started, and not yet finished or stopped.
    public private(set) var running = false
    private var scansOut = 0
    private var lastFired = false

    public init() {}

    public mutating func touch(_ pid: Int32) { touched.insert(pid) }

    /// The app quit: there is nothing of it left to scan.
    public mutating func forget(_ pid: Int32) { touched.remove(pid) }

    /// A new window replaces the one in progress; what was touched carries over to it.
    public mutating func start() {
        running = true
        scansOut = 0
        lastFired = false
    }

    /// Its pending moments were made stale (a press, or Space switching the mode off), and no
    /// window follows yet. What was touched waits for the next one.
    public mutating func stop() {
        running = false
        scansOut = 0
        lastFired = false
    }

    /// A moment fired and started `scansStarted` scans.
    public mutating func momentFired(last: Bool, scansStarted: Int, pressInFlight: Bool) {
        scansOut += scansStarted
        if last { lastFired = true }
        finishIfDone(pressInFlight: pressInFlight)
    }

    /// A scan this window started has answered. Case: a slow app's scan from the 2.0 s
    /// moment was still out when the 3.5 s moment's scans answered; counting only the last
    /// moment's scans finished the window without it.
    public mutating func scanAnswered(pressInFlight: Bool) {
        scansOut -= 1
        finishIfDone(pressInFlight: pressInFlight)
    }

    public mutating func reset() {
        stop()
        touched = []
    }

    /// A finished window forgets the apps it looked at, except while a press is in flight:
    /// `touched` then holds what that press touched, and the window that follows its report
    /// must still scan it. Case: a press into a menu bar extra, reported just after the
    /// previous window finished; clearing here left only the frontmost app to scan.
    private mutating func finishIfDone(pressInFlight: Bool) {
        guard running, lastFired, scansOut == 0 else { return }
        running = false
        if !pressInFlight { touched = [] }
    }
}
