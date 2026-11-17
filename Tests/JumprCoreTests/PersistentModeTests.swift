import Testing
@testable import JumprCore

// Pressing a search field means the next keys are for the field, not for labels.
@Test func aPressedTextFieldEndsPersistentMode() {
    for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
        #expect(endsPersistentMode(role: role, kind: .plain))
    }
    #expect(!endsPersistentMode(role: "AXButton", kind: .plain))
    #expect(!endsPersistentMode(role: "AXLink", kind: .command))
}

// Each day in a web date picker is an AXStaticText that takes focus: a control, not a field.
@Test func webTextThatTakesFocusDoesNotEndPersistentMode() {
    #expect(!endsPersistentMode(role: "AXStaticText", kind: .plain))
}

// The menu a right-click opens is not labelled; with the session up its arrow keys would be swallowed.
@Test func aRightClickEndsPersistentMode() {
    #expect(endsPersistentMode(role: "AXButton", kind: .right))
    for kind in [ClickKind.plain, .command, .double, .shift] {
        #expect(!endsPersistentMode(role: "AXButton", kind: kind))
    }
}

// Finder's toolbar Group button (an AXMenuButton) opened its menu with no labels on it, and
// the session still up swallowed the arrow keys and Return until Esc.
@Test func aPressedPopUpOrMenuButtonEndsPersistentMode() {
    #expect(endsPersistentMode(role: "AXPopUpButton", kind: .plain))
    #expect(endsPersistentMode(role: "AXMenuButton", kind: .plain))
    #expect(!endsPersistentMode(role: "AXButton", kind: .plain))
}

// A menu bar menu is labelled by the settle window's scan of the menu bar, so it keeps the mode.
@Test func aPressedMenuBarItemOrMenuItemDoesNotEndPersistentMode() {
    #expect(!endsPersistentMode(role: "AXMenuBarItem", kind: .plain))
    #expect(!endsPersistentMode(role: "AXMenuItem", kind: .plain))
}

// The log names why the mode ended, in fixed words, as every other ending does.
@Test func theEndingOfPersistentModeNamesItsReason() {
    #expect(persistentModeEnding(role: "AXTextField", kind: .plain) == "text field")
    #expect(persistentModeEnding(role: "AXButton", kind: .right) == "right-click")
    #expect(persistentModeEnding(role: "AXPopUpButton", kind: .plain) == "menu button")
    #expect(persistentModeEnding(role: "AXMenuButton", kind: .plain) == "menu button")
    #expect(persistentModeEnding(role: "AXButton", kind: .plain) == nil)
}

// A press into Finder and, half a second later, one into Safari: the second press starts a
// new settle window, and Finder must still be scanned in it.
@Test func theSettleWindowScansEveryAppTouchedSinceItLastFinished() {
    #expect(settleApps(touched: [10, 20], frontNow: 30, excluding: 99) == [10, 20, 30])
    #expect(settleApps(touched: [10, 99], frontNow: 10, excluding: 99) == [10])
    #expect(settleApps(touched: [], frontNow: nil, excluding: 99) == [])
}

@Test func theSettleMomentsAreTheOnesInTheDesign() {
    #expect(Settle.moments == [0.15, 0.5, 1.0, 2.0, 3.5])
}

// A page that loads a long list mid-run can need more labels than the pool holds: once that
// app's reconcile is done, one fresh trigger gives everything letters at a longer length.
@Test func aPoolThatRanOutRefreshesTheLabelsOnceTheAppIsReconciled() {
    #expect(afterReconcile(overflow: 3, labelsLeft: 40, poolLength: 1, pending: Pending(settleWindow: true)) == .refresh)
    #expect(afterReconcile(overflow: 30, labelsLeft: 0, poolLength: 1, pending: Pending()) == .refresh)
}

// Pressing the last labelled button (a dialog's OK that closes it) leaves nothing to type at;
// a capturing session would only swallow keys, as a trigger with no labels cancels today.
@Test func noLabelsLeftOnceEveryAppInTheSettleWindowHasAnsweredEndsTheSession() {
    #expect(afterReconcile(overflow: 0, labelsLeft: 0, poolLength: 2, pending: Pending()) == .end)
    #expect(afterReconcile(overflow: 0, labelsLeft: 5, poolLength: 2, pending: Pending()) == .carryOn)
}

// A page swap removes the old page's labels at 0.15 s and its new labels arrive at 0.5 s;
// and at the last moment Finder may answer with nothing placed while Safari, scanned in the
// same moment, has not answered yet. Neither ends the session: only the whole window can.
@Test func noLabelsLeftBeforeEveryAppInTheSettleWindowHasAnsweredLetsItGoOn() {
    #expect(afterReconcile(overflow: 0, labelsLeft: 0, poolLength: 2, pending: Pending(settleWindow: true)) == .carryOn)
}

