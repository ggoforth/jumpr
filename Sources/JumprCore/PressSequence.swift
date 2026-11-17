/// The order of presses in one session: whether a press is in flight, and the label typed
/// meanwhile. Two labels typed quickly in persistent mode must be pressed one after the other,
/// so the second waits for `Presser` to report on the first and the settle window follows
/// the last. A session that ends resets it.
public struct PressSequence {
    public struct Match: Equatable {
        public let target: Target
        public let kind: ClickKind

        public init(target: Target, kind: ClickKind) {
            self.target = target
            self.kind = kind
        }
    }

    public enum Step: Equatable {
        /// Press it now. `keepsSession`: the labels stay up and the press is in flight until
        /// reported; otherwise the caller ends the session and presses it by the plain path.
        case press(Match, keepsSession: Bool)
        /// A press is in flight: this match waits for its report.
        case hold
    }

    /// A press that kept the session has not reported yet.
    public private(set) var inFlight = false
    /// The latest label typed while a press was in flight; an earlier one is replaced.
    public private(set) var held: Match?

    public init() {}

    /// A label was typed. A match that would end the mode is held too while a press is in
    /// flight: a search field typed mid-press in another app went straight to `Presser`, and
    /// the two presses raced.
    public mutating func matched(_ m: Match, persistent: Bool) -> Step {
        if inFlight {
            held = m
            return .hold
        }
        return press(m, persistent: persistent)
    }

    /// `Presser` reported on the press in flight. Nil when nothing was held: the caller
    /// starts the settle window. A held match is pressed now, and keeps the session by the
    /// rule of this moment: with the mode switched off meanwhile it is still pressed (the
    /// user typed it), ending the session as the next match does with the mode off.
    public mutating func reported(persistent: Bool) -> Step? {
        inFlight = false
        carriedFrom = nil
        carriedInto = nil
        guard let m = held else { return nil }
        held = nil
        return press(m, persistent: persistent)
    }

    /// The generation the press in flight was started under, once a refresh carried it, and
    /// the session's generation it was carried into.
    private var carriedFrom: Int?
    private var carriedInto: Int?

    /// The letters ran out mid-run and a fresh trigger replaced the session at generation
    /// `from` with one at `into`. Case: Tab during a press in flight, and Tab's reconcile
    /// refreshed the labels; forgotten, the next label was pressed at once and raced the
    /// first press, and the first press's report was dropped as stale. A press in flight
    /// carries over with the label held behind it; a second refresh keeps the generation the
    /// press was started under, which is the one its report names.
    public mutating func carried(from: Int, into: Int) {
        guard inFlight else { return }
        if carriedFrom == nil { carriedFrom = from }
        carriedInto = into
    }

    /// Whether `Presser`'s report on a press started under generation `report` belongs to the
    /// session now at generation `session`: one made in it, or one carried into it.
    public func counts(report: Int, session: Int) -> Bool {
        report == session || (report == carriedFrom && session == carriedInto)
    }

    public mutating func reset() {
        inFlight = false
        held = nil
        carriedFrom = nil
        carriedInto = nil
    }

    private mutating func press(_ m: Match, persistent: Bool) -> Step {
        let keeps = persistent && !endsPersistentMode(role: m.target.role, kind: m.kind)
        inFlight = keeps
        return .press(m, keepsSession: keeps)
    }
}
