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
    #expect(afterReconcile(overflow: 3, labelsLeft: 40, windowFinished: false) == .refresh)
    #expect(afterReconcile(overflow: 1, labelsLeft: 0, windowFinished: true) == .refresh)
}

// Pressing the last labelled button (a dialog's OK that closes it) leaves nothing to type at;
// a capturing session would only swallow keys, as a trigger with no labels cancels today.
@Test func noLabelsLeftOnceEveryAppInTheSettleWindowHasAnsweredEndsTheSession() {
    #expect(afterReconcile(overflow: 0, labelsLeft: 0, windowFinished: true) == .end)
    #expect(afterReconcile(overflow: 0, labelsLeft: 5, windowFinished: true) == .carryOn)
}

// A page swap removes the old page's labels at 0.15 s and its new labels arrive at 0.5 s;
// and at the last moment Finder may answer with nothing placed while Safari, scanned in the
// same moment, has not answered yet. Neither ends the session: only the whole window can.
@Test func noLabelsLeftBeforeEveryAppInTheSettleWindowHasAnsweredLetsItGoOn() {
    #expect(afterReconcile(overflow: 0, labelsLeft: 0, windowFinished: false) == .carryOn)
}