// Review of persistent mode: when the letters ran out the fresh trigger had to give a longer
// length, or the run would refresh, run out again and refresh again. At three letters, or
// when the new count still fits the length in use, the run carries on with what fits.
@Test func aPoolThatRanOutRefreshesOnlyWhenALongerLengthIsAvailable() {
    #expect(afterReconcile(overflow: 5, labelsLeft: 2000, poolLength: 3, pending: Pending()) == .carryOn)
    #expect(afterReconcile(overflow: 5, labelsLeft: 400, poolLength: 2, pending: Pending()) == .carryOn)
    #expect(afterReconcile(overflow: 300, labelsLeft: 400, poolLength: 2, pending: Pending()) == .refresh)
}

// A Tab refresh finishes with nothing on screen while a press is in flight: the window that
// follows the press's report may still find something.
@Test func noLabelsLeftWhileAPressIsInFlightLetsItGoOn() {
    #expect(afterReconcile(overflow: 0, labelsLeft: 0, poolLength: 2, pending: Pending(press: true)) == .carryOn)
}

// MARK: - A settle window's bookkeeping

// A press into Finder, then ⌘T in Safari before Finder's window finished: both are scanned.
@Test func appsTouchedAccumulateAcrossPressesAndShortcuts() {
    var w = SettleWindow()
    w.touch(10)
    w.start()
    w.touch(20)
    w.start()
    #expect(w.touched == [10, 20])
}

// Review of persistent mode: a slow app's scan from the 2.0 s moment was still out when the
// 3.5 s moment's scans answered, and the window counted itself finished without it.
@Test func aWindowWaitsForScansStartedAtEarlierMoments() {
    var w = SettleWindow()
    w.start()
    w.momentFired(last: false, scansStarted: 1, pressInFlight: false)  // 2.0 s: Safari
    w.momentFired(last: true, scansStarted: 1, pressInFlight: false)   // 3.5 s: Finder
    w.scanAnswered(pressInFlight: false)                               // Finder answers
    #expect(w.running)
    w.scanAnswered(pressInFlight: false)                               // Safari answers
    #expect(!w.running)
}

// Every app's previous scan is still out at the last moment, so it starts none: the window
// finishes when those answer, or at once if nothing is out.
@Test func aLastMomentThatStartsNoScanFinishesTheWindowIfNothingElseIsOut() {
    var w = SettleWindow()
    w.start()
    w.momentFired(last: true, scansStarted: 0, pressInFlight: false)
    #expect(!w.running)

    w.start()
    w.momentFired(last: false, scansStarted: 1, pressInFlight: false)
    w.momentFired(last: true, scansStarted: 0, pressInFlight: false)
    #expect(w.running)
    w.scanAnswered(pressInFlight: false)
    #expect(!w.running)
}

// A finished window forgets what it looked at, so the next press does not scan it again.
@Test func aFinishedWindowForgetsTheAppsItLookedAt() {
    var w = SettleWindow()
    w.touch(10)
    w.start()
    w.momentFired(last: true, scansStarted: 0, pressInFlight: false)
    #expect(w.touched.isEmpty)
}

// A press into a menu bar extra, reported just after the previous window finished: clearing
// then would leave only the frontmost app for the window that follows the report.
@Test func aWindowThatFinishesDuringAPressKeepsTheAppsThatPressTouched() {
    var w = SettleWindow()
    w.start()
    w.touch(30)
    w.momentFired(last: true, scansStarted: 0, pressInFlight: true)
    #expect(!w.running)
    #expect(w.touched == [30])
}

// A press or Space switching the mode off makes the pending moments stale: the window no
// longer runs, and what was touched waits for the next one.
@Test func aStoppedWindowIsNotRunningButKeepsWhatWasTouched() {
    var w = SettleWindow()
    w.touch(10)
    w.start()
    w.momentFired(last: false, scansStarted: 2, pressInFlight: false)
    w.stop()
    #expect(!w.running)
    #expect(w.touched == [10])
}

// The pressed app quit: there is nothing of it left to scan.
@Test func anAppThatQuitIsNoLongerTouched() {
    var w = SettleWindow()
    w.touch(10)
    w.touch(20)
    w.forget(10)
    #expect(w.touched == [20])
}

@Test func resetForgetsEverything() {
    var w = SettleWindow()
    w.touch(10)
    w.start()
    w.reset()
    #expect(!w.running)
    #expect(w.touched.isEmpty)
}

// MARK: - Never left with nothing to type at

// Review of persistent mode: the pressed app quit and took the last labels with it, and the
// session went on swallowing every key with nothing to type at.
@Test func aSessionWithNoLabelsAndNothingPendingEnds() {
    #expect(endsForWantOfLabels(labelsLeft: 0, pending: Pending()))
    #expect(!endsForWantOfLabels(labelsLeft: 1, pending: Pending()))
}

// Labels can still come: the trigger's scans, a settle window's next moment, or the window
// that follows a press's report.
@Test func aSessionWithNoLabelsWaitsForAnythingThatCouldAddSome() {
    #expect(!endsForWantOfLabels(labelsLeft: 0, pending: Pending(triggerScans: true)))
    #expect(!endsForWantOfLabels(labelsLeft: 0, pending: Pending(settleWindow: true)))
    #expect(!endsForWantOfLabels(labelsLeft: 0, pending: Pending(press: true)))
}
