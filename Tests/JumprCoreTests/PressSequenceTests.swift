import CoreGraphics
import Testing
@testable import JumprCore

private func match(_ id: Int, role: String = "AXButton", kind: ClickKind = .plain) -> PressSequence.Match {
    PressSequence.Match(target: Target(id: ElementID(id), rect: CGRect(x: 0, y: 0, width: 20, height: 20),
                                       role: role, pid: 10, window: 5),
                        kind: kind)
}

// Play now in persistent mode: pressed at once, the labels stay up for Start game, and the
// press is in flight until Presser reports.
@Test func aMatchWithNoPressInFlightIsPressedNowAndKeepsAPersistentSession() {
    var p = PressSequence()
    #expect(p.matched(match(1), persistent: true) == .press(match(1), keepsSession: true))
    #expect(p.inFlight)
}

// With persistent mode off a press ends the session, as it always has: nothing waits for it.
@Test func aMatchOutsidePersistentModeEndsTheSession() {
    var p = PressSequence()
    #expect(p.matched(match(1), persistent: false) == .press(match(1), keepsSession: false))
    #expect(!p.inFlight)
}

// A search field: the next keys are for the field, so the press ends the mode.
@Test func aMatchThatEndsTheModeEndsTheSession() {
    var p = PressSequence()
    #expect(p.matched(match(1, role: "AXTextField"), persistent: true) == .press(match(1, role: "AXTextField"), keepsSession: false))
    #expect(p.matched(match(2, kind: .right), persistent: true) == .press(match(2, kind: .right), keepsSession: false))
    #expect(!p.inFlight)
}

// Two labels typed quickly: the second waits for the first press to report, so presses stay
// in order. A third typed meanwhile replaces the second.
@Test func aMatchWhileAPressIsInFlightIsHeldReplacingAnEarlierOne() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    #expect(p.matched(match(2), persistent: true) == .hold)
    #expect(p.matched(match(3), persistent: true) == .hold)
    #expect(p.held == match(3))
}

// Review of persistent mode: a search field's label typed while a press into another app was
// in flight went straight to Presser, and the two presses raced. It is held like any other.
@Test func aMatchThatWouldEndTheModeIsHeldWhileAPressIsInFlight() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    #expect(p.matched(match(2, role: "AXTextField"), persistent: true) == .hold)
    #expect(p.held == match(2, role: "AXTextField"))
}

// The first press reports and nothing was typed meanwhile: the caller starts its settle window.
@Test func aReportWithNothingHeldLeavesNothingInFlight() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    #expect(p.reported(persistent: true) == nil)
    #expect(!p.inFlight)
}

// The held label is pressed when the first press reports, and keeps the session by the same
// rule as any match: it is now in flight in its turn.
@Test func aHeldMatchIsPressedWhenThePressInFlightReports() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    _ = p.matched(match(2), persistent: true)
    #expect(p.reported(persistent: true) == .press(match(2), keepsSession: true))
    #expect(p.inFlight)
    #expect(p.held == nil)
}

// A held search field's label is pressed on the report and ends the session then.
@Test func aHeldMatchThatEndsTheModeEndsTheSessionWhenPressed() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    _ = p.matched(match(2, role: "AXTextField"), persistent: true)
    #expect(p.reported(persistent: true) == .press(match(2, role: "AXTextField"), keepsSession: false))
    #expect(!p.inFlight)
}

// A label typed during a press, then Space to switch the mode off: the user still typed that
// label, so it is pressed when the first press reports, ending the session as the next match
// does with the mode off.
@Test func aHeldMatchIsStillPressedAfterTheModeWasSwitchedOff() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    _ = p.matched(match(2), persistent: true)
    #expect(p.reported(persistent: false) == .press(match(2), keepsSession: false))
    #expect(!p.inFlight)
}

// Esc mid-press: nothing from the old session may be pressed later.
@Test func resetForgetsThePressInFlightAndTheHeldMatch() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    _ = p.matched(match(2), persistent: true)
    p.reset()
    #expect(!p.inFlight)
    #expect(p.held == nil)
    #expect(p.matched(match(3), persistent: true) == .press(match(3), keepsSession: true))
}

// MARK: - A press carried across a refresh

// Tab during a press in flight; Tab's reconcile finds the letters run out and the labels
// refresh, so the session at generation 3 becomes one at 5. The press was started under 3
// and its report names 3: it is still this session's press.
@Test func aPressCarriedAcrossARefreshStillReportsToTheSession() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    p.carried(from: 3, into: 5)
    #expect(p.counts(report: 3, session: 5))
    #expect(p.counts(report: 5, session: 5))
}

// The fresh labels ran out again before the press reported: a second refresh, 5 to 7. The
// report still names 3, the generation the press was started under.
@Test func aSecondRefreshKeepsTheGenerationThePressWasStartedUnder() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    p.carried(from: 3, into: 5)
    p.carried(from: 5, into: 7)
    #expect(p.counts(report: 3, session: 7))
    #expect(!p.counts(report: 5, session: 7))
}

// Esc, then the hotkey again: a press from the old session reports into the new one. It was
// never carried, so it does not count.
@Test func aReportFromAnOlderSessionThatWasNeverCarriedDoesNotCount() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    #expect(!p.counts(report: 3, session: 5))
}

// The carried press, then Esc: any other cancel forgets it, and its late report finds nothing.
@Test func afterAResetTheCarriedPressIsGoneAndItsLateReportDoesNotCount() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    p.carried(from: 3, into: 5)
    p.reset()
    #expect(!p.counts(report: 3, session: 5))
}

// The carried press reports: nothing is in flight, and a second report under its generation
// no longer counts.
@Test func nothingIsLeftInFlightOnceTheCarriedPressReports() {
    var p = PressSequence()
    _ = p.matched(match(1), persistent: true)
    p.carried(from: 3, into: 5)
    #expect(p.reported(persistent: true) == nil)
    #expect(!p.inFlight)
    #expect(!p.counts(report: 3, session: 5))
}

// A refresh with nothing in flight carries nothing: an old report still does not count.
@Test func aRefreshWithNoPressInFlightCarriesNothing() {
    var p = PressSequence()
    p.carried(from: 3, into: 5)
    #expect(!p.counts(report: 3, session: 5))
}
